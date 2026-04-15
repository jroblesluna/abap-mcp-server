# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

An MCP (Model Context Protocol) server that bridges AI assistants (Amazon Q Developer, Kiro) to SAP ABAP development systems via the SAP ADT (ABAP Development Tools) REST API. Exposes 15+ SAP development operations as MCP tools.

## Quick Reference

**Install and run locally:**
```bash
pip install -r requirements.txt
python src/aws_abap_accelerator/main.py
```

**Build and run with Docker:**
```bash
docker build -f Dockerfile.simple -t abap-accelerator-enterprise:latest .
docker run -it -p 8000:8000 -e CREDENTIAL_PROVIDER=interactive abap-accelerator-enterprise:latest
```

**MCP endpoint:** `http://localhost:8000/mcp`

**Key tools to test:**
- `aws_abap_cb_connection_status` - Verify SAP connection
- `aws_abap_cb_get_source` - Read ABAP source code
- `aws_abap_cb_update_source` - Modify ABAP source code
- `aws_abap_cb_activate_object` - Activate changed objects

## Running the Server

```bash
# Install dependencies
pip install -r requirements.txt

# Standard mode (single SAP system via .env config)
python src/aws_abap_accelerator/main.py

# Enterprise mode (multi-tenant, principal propagation, per-request SAP system selection)
python src/aws_abap_accelerator/enterprise_main.py
```

**Development mode selection:**
- Use `main.py` for local development with a single SAP system configured in `.env`. SAP credentials are loaded once at startup from `SAP_*` env vars; all tool calls share that single connection.
- Use `enterprise_main.py` when testing:
  - Multi-tenant features (multiple users, teams)
  - OAuth authentication flows (Cognito, Entra ID, Okta)
  - Principal propagation (certificate-based auth)
  - Per-request SAP system selection via headers
- Docker (`Dockerfile.simple`) defaults to `enterprise_main.py` — `ENABLE_ENTERPRISE_MODE=true` is set in the image.

**Environment files:**
- `.env` - Main configuration file (not committed to git)
- `.env.cognito` - Example configuration for AWS Cognito OAuth
- `.env.azure` - Example configuration for Microsoft Entra ID OAuth
- `sap-systems.yaml` - Multi-system configuration for local Docker deployments (host, client, non-sensitive config only)

## Local Development with Multiple SAP Systems

For local development with multiple SAP systems, create a `sap-systems.yaml` file:

```yaml
systems:
  S4H-DEV:
    host: sap-dev.company.com:44300
    client: "100"
    description: "Development System"
  S4H-QAS:
    host: sap-qas.company.com:44301
    client: "200"
    description: "QA System"
```

Then run with Docker mounting the config file:

```bash
docker run -it -p 8000:8000 \
  -v $(pwd)/sap-systems.yaml:/app/config/sap-systems.yaml:ro \
  -e CREDENTIAL_PROVIDER=interactive-multi \
  -e ENABLE_PRINCIPAL_PROPAGATION=false \
  abap-accelerator-enterprise:latest
```

**Note:** Credentials are never stored in `sap-systems.yaml` - they're prompted interactively at container startup.

## Docker

```bash
# Build (AMD64)
docker build -f Dockerfile.simple -t abap-accelerator-enterprise:latest .

# Build (ARM64 - Mac M1/M2)
docker buildx build --platform linux/arm64 -f Dockerfile.simple -t abap-accelerator-enterprise:latest .

# Run (single system, interactive credentials)
docker run -it -p 8000:8000 \
  -e CREDENTIAL_PROVIDER=interactive \
  -e ENABLE_PRINCIPAL_PROPAGATION=false \
  abap-accelerator-enterprise:latest
```

## Architecture

The server has three main layers:

**1. MCP Protocol Layer** — `src/aws_abap_accelerator/server/`
- `fastmcp_server.py` + `tool_handlers.py`: Used by `main.py`. Creates `ABAPAcceleratorServer` which initializes a single `SAPADTClient` at startup (from `.env`) and registers all MCP tools inline. `ToolHandlers` holds the business logic.
- `enterprise_main.py` + `enterprise_main_tools.py`: Used by Docker/ECS. `EnterpriseABAPAcceleratorServer` registers tools via `register_sap_tools()` in `enterprise_main_tools.py`. Each tool call creates a fresh `SAPADTClient` per request using identity extracted from headers (`x-user-id`, `x-sap-system-id`). **The `x-sap-system-id` header (or `sap_system_id` tool parameter) is required in enterprise mode.**
- `fastmcp_oauth_integration.py`: OAuth flow integration with FastMCP (see [OAuth Integration](#oauth-integration))

**2. Authentication Layer** — `src/aws_abap_accelerator/auth/`
- Two modes, controlled by `ENABLE_PRINCIPAL_PROPAGATION`:
  - **Principal Propagation** (`principal_propagation.py`): IAM Identity Center user → ephemeral X.509 cert → SAP CERTRULE maps cert CN to SAP username
  - **Keychain** (`keychain_manager.py`): Credentials from AWS Secrets Manager, OS keychain, env vars, or interactive prompts
- `providers/` contains pluggable credential provider implementations (basic_auth, certificate_auth, saml_sso, reentrance_ticket_auth)
- `principal_propagation_middleware.py`: Intercepts requests to extract user identity and generate certificates
- `sap_client_factory.py`: Creates `SAPADTClient` instances with appropriate auth provider based on config
- `multi_system_manager.py`: Per-system credential management for multi-tenant deployments

**3. SAP Client Layer** — `src/aws_abap_accelerator/sap/`
- `sap_client.py`: Main `SAPADTClient` class — owns HTTP session, CSRF tokens, session recovery
- `core/connection.py`: Connection establishment and health
- `core/activation_manager.py`: SAP object activation
- `core/object_manager.py`: Generic ABAP object CRUD
- `core/source_manager.py`: Source code read/write
- Specialized handlers for modern ABAP artifacts: `class_handler.py`, `cds_handler.py` (CDS views), `behavior_definition_handler.py`, `service_definition_handler.py`, `service_binding_handler.py`

**Supporting modules:**
- `enterprise/`: Multi-tenant context (`context_manager.py`), usage tracking, middleware — reads per-request headers (`x-user-id`, `x-sap-system-id`, `x-team-id`)
- `config/settings.py`: Pydantic-based settings, all config via environment variables
- `sap_types/sap_types.py`: Shared type definitions for all SAP operations
- `utils/`: Security (`sanitize_for_xml`, `sanitize_for_logging`), structured logging, XML parsing (`defusedxml`), `response_optimizer.py` (intelligent ABAP source truncation for large files)
- `server/oauth_manager.py`: OAuth state management, feature-flagged via `ENABLE_OAUTH_FLOW`
- `server/oauth_callback.py` + `oauth_helpers.py`: OAuth callback handling and token utilities
- `server/oidc_discovery.py`: OIDC provider discovery and `OAuthHandler` base class

**Python path note:** Locally, entry points use `sys.path.insert(0, str(Path(__file__).parent))` to enable `from sap.sap_client import ...` style imports. In Docker, `PYTHONPATH=/app` is set and source lives at `/app/src/` — imports work because `PYTHONPATH` points to `/app` and files are under `/app/src/aws_abap_accelerator/`.

## Available MCP Tools

The server exposes 15+ SAP development operations as MCP tools (defined in `server/tool_handlers.py` for `main.py` and in `enterprise_main_tools.py` for `enterprise_main.py`):

**Connection & Status:**
- `aws_abap_cb_connection_status` - Test SAP connection and retrieve system info

**Object Management:**
- `aws_abap_cb_get_objects` - List ABAP objects in a package
- `aws_abap_cb_search_object` - Search for objects by name/type
- `aws_abap_cb_create_object` - Create new ABAP object (class, interface, CDS, etc.)

**Source Code:**
- `aws_abap_cb_get_source` - Retrieve source code of an object
- `aws_abap_cb_update_source` - Modify source code (with transport request)

**Quality & Testing:**
- `aws_abap_cb_check_syntax` - Syntax check without activation
- `aws_abap_cb_activate_object` - Activate single object
- `aws_abap_cb_activate_objects_batch` - Activate multiple objects
- `aws_abap_cb_run_atc_check` - Run ATC quality checks
- `aws_abap_cb_run_unit_tests` - Execute ABAP unit tests
- `aws_abap_cb_get_test_classes` - List test classes for an object
- `aws_abap_cb_create_or_update_test_class` - Manage test classes

**Transport & Migration:**
- `aws_abap_cb_get_transport_requests` - List transport requests
- `aws_abap_cb_get_migration_analysis` - Custom/S/4HANA migration analysis

All tools support `sap_system_id` parameter for multi-system deployments. In enterprise mode this parameter (or `x-sap-system-id` header) is **required**.

## Request Flow

```
MCP Tool Call
  → tool_handlers.py (_get_sap_client_*)       [main.py path: reuses single SAPADTClient]
  → enterprise_main_tools.py (_get_sap_client)  [enterprise path: creates SAPADTClient per request]
  → Auth context (principal propagation or keychain)
  → SAPADTClient (HTTP + CSRF + session mgmt)
  → Specialized handler (class/CDS/behavior/service)
  → SAP ADT REST API (XML over HTTP/HTTPS)
  → Parse XML response → return MCP result
```

**Error propagation:**
- SAP errors (HTTP 4xx/5xx) → logged with sanitized context → returned as MCP error responses
- Connection failures trigger session recovery in `SAPADTClient` (re-authentication, CSRF token refresh)
- All errors include user-facing messages and are logged with structured context

## Key Configuration (`.env`)

| Variable | Purpose |
|---|---|
| `SAP_HOST` | SAP hostname (optionally with port) |
| `SAP_CLIENT` | SAP client number |
| `SAP_USERNAME` / `SAP_PASSWORD` | Credentials |
| `SAP_SECURE` | Use HTTPS |
| `SSL_VERIFY` | Verify SSL certs |
| `CREDENTIAL_PROVIDER` | `env`, `keychain`, `interactive`, `interactive-multi`, `aws_secrets` |
| `ENABLE_ENTERPRISE_MODE` | Multi-tenant features |
| `ENABLE_PRINCIPAL_PROPAGATION` | Certificate-based auth |
| `ENABLE_OAUTH_FLOW` | Enable OAuth authentication flow |
| `CA_CERT_PATH` / `CA_KEY_PATH` | CA cert paths for principal propagation |
| `SERVER_HOST` / `SERVER_PORT` | MCP server bind (default `0.0.0.0:8000`) |

**For OAuth configuration**, see [OAuth Integration](#oauth-integration) and README-PGE.md.

### Certificate Management (Principal Propagation)

When `ENABLE_PRINCIPAL_PROPAGATION=true`, the server generates ephemeral X.509 certificates for SAP authentication:

| Variable | Purpose |
|---|---|
| `CA_CERT_PATH` | Path to CA certificate (public) for signing ephemeral certs |
| `CA_KEY_PATH` | Path to CA private key for signing ephemeral certs |
| `SAVE_SAMPLE_CERT_DIR` | (Optional) Directory to save sample ephemeral certificates for SAP Basis testing |

**Local development:**
- Certificates stored in `certificates/` directory
- CA certificate (`certificates/abap-mcp-ca-cert.pem`) — public, safe to share
- CA private key (`certificates/abap-mcp-ca-key.pem`) — private, git-ignored
- Generate with: `./scripts/generate-ca-certificates.sh`

**ECS deployment:**
- CA certificate and private key stored in AWS Secrets Manager: `mcp/abap-mcp-server/ca-certificate`
- Secret format: `{"ca_certificate": "...", "ca_private_key": "..."}`
- Upload with: `./scripts/create-ca-secret.sh`
- Certificate validity: 10 years (rotate before expiry)
- Ephemeral certificates: 5-minute validity, auto-renewed

**Certificate Properties:**
- **CA Certificate:** RSA 4096-bit, self-signed, CN=ABAP MCP CA
- **Ephemeral Certificates:** RSA 2048-bit, CN=<LANID> (e.g., CN=AVRG)
- **SAP Configuration:** Import CA to STRUST PSE for port 1443/44300
- **User Mapping:** Use Login Type E (SU01 → SNC tab) for direct CN-to-username mapping

**Complete certificate setup documentation**: See README-PGE.md for generation, SAP STRUST configuration, and CERTRULE user mapping.

## OAuth Integration

**Status:** 🚧 Phase 2 feature (in development). Current deployment (Phase 1) uses static credentials from AWS Secrets Manager. See WIKI.md for current implementation status.

The server integrates OAuth authentication with FastMCP for multi-user principal propagation:

**Flow:**
1. User connects via MCP client (Q Developer/Kiro)
2. Server redirects to OAuth provider (Cognito, Entra ID)
3. User authenticates with IdP (SSO login)
4. Server receives OAuth token (JWT)
5. Server extracts user identity from token:
   - **Cognito:** UserInfo endpoint → email → LANID
   - **Entra ID:** JWT `preferred_username` claim → email → LANID
   - **LANID extraction:** `email.split('@')[0].upper()` (e.g., avrg@pge.com → AVRG)
6. Server generates ephemeral X.509 certificate with CN=<LANID>
7. Certificate used for TLS client authentication to SAP
8. SAP validates certificate (STRUST) and maps CN to SAP user (CERTRULE or Login Type E)

**Implementation:**
- `server/fastmcp_oauth_integration.py`: Integrates OAuth flow with FastMCP, extracts LANID from tokens
- `auth/providers/certificate_auth_provider.py`: Generates ephemeral certificates with CN=<LANID>
- `auth/principal_propagation.py`: Orchestrates identity resolution and certificate generation
- **Identity caching:** Module-level `_sub_identity_cache` (UUID → LANID) minimizes UserInfo API calls
- **Certificate validity:** 5 minutes (configurable via `validity_minutes` parameter)

**SSL Verification:**
The OAuth integration respects the `SSL_VERIFY` environment variable for all HTTP calls (OIDC discovery, token endpoints, JWKS). This is implemented via a monkey-patch of `httpx.AsyncClient.__init__` in `fastmcp_oauth_integration.py:351`:

```python
import httpx
_o = httpx.AsyncClient.__init__
httpx.AsyncClient.__init__ = lambda s,*a,**k: _o(s,*a,**{**k,'verify': False if os.getenv('SSL_VERIFY','true').lower()=='false' else True})
```

This ensures `httpx` (used internally by FastMCP) honors `SSL_VERIFY=false` for testing environments with self-signed certificates.

**IdP-Specific Patches:**
- **Okta**: Strips RFC 8707 `resource` parameter (not supported by Okta, causes `access_denied`)
- **Kiro compatibility**: Injects `client_id` in token exchange when missing (Kiro OAuth client bug)
- **Microsoft Entra ID**: Auto-detects token audience based on issuer URL

**Configuration:**
```bash
ENABLE_OAUTH_FLOW=true
OAUTH_ISSUER=https://cognito-idp.us-east-1.amazonaws.com/...
OAUTH_AUTH_ENDPOINT=https://your-domain.auth.us-east-1.amazoncognito.com/oauth2/authorize
OAUTH_TOKEN_ENDPOINT=https://your-domain.auth.us-east-1.amazoncognito.com/oauth2/token
OAUTH_CLIENT_ID=your-client-id
SERVER_BASE_URL=https://your-mcp-server.com
SSL_VERIFY=true  # Set to 'false' for testing with self-signed certs
```

See README-PGE.md for certificate setup, SAP STRUST configuration, and CERTRULE mapping.

## Important Patterns

**SSL verification**: The `SSL_VERIFY` environment variable controls certificate validation for all HTTP/HTTPS connections:
- SAP ADT connections: Configured via `SAPADTClient` initialization (uses `requests` library)
- OAuth/OIDC calls: Handled via `httpx.AsyncClient` monkey-patch (see [OAuth Integration](#oauth-integration))
- Set `SSL_VERIFY=false` only for testing with self-signed certificates; never in production

**XML handling**: All SAP ADT communication uses XML. Use `sanitize_for_xml()` from `utils/security.py` before inserting user content into XML payloads. Use `defusedxml` (never stdlib `xml`) for parsing SAP responses.

**Transport requests**: Most write operations accept a `transport_request` parameter — check existing handlers (e.g., `service_binding_handler.py`, `service_definition_handler.py`) for the correct pattern when adding new ones. Transport requests are passed in the `?corrNr=` query parameter for ADT API calls.

**CSRF tokens**: The `SAPADTClient` manages CSRF token lifecycle automatically via `X-CSRF-Token: Fetch` headers. Handlers do not need to handle this explicitly. Tokens are cached per session and refreshed on 403 responses.

**SAP object types**: The `sap_types/sap_types.py` module defines type strings used in ADT API paths (e.g., `CLAS`, `PROG`, `INTF`, `DDLS`, `BDEF`, `SRVD`, `SRVB`). Use these constants rather than hardcoding strings.

**Session recovery**: `SAPADTClient` automatically retries failed requests with session recovery (re-auth, CSRF refresh). Handlers can safely assume the session is valid unless an exception is raised.

## Adding New MCP Tools

When adding a tool, you need to add it in **both** entry point paths:

1. **`server/fastmcp_server.py` `_register_tools()`** — for `main.py` (single-system, uses `self.tool_handlers`)
2. **`enterprise_main_tools.py` `register_sap_tools()`** — for `enterprise_main.py` (multi-system, creates a client per call via `server._get_sap_client_and_context()`)

**Enterprise tool pattern** (from `enterprise_main_tools.py`):
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

3. **Create a handler in `src/aws_abap_accelerator/sap/` if needed** for complex operations (see `class_handler.py`, `cds_handler.py` as examples)

4. **Use existing patterns:**
   - Sanitize all inputs before constructing XML
   - Return structured dicts (converted to JSON by MCP)
   - For write operations, accept `transport_request: str | None = None`
   - For ADT API paths, consult SAP ADT REST API docs or existing handlers

## Development

**Code formatting** (optional, not currently enforced):
```bash
# Uncomment dev dependencies in requirements.txt first
black src/
flake8 src/
mypy src/
```

**Testing:**
No test infrastructure exists yet. When adding tests:
- Uncomment `pytest>=7.4.0` and `pytest-asyncio>=0.21.0` in `requirements.txt`
- Create `tests/` directory with unit and integration tests
- Mock SAP ADT API responses for unit tests
- Use test SAP systems for integration tests (never production systems)

**Debugging:**
- Set `LOG_LEVEL=DEBUG` in `.env` for verbose output (includes HTTP requests, XML payloads, CSRF tokens)
- Use `structlog` for structured logging (see existing handlers in `utils/logger.py`)
- Check CloudWatch logs in ECS deployments
- For OAuth issues: Check `/oauth/status` endpoint for configuration verification
- For SAP connection issues: Check `aws_abap_cb_connection_status` tool first

**Common development workflow:**
1. **Generate CA certificates** (one-time setup for principal propagation)
   ```bash
   ./scripts/generate-ca-certificates.sh
   ./scripts/create-ca-secret.sh  # Upload to AWS
   ```

2. **Make code changes** in `src/aws_abap_accelerator/`

3. **Test locally** with `python src/aws_abap_accelerator/main.py`
   - Configure `.env` with single SAP system
   - Use `CREDENTIAL_PROVIDER=env` or `interactive`

4. **Test enterprise features** with `enterprise_main.py` or Docker
   - Use `sap-systems.yaml` for multi-system testing
   - Test OAuth flows with `ENABLE_OAUTH_FLOW=true`
   - Test principal propagation:
     ```bash
     export CA_CERT_PATH=./certificates/abap-mcp-ca-cert.pem
     export CA_KEY_PATH=./certificates/abap-mcp-ca-key.pem
     export SAVE_SAMPLE_CERT_DIR=./certificates
     python src/aws_abap_accelerator/enterprise_main.py
     ```

5. **Verify with MCP client** (Q Developer/Kiro)
   - Point to `http://localhost:8000/mcp` in MCP config
   - Test all 15+ tools (connection status, get source, update source, etc.)

6. **Check logs** for errors or warnings
   - OAuth: Look for "OAuth: Resolved '<UUID>' → '<LANID>'" log entries
   - Certificates: Look for "Generated ephemeral certificate: CN=<LANID>" log entries
   - SAP: Look for connection attempts and error messages

7. **Build Docker image** for deployment testing
   ```bash
   ./scripts/build-and-push-docker.sh
   ```

8. **Deploy to ECS** for multi-user/production testing
   - Update `terraform/terraform.tfvars` with new image tag
   - Commit and push (TFC auto-deploys)

## Common Issues & Troubleshooting

### "SSL: CERTIFICATE_VERIFY_FAILED"
**Cause:** Corporate proxy or self-signed SAP certificate
**Solution:** Set `SSL_VERIFY=false` in `.env` (testing only) or add `CUSTOM_CA_CERT_PATH=/path/to/ca.pem`

### "401 Unauthorized" or "CSRF token validation failed"
**Cause:** Invalid credentials or expired session
**Solution:**
- Verify `SAP_USERNAME`/`SAP_PASSWORD` are correct
- Check SAP user is not locked (transaction SU01)
- `SAPADTClient` automatically refreshes CSRF tokens; check logs for retry attempts

### "No user identity found in request headers"
**Cause:** Running `enterprise_main.py` without OAuth or identity headers
**Solution:**
- Use `main.py` for local development without OAuth
- Or set `DEFAULT_USER_ID=testuser` in `.env` for testing
- Or configure OAuth properly with `ENABLE_OAUTH_FLOW=true`

### "Transport request required but not provided"
**Cause:** Write operation in transported object without `transport_request` parameter
**Solution:** Pass `transport_request` parameter (e.g., `DEVK900001`) or create object as local (`$TMP` package)

### MCP client can't connect to server
**Cause:** Server not running or wrong port
**Solution:**
- Check server is running: `curl http://localhost:8000/health`
- Verify `SERVER_PORT=8000` matches MCP client configuration
- Check firewall/network allows connection

## Utility Scripts

The `scripts/` directory contains deployment and management utilities:

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `generate-ca-certificates.sh` | Generate self-signed CA certificate for principal propagation | Once during initial setup (or when rotating certs) |
| `create-ca-secret.sh` | Upload CA certificates to AWS Secrets Manager | After generating certificates |
| `create-aws-secrets.sh` | Create SAP credentials in AWS Secrets Manager | Initial setup (deprecated with principal propagation) |
| `build-and-push-docker.sh` | Build Docker image and push to ECR | Every code change deployment |
| `cleanup-ecr.sh` | Delete ECR images and repository | After infrastructure teardown |

**Example workflow:**
```bash
# Initial setup
./scripts/generate-ca-certificates.sh
./scripts/create-ca-secret.sh

# Deploy new version
./scripts/build-and-push-docker.sh
# Update terraform/terraform.tfvars with new image tag
git add terraform/terraform.tfvars && git commit -m "chore: update image" && git push
```

**See also:** README-PGE.md Part 4 for detailed documentation of each script.

---

## Additional Documentation

### For Developers
- **CLAUDE.md** (this file) — Development guide for Claude Code
- **README-PGE.md** — Technical documentation (certificates, OAuth, scripts, deployment)
- **README.md** — Comprehensive deployment guide (local, Docker, ECS)

### For Operations/SAP Basis
- **README-PGE.md** — Certificate management, SAP STRUST setup, OAuth integration, troubleshooting, utility scripts
- **README.md** — Comprehensive deployment guide (local, Docker, ECS)

### For End Users
- **WIKI.md** — Project overview, Kiro IDE setup, features, benefits, current status
