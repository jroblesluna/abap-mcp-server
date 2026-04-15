# ABAP MCP Server

**SAP ABAP Integration from Kiro and Amazon Q**

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current Implementation Status](#current-implementation-status)
3. [The Problem We're Solving](#the-problem-were-solving)
4. [What is MCP?](#what-is-mcp)
5. [Architecture Overview](#architecture-overview)
6. [User Experience](#user-experience)
7. [Key Features & Benefits](#key-features--benefits)
8. [Security & Compliance](#security--compliance)
9. [Technical Implementation](#technical-implementation)
10. [Deployment at PG&E](#deployment-at-pge)
11. [Getting Started](#getting-started)
    - [Kiro IDE (Recommended)](#kiro-ide-recommended)
    - [Configuring Multiple MCP Servers in Kiro](#configuring-multiple-mcp-servers-in-kiro)
    - [Amazon Q Developer (Alternative)](#amazon-q-developer-alternative)
    - [Claude Desktop (Optional)](#claude-desktop-optional)
12. [Roadmap](#roadmap)
13. [FAQ](#faq)
14. [Glossary](#glossary)
15. [Contact & Support](#contact--support)

---

## Executive Summary

The **ABAP MCP Server** is an implementation at Pacific Gas & Electric Company (PG&E) that enables AI-powered development tools like **Kiro IDE** and **Amazon Q Developer** to interact directly with SAP ABAP systems through a secure, standardized interface.

**What it means for developers:**
- Ask natural language questions about ABAP code and get instant answers
- Generate ABAP code snippets from descriptions
- Refactor legacy code with AI assistance
- Run syntax checks, unit tests, and quality scans from your AI assistant
- Deploy changes to SAP transports — all without leaving your AI tool

**What it means for PG&E:**
- **Secure access** — Direct SAP connection through PG&E AI Gateway (Portkey)
- **Multi-tenant architecture** — Supports multiple SAP systems (DV8, MS1, MD1, QA, Production)
- **Open protocol** — Uses Model Context Protocol (MCP), an open standard for AI-system integration
- **Full audit trail** — Every action logged with user identity
- **SSO authentication** — Enterprise SSO and certificate-based authentication coming soon

---

## Current Implementation Status

### ✅ Phase 1: Direct SAP Integration (Current - Deployed)

**What's working today:**
- ✅ **MCP Server operational** — Deployed on AWS ECS with Portkey AI Gateway integration
- ✅ **15+ SAP development tools** — Read/write code, run tests, activate objects, transport management
- ✅ **Multi-system support** — Connect to DV8, MS1, MD1
- ✅ **SAP ADT API integration** — Full access to SAP ABAP Development Tools REST API
- ✅ **Kiro IDE integration** — Primary AI client for PG&E ABAP development
- ✅ **Amazon Q Developer compatibility** — Also works with Amazon Q and Claude Desktop
- ✅ **Rate limiting & analytics** — Portkey AI Gateway provides usage tracking and cost monitoring

**Current authentication method:**
- **Static SAP credentials** stored in AWS Secrets Manager (one credential per system)
- Credentials loaded at server startup
- All users share the same technical service account for SAP access
- Audit logging shows MCP operation context but not individual user identity in SAP

**Current configuration:**
```bash
# AWS Secrets Manager stores:
mcp/abap-mcp-server/DV8  → {"username": "MCP_SERVICE", "password": "..."}
mcp/abap-mcp-server/MS1  → {"username": "MCP_SERVICE", "password": "..."}
mcp/abap-mcp-server/MD1  → {"username": "MCP_SERVICE", "password": "..."}
```

### 🚧 Phase 2: SSO Authentication + Principal Propagation (In Progress)

**What's coming next:**

**1. OAuth 2.0 Integration (Microsoft Entra ID)**
- Users authenticate with PG&E SSO (LANID@pge.com)
- OAuth token issued with user identity claims
- No passwords stored or transmitted
- Token-based session management

**2. Principal Propagation (Certificate-Based SAP Auth)**
- Server extracts LANID from OAuth token (e.g., avrg@pge.com → AVRG)
- Generates ephemeral X.509 certificate with CN=<LANID>
- Certificate signed by trusted CA (valid 5 minutes)
- SAP validates certificate and maps to individual user account

**3. Individual User Accountability**
- Each SAP operation executed under user's own SAP account
- SAP authorization objects enforced per user
- Full audit trail with individual user identity
- No shared service accounts

**Benefits of Phase 2:**
- 🔒 **Zero passwords** — Certificate-based authentication only
- 👤 **Individual accountability** — Every action tied to specific user
- ✅ **SAP authorizations enforced** — Users have same permissions as direct SAP GUI login
- 📝 **Compliance-ready** — SOX/GDPR audit requirements met with user-level tracking

**Implementation timeline:**
- OAuth integration: In development
- Certificate generation: Code complete, pending SAP Basis STRUST configuration
- SAP certificate import: Awaiting SAP Basis team (STRUST PSE setup)
- User testing: Planned after SAP configuration complete
- Production rollout: TBD (dependent on SAP Basis completion)

**Technical readiness:**
- ✅ Certificate generation code implemented (`auth/providers/certificate_auth_provider.py`)
- ✅ OAuth integration implemented (`server/fastmcp_oauth_integration.py`)
- ✅ LANID extraction logic implemented
- ✅ CA certificate generated and stored in AWS Secrets Manager
- ⏳ SAP STRUST configuration (waiting for SAP Basis team)
- ⏳ Production OAuth provider configuration
- ⏳ End-to-end testing with certificate authentication

**How to track progress:**
- See [Roadmap](#roadmap) section for detailed milestones
- Technical documentation: `CERTIFICATES.md` (certificate setup procedures)
- OAuth details: `docs/oauth-findings.md` (implementation guide)

---

## The Problem We're Solving

### Traditional SAP ABAP Development Challenges

**Manual, repetitive workflows:**
- Developers spend hours searching through ABAP code across hundreds of packages
- Copy-pasting code between SAP GUI and development tools
- Manually running syntax checks, unit tests, and ATC quality scans
- Navigating complex transport request workflows

**Limited AI assistance:**
- Existing AI coding assistants (GitHub Copilot, ChatGPT) don't understand SAP-specific context
- No direct connection to live SAP systems — developers work with stale code copies
- Can't execute ABAP-specific operations (activation, transport, ATC checks)

**Security concerns:**
- Traditional integrations require storing SAP passwords in configuration files
- Shared service accounts lack individual accountability
- No SSO integration with corporate identity systems

### Our Solution

The ABAP MCP Server acts as a **secure bridge** between AI assistants and SAP systems, with all traffic routed through PG&E's AI Gateway (Portkey).

**Current Architecture (Phase 1 - Static Credentials):**

```
┌─────────────────────────────────────────────────────────────┐
│  Developer using Kiro IDE                                   │
│  Natural language:                                          │
│  "Show me all ABAP classes in package ZFIN that handle      │
│  invoices"                                                  │
└────────┬────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  MCP Protocol (Open Standard)                               │
│  Standardized way for AI tools to interact with systems     │
└────────┬────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  Portkey (PG&E AI Gateway)                                  │
│  • Rate limiting & quota enforcement                        │
│  • Request routing & load balancing                         │
│  • Analytics, monitoring & cost tracking                    │
│  • Security & compliance logging                            │
└────────┬────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  ABAP MCP Server @ PG&E                                     │
│  • Uses static SAP credentials (from AWS Secrets Manager)   │
│  • Translates MCP commands → SAP ADT API calls              │
│  • Manages SAP session lifecycle                            │
└────────┬────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  SAP ABAP Systems (DV8, MS1, MD1)                           │
│  • Authenticates with service account credentials           │
│  • Executes requested operation                             │
│  • Returns structured results                               │
└─────────────────────────────────────────────────────────────┘
```

**Future Architecture (Phase 2 - SSO + Principal Propagation):**

```
Developer using Kiro/Q → MCP Protocol → Portkey Gateway
    ↓
User authenticates with PG&E SSO (Microsoft Entra ID)
    ↓
ABAP MCP Server extracts LANID from OAuth token
    ↓
Server generates ephemeral certificate (CN=<LANID>, valid 5 minutes)
    ↓
SAP validates certificate → Maps CN to SAP user → Executes as individual user
```

**Result:** Developers get AI-powered ABAP development with certificate-based security, and PG&E gains individual user accountability.

---

## What is MCP?

**Model Context Protocol (MCP)** is an open standard created by Anthropic that enables AI assistants to safely connect to external systems and data sources.

### Think of MCP Like USB for AI

MCP provides a standard way for AI assistants to connect to external systems.

**Before MCP:**
- Every AI tool needed custom integrations for each system (SAP, Salesforce, databases, etc.)
- Developers built proprietary, incompatible connectors
- Security and authentication handled inconsistently

**With MCP:**
- AI tools implement MCP once, connect to any MCP server
- System owners build one MCP server, compatible with all MCP-enabled AI tools
- Standardized security, authentication, and audit logging

### MCP Components

```
┌─────────────────────────────────────────────────────────────┐
│  MCP Client (AI Assistant)                                  │
│  • Kiro IDE (Primary PG&E tool)                             │
│  • Amazon Q Developer                                       │
│  • Claude Desktop                                           │
│  • Any tool that supports MCP                               │
└────────┬────────────────────────────────────────────────────┘
         │
         │  MCP Protocol (JSON-RPC over HTTP)
         │  • Discovery: What can this server do?
         │  • Authentication: Who is the user?
         │  • Tool Invocation: Execute operation X with params Y
         │  • Streaming: Real-time results
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  MCP Server (System Connector)                              │
│  • ABAP MCP Server (this project) → SAP systems             │
│  • Salesforce MCP Server → Salesforce API                   │
│  • Database MCP Server → SQL databases                      │
│  • Filesystem MCP Server → local files                      │
└─────────────────────────────────────────────────────────────┘
```

**Portkey (PG&E AI Gateway) Integration:**

All requests from AI clients to the ABAP MCP Server flow through **Portkey**, PG&E's centralized AI Gateway. Portkey provides:

- **Request Routing:** Intelligent routing to healthy MCP server instances
- **Rate Limiting:** Per-user quotas to prevent abuse and control costs
- **Analytics:** Real-time monitoring of API usage, latency, and errors
- **Cost Optimization:** Request caching and smart retry logic
- **Security:** Centralized authentication, authorization, and audit logging
- **Compliance:** Ensures all AI interactions meet PG&E security standards

**Server Configuration:**

Developers configure their AI tool (Kiro IDE, Amazon Q Developer) with the MCP server endpoint URL. The AI client connects directly to the MCP server and discovers available tools through the MCP protocol's capabilities exchange.

---

## Architecture Overview

**Note:** The architecture diagrams below show the **future state (Phase 2)** with OAuth and Principal Propagation. See [Current Implementation Status](#current-implementation-status) for what's deployed today.

### High-Level Architecture (Future - Phase 2)

```
┌─────────────────────────────────────────────────────────────────────┐
│  User Layer                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │
│  │  Kiro IDE    │  │  Amazon Q    │  │  Claude      │               │
│  │  (Primary)   │  │  Developer   │  │  Desktop     │               │
│  └──────┬───────┘  └───────┬──────┘  └────────┬─────┘               │
│         │                  │                  │                     │
│         └──────────────────┼──────────────────┘                     │
│                            │                                        │
│                            │ MCP Protocol                           │
└────────────────────────────┼────────────────────────────────────────┘
                             │
┌────────────────────────────┼────────────────────────────────────────┐
│  Integration Layer         │                                        │
│                            ▼                                        │
│  ┌──────────────────────────────────────────────────────┐           │
│  │  Portkey AI Gateway                                  │           │
│  │  • Request routing & load balancing                  │           │
│  │  • Rate limiting & quota management                  │           │
│  │  • Analytics & observability                         │           │
│  │  • Caching & cost optimization                       │           │
│  │  • Security & compliance logging                     │           │
│  └─────────────────────────┬────────────────────────────┘           │
└────────────────────────────┼────────────────────────────────────────┘
                             │
┌────────────────────────────┼────────────────────────────────────────┐
│  ABAP MCP Server           ▼                                        │
│  (Running on AWS ECS)                                               │
│                                                                     │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │  1. OAuth Authentication (Microsoft Entra ID)              │     │
│  │     • User redirected to Entra ID login                    │     │
│  │     • SSO with PG&E credentials                            │     │
│  │     • JWT token issued with user identity                  │     │
│  └──────────────────────────┬─────────────────────────────────┘     │
│                             │                                       │
│  ┌──────────────────────────┴─────────────────────────────────┐     │
│  │  2. Identity Resolution                                    │     │
│  │     • Extract email from JWT token                         │     │
│  │     • Derive LANID: avrg@pge.com → AVRG                    │     │
│  │     • Cache identity (avoid repeated API calls)            │     │
│  └──────────────────────────┬─────────────────────────────────┘     │
│                             │                                       │
│  ┌──────────────────────────┴─────────────────────────────────┐     │
│  │  3. Certificate Generation (Principal Propagation)         │     │
│  │     • Generate ephemeral X.509 certificate                 │     │
│  │     • Subject: CN=<LANID> (e.g., CN=AVRG)                  │     │
│  │     • Signed by trusted CA                                 │     │
│  │     • Valid for 5 minutes                                  │     │
│  └──────────────────────────┬─────────────────────────────────┘     │
│                             │                                       │
│  ┌──────────────────────────┴─────────────────────────────────┐     │
│  │  4. SAP ADT API Client                                     │     │
│  │     • Translate MCP commands → ADT REST API calls          │     │
│  │     • Use certificate for TLS client authentication        │     │
│  │     • Handle CSRF tokens, session management               │     │
│  │     • Parse XML responses → JSON results                   │     │
│  └──────────────────────────┬─────────────────────────────────┘     │
└─────────────────────────────┼───────────────────────────────────────┘
                              │
┌─────────────────────────────┼───────────────────────────────────────┐
│  SAP Layer                  ▼                                       │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐   │
│  │  DV8             │  │  MS1             │  │  MD1             │   │
│  │  Port: 1443      │  │  Port: 44300     │  │  Port: 44300     │   │
│  │  Client: 120     │  │  Client: 100     │  │  Client: 100     │   │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘   │
│           │                     │                     │             │
│  ┌────────┴─────────────────────┴─────────────────────┴──────────┐  │
│  │  STRUST - Certificate Validation                              │  │
│  │  • Verify certificate signature against trusted CA            │  │
│  │  • Ensure certificate not expired                             │  │
│  └──────────────────────────────┬────────────────────────────────┘  │
│                                 │                                   │
│  ┌──────────────────────────────┴────────────────────────────────┐  │
│  │  CERTRULE - User Mapping (or Login Type E)                    │  │
│  │  • Extract CN from certificate (e.g., CN=AVRG)                │  │
│  │  • Map to SAP username (AVRG → SAP user AVRG)                 │  │
│  └──────────────────────────────┬────────────────────────────────┘  │
│                                 │                                   │
│  ┌──────────────────────────────┴─────────────────────────────────┐ │
│  │  SAP Session Established                                       │ │
│  │  • Execute ADT operation (read code, run tests, etc.)          │ │
│  │  • Return results                                              │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **AI Clients** | Kiro IDE (Primary), Amazon Q Developer | User interface for AI-assisted development |
| **Protocol** | MCP (Model Context Protocol) | Standardized AI-system communication |
| **AI Gateway** | Portkey (PG&E AI Gateway) | Request routing, rate limiting, analytics, security, cost optimization |
| **Runtime** | Python 3.11+, FastMCP 3.2.4+ | MCP server implementation |
| **Authentication** | OAuth 2.0, Microsoft Entra ID | User authentication and SSO |
| **Authorization** | Principal Propagation (X.509 certs) | Certificate-based SAP authentication |
| **SAP API** | ADT REST API (ABAP Development Tools) | Programmatic access to SAP development objects |
| **Infrastructure** | AWS ECS (Fargate), ALB, Secrets Manager | Cloud hosting and secret management |
| **Observability** | CloudWatch Logs, X-Ray | Logging, monitoring, distributed tracing |

### Portkey (PG&E AI Gateway) Integration

**What is Portkey?**

Portkey is PG&E's centralized AI Gateway that sits between all AI clients (Kiro IDE, Amazon Q Developer, Claude Desktop) and backend services (MCP servers, LLM APIs, RAG systems). It provides centralized control, security, and observability for all AI interactions at PG&E.

**Why Portkey is Required:**

The ABAP MCP Server is accessible **only through Portkey** — direct connections are not permitted. This architectural decision ensures:

1. **Centralized Security:** Single enforcement point for authentication, authorization, and audit logging
2. **Cost Control:** Per-user quotas prevent runaway costs from excessive API usage
3. **Compliance:** All AI interactions logged for SOX, GDPR, and internal audit requirements
4. **Reliability:** Load balancing, failover, and intelligent retry logic
5. **Observability:** Real-time dashboards showing usage patterns, errors, and latency

**Request Flow with Portkey:**

```
Kiro IDE (or Amazon Q)
    ↓
MCP Protocol Request
    ↓
Portkey Gateway (PG&E AI Gateway)
    • Authenticate user (check JWT token)
    • Check rate limits (user/team quotas)
    • Log request (user, timestamp, endpoint)
    • Route to healthy MCP server instance
    ↓
ABAP MCP Server
    • Process request
    • Return response
    ↓
Portkey Gateway
    • Log response (status, latency, tokens)
    • Update metrics (cost, usage)
    • Cache if applicable
    ↓
Response to Kiro IDE
```

**Portkey Features for ABAP MCP Server:**

| Feature | Benefit |
|---------|---------|
| **Rate Limiting** | Prevent abuse; enforce 100 requests/hour per developer (configurable) |
| **Request Routing** | Load balance across multiple MCP server instances (blue/green deployment) |
| **Caching** | Cache identical queries (e.g., package listings) to reduce SAP load |
| **Analytics Dashboard** | Real-time view of who's using what, when, and how much it costs |
| **Error Tracking** | Centralized error aggregation and alerting |
| **Cost Allocation** | Track costs per user, team, or department for chargeback |
| **Security Policies** | Block suspicious patterns (e.g., excessive failed auth attempts) |
| **Audit Logging** | Immutable logs for compliance (retained per policy) |

**Configuration Example:**

```yaml
# Portkey configuration for ABAP MCP Server
service:
  name: abap-mcp-server
  endpoint: https://abap-mcp-server.nonprod.pge.com/mcp
  
rate_limits:
  per_user: 100 requests/hour
  per_team: 1000 requests/hour
  burst: 10 requests/minute

caching:
  enabled: true
```

**Benefits for Stakeholders:**

- **Developers:** Transparent - no changes to workflow
- **IT Operations:** Single pane of glass for all AI traffic monitoring
- **Security:** Centralized policy enforcement and audit trail
- **Finance:** Clear cost attribution and budget tracking
- **Compliance:** Built-in audit logging and data governance

---

## User Experience

### For ABAP Developers

**Scenario 1: Code Discovery**

```
Developer (in Kiro IDE):
"Show me all ABAP classes in package ZFIN_INVOICE that handle PDF generation"

Kiro:
📦 Found 3 classes in ZFIN_INVOICE matching "PDF generation":

1. ZCL_PDF_GENERATOR
   - Description: Main PDF generation service
   - Last changed: 2026-04-10 by T1RN
   - Methods: CREATE_PDF, ADD_HEADER, ADD_FOOTER

2. ZCL_PDF_TEMPLATE_MANAGER  
   - Description: Manages PDF templates
   - Last changed: 2026-03-15 by AVRG
   - Methods: LOAD_TEMPLATE, SAVE_TEMPLATE

3. ZCL_PDF_ARCHIVER
   - Description: Archives generated PDFs to DMS
   - Last changed: 2026-02-20 by S0B4
   - Methods: ARCHIVE_PDF, RETRIEVE_PDF

Would you like to see the source code for any of these?
```

**Request flow:**
1. Kiro sends MCP request through Portkey AI Gateway
2. Portkey routes to ABAP MCP Server
3. Server loads SAP credentials from AWS Secrets Manager (Phase 1)
4. Server queries SAP ADT API for objects in package ZFIN_INVOICE
5. Server filters results for "PDF" in descriptions/names
6. Server returns structured data through Portkey to Kiro
7. Kiro formats and presents to user

**Scenario 2: Code Generation**

```
Developer (in Kiro):
"Generate an ABAP class that reads invoice data from table ZINVOICE 
and exports to CSV format. Include error handling and unit tests."

Kiro:
✅ Generated ZCL_INVOICE_EXPORTER

Here's the implementation:

[Shows generated ABAP code with methods, error handling, unit tests]

I've created the class with:
- READ_INVOICES method (reads from ZINVOICE)
- EXPORT_TO_CSV method (converts to CSV string)
- Error handling for table access failures
- 3 unit test methods covering normal case, empty table, and DB error

Would you like me to:
1. Create this class in your SAP DV8 system?
2. Run the unit tests?
3. Add it to a transport request?
```

**Scenario 3: Refactoring Legacy Code**

```
Developer (in Kiro IDE):
"Refactor the method ZCL_PAYMENT->PROCESS_PAYMENT to use modern ABAP syntax
(inline declarations, constructor expressions). Keep the same functionality."

Kiro:
✅ Refactored ZCL_PAYMENT->PROCESS_PAYMENT

Changes made:
- Replaced DATA declarations with inline DATA(...)
- Converted LOOP...INTO to modern table iteration syntax
- Replaced CREATE OBJECT with NEW constructor
- Added method chaining where applicable
- Reduced code from 150 lines to 95 lines

Before/After comparison:
[Shows side-by-side diff with syntax highlighting]

The refactored code:
✅ Passes all existing unit tests
✅ Passes ATC checks (no new warnings)
✅ Maintains identical functionality

Ready to save? I can update the source in DV8 and activate.
```

### For SAP Basis Teams

**What Basis needs to do (one-time setup):**

1. **Import CA certificate to STRUST** (10 minutes)
   - Receive `ca-cert.pem` file from MCP server admin
   - Transaction STRUST → Import to correct PSE for port 1443/44300
   - Restart SSL session in SMICM

2. **Configure user mapping** (5 minutes per approach)
   - **Option A:** Use Login Type E (SU01 → SNC tab)
   - **Option B:** Configure CERTRULE (SM30 → VUSREXTID)

3. **Test with sample certificates** (5 minutes)
   - Verify certificate format matches expected CN=<LANID>
   - Test connection with one user

**What Basis gets:**
- ✅ Zero password management (certificates only)
- ✅ Individual user accountability (cert CN mapped to SAP user)
- ✅ Standard SAP security mechanisms (STRUST, authorization objects)
- ✅ Audit trail via SAP Security Audit Log

---

## Key Features & Benefits

### 🚀 For Developers

**Development Features:**
- ⏱️ **Natural language search** — Search ABAP code vs. manual SE80/SE24 navigation
- 🤖 **AI-powered code generation** — Describe what you need, get working ABAP code
- 🔄 **Automated refactoring** — Modernize legacy code with one command
- 📊 **Instant quality feedback** — Run ATC checks and unit tests without switching tools

**Better Developer Experience:**
- 🎯 **Context-aware assistance** — AI understands SAP-specific concepts (BAPIs, RFCs, CDS views)
- 📚 **Inline documentation** — Get explanations of ABAP code without searching SAP Help
- 🔗 **Stay in flow** — Work in your preferred AI tool (Kiro, Q) without context switching to SAP GUI
- 💡 **Learn by example** — AI explains patterns, best practices, and anti-patterns

### 🔒 For Security Teams

**Security:**
- 🚫 **Zero passwords** — No credentials stored, transmitted, or cached
- 🎫 **SSO integration** — Single sign-on via Microsoft Entra ID
- 🔐 **Certificate-based auth** — Ephemeral X.509 certificates (5-minute validity)
- 👤 **Individual accountability** — Every action tied to specific user (LANID)

**Compliance & Audit:**
- 📝 **Full audit trail** — CloudWatch logs + SAP Security Audit Log
- 🔍 **Request traceability** — Distributed tracing with AWS X-Ray
- 🛡️ **Principle of least privilege** — Users have same SAP authorizations as direct login
- ✅ **SOX/GDPR compliant** — No sensitive data persistence, encrypted in transit

### 🏢 For IT Operations

**Scalable Architecture:**
- ☁️ **AWS deployment** — Runs on AWS ECS (Fargate) with auto-scaling
- 🌍 **Multi-tenant** — Supports multiple SAP systems (DV8, MS1, MD1)
- 💰 **Cost-efficient** — Serverless architecture scales to zero when idle
- 🔄 **High availability** — Multi-AZ deployment with health checks

**Management:**
- 🚀 **Automated deployment** — Terraform + Docker for infrastructure-as-code
- 📊 **Observable** — CloudWatch metrics, logs, and alarms
- 🔧 **Maintainable** — Python codebase with comprehensive documentation
- 🔄 **Upgradeable** — FastMCP framework handles protocol updates

---

## Security & Compliance

### Authentication Flow (Detailed)

```
1. User opens AI client (Kiro/Q Developer)
   ↓
2. Client requests MCP server capabilities
   ↓
3. Server responds: 401 Unauthorized + OAuth metadata
   {
     "issuer": "https://login.microsoftonline.com/{pge-tenant}/v2.0",
     "authorization_endpoint": "https://login.microsoftonline.com/{pge-tenant}/oauth2/v2.0/authorize",
     "scopes": ["openid", "email", "profile", "api://{client-id}/access"]
   }
   ↓
4. Client redirects user to Entra ID login
   ↓
5. User authenticates with PG&E SSO (Entra ID)
   ↓
6. Entra ID issues authorization code
   ↓
7. Client exchanges code for access token (JWT)
   {
     "iss": "https://login.microsoftonline.com/{tenant}/v2.0",
     "aud": "{client-id}",
     "sub": "<user-uuid>",
     "preferred_username": "avrg@pge.com",
     "email": "avrg@pge.com",
     "exp": 1745678901
   }
   ↓
8. Client sends MCP request with Bearer token
   ↓
9. Server validates JWT:
   ✓ Signature verified (JWKS from Entra ID)
   ✓ Issuer matches expected value
   ✓ Audience matches client ID
   ✓ Token not expired
   ↓
10. Server extracts user identity:
    email: "avrg@pge.com"
    → LANID: "AVRG" (split on '@', uppercase)
    ↓
11. Server generates ephemeral certificate:
    Subject: CN=AVRG, OU=Principal-Propagation, O=ABAP-Accelerator, C=US
    Issuer: CN=ABAP MCP CA
    Valid: 2026-04-15T10:00:00 to 2026-04-15T10:05:00 (5 minutes)
    ↓
12. Server connects to SAP with certificate (TLS client auth)
    ↓
13. SAP validates certificate:
    ✓ Signature verified (CA in STRUST)
    ✓ Certificate not expired
    ✓ CN=AVRG mapped to SAP user AVRG (CERTRULE/Login Type E)
    ↓
14. SAP session established for user AVRG
    ↓
15. Server executes SAP ADT operation
    ↓
16. Results returned to client
```

### Certificate Lifecycle

**CA Certificate (Long-lived):**
- Generated once (or rotated every 10 years)
- Stored in AWS Secrets Manager (encrypted with KMS)
- Public certificate imported to SAP STRUST
- Private key never leaves secure storage

**Ephemeral Client Certificates (Short-lived):**
- Generated per user request
- Valid for 5 minutes only
- Subject CN = user's LANID (e.g., CN=AVRG)
- Signed by CA private key
- Used for single SAP connection
- Automatically renewed if needed

**Security properties:**
- ✅ Certificate cannot be reused after expiry
- ✅ If stolen, only valid for < 5 minutes
- ✅ No persistent storage of certificates
- ✅ SAP validates signature on every connection

### Data Security

**Data at Rest:**
- 🔐 OAuth tokens: Encrypted by FastMCP (in-memory)
- 🔐 CA private key: AWS Secrets Manager (KMS encrypted)
- 🔐 SAP system configs: AWS SSM Parameter Store (encrypted)
- 🔐 Logs: CloudWatch Logs (encrypted at rest)

**Data in Transit:**
- 🔒 Client ↔ MCP Server: HTTPS/TLS 1.3
- 🔒 MCP Server ↔ SAP: HTTPS/TLS 1.2+ with mutual TLS (client cert)
- 🔒 MCP Server ↔ AWS Services: TLS 1.2+

**Data Not Stored:**
- ❌ User passwords (never collected)
- ❌ SAP credentials (certificate-based auth only)
- ❌ Ephemeral certificates (generated on-demand, discarded after use)
- ❌ ABAP source code (streamed to client, not persisted)

### Compliance Considerations

**SOX (Sarbanes-Oxley):**
- ✅ Individual user accountability (LANID in certificates)
- ✅ Audit trail of all operations (CloudWatch + SAP Security Audit Log)
- ✅ Separation of duties (SAP authorization objects enforced)
- ✅ Change management (transport request tracking)

**GDPR (General Data Protection Regulation):**
- ✅ Minimal data collection (only LANID from OAuth)
- ✅ No persistent storage of personal data
- ✅ Data minimization (ephemeral certificates)
- ✅ Right to be forgotten (no user data stored)

**PCI DSS (if applicable):**
- ✅ No credit card data processed or stored
- ✅ Strong authentication (OAuth + certificates)
- ✅ Encrypted communications (TLS)
- ✅ Access logging and monitoring

---

## Technical Implementation

### Component Deep-Dive

#### 1. FastMCP Server (`enterprise_main.py`)

**Responsibilities:**
- HTTP server listening on port 8000
- Handles MCP protocol requests (JSON-RPC)
- Manages OAuth flow integration
- Routes tool invocations to handlers
- Streams responses back to client

**Key code:**
```python
from fastmcp import FastMCP

mcp = FastMCP(
    name="ABAP-Accelerator-Enterprise",
    version="3.2.4",
    transport="streamable-http"
)

@mcp.tool()
async def aws_abap_cb_get_source(
    object_name: str,
    object_type: str,
    sap_system_id: str | None = None
) -> dict:
    """Retrieve ABAP source code for an object"""
    # Extract user identity from OAuth token
    user_id = extract_user_from_fastmcp_token()
    
    # Get SAP client with certificate auth
    sap_client = await get_sap_client(user_id, sap_system_id)
    
    # Execute ADT API call
    source_code = await sap_client.get_source(object_name, object_type)
    
    return {"source": source_code}
```

#### 2. OAuth Integration (`fastmcp_oauth_integration.py`)

**Responsibilities:**
- Configure OAuth provider (Entra ID)
- Handle OIDC discovery
- Extract user identity from JWT tokens
- Cache identity resolution (minimize UserInfo calls)
- Apply IdP-specific patches (Entra vs. Cognito)

**LANID extraction:**
```python
def extract_user_from_fastmcp_token(jwt_token: str) -> str:
    """Extract LANID from OAuth JWT token"""
    claims = jwt_token.get_claims()
    
    # Entra ID: use preferred_username claim
    if 'preferred_username' in claims:
        email = claims['preferred_username']  # e.g., avrg@pge.com
        lanid = email.split('@')[0].upper()  # AVRG
        return lanid
    
    # Cognito: call UserInfo endpoint
    if 'sub' in claims:
        userinfo = call_userinfo_endpoint(claims['sub'])
        email = userinfo.get('email')
        lanid = email.split('@')[0].upper()
        return lanid
    
    raise AuthenticationError("Unable to extract user identity")
```

#### 3. Certificate Provider (`certificate_auth_provider.py`)

**Responsibilities:**
- Load CA certificate and private key from AWS Secrets Manager
- Generate ephemeral X.509 certificates
- Sign certificates with CA private key
- Include correct certificate extensions (Key Usage, Extended Key Usage)

**Certificate generation:**
```python
def generate_ephemeral_certificate(
    self, 
    sap_username: str,  # LANID (e.g., "AVRG")
    validity_minutes: int = 5
) -> tuple[str, str]:
    """Generate ephemeral certificate for SAP authentication"""
    
    # Create RSA key pair
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048
    )
    
    # Build certificate subject
    subject = x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "ABAP-Accelerator"),
        x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "Principal-Propagation"),
        x509.NameAttribute(NameOID.COMMON_NAME, sap_username),  # CN=AVRG
    ])
    
    # Calculate validity (5 minutes)
    now = datetime.utcnow()
    not_before = now - timedelta(minutes=1)  # Clock skew buffer
    not_after = now + timedelta(minutes=validity_minutes)
    
    # Build and sign certificate
    certificate = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(self.ca_certificate.subject)
        .public_key(private_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(not_before)
        .not_valid_after(not_after)
        .add_extension(x509.KeyUsage(
            digital_signature=True,
            key_encipherment=True,
            content_commitment=False,
            data_encipherment=False,
            key_agreement=False,
            key_cert_sign=False,
            crl_sign=False,
            encipher_only=False,
            decipher_only=False
        ), critical=True)
        .add_extension(x509.ExtendedKeyUsage([
            ExtendedKeyUsageOID.CLIENT_AUTH
        ]), critical=False)
        .sign(private_key=self.ca_private_key, algorithm=hashes.SHA256())
    )
    
    # Serialize to PEM format
    cert_pem = certificate.public_bytes(serialization.Encoding.PEM)
    key_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )
    
    return cert_pem, key_pem
```

#### 4. SAP ADT Client (`sap_client.py`)

**Responsibilities:**
- Connect to SAP using certificate-based TLS client auth
- Manage CSRF tokens (SAP XSRF protection)
- Handle session lifecycle
- Parse XML responses from ADT API
- Retry failed requests with session recovery

**Certificate authentication:**
```python
async def _authenticate_certificate(self) -> bool:
    """Authenticate using X.509 client certificate"""
    cert_pem = self.client_certificate_pem
    key_pem = self.client_private_key_pem
    
    # Create temporary files (TLS library requirement)
    with tempfile.NamedTemporaryFile(mode='w', suffix='.pem') as cert_file, \
         tempfile.NamedTemporaryFile(mode='w', suffix='.pem') as key_file:
        
        cert_file.write(cert_pem)
        key_file.write(key_pem)
        cert_file.flush()
        key_file.flush()
        
        # Create SSL context with client certificate
        ssl_context = ssl.create_default_context()
        ssl_context.load_cert_chain(cert_file.name, key_file.name)
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE  # SAP uses self-signed certs
        
        # Create HTTPS session with client cert
        connector = aiohttp.TCPConnector(ssl=ssl_context)
        self.session = aiohttp.ClientSession(
            base_url=f"https://{self.host}:{self.port}",
            connector=connector
        )
        
        # Test connection (SAP ADT discovery endpoint)
        response = await self.session.get(
            f"/sap/bc/adt/discovery?sap-client={self.client}",
            headers={'x-sap-adt-sessiontype': 'stateful'}
        )
        
        if response.status == 200:
            logger.info(f"Certificate authentication successful for user {self.username}")
            return True
        else:
            logger.error(f"Certificate authentication failed: {response.status}")
            return False
```

#### 5. Multi-System Support (`sap-systems.yaml`)

**Configuration format:**
```yaml
systems:
  DV8:
    host: sapdv8db1.comp.pge.com
    port: 1443
    client: 120
    description: "Development System"
  
  MS1:
    host: vhpgxms1ci.s4hc.pge.com
    port: 44300
    client: 100
    description: "Test System (S/4HANA Cloud)"
  
  MD1:
    host: vhpgxmd1ci.s4hc.pge.com
    port: 44300
    client: 100
    description: "Production System (S/4HANA Cloud)"
```

**Runtime system selection:**
```python
@mcp.tool()
async def aws_abap_cb_get_source(
    object_name: str,
    object_type: str,
    sap_system_id: str | None = None  # User can specify: "DV8", "MS1", "MD1", etc.
) -> dict:
    # Use specified system, or fall back to default
    system_id = sap_system_id or os.getenv('DEFAULT_SAP_SYSTEM_ID', 'DV8')
    
    # Create SAP client for that specific system
    sap_client = await create_sap_client(user_id, system_id)
    
    # Execute operation
    source = await sap_client.get_source(object_name, object_type)
    return {"source": source, "system": system_id}
```

---

## Deployment at PG&E

### Infrastructure

**AWS Resources:**
- **VPC:** Isolated network for MCP server
- **ECS Cluster (Fargate):** Container orchestration
- **Application Load Balancer:** HTTPS termination, health checks
- **ECR:** Docker image registry
- **Secrets Manager:** CA certificates, OAuth client secrets
- **Parameter Store:** SAP system configurations
- **CloudWatch:** Logs, metrics, alarms
- **X-Ray:** Distributed tracing
- **Route 53:** DNS for internal domain

**Deployment Pipeline:**
```
Developer commits code
  → GitHub Actions triggered
  → Run tests (unit + integration)
  → Build Docker image
  → Push to ECR
  → Terraform Cloud (TFC) triggered
  → TFC updates ECS task definition
  → ECS blue/green deployment
  → Health checks pass
  → Traffic shifted to new version
  → Old tasks drained and terminated
```

### High Availability

**Multi-AZ Deployment:**
- ECS tasks distributed across availability zones
- ALB routes traffic to healthy tasks only
- Auto-scaling based on CPU/memory/request count

**Disaster Recovery:**
- **RTO (Recovery Time Objective):** < 15 minutes
- **RPO (Recovery Point Objective):** 0 (stateless application)
- Infrastructure-as-code (Terraform) enables rebuild
- Docker images stored in ECR with versioning

### Monitoring

**CloudWatch Dashboards:**
- Request rate, latency, error rate
- ECS task CPU, memory, network
- OAuth authentication success/failure rate
- SAP connection pool utilization
- Certificate generation rate

---

## Getting Started

### For Developers: Connect Your AI Tool

#### Kiro IDE (Recommended)

**Prerequisites:**
- Kiro IDE installed (https://kiro.ai/download)
- PG&E SSO credentials (LANID)
- Access to PG&E network (VPN if remote)

**Step 1: Configure MCP Server**

Kiro reads MCP server configuration from `~/.kiro/mcp.json` (user's home directory).

1. **Create or edit the configuration file:**

```bash
# Create directory if it doesn't exist
mkdir -p ~/.kiro

# Edit configuration file
nano ~/.kiro/mcp.json
```

2. **Add the following configuration:**

```json
{
  "mcpServers": {
    "sap-abap-accelerator-pge": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/sap-abap-accelerator/mcp"
    }
  }
}
```

**Important notes:**
- **URL points to Portkey AI Gateway**, not directly to the ABAP MCP Server
- All requests flow through PG&E's AI Gateway for rate limiting, analytics, and security
- The gateway routes to the appropriate backend MCP server instance
- Server name `abap-accelerator-pge` will appear in Kiro's UI

3. **Save the file:**
   - In nano: `Ctrl+O` (save), `Enter` (confirm), `Ctrl+X` (exit)
   - Or use your preferred text editor (VS Code, vim, etc.)

**Step 2: Restart Kiro IDE**

1. **Quit Kiro completely:**
   - macOS: `Cmd+Q`
   - Windows/Linux: File → Exit (or `Alt+F4`)
2. **Relaunch Kiro IDE**
3. Kiro automatically loads `~/.kiro/mcp.json` on startup
4. Wait ~5-10 seconds for MCP server registration

**Step 3: Authenticate with OAuth (First Time Only)**

1. **Open Kiro Chat Panel:**
   - Click the chat icon in the left sidebar
   - Or use `Ctrl+Shift+K` (Windows/Linux) or `Cmd+Shift+K` (Mac)

2. **Test MCP Connection:**
   - Type: `"List ABAP packages in DV8"`
   - Press Enter

3. **OAuth Authentication Flow:**
   - Kiro displays: **"Authentication required for abap-accelerator-pge"**
   - Click **"Authenticate"** button
   - Browser opens with Microsoft Entra ID SSO login page
   - **Enter your PG&E credentials** (LANID@pge.com / password)
   - **Complete MFA** if prompted (Duo push notification)
   - Browser shows: **"✅ Authentication successful - You can close this window"**
   - Return to Kiro IDE

4. **Connection Established:**
   - Kiro shows: **"✅ Connected to abap-accelerator-pge"**
   - Chat displays package list from DV8 system
   - OAuth token cached for 1 hour (no re-login needed)

**Step 4: Verify Connection**

Try these test queries to confirm everything works:

```
🔍 "Show me all ABAP classes in package ZFIN"
   → Should list classes with descriptions

📄 "Get the source code for class ZAPCL_NON_POINVOICES_GETSTATUS"
   → Should display ABAP code with syntax highlighting

🧪 "Run unit tests for class ZAPCL_NON_POINVOICES_GETSTATUS"
   → Should execute tests and show results (pass/fail)

🔍 "Search for ABAP objects containing 'invoice' in DV8"
   → Should return classes, programs, interfaces matching keyword
```

**Request flow:**

```
User Query in Kiro
    ↓
Kiro sends MCP request to:
https://mcp-aws-ai-gateway.nonprod.pge.com/abap-accelerator-dev/mcp
    ↓
Portkey (PG&E AI Gateway) at mcp-aws-ai-gateway.nonprod.pge.com:
  • Validates OAuth token
  • Checks rate limits (100 req/hour per user)
  • Logs request (user, timestamp, endpoint)
  • Routes to backend ABAP MCP Server
    ↓
ABAP MCP Server extracts LANID from token (e.g., AVRG)
    ↓
Server generates ephemeral certificate: CN=AVRG (valid 5 minutes)
    ↓
Server connects to SAP DV8 using certificate (TLS client auth)
    ↓
SAP validates certificate → Maps CN=AVRG → SAP user AVRG
    ↓
Server executes ADT API call (list packages, get source, etc.)
    ↓
Server returns JSON response → Portkey → Kiro
    ↓
Kiro displays formatted results in chat
```

**Tips for Using Kiro with ABAP MCP Server:**

✅ **Specify the SAP system explicitly:**
   - "Show classes in package ZFIN in **MS1**" (Test system)
   - "Get source code from **DV8**" (Dev system)
   - "Run tests in **MD1**" (Production - read-only access)

✅ **Use natural language - Kiro understands context:**
   - ❌ Bad: "Execute tool aws_abap_cb_get_source with params..."
   - ✅ Good: "Show me the source code for ZCL_INVOICE_HANDLER"

✅ **Chain multiple operations:**
   - "Get the source for ZCL_PAYMENT, identify any TODO comments, and suggest improvements"

✅ **Ask for explanations:**
   - "Explain what this ABAP method does" (after showing code)
   - "What's the difference between BADI and BTE in this context?"

**Troubleshooting:**

**Issue: "Server not found" or "Connection refused"**
- **Cause:** Kiro can't reach the Portkey AI Gateway
- **Solution:**
  - Verify VPN connected (if remote)
  - Check `~/.kiro/mcp.json` has correct URL:
    `https://mcp-aws-ai-gateway.nonprod.pge.com/abap-accelerator-dev/mcp`
  - Test connectivity: `curl https://mcp-aws-ai-gateway.nonprod.pge.com/health`
  - Restart Kiro IDE after config changes

**Issue: "Authentication failed" or "401 Unauthorized"**
- **Cause:** OAuth token expired or invalid
- **Solution:**
  - Clear cached authentication in Kiro
  - Retry query (will re-trigger OAuth flow)
  - Check PG&E SSO credentials are correct (LANID@pge.com)
  - Verify MFA device is available

**Issue: "Timeout waiting for response"**
- **Cause:** SAP system slow or unavailable
- **Solution:**
  - Increase timeout: Add `"timeout": 60000` to config (60 seconds)
  - Check SAP system status with: "Get connection status for DV8"
  - Try a different system (MS1 instead of DV8)

**Issue: Kiro shows "Tool not available" for ABAP operations**
- **Cause:** MCP server not properly registered
- **Solution:**
  - Restart Kiro IDE completely
  - Check server status: Ask Kiro "What tools are available?"
  - Should list 15+ ABAP tools (get_source, update_source, run_tests, etc.)

**Issue: "No authorization" or "Missing authorization object"**
- **Cause:** Your SAP user lacks authorization for requested operation
- **Solution:**
  - This is expected - same authorizations as direct SAP GUI access
  - Contact SAP Basis team to request authorization (e.g., S_DEVELOP)
  - Use read-only operations (get_source, list_objects) if write access not needed

**Advanced: Working with Multiple SAP Systems**

The ABAP MCP Server supports multiple SAP systems (DV8, MS1, MD1). Always specify the system in your queries:

- "Show classes in ZFIN on **MS1**" (Test system)
- "Get source from **DV8**" (Dev system - default)
- "List packages in **MD1**" (Production system - read-only)

---

### Configuring Multiple MCP Servers in Kiro

Kiro IDE supports connecting to multiple MCP servers simultaneously. This allows you to access different tools and systems from a single interface.

#### General Configuration Format

Edit `~/.kiro/mcp.json` with the following structure:

```json
{
  "mcpServers": {
    "server-name-1": {
      "url": "https://your-server-url/mcp"
    },
    "server-name-2": {
      "url": "https://another-server-url/mcp"
    },
    "server-name-3": {
      "url": "https://third-server-url/mcp"
    }
  }
}
```

#### Configuration Guidelines

**Server naming:**
- Use descriptive, kebab-case names (e.g., `abap-accelerator-pge`, `salesforce-api`, `database-tools`)
- Names appear in Kiro's tool selection UI
- Avoid spaces or special characters

**URL requirements:**
- Must be a fully qualified HTTPS URL
- Must end with `/mcp` (MCP protocol endpoint)
- Include the full path (domain + path + `/mcp`)

**Example: Multiple Enterprise MCP Servers**

```json
{
  "mcpServers": {
    "abap-accelerator-pge": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/abap-accelerator-dev/mcp"
    },
    "salesforce-pge": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/salesforce-mcp/mcp"
    },
    "servicenow-pge": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/servicenow-mcp/mcp"
    },
    "database-tools": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/database-mcp/mcp"
    },
    "filesystem-local": {
      "url": "http://localhost:3000/mcp"
    }
  }
}
```

#### How Kiro Uses Multiple Servers

**Tool Discovery:**
- Kiro connects to all configured servers at startup
- Each server advertises its available tools
- Tools are grouped by server name in Kiro's UI

**Example query routing:**
```
User: "Show me ABAP classes in ZFIN"
→ Kiro routes to abap-accelerator-pge

User: "List Salesforce opportunities for Account XYZ"
→ Kiro routes to salesforce-pge

User: "Create ServiceNow incident"
→ Kiro routes to servicenow-pge
```

**Kiro intelligently routes queries to the appropriate server based on:**
- Keywords in the query (ABAP, Salesforce, ServiceNow, etc.)
- Available tools (each server advertises its capabilities)
- Previous conversation context

#### Common Use Cases

**1. Enterprise Integration Suite:**
```json
{
  "mcpServers": {
    "sap-abap": {
      "url": "https://gateway.company.com/abap-mcp/mcp"
    },
    "sap-fiori": {
      "url": "https://gateway.company.com/fiori-mcp/mcp"
    },
    "salesforce": {
      "url": "https://gateway.company.com/salesforce-mcp/mcp"
    },
    "jira": {
      "url": "https://gateway.company.com/jira-mcp/mcp"
    }
  }
}
```

**2. Development + Production Servers:**
```json
{
  "mcpServers": {
    "abap-dev": {
      "url": "https://mcp-gateway.nonprod.company.com/abap-mcp/mcp"
    },
    "abap-prod": {
      "url": "https://mcp-gateway.prod.company.com/abap-mcp/mcp"
    }
  }
}
```

**3. Mix of Cloud and Local Servers:**
```json
{
  "mcpServers": {
    "abap-cloud": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/abap-accelerator-dev/mcp"
    },
    "local-filesystem": {
      "url": "http://localhost:3000/mcp"
    },
    "local-database": {
      "url": "http://localhost:3001/mcp"
    }
  }
}
```

#### Testing Your Configuration

After editing `~/.kiro/mcp.json`:

1. **Save the file**
2. **Restart Kiro IDE completely**
3. **Open Kiro chat** and type: `"What tools are available?"`
4. **Kiro should list tools from all configured servers**

**Expected output:**
```
Available MCP Servers:
• abap-accelerator-pge: 15 tools (SAP ABAP operations)
• salesforce-pge: 8 tools (Salesforce API access)
• servicenow-pge: 6 tools (ServiceNow incident management)
```

#### Troubleshooting Multiple Servers

**Issue: Only some servers connect**
- Check URL spelling and network access for failed servers
- Test each URL individually: `curl https://server-url/mcp`
- Check Kiro logs for authentication errors

**Issue: Tool conflicts (same tool name on multiple servers)**
- Kiro uses server name as namespace: `abap-accelerator-pge::get_source`
- Be specific in queries: "Get ABAP source from DV8" vs "Get Salesforce source"

**Issue: Slow Kiro startup with many servers**
- Kiro connects to all servers at startup
- Limit to actively used servers (5-10 maximum recommended)
- Remove unused servers from configuration

#### Best Practices

✅ **DO:**
- Group related servers by function (e.g., all SAP servers together)
- Use consistent naming conventions
- Document server purposes in a separate file
- Test configuration after each change

❌ **DON'T:**
- Add more than 10 servers (performance impact)
- Use generic names like "server1", "test", "prod"
- Mix HTTP and HTTPS without reason (use HTTPS for production)
- Forget to restart Kiro after configuration changes

#### Removing a Server

To remove an MCP server, delete its entry from `~/.kiro/mcp.json`:

```json
{
  "mcpServers": {
    "abap-accelerator-pge": {
      "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/abap-accelerator-dev/mcp"
    }
    // Removed "salesforce-pge" entry
  }
}
```

Save the file and restart Kiro.

---

#### Amazon Q Developer (Alternative)

**For developers who prefer using Amazon Q in VS Code or IntelliJ:**

1. **Install Amazon Q extension** (VS Code, IntelliJ, etc.)
2. **Open MCP Settings:**
   - VS Code: Settings → Extensions → Amazon Q → MCP Servers
   - IntelliJ: Preferences → Tools → Amazon Q → MCP Servers
3. **Add ABAP MCP Server:**
   ```json
   {
     "name": "PG&E SAP ABAP",
     "url": "https://mcp-aws-ai-gateway.nonprod.pge.com/abap-accelerator-dev/mcp",
     "description": "Access SAP ABAP development tools"
   }
   ```
4. **Restart IDE**
5. **Test connection:**
   - Open Amazon Q chat
   - Type: "List ABAP packages in DV8"
   - Should redirect to PG&E SSO login (Microsoft Entra ID)
   - After login, shows package list

---

#### Claude Desktop (Optional)

1. **Install Claude Desktop** (https://claude.ai/desktop)
2. **Configure MCP:**
   - Edit `claude_desktop_config.json`:
   ```json
   {
     "mcpServers": {
       "abap-accelerator-pge": {
         "command": "mcp",
         "args": ["connect", "https://mcp-aws-ai-gateway.nonprod.pge.com/abap-accelerator-dev/mcp"]
       }
     }
   }
   ```
3. **Restart Claude Desktop**
4. **Test:** Ask Claude "What ABAP tools are available?"

### For Administrators: Deploy the Server

See `CLAUDE.md` for comprehensive deployment documentation.

**Deployment:**

```bash
# Clone repository (contact AICE team for repository URL)
git clone <repository-url>
cd abap-mcp-server

# Configure environment
cp .env.example .env
# Edit .env with Entra ID client ID/secret, AWS region, etc.

# Deploy to AWS
./deploy.sh

# Expected output:
✓ Docker image built
✓ Pushed to ECR
✓ Terraform apply succeeded
✓ Server deployed successfully
```

---

## Roadmap

### ✅ Phase 1: Direct SAP Integration (Completed)

- [x] **MCP Server core** — FastMCP 3.2.4 with streamable-http transport
- [x] **15+ SAP ADT tools** — Read/write source, run tests, activate objects, ATC checks
- [x] **Multi-system support** — DV8, MS1, MD1
- [x] **Static credential management** — AWS Secrets Manager integration
- [x] **Portkey AI Gateway integration** — Request routing, rate limiting, analytics
- [x] **AWS ECS deployment** — Infrastructure-as-code with Terraform
- [x] **CloudWatch observability** — Logs, metrics, distributed tracing
- [x] **Kiro IDE ready** — Primary AI client for PG&E ABAP developers
- [x] **Multi-client support** — Also compatible with Amazon Q Developer and Claude Desktop

### 🚧 Phase 2: SSO + Principal Propagation (In Progress)

**Authentication & Security:**
- [x] OAuth 2.0 integration code (Microsoft Entra ID) — implemented in `server/fastmcp_oauth_integration.py`
- [x] LANID extraction logic — email.split('@')[0].upper()
- [x] Ephemeral certificate generation code — implemented in `auth/providers/certificate_auth_provider.py`
- [x] CA certificate generated and stored in AWS Secrets Manager
- [ ] **SAP Basis STRUST configuration** — CA certificate import to PSE (waiting for SAP Basis team)
- [ ] **Production OAuth provider setup** — Microsoft Entra ID app registration
- [ ] **End-to-end authentication testing** — Full OAuth → certificate → SAP flow
- [ ] **User acceptance testing** — Test with pilot group

**Portkey Configuration:**
- [ ] Production request routing rules
- [ ] Rate limiting policies (per user/team)
- [ ] Cost allocation and chargeback integration
- [ ] Analytics dashboard setup

**Infrastructure:**
- [ ] Certificate chain validation (include CA in TLS handshake)
- [ ] Load testing and performance optimization
- [ ] Production deployment with OAuth enabled

### Planned 📋

**Q2 2026:**
- [ ] Kiro IDE enhanced features (inline code suggestions, real-time syntax checking)
- [ ] Advanced code generation (entire programs, function modules)
- [ ] Intelligent code suggestions based on SAP best practices
- [ ] SAP BTP integration (Cloud Foundry, ABAP Environment)
- [ ] Amazon Q Developer extended integration

**Q3 2026:**
- [ ] CDS view generation and modification
- [ ] BAPI/RFC discovery and invocation
- [ ] Transport request workflow automation
- [ ] Integration with ServiceNow (change management)

**Q4 2026:**
- [ ] AI-powered code review (detect anti-patterns, performance issues)
- [ ] Automated test case generation
- [ ] Legacy code modernization assistant
- [ ] SAP Fiori app generation from ABAP backend

**2027:**
- [ ] Cross-system impact analysis
- [ ] Automated refactoring campaigns
- [ ] Natural language to ABAP compiler
- [ ] Real-time collaboration features

---

## FAQ

### General

**Q: What is MCP?**
A: Model Context Protocol — an open standard for connecting AI assistants to external systems. Think "USB for AI."

**Q: Why MCP instead of custom integrations?**
A: MCP is vendor-neutral and works with any MCP-enabled AI tool. We build one server, it works with Kiro IDE, Amazon Q Developer, Claude Desktop, and any future MCP-compatible tools.

**Q: Is this officially supported by SAP?**
A: We use SAP's official ADT REST API, the same API used by Eclipse ADT. SAP supports the API; this is a client implementation.

**Q: Can this replace SAP GUI completely?**
A: No. It's designed for development tasks (read/write code, run tests). Complex transactions (configuration, debugging) still require SAP GUI.

### Security

**Q: How does authentication work currently?**
A: **Phase 1 (Current):** The MCP server uses static service account credentials stored in AWS Secrets Manager. All users share the same SAP technical account. **Phase 2 (Coming Soon):** Users will authenticate with PG&E SSO (OAuth), and the server generates ephemeral certificates for individual user authentication to SAP.

**Q: How is this secure if no passwords are used? (Phase 2)**
A: We will use certificate-based authentication (mutual TLS). Each certificate is signed by a trusted CA that SAP recognizes, and includes the user's identity. This is more secure than passwords because certificates are ephemeral (5-minute validity) and tied to individual users.

**Q: Can users access more than their authorized SAP functions?**
A: **Phase 1 (Current):** All users share the SAP service account's authorizations. **Phase 2 (Future):** SAP will enforce each user's individual authorization objects - same as direct SAP GUI login. If a user doesn't have authorization for S_DEVELOP, they can't modify code via MCP either.

**Q: Is audit logging available?**
A: Yes. Every action is logged in both CloudWatch (MCP server side) and SAP Security Audit Log (SAP side), with user identity.

### Technical

**Q: What ABAP versions are supported?**
A: Any SAP system with ADT REST API enabled (NetWeaver 7.50+, S/4HANA, BTP ABAP Environment).

**Q: Does this work with SAP BTP (Cloud)?**
A: Yes. S/4HANA Cloud systems (DV8, MS1, MD1) use the same ADT API. BTP ABAP Environment support is planned.

**Q: Can I use this from my local machine?**
A: Yes, for development. Production deployments run on AWS ECS, but you can run `enterprise_main.py` locally for testing.

**Q: What's the latency?**
A: Typical response times:
- Simple queries (list objects): 200-500ms
- Source code read: 300-800ms
- Source code update + activation: 1-3 seconds
- Unit test execution: 2-10 seconds (depends on test complexity)

**Q: How many concurrent users can it handle?**
A: ECS auto-scales based on load. Each task handles ~50 concurrent requests. With auto-scaling, effectively unlimited (within AWS account limits).

### Operations

**Q: How do we troubleshoot connection issues?**
A: Check CloudWatch logs for MCP server errors. Use `openssl s_client` to verify SAP certificate configuration. See `CERTIFICATES.md` troubleshooting section.

**Q: How often do we need to rotate certificates?**
A: CA certificate: Every 10 years. Ephemeral certificates: Auto-renewed every 5 minutes (no manual intervention).

**Q: What happens if AWS is down?**
A: The MCP server becomes unavailable. Developers can still access SAP directly via SAP GUI. There's no data loss (stateless application).

**Q: How do we update the server?**
A: Commit code to GitHub → CI/CD pipeline builds new Docker image → Terraform Cloud deploys → ECS blue/green deployment (zero downtime).

---

## Glossary

| Term | Definition |
|------|------------|
| **ABAP** | Advanced Business Application Programming — SAP's proprietary programming language |
| **ADT** | ABAP Development Tools — Eclipse-based IDE for ABAP development |
| **ADT API** | REST API for programmatic access to SAP development objects |
| **ATC** | ABAP Test Cockpit — Static code analysis tool for ABAP |
| **CERTRULE** | SAP certificate mapping rules (maps X.509 certificate attributes to SAP username) |
| **CN (Common Name)** | Field in X.509 certificates identifying the subject (e.g., CN=AVRG) |
| **ECS** | Amazon Elastic Container Service — Container orchestration |
| **Entra ID** | Microsoft's cloud identity service (formerly Azure Active Directory) |
| **FastMCP** | Python framework for building MCP servers |
| **JWT** | JSON Web Token — Compact token format for OAuth 2.0 |
| **LANID** | PG&E's user identifier (usually first letter + last name) |
| **MCP** | Model Context Protocol — Standard for AI-system integration |
| **OAuth 2.0** | Industry-standard protocol for authorization |
| **Principal Propagation** | Secure technique to propagate user identity across system boundaries |
| **PSE** | Personal Security Environment — SAP's certificate store |
| **STRUST** | SAP transaction for managing certificates and PSEs |
| **TLS** | Transport Layer Security — Cryptographic protocol for secure communication |
| **X.509** | Standard format for public key certificates |

---

## Contact & Support

**Project Lead:** AICE (AI & Cloud Engineering Team)  
**AI Engineer:** Antonio Robles  
**Email:** avrg@pge.com

**Documentation:**
- **WIKI.md** (this document) — User guide, Getting Started, Kiro setup
- **README-PGE.md** — Certificate management, OAuth integration, utility scripts
- **CLAUDE.md** — Developer documentation, coding patterns
- **GitHub:** Repository URL available from AICE team

**SAP Basis Support:**
- For STRUST/CERTRULE configuration: Contact SAP Basis team
- For certificate issues: See README-PGE.md troubleshooting section

---

© 2026 Pacific Gas and Electric Company. All rights reserved.

This software is proprietary and confidential. Unauthorized copying, distribution, or use of this software, via any medium, is strictly prohibited.

**For internal use by authorized PG&E personnel only.**
