# PG&E ABAP MCP Server — Technical Reference

Complete reference for deployment, infrastructure, certificate management, identity integration, and SAP configuration.

---

## Table of Contents

### Part 1: Deployment Architecture
1. [System Overview](#system-overview)
2. [Infrastructure Components](#infrastructure-components)
3. [Terraform Configuration](#terraform-configuration)
4. [Secrets and Parameters](#secrets-and-parameters)

### Part 2: Certificate Management
5. [Principal Propagation Overview](#principal-propagation-overview)
6. [Certificate Architecture](#certificate-architecture)
7. [Generating Certificates](#generating-certificates)
8. [Certificate Rotation](#certificate-rotation)

### Part 3: Identity & Authentication
9. [Identity Sources](#identity-sources)
10. [Portkey Identity Forwarding — Primary Production Path](#portkey-identity-forwarding--primary-production-path)
11. [OAuth Direct Flow — Alternative](#oauth-direct-flow--alternative)
12. [LANID Extraction Logic](#lanid-extraction-logic)

### Part 4: SAP Configuration
13. [SAP Systems Configuration](#sap-systems-configuration)
14. [STRUST Certificate Import](#strust-certificate-import)
15. [User Mapping](#user-mapping)
16. [Authorization Objects](#authorization-objects)

### Part 5: Utility Scripts
17. [Deployment Scripts](#deployment-scripts)
18. [Certificate Scripts](#certificate-scripts)
19. [AWS Resource Scripts](#aws-resource-scripts)
20. [Typical Workflows](#typical-workflows)
21. [Troubleshooting](#troubleshooting)

---

# PART 1: DEPLOYMENT ARCHITECTURE

---

## System Overview

The ABAP MCP Server runs on AWS ECS Fargate. All user traffic routes through the PG&E AI Gateway (Portkey), which authenticates users via PG&E SSO and forwards their identity to the MCP server via the `X-User-Claims` header. The server derives the user's LANID from that header, generates an ephemeral X.509 certificate with `CN=<LANID>`, and uses it for TLS client authentication to SAP — enabling per-user accountability without shared credentials.

```
┌─────────────────────────────────────────────────────────────────┐
│  MCP Client (Kiro IDE / Amazon Q)                               │
│  mcp.json → https://mcp-aws-ai-gateway.nonprod.pge.com/        │
│                abap-mcp-server/mcp                              │
└─────────────────────────────┬───────────────────────────────────┘
                              │ HTTPS + MCP Protocol
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Portkey AI Gateway (MCP Registry)                              │
│  • Authenticates user via PG&E SSO                             │
│  • Forwards identity via X-User-Claims header:                  │
│    {"email":"avrg@pge.com","sub":"...","name":"...","groups":[]}│
│  • Routes to: https://abap-mcp-server.nonprod.pge.com/mcp      │
└─────────────────────────────┬───────────────────────────────────┘
                              │ HTTPS + X-User-Claims header
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  ABAP MCP Server (ECS Fargate)                                  │
│  Internal ALB: https://abap-mcp-server.nonprod.pge.com         │
│  • Reads X-User-Claims → extracts email claim                   │
│  • LANID: avrg@pge.com → AVRG  (email local part, uppercase)   │
│  • Generates ephemeral X.509 cert: CN=AVRG, valid 5 min        │
│  • Connects to SAP via TLS client authentication                 │
└─────────────────────────────┬───────────────────────────────────┘
                              │ HTTPS + TLS client cert (CN=AVRG)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  SAP Systems (DV8 · MS1 · MD1)                                  │
│  • STRUST: validates certificate signature against trusted CA   │
│  • CERTRULE / SU01 Login Type E: CN=AVRG → SAP user AVRG       │
│  • Executes ADT operation under SAP user AVRG                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Infrastructure Components

| Component | Details |
|-----------|---------|
| **ECS Cluster** | Fargate, 512 CPU / 1024 MB, `abap-mcp-server-Dev` |
| **ALB** | Internal HTTPS (443), ACM certificate, health check `/health` |
| **Route53** | Private hosted zone: `abap-mcp-server.nonprod.pge.com` |
| **Secrets Manager** | CA cert+key, OAuth client secret, JWT signing key |
| **SSM Parameter Store** | SAP endpoints (YAML), user exceptions (YAML) |
| **CloudWatch** | Log group `/ecs/abap-mcp-server-Dev`, 30-day retention |
| **IAM** | Task role (runtime), execution role (startup), least-privilege |
| **ECR** | `064160142714.dkr.ecr.us-west-2.amazonaws.com/abap-mcp-server` |
| **Terraform Cloud** | Org `pgetech`, workspace `abap-mcp-server-terraform` |

---

## Terraform Configuration

All infrastructure is managed via Terraform Cloud. The `terraform/` directory contains the configuration. No defaults exist in `variables.tf` — all values must be set in `terraform.tfvars`.

**Key design decisions:**
- Secrets referenced by **name** (not ARN) — cleaner config, no circular dependencies
- SSM parameters created via scripts, not Terraform resources
- OAuth infrastructure (Entra ID app, Cognito User Pool) managed externally — Terraform only references existing resources
- No Cognito module — the Cognito User Pool was created outside Terraform by a separate team

### terraform.tfvars Structure

```hcl
# AWS Account
region       = "us-west-2"
environment  = "Dev"
project_name = "abap-mcp-server"
account_num  = "064160142714"
aws_role     = "CloudAdmin"

# Multi-account Route53 (DNS record lives in a different AWS account)
account_num_r53 = "514712703977"
aws_r53_role    = "TFCBR53Role"

# Networking
vpc_id             = "vpc-0f991a507e8e58aa1"
private_subnet_ids = ["subnet-...", "subnet-...", "subnet-..."]

# Container image (updated by build-and-push-docker.sh)
container_image  = "064160142714.dkr.ecr.us-west-2.amazonaws.com/abap-mcp-server:YYYYMMDDHHMMSS"
container_cpu    = 512
container_memory = 1024
desired_count    = 1

# Application features
enable_enterprise_mode       = true
enable_principal_propagation = true
enable_oauth_flow            = true
credential_provider          = "aws_secrets"
ssl_verify                   = "true"

# Secrets (managed externally, referenced by name only)
ca_secret_name              = "mcp/abap-mcp-server/ca-certificate"
oauth_secret_name           = "mcp/abap-mcp-server/oauth-credentials"
jwt_signing_key_secret_name = "mcp/abap-mcp-server/jwt-signing-key"

# SSM Parameters (created via scripts/create-aws-parameters.sh)
sap_endpoints_parameter   = "/mcp/abap-mcp-server/sap-endpoints"
user_exceptions_parameter = "/mcp/abap-mcp-server/user-exceptions"

# OAuth / OIDC (Microsoft Entra ID — app managed by separate team)
oauth_issuer         = "https://login.microsoftonline.com/<tenant-id>/v2.0"
oauth_auth_endpoint  = "https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize"
oauth_token_endpoint = "https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token"
oauth_client_id      = "128a32b7-358e-4f9d-915d-2dd7d7d34bbb"
server_base_url      = "https://abap-mcp-server.nonprod.pge.com"
```

### Deploying a New Image

```bash
# Build, tag with timestamp, push to ECR, auto-update terraform.tfvars and commit
./scripts/build-and-push-docker.sh

# Push commit → Terraform Cloud detects change → auto-deploys
git push origin dev
```

Monitor deployment:
```bash
# Terraform Cloud run
https://app.terraform.io/app/pgetech/workspaces/abap-mcp-server-terraform

# ECS container logs
aws logs tail /ecs/abap-mcp-server-Dev --follow --region us-west-2
```

---

## Secrets and Parameters

### AWS Secrets Manager

All secrets are created and managed manually via scripts (not Terraform resources).

| Secret Name | Format | Purpose |
|-------------|--------|---------|
| `mcp/abap-mcp-server/ca-certificate` | `{"ca_certificate":"...","ca_private_key":"..."}` | Sign ephemeral certs |
| `mcp/abap-mcp-server/oauth-credentials` | `{"client_secret":"..."}` | OAuth token exchange |
| `mcp/abap-mcp-server/jwt-signing-key` | `{"jwt_signing_key":"..."}` | Session persistence across restarts |
| `mcp/abap-mcp-server/DV8` | `{"SAP_USERNAME":"...","SAP_PASSWORD":"..."}` | Per-system static credentials |
| `mcp/abap-mcp-server/MS1` | `{"SAP_USERNAME":"...","SAP_PASSWORD":"..."}` | Per-system static credentials |
| `mcp/abap-mcp-server/MD1` | `{"SAP_USERNAME":"...","SAP_PASSWORD":"..."}` | Per-system static credentials |

```bash
./scripts/create-ca-secret.sh        # Upload CA certificate + private key
./scripts/create-oauth-secret.sh     # Upload OAuth client secret
./scripts/create-jwt-secret.sh       # Generate and upload JWT signing key
```

### SSM Parameter Store

| Parameter | Format | Purpose |
|-----------|--------|---------|
| `/mcp/abap-mcp-server/sap-endpoints` | YAML | SAP system host/port/client for all systems |
| `/mcp/abap-mcp-server/user-exceptions` | YAML | LANID override mappings |

```bash
./scripts/create-aws-parameters.sh   # Creates or updates both parameters
```

**SAP Endpoints YAML format:**
```yaml
endpoints:
  DV8:
    host: sapdv8db1.comp.pge.com
    port: 1443
    client: "120"
    description: SAP Development System DV8 Client 120
  MS1:
    host: vhpgxms1ci.s4hc.pge.com
    port: 44300
    client: "100"
    description: SAP Development System MS1 Client 100
  MD1:
    host: vhpgxmd1ci.s4hc.pge.com
    port: 44300
    client: "100"
    description: SAP Development System MD1 Client 100
```

**User Exceptions YAML format:**
```yaml
exceptions: {}
# Uncomment and add overrides when email username ≠ SAP username:
# exceptions:
#   john.doe@pge.com: JDOE_SAP
#   contractor@external.com: CUSER1
```

### ECS Task Definition — Environment Variables

Terraform injects these into the task definition from Secrets Manager and `terraform.tfvars`:

| Variable | Source |
|----------|--------|
| `CA_CERT` | Secrets Manager field: `mcp/abap-mcp-server/ca-certificate:ca_certificate` |
| `CA_KEY` | Secrets Manager field: `mcp/abap-mcp-server/ca-certificate:ca_private_key` |
| `OAUTH_CLIENT_SECRET` | Secrets Manager field: `mcp/abap-mcp-server/oauth-credentials:client_secret` |
| `JWT_SIGNING_KEY` | Secrets Manager field: `mcp/abap-mcp-server/jwt-signing-key:jwt_signing_key` |
| `SAP_ENDPOINTS_PARAMETER` | `/mcp/abap-mcp-server/sap-endpoints` |
| `USER_EXCEPTIONS_PARAMETER` | `/mcp/abap-mcp-server/user-exceptions` |
| `OAUTH_ISSUER` | From `terraform.tfvars` |
| `OAUTH_CLIENT_ID` | From `terraform.tfvars` |
| `OAUTH_AUTH_ENDPOINT` | From `terraform.tfvars` |
| `OAUTH_TOKEN_ENDPOINT` | From `terraform.tfvars` |
| `SERVER_BASE_URL` | From `terraform.tfvars` |
| `SSL_VERIFY` | From `terraform.tfvars` |

---

# PART 2: CERTIFICATE MANAGEMENT

---

## Principal Propagation Overview

Principal Propagation is the mechanism by which each user's personal identity is propagated to SAP so that every operation executes under their individual SAP account — not a shared service account.

**How it works:**
1. User's email arrives in `X-User-Claims` header (forwarded by Portkey after SSO)
2. Server extracts LANID: `avrg@pge.com` → `AVRG`
3. Server generates an ephemeral X.509 certificate with `CN=AVRG`, signed by the trusted CA, valid 5 minutes
4. Server presents the certificate for TLS client authentication to SAP
5. SAP validates the certificate against the CA imported in STRUST, then maps `CN=AVRG` to SAP user `AVRG` via CERTRULE or SU01 Login Type E

**Benefits:**
- Individual user accountability in SAP Security Audit Log
- SAP authorization objects enforced per user (same as direct SAP GUI)
- No shared service accounts
- No password storage or transmission

---

## Certificate Architecture

```
CA Certificate  (RSA 4096-bit · 10-year validity)
  Stored in:  AWS Secrets Manager — mcp/abap-mcp-server/ca-certificate
  Public cert: imported to SAP STRUST (one-time, per system, per port)
  Private key: signs all ephemeral certificates
       │
       │ signs
       ▼
Ephemeral Client Certificate  (RSA 2048-bit · 5-minute validity)
  CN = <LANID>   (e.g., CN=AVRG)
  Key Usage:           Digital Signature, Key Encipherment
  Extended Key Usage:  Client Authentication
  Storage:             In-memory only — never persisted
  Renewal:             Auto-renewed 1 minute before expiry
```

| Property | CA Certificate | Ephemeral Certificate |
|----------|---------------|----------------------|
| Algorithm | RSA 4096-bit | RSA 2048-bit |
| Validity | 10 years | 5 minutes |
| Subject CN | `ABAP MCP CA` | `<LANID>` (e.g., `AVRG`) |
| Storage | AWS Secrets Manager | In-memory only |
| Rotation | Manual (scripts) | Automatic per request |

---

## Generating Certificates

### Step 1: Generate CA Certificate

```bash
./scripts/generate-ca-certificates.sh
```

Creates:
- `certificates/abap-mcp-ca-cert.pem` — public certificate (committed to repo, safe to share)
- `certificates/abap-mcp-ca-key.pem` — private key (git-ignored, keep secure)

Inspect the certificate:
```bash
openssl x509 -in certificates/abap-mcp-ca-cert.pem -text -noout \
  | grep -E "Subject:|Issuer:|Not Before:|Not After:"
```

### Step 2: Upload to AWS Secrets Manager

```bash
./scripts/create-ca-secret.sh
```

Creates secret `mcp/abap-mcp-server/ca-certificate`:
```json
{
  "ca_certificate": "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----",
  "ca_private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
}
```

### Step 3: Share Public Certificate with SAP Basis

Provide `certificates/abap-mcp-ca-cert.pem` to the SAP Basis team. Email template:

```
Subject: CA Certificate for ABAP MCP Server — Principal Propagation Setup

Team,

Please import the attached CA certificate into STRUST for the SSL Client (Standard) PSE.
This certificate is used to validate short-lived client certificates generated by the MCP server.

Certificate Details:
  CN:        ABAP MCP CA
  Algorithm: RSA 4096-bit
  Validity:  10 years

Target Systems and Ports:
  DV8  — sapdv8db1.comp.pge.com:1443
  MS1  — vhpgxms1ci.s4hc.pge.com:44300
  MD1  — vhpgxmd1ci.s4hc.pge.com:44300

The MCP server will generate client certificates (5-minute validity) signed by this CA.
Each certificate has CN=<LANID> (e.g., CN=AVRG for user avrg@pge.com).

Please configure either:
  Option A — SU01 Login Type E (per user, SNC tab): maps cert CN directly to SAP username
  Option B — CERTRULE (central rule): maps any CN=* to the CN value as SAP username

A sample ephemeral certificate is attached (sample-ephemeral-cert-AVRG.pem) for testing
STRUST and CERTRULE before go-live.

Thanks,
[Your name]
```

### Step 4: Generate Sample Certificate for Basis Testing

To produce a sample ephemeral certificate for SAP Basis to verify STRUST/CERTRULE:

```bash
export CA_CERT_PATH=./certificates/abap-mcp-ca-cert.pem
export CA_KEY_PATH=./certificates/abap-mcp-ca-key.pem
export SAVE_SAMPLE_CERT_DIR=./certificates
python src/aws_abap_accelerator/enterprise_main.py
```

On startup, the server saves `certificates/sample-ephemeral-cert-<LANID>.pem` and `certificates/sample-ephemeral-key-<LANID>.pem`. SAP Basis can use these to test the certificate chain without needing the full MCP flow running.

---

## Certificate Rotation

CA certificates have 10-year validity. Coordinate rotation 6 months before expiry.

```bash
# 1. Generate new CA
./scripts/generate-ca-certificates.sh

# 2. Upload to Secrets Manager (overwrites existing secret)
./scripts/create-ca-secret.sh

# 3. Send new public cert to SAP Basis
#    They import it alongside the old cert during the transition window

# 4. Force ECS redeployment (new tasks load the new CA from Secrets Manager)
aws ecs update-service \
  --cluster abap-mcp-server-Dev-cluster \
  --service abap-mcp-server-Dev-service \
  --force-new-deployment \
  --region us-west-2 \
  --profile CloudAdminNonProdAccess-064160142714

# 5. After confirming new CA is working, SAP Basis removes the old CA from STRUST
```

Ephemeral certificates are auto-rotated every 5 minutes — no manual action needed.

---

# PART 3: IDENTITY & AUTHENTICATION

---

## Identity Sources

The server resolves user identity from request headers in priority order (`auth/iam_identity_validator.py`):

| Priority | Source | Header | Use Case |
|----------|--------|--------|----------|
| 1 | IAM Identity Center JWT | `Authorization: Bearer <token>` | Amazon Q Developer |
| 2 | ALB OIDC | `x-amzn-oidc-identity` | ALB-managed OIDC |
| **3** | **Portkey Claims** | **`X-User-Claims` (JSON)** | **Production — Kiro via Portkey** |
| 4 | Dev fallback | `x-user-id` | Local development only |

All paths converge: the extracted email → LANID → ephemeral certificate CN.

---

## Portkey Identity Forwarding — Primary Production Path

The production deployment uses Portkey's `user_identity_forwarding` feature. Portkey authenticates the user (via PG&E SSO) and injects their identity claims as a JSON header on every forwarded request. The MCP server reads this header — no OAuth redirect flow needed.

### X-User-Claims Header

Portkey injects:
```http
X-User-Claims: {"sub":"abc-uuid","email":"avrg@pge.com","name":"Antonio Robles","groups":["ABAP-Developers"],"workspace_id":"...","organisation_id":"..."}
```

Server reads it (`auth/iam_identity_validator.py:107-123`):
```python
claims_header = headers.get('x-user-claims') or headers.get('X-User-Claims')
claims = json.loads(claims_header)
email = claims.get('email') or claims.get('sub')
# → identity: {login_identifier: "avrg@pge.com", source: "portkey-claims-header"}
```

LANID derived → ephemeral cert generated → SAP connection established per user.

### Portkey MCP Registry Configuration

In Portkey's MCP Registry, the `abap-mcp-server` entry is configured as follows:

```
Security & Authentication:
  Auth Type: none
  (Portkey handles authentication — the MCP server trusts the forwarded claims)

Configuration:
  Server URL: https://abap-mcp-server.nonprod.pge.com/mcp
  Transport:  Streamable HTTP

Advanced Configuration (JSON):
{
  "user_identity_forwarding": {
    "method": "claims_header",
    "header_name": "X-User-Claims",
    "include_claims": [
      "sub",
      "email",
      "name",
      "groups",
      "workspace_id",
      "organisation_id"
    ]
  }
}
```

**This pattern is replicable for any MCP server** behind the Portkey gateway. Any MCP server that reads the `X-User-Claims` header can obtain the authenticated user's identity without implementing its own OAuth flow. The Portkey configuration above can be applied to any MCP Registry entry.

### Kiro Configuration

Users configure Kiro to connect through the Portkey gateway path for this MCP server.

**`~/.kiro/mcp.json`** (macOS/Linux) or **`%USERPROFILE%\.kiro\mcp.json`** (Windows):

```json
{
  "mcpServers": {
    "abap-mcp-server": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/abap-mcp-server/mcp"
    }
  }
}
```

Kiro passes through the Portkey gateway, which routes to `https://abap-mcp-server.nonprod.pge.com/mcp` and injects `X-User-Claims`.

**Multiple MCP servers — example for enterprise integration suite:**
```json
{
  "mcpServers": {
    "abap-mcp-server": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/abap-mcp-server/mcp"
    },
    "salesforce-mcp": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/salesforce-mcp/mcp"
    },
    "servicenow-mcp": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/servicenow-mcp/mcp"
    }
  }
}
```

Each server listed in Portkey MCP Registry independently configures `user_identity_forwarding`. Kiro discovers all servers' tools at startup and routes queries to the appropriate server based on context.

**Amazon Q Developer** (`~/.aws/amazonq/mcp.json`):
```json
{
  "mcpServers": {
    "abap-mcp-server": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/abap-mcp-server/mcp"
    }
  }
}
```

---

## OAuth Direct Flow — Alternative

When `ENABLE_OAUTH_FLOW=true` and a client connects directly to the MCP server (bypassing Portkey), the server handles OAuth itself via `server/fastmcp_oauth_integration.py`.

**Flow:**
```
MCP Client → MCP Server → 401 + OAuth metadata
→ Client redirects user to OAuth provider (Entra ID / Cognito)
→ User authenticates → authorization code issued
→ Client exchanges code for JWT access token
→ Client sends Bearer token on subsequent requests
→ Server extracts email from JWT → LANID → ephemeral cert
```

**Supported providers:**
- **Microsoft Entra ID** — extracts identity from `preferred_username` JWT claim
- **AWS Cognito** — calls UserInfo endpoint to resolve `sub` → email
- **Okta** — supported with RFC 8707 `resource` parameter stripped

**Applied patches** (`server/fastmcp_oauth_integration.py`):
- Okta: removes `resource` parameter (not supported — causes `access_denied`)
- Kiro: injects `client_id` in token exchange (Kiro OAuth client bug)
- Entra ID: auto-detects token audience from issuer URL
- SSL: respects `SSL_VERIFY` env var via `httpx.AsyncClient.__init__` monkey-patch (line 351)

The OAuth flow is used when the MCP client connects directly (e.g., testing without Portkey, or Amazon Q Developer with IAM Identity Center tokens). The Portkey `X-User-Claims` path takes priority in production.

---

## LANID Extraction Logic

The LANID is derived algorithmically from the email address (`auth/principal_propagation.py:295-300`):

```python
# avrg@pge.com       → AVRG
# john.doe@pge.com   → JOHN.DOE  (preserves full local part, uppercase)
if '@' in login_identifier:
    cn_value = login_identifier.split('@')[0].upper()
else:
    cn_value = login_identifier.upper()
```

The CN value is used directly as the SAP username. SAP must have the corresponding user configured (via CERTRULE or SU01 Login Type E).

**CN length limit:** SAP X.509 CN field is limited to 64 characters. Values exceeding this are truncated with a warning in the logs.

**Overrides:** When the algorithmic extraction doesn't produce the correct SAP username, add an entry to SSM Parameter Store `/mcp/abap-mcp-server/user-exceptions`:

```yaml
exceptions:
  john.doe@pge.com: JDOE_SAP       # email → override LANID
  contractor@external.com: CUSER1   # external contractor mapping
```

---

# PART 4: SAP CONFIGURATION

---

## SAP Systems Configuration

SAP endpoint configurations are stored in SSM Parameter Store at `/mcp/abap-mcp-server/sap-endpoints`. The server reads this parameter at startup. System selection at runtime uses the `sap_system_id` tool parameter or the `x-sap-system-id` request header.

**Current PG&E systems:**

| System ID | Host | Port | Client | Description |
|-----------|------|------|--------|-------------|
| `DV8` | sapdv8db1.comp.pge.com | 1443 | 120 | Development |
| `MS1` | vhpgxms1ci.s4hc.pge.com | 44300 | 100 | S/4HANA Test |
| `MD1` | vhpgxmd1ci.s4hc.pge.com | 44300 | 100 | S/4HANA Dev |

**Adding a new system:**

1. Edit `scripts/create-aws-parameters.sh` — add the new system to the YAML
2. Run the script:
   ```bash
   ./scripts/create-aws-parameters.sh
   ```
3. Create a credentials secret for the new system:
   ```bash
   aws secretsmanager create-secret \
     --name mcp/abap-mcp-server/QS1 \
     --secret-string '{"SAP_USERNAME":"MCRPC_USER","SAP_PASSWORD":"..."}' \
     --region us-west-2 \
     --profile CloudAdminNonProdAccess-064160142714
   ```
4. Restart ECS service (new tasks read updated parameter on startup)
5. Import CA certificate to STRUST on the new system

---

## STRUST Certificate Import

**Transaction:** STRUST  
**Perform on:** Each SAP system (DV8, MS1, MD1), for each port used (1443 or 44300).

1. Navigate to **SSL Client (Standard)** node in STRUST
2. Click the **pencil (edit)** icon to enter edit mode
3. Click **Import certificate**
4. Select `certificates/abap-mcp-ca-cert.pem`
5. Click **Add to Certificate List**
6. Click **Save** (floppy disk icon)
7. Transaction **SMICM** → Administration → ICM → Exit Soft → Yes (reload SSL context)

**Verify the import:**
```bash
# Test TLS handshake presenting a sample ephemeral certificate
openssl s_client \
  -connect sapdv8db1.comp.pge.com:1443 \
  -cert certificates/sample-ephemeral-cert-AVRG.pem \
  -key certificates/sample-ephemeral-key-AVRG.pem \
  -CAfile certificates/abap-mcp-ca-cert.pem \
  -verify_return_error
```

A successful TLS handshake followed by an SAP response confirms the CA is trusted.

---

## User Mapping

The certificate CN (which equals the user's LANID) is mapped to the SAP username via one of two methods:

### Method 1: SU01 Login Type E (Recommended for most users)

1. Transaction **SU01** → open the user record (e.g., `AVRG`)
2. Tab **SNC**
3. **Login Type** = `E` (External Identification)
4. **SNC Name** = leave empty
5. Save

**Result:** SAP maps certificate CN directly to the username. `CN=AVRG` authenticates as SAP user `AVRG`.

### Method 2: CERTRULE (Centralized Rule)

Transaction **CERTRULE** (or SM30 → maintenance view `VUSREXTID`):

| Field | Value |
|-------|-------|
| Rule Name | `MCP_CN_MAPPING` |
| Certificate Attribute | `CN` |
| Attribute Value | `*` (wildcard — any CN) |
| Login Data | Use CN value as SAP username |

Use CERTRULE when managing many users centrally or when prefix/suffix transformations are needed.

---

## Authorization Objects

After certificate authentication, SAP enforces standard authorization objects — the same as a direct SAP GUI login. Users have exactly the permissions their SAP account has.

| MCP Tool Operation | Authorization Object | Required Activity |
|-------------------|---------------------|-------------------|
| Read source code | `S_DEVELOP` | OBJTYPE=*, ACTVT=03 |
| Modify source code | `S_DEVELOP` | OBJTYPE=*, ACTVT=02 |
| Activate objects | `S_DEVELOP` | OBJTYPE=*, ACTVT=01 |
| Transport requests | `S_TRANSPRT` | TTYPE=*, ACTVT=02 |
| Run ATC checks | `S_ATC` | ACTVT=03 |
| Execute unit tests | `S_DEVELOP` | OBJTYPE=*, ACTVT=16 |

**Recommended role:** Create `Z_MCP_DEVELOPER` in PFCG containing the above authorization objects and assign it to users who need MCP access.

---

# PART 5: UTILITY SCRIPTS

---

## Deployment Scripts

### `scripts/build-and-push-docker.sh`

Builds Docker image from `Dockerfile.simple`, tags with timestamp (`YYYYMMDDHHMMSS`), pushes to ECR, auto-updates `terraform/terraform.tfvars` with the new `container_image`, and commits the change.

```bash
./scripts/build-and-push-docker.sh
# → Updates terraform.tfvars
# → git commit + git push origin dev
# → Terraform Cloud auto-deploys
```

### `scripts/cleanup-ecr.sh`

Deletes all images from the ECR repository. **Only use when tearing down infrastructure.**

```bash
./scripts/cleanup-ecr.sh
```

---

## Certificate Scripts

### `scripts/generate-ca-certificates.sh`

Generates a self-signed RSA 4096-bit CA certificate valid for 10 years.

```bash
./scripts/generate-ca-certificates.sh
# Creates: certificates/abap-mcp-ca-cert.pem  (committed to repo)
#          certificates/abap-mcp-ca-key.pem    (git-ignored — keep secure)
```

### `scripts/create-ca-secret.sh`

Reads both PEM files and uploads them to AWS Secrets Manager as `mcp/abap-mcp-server/ca-certificate`.

```bash
./scripts/create-ca-secret.sh
```

---

## AWS Resource Scripts

### `scripts/create-aws-parameters.sh`

Creates or updates both SSM Parameter Store entries with PG&E SAP system configurations.

```bash
./scripts/create-aws-parameters.sh
# Creates/updates:
#   /mcp/abap-mcp-server/sap-endpoints
#   /mcp/abap-mcp-server/user-exceptions
```

Edit the YAML content inside the script to update system configurations before running.

### `scripts/create-oauth-secret.sh`

Prompts for the OAuth client secret from Microsoft Entra ID and stores it in Secrets Manager.

```bash
./scripts/create-oauth-secret.sh
# Prompts: "Enter OAuth Client Secret:"
# Creates: mcp/abap-mcp-server/oauth-credentials  → {"client_secret": "..."}
```

### `scripts/create-jwt-secret.sh`

Generates a 64-character hex key and uploads it to Secrets Manager for signing OAuth session tokens (enables session persistence across ECS task restarts).

```bash
./scripts/create-jwt-secret.sh
# Creates: mcp/abap-mcp-server/jwt-signing-key  → {"jwt_signing_key": "..."}
```

---

## Typical Workflows

### Initial Setup (One-Time)

```bash
# 1. Generate CA certificate
./scripts/generate-ca-certificates.sh

# 2. Upload CA to AWS Secrets Manager
./scripts/create-ca-secret.sh

# 3. Create SAP endpoint parameters in SSM
./scripts/create-aws-parameters.sh

# 4. Upload OAuth client secret
./scripts/create-oauth-secret.sh

# 5. Generate JWT signing key
./scripts/create-jwt-secret.sh

# 6. Build and push first Docker image
./scripts/build-and-push-docker.sh

# 7. Push to trigger Terraform Cloud deployment
git push origin dev

# 8. Share CA certificate with SAP Basis for STRUST import
# See: Part 2 — Generating Certificates, Steps 3 and 4
```

### Code Update Deployment

```bash
# Build, update terraform.tfvars, commit, push
./scripts/build-and-push-docker.sh
git push origin dev
# Terraform Cloud deploys automatically
```

### Add a New SAP System

```bash
# 1. Edit scripts/create-aws-parameters.sh — add new system to YAML
# 2. Update parameters
./scripts/create-aws-parameters.sh
# 3. Create system credentials
aws secretsmanager create-secret \
  --name mcp/abap-mcp-server/NEW1 \
  --secret-string '{"SAP_USERNAME":"MCRPC","SAP_PASSWORD":"..."}' \
  --region us-west-2
# 4. Import CA cert to STRUST on the new system
# 5. Restart ECS service to reload the updated parameter
aws ecs update-service \
  --cluster abap-mcp-server-Dev-cluster \
  --service abap-mcp-server-Dev-service \
  --force-new-deployment \
  --region us-west-2
```

---

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| `AccessDeniedException` on SAP endpoints load | IAM task role missing `ssm:GetParameter` | Check task role policy in IAM console |
| OAuth redirect loop | `server_base_url` doesn't match Entra ID redirect URI | Verify `server_base_url` = `https://abap-mcp-server.nonprod.pge.com` matches app registration |
| Certificate auth fails — SAP 401 | CA not imported to STRUST on this system/port | Import `abap-mcp-ca-cert.pem` to STRUST, restart SMICM |
| Wrong user in SAP audit log | LANID mismatch between cert CN and SAP username | Add override in `/mcp/abap-mcp-server/user-exceptions` |
| `No user identity found` | Missing or malformed `X-User-Claims` header | Verify Portkey MCP Registry `user_identity_forwarding` configuration |
| SAP 401 after valid cert TLS | CERTRULE/SU01 not configured for this user | Set Login Type E in SU01 SNC tab, or add CERTRULE entry |
| `Failed to connect to SAP ... with certificate auth` | SAP can't validate cert / session issue | Check STRUST cert list, verify port, check SAP logs in SM21 |
| `SSL: CERTIFICATE_VERIFY_FAILED` | Corporate proxy or self-signed SAP cert | Set `ssl_verify = "false"` in `terraform.tfvars` (non-prod only) |

**Useful log patterns** (CloudWatch `/ecs/abap-mcp-server-Dev`):
```
Using Portkey X-User-Claims for identity: <email>
Certificate CN derived: avrg@pge.com -> AVRG
Generated ephemeral certificate: CN=AVRG
Failed to connect to SAP system ...
```

---

**Last Updated:** 2026-04-18  
**Maintained By:** PG&E AI Development Team — avrg@pge.com  
**Terraform Cloud:** https://app.terraform.io/app/pgetech/workspaces/abap-mcp-server-terraform  
**MCP Endpoint:** https://abap-mcp-server.nonprod.pge.com/mcp  
**CloudWatch:** `/ecs/abap-mcp-server-Dev`
