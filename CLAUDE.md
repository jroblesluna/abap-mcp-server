# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

An MCP (Model Context Protocol) server that bridges AI assistants (Kiro IDE, Amazon Q Developer) to SAP ABAP development systems via the SAP ADT (ABAP Development Tools) REST API. Deployed on AWS ECS Fargate at PG&E. All production traffic routes through the Portkey AI Gateway, which authenticates users and forwards their identity via `X-User-Claims` header. The server derives the user's LANID from that header, generates an ephemeral X.509 certificate (CN=LANID), and uses it for TLS client authentication to SAP — enabling principal propagation without shared service accounts.

## Quick Reference

```bash
# Install and run locally
pip install -r requirements.txt
python src/aws_abap_accelerator/main.py

# Build and run with Docker
docker build -f Dockerfile.simple -t abap-accelerator-enterprise:latest .
docker run -it -p 8000:8000 -e CREDENTIAL_PROVIDER=interactive abap-accelerator-enterprise:latest
```

**MCP endpoint:** `http://localhost:8000/mcp`

## Running the Server

```bash
pip install -r requirements.txt

# Standard mode — single SAP system, credentials from .env
python src/aws_abap_accelerator/main.py

# Enterprise mode — multi-tenant, principal propagation, per-request SAP system selection
python src/aws_abap_accelerator/enterprise_main.py
```

**Mode selection:**
- `main.py` — local development with a single SAP system in `.env`. One `SAPADTClient` shared by all tool calls.
- `enterprise_main.py` — multi-tenant, creates a fresh `SAPADTClient` per request using identity from headers. **Required for principal propagation and multi-system support.** Docker uses this.
- Docker (`Dockerfile.simple`) sets `ENABLE_ENTERPRISE_MODE=true` and runs `enterprise_main.py`.

**Environment files:**
- `.env` — Main config (not committed to git)
- `.env.example.cognito` — Example config for AWS Cognito OAuth
- `.env.example.azure` — Example config for Microsoft Entra ID OAuth
- `sap-systems.yaml` — Multi-system config for local Docker (non-sensitive config only)

## Local Development with Multiple SAP Systems

Create a `sap-systems.yaml` for local Docker runs:

```yaml
systems:
  S4H-DEV:
    host: sap-dev.company.com:44300
    client: "100"
    description: "Development System"
```

```bash
docker run -it -p 8000:8000 \
  -v $(pwd)/sap-systems.yaml:/app/config/sap-systems.yaml:ro \
  -e CREDENTIAL_PROVIDER=interactive-multi \
  -e ENABLE_PRINCIPAL_PROPAGATION=false \
  abap-accelerator-enterprise:latest
```

Credentials are never stored in `sap-systems.yaml` — prompted interactively at container startup.

## Docker

```bash
# Build (AMD64)
docker build -f Dockerfile.simple -t abap-accelerator-enterprise:latest .

# Build (ARM64 — Mac M1/M2/M3)
docker buildx build --platform linux/arm64 -f Dockerfile.simple -t abap-accelerator-enterprise:latest .

# Run (single system, interactive credentials)
docker run -it -p 8000:8000 \
  -e CREDENTIAL_PROVIDER=interactive \
  -e ENABLE_PRINCIPAL_PROPAGATION=false \
  abap-accelerator-enterprise:latest
```

## Architecture

Three main layers:

**1. MCP Protocol Layer** — `src/aws_abap_accelerator/server/`

- `fastmcp_server.py` + `tool_handlers.py`: Used by `main.py`. `ABAPAcceleratorServer` initializes a single `SAPADTClient` at startup and registers all MCP tools inline. `ToolHandlers` contains business logic.
- `enterprise_main.py` + `enterprise_main_tools.py`: Used by Docker/ECS. `EnterpriseABAPAcceleratorServer` registers tools via `register_sap_tools()`. Each tool call creates a fresh `SAPADTClient` per request using identity from `x-user-id` / `x-sap-system-id` / `X-User-Claims` headers. In enterprise mode, `x-sap-system-id` header (or `sap_system_id` tool param) is required.
- `fastmcp_oauth_integration.py`: OAuth flow with FastMCP for direct connections (not via Portkey). Handles Entra ID, Cognito, Okta. Includes IdP-specific patches.

**2. Authentication Layer** — `src/aws_abap_accelerator/auth/`

- `iam_identity_validator.py`: Extracts user identity from request headers. Priority order: (1) IAM Identity Center JWT, (2) ALB OIDC `x-amzn-oidc-identity`, (3) **Portkey `X-User-Claims` header** (production path), (4) `x-user-id` fallback for dev.
- `principal_propagation.py`: Derives LANID from login_identifier (`email.split('@')[0].upper()`), generates ephemeral X.509 certificate with `CN=<LANID>`, loads CA from Secrets Manager.
- `providers/certificate_auth_provider.py`: Generates ephemeral RSA 2048-bit certificates signed by CA, 5-minute validity, `CN=<LANID>`.
- `keychain_manager.py`: Credential fallback chain — AWS Secrets Manager → OS keychain → env vars → interactive prompt.
- `sap_client_factory.py`: Creates `SAPADTClient` with appropriate auth provider based on config.
- `multi_system_manager.py`: Per-system credential management for multi-tenant deployments.

**3. SAP Client Layer** — `src/aws_abap_accelerator/sap/`

- `sap_client.py`: Main `SAPADTClient` — HTTP session, CSRF tokens, session recovery.
- `core/connection.py`: Connection establishment and health check.
- `core/activation_manager.py`: SAP object activation.
- `core/object_manager.py`: Generic ABAP object CRUD.
- `core/source_manager.py`: Source code read/write.
- `class_handler.py`, `cds_handler.py`, `behavior_definition_handler.py`, `service_definition_handler.py`, `service_binding_handler.py`: Specialized handlers for modern ABAP artifacts.

**Supporting modules:**
- `enterprise/context_manager.py`: Multi-tenant context, reads per-request headers (`x-user-id`, `x-sap-system-id`, `x-team-id`).
- `config/settings.py`: Pydantic settings — all config via env vars.
- `sap_types/sap_types.py`: Shared type definitions (ADT API path strings).
- `utils/security.py`: `sanitize_for_xml()`, `sanitize_for_logging()`.
- `utils/response_optimizer.py`: Intelligent ABAP source truncation for large files.
- `server/oauth_manager.py`: OAuth state management, feature-flagged via `ENABLE_OAUTH_FLOW`.
- `server/fastmcp_oauth_integration.py`: OAuth flow integration, LANID extraction, IdP patches.
- `server/oidc_discovery.py`: OIDC provider discovery, `OAuthHandler` base class.

**Python path:** Entry points use `sys.path.insert(0, ...)` locally. Docker uses `PYTHONPATH=/app`.

## Identity Flow (Production — Portkey)

```
Kiro IDE
  → mcp-aws-ai-gateway.nonprod.pge.com/abap-mcp-server/mcp
  → Portkey authenticates user (PG&E SSO)
  → Portkey injects X-User-Claims: {"email":"avrg@pge.com",...}
  → abap-mcp-server.nonprod.pge.com/mcp
  → iam_identity_validator: reads X-User-Claims → email → login_identifier
  → principal_propagation: avrg@pge.com → AVRG → CN=AVRG (ephemeral cert)
  → SAPADTClient: TLS client auth with cert to SAP
  → SAP STRUST: validates cert → CERTRULE/SU01: CN=AVRG → user AVRG
```

## Available MCP Tools

Defined in `server/tool_handlers.py` (main.py) and `enterprise_main_tools.py` (enterprise):

**Connection:** `aws_abap_cb_connection_status`

**Objects:** `aws_abap_cb_get_objects`, `aws_abap_cb_search_object`, `aws_abap_cb_create_object`

**Source:** `aws_abap_cb_get_source`, `aws_abap_cb_update_source`

**Quality:** `aws_abap_cb_check_syntax`, `aws_abap_cb_activate_object`, `aws_abap_cb_activate_objects_batch`, `aws_abap_cb_run_atc_check`, `aws_abap_cb_run_unit_tests`, `aws_abap_cb_get_test_classes`, `aws_abap_cb_create_or_update_test_class`

**Transport:** `aws_abap_cb_get_transport_requests`, `aws_abap_cb_get_migration_analysis`

All tools accept `sap_system_id` for multi-system deployments. In enterprise mode this param (or `x-sap-system-id` header) is **required**.

## Request Flow

```
MCP Tool Call
  → enterprise_main_tools.py (_get_sap_client_and_context)
  → iam_identity_validator (Portkey X-User-Claims → login_identifier)
  → principal_propagation (login_identifier → LANID → ephemeral cert)
  → SAPADTClient (HTTP + CSRF + TLS client cert)
  → Specialized handler (class/CDS/behavior/service)
  → SAP ADT REST API (XML over HTTPS)
  → Parse XML → return MCP result
```

## Key Configuration (`.env`)

| Variable | Purpose |
|---|---|
| `SAP_HOST` | SAP hostname (with optional port) |
| `SAP_CLIENT` | SAP client number |
| `SAP_USERNAME` / `SAP_PASSWORD` | Credentials |
| `SAP_SECURE` | Use HTTPS |
| `SSL_VERIFY` | Verify SSL certificates |
| `CREDENTIAL_PROVIDER` | `env`, `keychain`, `interactive`, `interactive-multi`, `aws_secrets` |
| `ENABLE_ENTERPRISE_MODE` | Multi-tenant features |
| `ENABLE_PRINCIPAL_PROPAGATION` | Certificate-based auth |
| `ENABLE_OAUTH_FLOW` | OAuth flow for direct (non-Portkey) connections |
| `CA_CERT_PATH` / `CA_KEY_PATH` | Local CA cert paths (dev/testing) |
| `SERVER_HOST` / `SERVER_PORT` | MCP server bind (default `0.0.0.0:8000`) |
| `SAVE_SAMPLE_CERT_DIR` | Directory for sample ephemeral certs (Basis testing) |

## ECS Deployment (Terraform)

All ECS configuration in `terraform/terraform.tfvars`. No defaults in `variables.tf`.

**Config sources:**

| Data Type | Storage |
|-----------|---------|
| Sensitive (certs, keys, secrets) | AWS Secrets Manager |
| Non-sensitive (SAP endpoints, user exceptions) | SSM Parameter Store |
| OAuth settings + infrastructure | `terraform.tfvars` |

**SAP systems:** Python reads endpoints from SSM Parameter `SAP_ENDPOINTS_PARAMETER` at startup — not from env vars. Created via `./scripts/create-aws-parameters.sh`.

`SAP_SYSTEMS_YAML` is not used in ECS. Only for local Docker with mounted `sap-systems.yaml`.

## Certificate Management (Principal Propagation)

When `ENABLE_PRINCIPAL_PROPAGATION=true`, the server generates ephemeral X.509 certs:

| Variable | Purpose |
|---|---|
| `CA_CERT_PATH` | Path to CA public certificate |
| `CA_KEY_PATH` | Path to CA private key |
| `SAVE_SAMPLE_CERT_DIR` | Save sample ephemeral cert for SAP Basis testing |

**Local setup:**
```bash
./scripts/generate-ca-certificates.sh   # creates certificates/
./scripts/create-ca-secret.sh           # upload to AWS Secrets Manager
```

**ECS:** CA cert + key stored in Secrets Manager `mcp/abap-mcp-server/ca-certificate`.

**Certificate properties:**
- CA: RSA 4096-bit, 10-year validity, `CN=ABAP MCP CA`
- Ephemeral: RSA 2048-bit, 5-minute validity, `CN=<LANID>`
- LANID derived: `email.split('@')[0].upper()` — `avrg@pge.com` → `AVRG`

See `README-PGE.md` for STRUST configuration and CERTRULE user mapping.

## Portkey Integration (Production Identity Path)

The Portkey MCP Registry forwards user identity via `X-User-Claims` header:

```json
{
  "user_identity_forwarding": {
    "method": "claims_header",
    "header_name": "X-User-Claims",
    "include_claims": ["sub", "email", "name", "groups", "workspace_id", "organisation_id"]
  }
}
```

The `IAMIdentityValidator.extract_identity_from_headers()` reads this header (priority 3). No OAuth flow needed when Portkey is the gateway — Portkey handles SSO and the MCP server trusts the forwarded claims.

**This pattern is replicable for any MCP server** behind the Portkey gateway. Any server reading `X-User-Claims` gets the authenticated user's identity without implementing OAuth itself.

## OAuth Integration (Direct Connection)

When `ENABLE_OAUTH_FLOW=true` and a client connects directly (not via Portkey):

**Supported providers:** Entra ID, Cognito, Okta  
**Key patches in `fastmcp_oauth_integration.py`:**
- Okta: strips RFC 8707 `resource` param (not supported)
- Kiro: injects `client_id` in token exchange (Kiro bug)
- Entra ID: auto-detects token audience from issuer URL
- SSL: respects `SSL_VERIFY` via `httpx.AsyncClient.__init__` monkey-patch (line 351)

**Identity caching:** Module-level `_sub_identity_cache` (UUID → LANID) minimizes UserInfo API calls.

## Important Patterns

**SSL verification:** `SSL_VERIFY` env var controls all connections:
- SAP ADT: via `SAPADTClient` initialization (`requests` library)
- OAuth/OIDC: via `httpx.AsyncClient` monkey-patch in `fastmcp_oauth_integration.py`
- `SSL_VERIFY=false` only for testing with self-signed certs — never in production

**XML handling:** Use `sanitize_for_xml()` from `utils/security.py` before inserting user content into XML. Use `defusedxml` (never stdlib `xml`) for parsing SAP responses.

**Transport requests:** Write operations accept `transport_request: str | None`. Passed as `?corrNr=` query param. See `service_binding_handler.py` for the correct pattern.

**CSRF tokens:** `SAPADTClient` manages CSRF token lifecycle automatically. Handlers do not handle this explicitly. Tokens cached per session, refreshed on 403.

**Session recovery:** `SAPADTClient` auto-retries with session recovery (re-auth, CSRF refresh). Handlers can assume session is valid unless an exception is raised.

**stateless_http:** `enterprise_main.py` runs FastMCP with `stateless_http=True` — required for Portkey/streamable-HTTP transport compatibility.

## Adding New MCP Tools

Add to **both** entry point paths:

1. **`server/fastmcp_server.py` `_register_tools()`** — for `main.py`
2. **`enterprise_main_tools.py` `register_sap_tools()`** — for `enterprise_main.py`

Enterprise tool pattern:
```python
@mcp.tool()
async def aws_abap_cb_your_new_tool(
    object_name: str,
    sap_system_id: str | None = None
) -> dict:
    """Tool description."""
    from fastmcp import Context
    ctx = Context()
    headers = dict(ctx.request_context.request.headers) if ctx.request_context else {}
    user_id, login_id = _extract_user_identity(headers)
    system_id = sap_system_id or headers.get('x-sap-system-id') or os.getenv('DEFAULT_SAP_SYSTEM_ID')
    sap_client, context_info = await server._get_sap_client_and_context(user_id, system_id, login_id)
    return your_handler.do_something(sap_client, object_name)
```

3. Create a handler in `src/aws_abap_accelerator/sap/` for complex operations.
4. Sanitize all inputs before XML construction. Return structured dicts. For write operations accept `transport_request: str | None = None`.

## Development

**Testing:** No test infrastructure yet. When adding tests: uncomment `pytest` in `requirements.txt`, create `tests/`, mock SAP ADT API responses for unit tests.

**Debugging:** `LOG_LEVEL=DEBUG` for verbose output. Use `structlog` (`utils/logger.py`).

**Testing principal propagation locally:**
```bash
export CA_CERT_PATH=./certificates/abap-mcp-ca-cert.pem
export CA_KEY_PATH=./certificates/abap-mcp-ca-key.pem
export SAVE_SAMPLE_CERT_DIR=./certificates
python src/aws_abap_accelerator/enterprise_main.py
```

**Common workflow:**
1. Make code changes in `src/aws_abap_accelerator/`
2. Test locally: `python src/aws_abap_accelerator/main.py`
3. Test enterprise: `enterprise_main.py` or Docker
4. Verify with MCP client (Kiro) at `http://localhost:8000/mcp`
5. Check logs for errors
6. Deploy: `./scripts/build-and-push-docker.sh && git push origin dev`

## Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `SSL: CERTIFICATE_VERIFY_FAILED` | Corporate proxy / self-signed cert | `SSL_VERIFY=false` in `.env` (testing only) |
| `401 Unauthorized` / CSRF failure | Invalid credentials / expired session | Verify credentials, check SU01 lock status |
| `No user identity found` | Missing headers | Use `main.py` locally, or set `DEFAULT_USER_ID=testuser` |
| `Transport request required` | Write to transported object without TR | Pass `transport_request` param or use `$TMP` package |
| MCP client can't connect | Server not running / wrong port | `curl http://localhost:8000/health`, check `SERVER_PORT=8000` |

## Additional Documentation

- **README-PGE.md** — Deployment, certificates, identity, SAP config, scripts (comprehensive technical reference)
- **WIKI.md** — Internal user guide: Kiro setup, Portkey integration, architecture overview for stakeholders
- **README.md** — Original AWS samples README (base project)
