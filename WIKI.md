# ABAP MCP Server — PG&E Internal Wiki

**SAP ABAP Integration via Kiro IDE and Amazon Q Developer**

---

## Table of Contents

1. [What Is This?](#what-is-this)
2. [Current Status](#current-status)
3. [How It Works](#how-it-works)
4. [PG&E AI Gateway (Portkey) — Why It Matters](#pge-ai-gateway-portkey--why-it-matters)
5. [Portkey Identity Forwarding — The Key Innovation](#portkey-identity-forwarding--the-key-innovation)
6. [Principal Propagation — Individual SAP Authentication](#principal-propagation--individual-sap-authentication)
7. [Getting Started — Kiro IDE](#getting-started--kiro-ide)
8. [Configuring Multiple MCP Servers in Kiro](#configuring-multiple-mcp-servers-in-kiro)
9. [Getting Started — Amazon Q Developer](#getting-started--amazon-q-developer)
10. [What You Can Do with the ABAP MCP Server](#what-you-can-do-with-the-abap-mcp-server)
11. [For SAP Basis Teams](#for-sap-basis-teams)
12. [Security & Compliance](#security--compliance)
13. [Project History](#project-history)
14. [FAQ](#faq)
15. [Glossary](#glossary)
16. [Contact & Support](#contact--support)

---

## What Is This?

The **ABAP MCP Server** lets AI-powered development tools — primarily **Kiro IDE** — interact directly with PG&E's SAP ABAP systems through a secure, standardized interface. Developers ask natural language questions about ABAP code, generate and refactor code, run tests and quality checks, and manage transport requests — all without leaving their AI tool.

**What MCP means:** Model Context Protocol is an open standard (created by Anthropic) that lets any MCP-enabled AI tool connect to any MCP server. We build one server; it works with Kiro, Amazon Q Developer, Claude Desktop, and any future MCP-compatible tool.

**What PG&E added on top of the AWS reference implementation:**
- Full AWS infrastructure (ECS Fargate, Terraform, Terraform Cloud deployment)
- Portkey AI Gateway integration with identity forwarding
- Principal propagation via ephemeral X.509 certificates (per-user SAP authentication)
- Support for multiple SAP systems (DV8, MS1, MD1) with per-user identity
- Stateless HTTP transport (`stateless_http=True`) for Portkey/streamable-HTTP compatibility

---

## Current Status

**Deployed and operational.** The MCP Server runs on AWS ECS Fargate at `https://abap-mcp-server.nonprod.pge.com/mcp`, accessible via Portkey AI Gateway.

**What's working:**
- ✅ 15+ SAP development tools (read/write source, run tests, activate objects, ATC checks, transport management)
- ✅ Multi-system support — DV8, MS1, MD1
- ✅ Per-user SAP authentication via Principal Propagation (ephemeral X.509 certificates)
- ✅ Kiro IDE integration via Portkey AI Gateway
- ✅ Amazon Q Developer compatibility
- ✅ Individual user accountability — every SAP operation runs under the user's own LANID
- ✅ Rate limiting, analytics, and cost tracking via Portkey

**Pending (SAP Basis action required):**
- ⏳ STRUST import on each SAP system — CA certificate not yet imported
- ⏳ CERTRULE or SU01 Login Type E configured per user

The MCP server code is complete and deployed. The remaining step is SAP Basis configuring certificate trust on DV8, MS1, and MD1.

---

## How It Works

```
Developer → Kiro IDE
    │
    │  mcp.json URL → Portkey AI Gateway
    ↓
Portkey AI Gateway (mcp-aws-ai-gateway.nonprod.pge.com)
    │  • Authenticates user via PG&E SSO
    │  • Forwards identity: X-User-Claims: {"email":"avrg@pge.com",...}
    ↓
ABAP MCP Server (abap-mcp-server.nonprod.pge.com)
    │  • Reads X-User-Claims → email → LANID: AVRG
    │  • Generates ephemeral certificate: CN=AVRG (valid 5 minutes)
    ↓
SAP System (DV8 / MS1 / MD1)
    │  • STRUST validates certificate against trusted CA
    │  • CERTRULE/SU01: CN=AVRG → SAP user AVRG
    │  • Executes operation under user AVRG
    ↓
Results → MCP Server → Portkey → Kiro
```

No passwords are used for SAP access. The certificate is generated on-demand, valid for only 5 minutes, and tied to the user's LANID.

---

## PG&E AI Gateway (Portkey) — Why It Matters

All AI traffic at PG&E routes through Portkey, the centralized AI Gateway. For the ABAP MCP Server, Portkey provides:

| Feature | Benefit |
|---------|---------|
| **Authentication** | Users authenticate with PG&E SSO once — Portkey handles the OAuth flow |
| **Identity forwarding** | Portkey injects the authenticated user's identity into every MCP request |
| **Rate limiting** | Per-user quotas prevent abuse and control costs |
| **Analytics** | Real-time dashboards: who's using what, how often, at what cost |
| **Request routing** | Routes to the correct MCP server based on registry configuration |
| **Audit logging** | Immutable logs for compliance (SOX, GDPR) |
| **Cost allocation** | Track costs per user, team, department |

**The ABAP MCP Server is accessible only through Portkey.** Direct access to the ALB endpoint requires VPC connectivity and is not exposed to end users.

---

## Portkey Identity Forwarding — The Key Innovation

The most important architectural decision in the PG&E implementation is how user identity reaches the MCP server.

**The problem:** The MCP server needs to know who the user is so it can generate the right certificate for SAP. But the MCP server doesn't want to manage its own OAuth flow — that would mean users having to authenticate separately to Portkey and to the MCP server.

**The solution:** Portkey's `user_identity_forwarding` feature. After Portkey authenticates the user via PG&E SSO, it automatically injects the user's identity claims into every request it forwards to the MCP server, as an `X-User-Claims` JSON header:

```http
X-User-Claims: {
  "sub": "abc-uuid-123",
  "email": "avrg@pge.com",
  "name": "Antonio Robles",
  "groups": ["ABAP-Developers"],
  "workspace_id": "...",
  "organisation_id": "..."
}
```

The MCP server reads this header, extracts the email, derives the LANID (`avrg@pge.com` → `AVRG`), and generates the ephemeral certificate. The user authenticates once with PG&E SSO; everything else is automatic.

### Portkey MCP Registry Configuration

In Portkey's MCP Registry, the entry for `abap-mcp-server` is configured as:

```
Security & Authentication:
  Auth Type: none
  (Portkey handles user authentication; MCP server trusts forwarded claims)

Configuration:
  Server URL: https://abap-mcp-server.nonprod.pge.com/mcp
  Transport:  Streamable HTTP

Advanced Configuration:
{
  "user_identity_forwarding": {
    "method": "claims_header",
    "header_name": "X-User-Claims",
    "include_claims": ["sub", "email", "name", "groups", "workspace_id", "organisation_id"]
  }
}
```

**This pattern applies to any MCP server behind Portkey.** Any MCP server can receive the authenticated user's identity via `X-User-Claims` without implementing its own OAuth flow — just read the header that Portkey injects. This makes adding new MCP servers behind the gateway straightforward: the server registration in Portkey MCP Registry follows the same pattern above, and the server code reads `X-User-Claims`.

---

## Principal Propagation — Individual SAP Authentication

Principal Propagation is the mechanism that ensures every SAP operation runs under the individual user's SAP account, not a shared service account.

### How Ephemeral Certificates Work

1. User's email arrives via `X-User-Claims` header (forwarded by Portkey after SSO)
2. Server extracts LANID: `avrg@pge.com` → `AVRG`
3. Server generates a new X.509 certificate:
   - Subject: `CN=AVRG`
   - Signed by the trusted CA (imported to SAP STRUST)
   - Valid for **5 minutes only**
   - Generated in memory — never written to disk
4. Server presents this certificate during TLS connection to SAP
5. SAP validates the certificate signature against the trusted CA
6. SAP maps `CN=AVRG` to SAP user `AVRG` (via CERTRULE rule or SU01 Login Type E)
7. SAP session established for user AVRG — operation executes under AVRG's authorizations

### Why 5-Minute Certificates?

- If intercepted, the certificate is worthless in under 5 minutes
- No persistent credential storage — the certificate is gone after use
- Auto-renewed transparently — developers never see the renewal

### What SAP Basis Needs to Do (One-Time Per System)

1. **Import CA certificate to STRUST** — `abap-mcp-ca-cert.pem` is provided by the AICE team
2. **Configure user mapping** — either SU01 Login Type E (per user) or CERTRULE (central rule)
3. **Test** using sample ephemeral certificate provided by the AICE team

This is a one-time setup. After it's done, no further Basis involvement is needed for day-to-day operation.

See `README-PGE.md` Part 4 for detailed STRUST and CERTRULE configuration steps.

---

## Getting Started — Kiro IDE

### Prerequisites

- Kiro IDE installed
- PG&E network access (or VPN if remote)
- PG&E SSO credentials (LANID@pge.com)
- SAP Basis has completed STRUST configuration (required for SAP operations)

### Step 1: Configure MCP Server

Edit `~/.kiro/mcp.json` (create it if it doesn't exist):

```json
{
  "powers": {
    "mcpServers": {}
  },
  "mcpServers": {
    "abap-mcp-server": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/abap-mcp-server/mcp"
    }
  }
}
```

**Important:** The URL points to the **Portkey AI Gateway**, not directly to the ABAP MCP Server. All traffic flows through Portkey for authentication and monitoring.

### Step 2: Restart Kiro IDE

Quit Kiro completely and relaunch. Kiro loads `mcp.json` at startup and connects to all configured MCP servers.

### Step 3: Verify Connection

In Kiro chat, type:
```
What tools are available from the ABAP MCP Server?
```

Kiro should list 15+ tools including `aws_abap_cb_get_source`, `aws_abap_cb_update_source`, `aws_abap_cb_run_unit_tests`, etc.

### Step 4: Test with a Real Query

```
Show me all ABAP classes in package ZFIN in DV8
```

If SAP Basis has completed STRUST configuration, this returns the package contents. Otherwise you'll see a certificate authentication error.

### Example Queries

```
Get the source code for class ZCL_INVOICE_HANDLER in DV8

Run unit tests for ZCL_PAYMENT in MS1

Search for ABAP objects containing "invoice" in DV8

Check syntax of class ZCL_NEW_CLASS before activating

Get the transport request list for my user in DV8
```

### Tips

- **Specify the SAP system** — DV8 (development), MS1 (test), MD1 (dev S/4HANA)
- **Use natural language** — Kiro understands ABAP context
- **Chain operations** — "Get source, check syntax, and activate ZCL_MY_CLASS in DV8"

### Troubleshooting

| Issue | Solution |
|-------|----------|
| "Server not found" / "Connection refused" | Verify VPN connected, check mcp.json URL, restart Kiro |
| "Certificate authentication failed" | SAP Basis hasn't completed STRUST setup yet — contact Basis team |
| "Authorization error" | Your SAP user lacks the required authorization object — contact Basis team |
| "Tool not available" | Restart Kiro, ask "What tools are available?" to confirm server connected |
| Slow or no response | Check SAP system status: "Get connection status for DV8" |

---

## Configuring Multiple MCP Servers in Kiro

Kiro supports multiple MCP servers simultaneously. All servers at PG&E are accessed via the same Portkey gateway — each server has its own registry entry.

### Kiro Configuration Format

```json
{
  "powers": {
    "mcpServers": {}
  },
  "mcpServers": {
    "server-name": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/<registry-name>/mcp"
    }
  }
}
```

### PG&E Enterprise Integration Suite Example

```json
{
  "powers": {
    "mcpServers": {}
  },
  "mcpServers": {
    "abap-mcp-server": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/abap-mcp-server/mcp"
    },
    "salesforce-mcp": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/salesforce-mcp/mcp"
    },
    "servicenow-mcp": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/servicenow-mcp/mcp"
    },
    "database-mcp": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/database-mcp/mcp"
    }
  }
}
```

Kiro discovers all servers' tools at startup and routes queries based on context:
- "Show ABAP classes in ZFIN" → `abap-mcp-server`
- "List Salesforce opportunities" → `salesforce-mcp`
- "Create ServiceNow incident" → `servicenow-mcp`

### Guidelines

- Use descriptive kebab-case names matching the Portkey registry name
- Each server behind Portkey uses the same `user_identity_forwarding` pattern — no per-server authentication needed by the user
- 5–10 servers is a practical maximum (Kiro connects to all at startup)
- Restart Kiro after any config change

### Removing a Server

Delete its entry from `mcp.json` and restart Kiro.

---

## Getting Started — Amazon Q Developer

1. Install Amazon Q Developer (VS Code extension or IntelliJ plugin)
2. Edit `~/.aws/amazonq/mcp.json`:

```json
{
  "mcpServers": {
    "abap-mcp-server": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/abap-mcp-server/mcp"
    }
  }
}
```

3. Restart the IDE
4. Open Amazon Q chat and test: "List ABAP packages in DV8"

Amazon Q can also authenticate via IAM Identity Center tokens — in that case the identity is extracted from the `Authorization: Bearer` JWT header directly, without Portkey intermediation.

---

## What You Can Do with the ABAP MCP Server

| Category | Tool | What It Does |
|----------|------|-------------|
| **Browse** | `aws_abap_cb_get_objects` | List all ABAP objects in a package |
| **Browse** | `aws_abap_cb_search_object` | Search for objects by name or pattern |
| **Read** | `aws_abap_cb_get_source` | Retrieve source code of any ABAP object |
| **Write** | `aws_abap_cb_update_source` | Modify source code (with transport request) |
| **Create** | `aws_abap_cb_create_object` | Create new class, interface, CDS view, etc. |
| **Quality** | `aws_abap_cb_check_syntax` | Check syntax without activating |
| **Quality** | `aws_abap_cb_run_atc_check` | Run ATC static analysis checks |
| **Testing** | `aws_abap_cb_run_unit_tests` | Execute ABAP unit tests |
| **Testing** | `aws_abap_cb_get_test_classes` | List test classes for an object |
| **Testing** | `aws_abap_cb_create_or_update_test_class` | Manage test classes |
| **Deploy** | `aws_abap_cb_activate_object` | Activate a single object |
| **Deploy** | `aws_abap_cb_activate_objects_batch` | Activate multiple objects at once |
| **Transport** | `aws_abap_cb_get_transport_requests` | List open transport requests |
| **Analysis** | `aws_abap_cb_get_migration_analysis` | S/4HANA migration analysis |
| **Status** | `aws_abap_cb_connection_status` | Test SAP connection and get system info |

All tools accept a `sap_system_id` parameter: `DV8`, `MS1`, or `MD1`.

---

## For SAP Basis Teams

The ABAP MCP Server uses certificate-based authentication (Principal Propagation). It generates a short-lived X.509 client certificate for each user and presents it to SAP during TLS connection — the same mechanism as SAP Single Sign-On with X.509 certificates.

### What Needs to Be Done (One-Time, Per System)

**Step 1: Import CA Certificate to STRUST**

The AICE team provides `abap-mcp-ca-cert.pem`. Import it into **STRUST → SSL Client (Standard) PSE**:
1. Transaction STRUST
2. SSL Client (Standard) → Edit (pencil icon)
3. Import certificate → select `abap-mcp-ca-cert.pem`
4. Add to Certificate List → Save
5. Transaction SMICM → Administration → ICM → Exit Soft (reload SSL context)

Perform on: DV8 (port 1443), MS1 (port 44300), MD1 (port 44300).

**Step 2: Configure User Mapping**

Choose one method:

*Option A — SU01 Login Type E (per user):*
1. Transaction SU01 → open user (e.g., `AVRG`)
2. Tab SNC
3. Login Type = `E` (External Identification)
4. SNC Name = leave empty
5. Save

*Option B — CERTRULE (central, recommended for many users):*
1. Transaction CERTRULE (or SM30 → VUSREXTID)
2. Create rule: Certificate Attribute = `CN`, Attribute Value = `*`, Login Data = use CN as username

**Step 3: Test with Sample Certificate**

The AICE team provides `sample-ephemeral-cert-AVRG.pem` — a real certificate signed by the CA, with `CN=AVRG`, valid for 5 minutes. Test using:

```bash
openssl s_client \
  -connect sapdv8db1.comp.pge.com:1443 \
  -cert sample-ephemeral-cert-AVRG.pem \
  -key sample-ephemeral-key-AVRG.pem \
  -CAfile abap-mcp-ca-cert.pem
```

A successful TLS handshake followed by an HTTP 200 from SAP confirms the setup is correct.

### What Basis Gets

- ✅ Zero password management — certificates only
- ✅ Individual user accountability in SAP Security Audit Log (SM20)
- ✅ Standard SAP authorization objects enforced per user
- ✅ Certificate validity managed by the MCP server — no Basis involvement needed day-to-day
- ✅ CA certificate rotation every 10 years maximum — coordinated with Basis

### Certificate Reference

| Property | CA Certificate | Ephemeral Certificate |
|----------|---------------|----------------------|
| Algorithm | RSA 4096-bit | RSA 2048-bit |
| Validity | 10 years | 5 minutes |
| CN | `ABAP MCP CA` | `<LANID>` (e.g., `AVRG`) |
| Key Usage | Certificate Sign | Digital Signature, Key Encipherment |
| Extended Key Usage | — | Client Authentication |

---

## Security & Compliance

### Authentication Flow

```
1. Developer opens Kiro IDE
2. Kiro connects to Portkey AI Gateway
3. Portkey authenticates user via PG&E SSO (Microsoft Entra ID)
4. Portkey injects X-User-Claims into every forwarded request:
   {"email":"avrg@pge.com","sub":"...","groups":["ABAP-Developers"]}
5. MCP server reads X-User-Claims → LANID = AVRG
6. MCP server generates ephemeral certificate:
   CN=AVRG, signed by trusted CA, valid 5 minutes
7. MCP server connects to SAP with certificate (mutual TLS)
8. SAP validates signature → maps CN=AVRG → user AVRG
9. SAP executes operation under AVRG's authorizations
10. Results returned via MCP → Portkey → Kiro
```

### Data Security

**At rest:**
- CA private key: AWS Secrets Manager (KMS-encrypted)
- SAP configs: SSM Parameter Store (encrypted)
- Logs: CloudWatch Logs (encrypted at rest)

**In transit:**
- Client ↔ Portkey: HTTPS/TLS
- Portkey ↔ MCP Server: HTTPS/TLS
- MCP Server ↔ SAP: HTTPS mutual TLS (client certificate)

**Never stored:**
- User passwords
- Ephemeral certificates (in-memory only, discarded after use)
- ABAP source code (streamed to client, not persisted)

### Compliance

| Standard | How We Comply |
|----------|--------------|
| **SOX** | Individual user accountability via LANID in certificates; SAP Security Audit Log; transport request tracking |
| **GDPR** | Minimal data collection (LANID only); no persistent personal data; ephemeral certificates |
| **PCI DSS** | No card data; strong mutual TLS auth; access logging |

---

## Project History

The ABAP MCP Server started from the AWS Samples reference implementation (`aws-abap-accelerator`). Here is how it evolved:

**Phase 1 — Connectivity Validation**
The first goal was verifying that the MCP protocol could reach SAP ABAP systems from AWS. The AWS reference implementation used static credentials. PG&E added Terraform infrastructure (ECS Fargate, ALB, Secrets Manager, Route53, CloudWatch) following PGE-standard patterns, deployed it on ECS, and confirmed the 15+ SAP ADT tools worked end-to-end with static service account credentials.

**Phase 2 — OAuth and Cognito/Entra ID Integration**
With connectivity confirmed, the next goal was replacing static credentials with SSO authentication. The original codebase had bugs in FastMCP OAuth integration — IdP-specific issues with audience validation, scope handling, and the Kiro MCP client's behavior during token exchange. These were identified, fixed, and documented. Both AWS Cognito and Microsoft Entra ID were tested and working (commit `c81877e`). This established that user identity could be reliably extracted from OAuth tokens.

**Phase 3 — Principal Propagation via Portkey Identity Forwarding**
The final and current architecture addresses a key insight: if MCP clients like Kiro access the server through Portkey (the PG&E AI Gateway), Portkey already handles authentication. Rather than requiring a separate OAuth flow at the MCP server, Portkey can forward the authenticated user's claims via the `X-User-Claims` header.

This led to implementing:
- `X-User-Claims` header parsing in `iam_identity_validator.py`
- LANID derivation in `principal_propagation.py` (`email.split('@')[0].upper()`)
- Ephemeral certificate generation with `CN=<LANID>` in `certificate_auth_provider.py`
- `stateless_http=True` in `enterprise_main.py` for Portkey/streamable-HTTP compatibility

The result: Kiro users authenticate once with PG&E SSO via Portkey, and the MCP server uses their email claim to generate a per-user SAP certificate automatically — no separate OAuth challenge, no shared credentials. The mechanism is generic: any MCP server behind Portkey can adopt the same pattern.

**What's pending:** SAP Basis STRUST import and CERTRULE configuration on the SAP systems. The server code is complete.

---

## FAQ

**Q: Do I need to log in to use the ABAP MCP Server?**
A: You authenticate once with PG&E SSO when Kiro connects to Portkey. After that, everything is automatic — Portkey forwards your identity to the MCP server with every request.

**Q: What SAP systems can I access?**
A: DV8 (development), MS1 (S/4HANA test), MD1 (S/4HANA dev). Specify the system in your Kiro query: "Get source for ZCL_MY_CLASS in **MS1**".

**Q: Can I modify SAP objects?**
A: Yes, for systems where you have write access (typically DV8). You'll need a transport request number. The MCP server enforces the same SAP authorizations as your direct SAP GUI login.

**Q: What if I get a certificate authentication error?**
A: SAP Basis hasn't completed STRUST configuration yet. Contact the Basis team — this is a one-time setup.

**Q: Is this officially supported by SAP?**
A: The server uses SAP's official ADT REST API — the same API used by Eclipse ADT. The API is supported by SAP; this is a client implementation.

**Q: Can multiple people use it at the same time?**
A: Yes. Each user gets their own ephemeral certificate. The server is multi-tenant by design.

**Q: What happens if I leave Kiro idle?**
A: Portkey sessions expire per PG&E SSO policy. When you next use Kiro, Portkey may prompt re-authentication. The MCP server itself is stateless.

**Q: Can this replace SAP GUI?**
A: No. It's designed for development tasks: reading/writing code, running tests, syntax checks. Complex transactions (debugging, configuration, basis tasks) still require SAP GUI.

**Q: How do I add another MCP server to Kiro?**
A: Edit `~/.kiro/mcp.json` and add the server's Portkey gateway URL. Restart Kiro. See [Configuring Multiple MCP Servers](#configuring-multiple-mcp-servers-in-kiro).

**Q: What is the latency?**
A: Typical response times: list objects 200–500ms, read source 300–800ms, update + activate 1–3s, run unit tests 2–10s.

---

## Glossary

| Term | Definition |
|------|------------|
| **ABAP** | Advanced Business Application Programming — SAP's proprietary programming language |
| **ADT API** | ABAP Development Tools REST API — SAP's official programmatic access API |
| **ATC** | ABAP Test Cockpit — static code analysis tool |
| **CERTRULE** | SAP certificate mapping rules — maps X.509 CN attribute to SAP username |
| **CN (Common Name)** | Field in X.509 certificates identifying the subject (e.g., `CN=AVRG`) |
| **ECS** | Amazon Elastic Container Service (Fargate) — serverless container runtime |
| **Entra ID** | Microsoft's cloud identity service (formerly Azure Active Directory) |
| **FastMCP** | Python framework for building MCP servers |
| **JWT** | JSON Web Token — compact token format for OAuth 2.0 |
| **LANID** | PG&E user identifier — typically first letter + last name (e.g., `AVRG`) |
| **MCP** | Model Context Protocol — open standard for AI-system integration |
| **OAuth 2.0** | Industry-standard protocol for authorization and identity delegation |
| **Portkey** | PG&E's centralized AI Gateway — handles authentication, routing, rate limiting |
| **Principal Propagation** | Technique to propagate user identity across system boundaries using certificates |
| **PSE** | Personal Security Environment — SAP's certificate trust store |
| **STRUST** | SAP transaction for managing certificates and PSEs |
| **TLS** | Transport Layer Security — cryptographic protocol for secure communication |
| **X-User-Claims** | HTTP header injected by Portkey containing authenticated user's identity claims (JSON) |
| **X.509** | Standard format for public key certificates |

---

## Contact & Support

**Project Lead:** AICE (AI & Cloud Engineering Team)  
**AI Engineer:** Antonio Robles — avrg@pge.com

**Documentation:**
- **WIKI.md** (this file) — User guide, Kiro setup, Portkey integration
- **README-PGE.md** — Technical reference: deployment, certificates, identity, SAP config, scripts
- **CLAUDE.md** — Developer reference: architecture, code patterns, adding tools

**SAP Basis — for STRUST/CERTRULE setup:**  
See README-PGE.md Part 4 for step-by-step instructions and certificate details.

**For access issues or new user onboarding:**  
Contact the AICE team for Portkey gateway access and SAP Basis coordination.

---

© 2026 Pacific Gas and Electric Company. All rights reserved.  
**For internal use by authorized PG&E personnel only.**
