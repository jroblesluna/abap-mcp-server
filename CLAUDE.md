# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

An MCP (Model Context Protocol) server that bridges AI assistants (Amazon Q Developer, Kiro) to SAP ABAP development systems via the SAP ADT (ABAP Development Tools) REST API. Exposes 15+ SAP development operations as MCP tools.

## Running the Server

```bash
# Install dependencies
pip install -r requirements.txt

# Standard mode (single SAP system via .env config)
python src/aws_abap_accelerator/main.py

# Enterprise mode (multi-tenant, principal propagation, per-request SAP system selection)
python src/aws_abap_accelerator/enterprise_main.py
```

## Docker

```bash
# Build (AMD64)
docker build -f Dockerfile.simple -t abap-accelerator-enterprise:latest .

# Build (ARM64 - Mac M1/M2)
docker buildx build --platform linux/arm64 -f Dockerfile.simple -t abap-accelerator-enterprise:latest .

docker run -it -p 8000:8000 abap-accelerator-enterprise:latest
```

## Architecture

The server has three main layers:

**1. MCP Protocol Layer** — `src/aws_abap_accelerator/server/`
- `fastmcp_server.py`: Creates the FastMCP HTTP server instance
- `tool_handlers.py`: Registers and implements all MCP tools. Each tool calls `_get_sap_client_*()` to obtain an authenticated `SAPADTClient`, then delegates to SAP handlers.
- `oauth_manager.py`: OAuth integration for multi-user flows

**2. Authentication Layer** — `src/aws_abap_accelerator/auth/`
- Two modes, controlled by `ENABLE_PRINCIPAL_PROPAGATION`:
  - **Principal Propagation** (`providers/principal_propagation.py`): IAM Identity Center user → ephemeral X.509 cert → SAP CERTRULE maps cert CN to SAP username
  - **Keychain** (`keychain_manager.py`): Credentials from AWS Secrets Manager, OS keychain, env vars, or interactive prompts
- `providers/` contains pluggable credential provider implementations

**3. SAP Client Layer** — `src/aws_abap_accelerator/sap/`
- `sap_client.py`: Main `SAPADTClient` class — owns HTTP session, CSRF tokens, session recovery
- `core/connection.py`: Connection establishment and health
- `core/activation_manager.py`: SAP object activation
- `core/object_manager.py`: Generic ABAP object CRUD
- `core/source_manager.py`: Source code read/write
- Specialized handlers for modern ABAP artifacts: `class_handler.py`, `cds_handler.py` (CDS views), behavior definitions, service definitions, service bindings

**Supporting modules:**
- `enterprise/`: Multi-tenant context (`context_manager.py`), usage tracking, middleware — reads per-request headers (`x-user-id`, `x-sap-system-id`, `x-team-id`)
- `config/settings.py`: Pydantic-based settings, all config via environment variables
- `sap_types/sap_types.py`: Shared type definitions for all SAP operations
- `utils/`: Security (`sanitize_for_xml`, `sanitize_for_logging`), structured logging, XML parsing (`defusedxml`)

## Request Flow

```
MCP Tool Call
  → tool_handlers.py (_get_sap_client_*)
  → Auth context (principal propagation or keychain)
  → SAPADTClient (HTTP + CSRF + session mgmt)
  → Specialized handler (class/CDS/behavior/service)
  → SAP ADT REST API (XML over HTTP/HTTPS)
  → Parse XML response → return MCP result
```

## Key Configuration (`.env`)

| Variable | Purpose |
|---|---|
| `SAP_HOST` | SAP hostname (optionally with port) |
| `SAP_CLIENT` | SAP client number |
| `SAP_USERNAME` / `SAP_PASSWORD` | Credentials |
| `SAP_SECURE` | Use HTTPS |
| `SSL_VERIFY` | Verify SSL certs |
| `CREDENTIAL_PROVIDER` | `env`, `keychain`, `interactive`, `aws_secrets` |
| `ENABLE_ENTERPRISE_MODE` | Multi-tenant features |
| `ENABLE_PRINCIPAL_PROPAGATION` | Certificate-based auth |
| `CA_CERT_PATH` / `CA_KEY_PATH` | CA cert paths for principal propagation |
| `SERVER_HOST` / `SERVER_PORT` | MCP server bind (default `0.0.0.0:8000`) |

## Important Patterns

**XML handling**: All SAP ADT communication uses XML. Use `sanitize_for_xml()` from `utils/security.py` before inserting user content into XML payloads. Use `defusedxml` (never stdlib `xml`) for parsing SAP responses.

**Transport requests**: Most write operations accept a `transport_request` parameter — check existing handlers (e.g., `service_binding`, `service_definition`) for the correct pattern when adding new ones.

**CSRF tokens**: The `SAPADTClient` manages CSRF token lifecycle automatically; handlers do not need to handle this.

**SAP object types**: The `sap_types/sap_types.py` module defines type strings used in ADT API paths (e.g., `CLAS`, `PROG`, `INTF`, `DDLS`, `BDEF`, `SRVD`, `SRVB`).
