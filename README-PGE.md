# PG&E ABAP MCP Server — Technical Documentation

**Comprehensive guide for certificate management, OAuth integration, and deployment scripts**

---

## Table of Contents

### Part 1: Certificate Management
1. [Current Implementation Status](#current-implementation-status)
2. [Certificate Overview](#certificate-overview)
3. [Certificate Files and Storage](#certificate-files-and-storage)
4. [CA Certificate Properties](#ca-certificate-properties)
5. [Ephemeral Client Certificates](#ephemeral-client-certificates)
6. [SAP Configuration](#sap-configuration)
7. [Generating CA Certificates](#generating-ca-certificates)
8. [Troubleshooting Certificates](#troubleshooting-certificates)
9. [Certificate Security Best Practices](#certificate-security-best-practices)
10. [Certificate Rotation](#certificate-rotation)

### Part 2: Local Certificate Development
11. [Local Development Setup](#local-development-setup)
12. [Generating Certificates Locally](#generating-certificates-locally)
13. [Production Deployment to AWS](#production-deployment-to-aws)
14. [Terraform Cloud Integration](#terraform-cloud-integration)
15. [Sharing Certificates with SAP Basis](#sharing-certificates-with-sap-basis)
16. [Local Troubleshooting](#local-troubleshooting)

### Part 3: OAuth Integration
17. [OAuth Architecture Overview](#oauth-architecture-overview)
18. [Microsoft Entra ID Configuration](#microsoft-entra-id-configuration)
19. [AWS Cognito Configuration](#aws-cognito-configuration)
20. [IdP Auto-Detection](#idp-auto-detection)
21. [Required Code Changes for OAuth](#required-code-changes-for-oauth)
22. [OAuth Testing & Troubleshooting](#oauth-testing--troubleshooting)
23. [OAuth Security Considerations](#oauth-security-considerations)

### Part 4: Utility Scripts
24. [Scripts Overview](#scripts-overview)
25. [Certificate Generation Script](#certificate-generation-script)
26. [CA Secret Upload Script](#ca-secret-upload-script)
27. [JWT Signing Key Script](#jwt-signing-key-script)
28. [SAP Credentials Script](#sap-credentials-script)
29. [Docker Build and Push Script](#docker-build-and-push-script)
30. [ECR Cleanup Script](#ecr-cleanup-script)
31. [Typical Deployment Workflows](#typical-deployment-workflows)

---

# PART 1: CERTIFICATE MANAGEMENT FOR PRINCIPAL PROPAGATION

---

## Current Implementation Status

**⚠️ Important:** Principal Propagation (certificate-based authentication) is **Phase 2** and currently in development.

| Phase | Status | Authentication Method |
|-------|--------|----------------------|
| **Phase 1** | ✅ **Deployed (Current)** | Static SAP credentials from AWS Secrets Manager |
| **Phase 2** | 🚧 **In Development** | OAuth + Principal Propagation with ephemeral certificates |

**What's working today (Phase 1):**
- MCP Server uses static service account credentials
- All users share the same SAP technical account
- Credentials loaded from AWS Secrets Manager at startup
- No individual user identity in SAP

**What's coming soon (Phase 2):**
- OAuth authentication (Microsoft Entra ID)
- Ephemeral X.509 certificates with user's LANID
- Individual user accountability in SAP
- SAP authorization objects enforced per user
- **Awaiting:** SAP Basis STRUST configuration

---

## Certificate Overview

**What is Principal Propagation?**

Principal Propagation enables secure single sign-on (SSO) from external applications to SAP systems without storing or transmitting passwords. The ABAP MCP Server implements this using:

1. **OAuth authentication** (Microsoft Entra ID / AWS Cognito) — user authenticates once
2. **Identity resolution** — OAuth token → LANID extraction
3. **Ephemeral certificates** — short-lived X.509 client certificates signed with a trusted CA
4. **SAP certificate authentication** — SAP validates the certificate and maps to SAP user

**Certificate Architecture:**

```
┌─────────────────────────────────────────────────────────────────┐
│  CA Certificate (long-lived, 10 years)                          │
│  - Stored in AWS Secrets Manager                                │
│  - Imported to SAP STRUST (one-time setup)                      │
│  - CN=ABAP MCP CA                                               │
└───────────────────────────────────────────────────────────────┘
                                │
                                │ Signs
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Ephemeral Client Certificates (short-lived, 5 minutes)         │
│  - Generated per user request                                   │
│  - CN=<LANID> (e.g., CN=AVRG, CN=S0B4)                          │
│  - Used for TLS client authentication to SAP                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Certificate Files and Storage

### Local Development (`certificates/` directory)

```
certificates/
├── abap-mcp-ca-cert.pem          # CA public certificate (safe to share)
├── abap-mcp-ca-key.pem           # CA private key (NEVER commit - git-ignored)
├── README.md                     # Documentation
└── sample_user_*.cer             # Sample ephemeral certs for SAP Basis (DER format)
```

**Usage:**
- Local testing with `enterprise_main.py`
- Generating sample certificates for SAP Basis team
- Certificate validation and troubleshooting

**Environment variables for local mode:**
```bash
CA_CERT_PATH=/path/to/certificates/abap-mcp-ca-cert.pem
CA_KEY_PATH=/path/to/certificates/abap-mcp-ca-key.pem
```

### Production Deployment (AWS Secrets Manager)

**Secret name:** `mcp/abap-mcp-server/ca-certificate`

**Secret structure (JSON):**
```json
{
  "ca_certificate": "-----BEGIN CERTIFICATE-----\nMIIF...",
  "ca_private_key": "-----BEGIN PRIVATE KEY-----\nMIIJ..."
}
```

**Access:**
- ECS task IAM role reads secret at startup
- Secret encrypted at rest with AWS KMS
- Secret rotation: every 10 years (before expiry)

---

## CA Certificate Properties

| Property | Value |
|----------|-------|
| **Common Name (CN)** | ABAP MCP CA |
| **Organization (O)** | Pacific Gas and Electric Company |
| **Organizational Unit (OU)** | ABAP MCP Server |
| **Locality (L)** | San Francisco |
| **State (ST)** | California |
| **Country (C)** | US |
| **Key Type** | RSA 4096-bit |
| **Signature Algorithm** | SHA256 with RSA Encryption |
| **Validity** | 10 years |
| **Type** | Self-signed CA |
| **Extensions** | Basic Constraints: CA:TRUE, pathlen:0 |

---

## Ephemeral Client Certificates

### Properties

| Property | Value |
|----------|-------|
| **Common Name (CN)** | `<LANID>` (e.g., AVRG, S0B4, T1RN) |
| **Organizational Unit (OU)** | Principal-Propagation |
| **Organization (O)** | ABAP-Accelerator |
| **Country (C)** | US |
| **Issuer** | CN=ABAP MCP CA |
| **Validity** | 5 minutes |
| **Key Type** | RSA 2048-bit |
| **Extensions** | Key Usage: Digital Signature, Key Encipherment<br>Extended Key Usage: TLS Client Auth |

### Generation Flow

```
User authenticates with Entra ID/Cognito
        ↓
OAuth token received (JWT)
        ↓
Extract user identity from token
  - Entra: preferred_username or email claim
  - Cognito: UserInfo endpoint → email
        ↓
Derive LANID: email.split('@')[0].upper()
  - Example: avrg@pge.com → AVRG
        ↓
Generate ephemeral certificate
  - Subject: CN=AVRG, OU=Principal-Propagation, O=ABAP-Accelerator, C=US
  - Signed by CA private key
  - Valid for 5 minutes
        ↓
Use certificate for TLS client auth to SAP
        ↓
SAP validates certificate against trusted CA
        ↓
SAP maps CN=AVRG to SAP username (CERTRULE or Login Type E)
        ↓
SAP session established for user AVRG
```

### Caching Behavior

**What is cached:**
- ✅ **User identity** (`sub` UUID → LANID mapping) — avoids repeated UserInfo HTTP calls
- ✅ **OAuth tokens** (managed by FastMCP OAuth proxy)

**What is NOT cached:**
- ❌ **Ephemeral certificates** — regenerated on every tool invocation (5-minute validity ensures freshness)

---

## SAP Configuration

### Step 1: Import CA Certificate to STRUST

**Required PSE:** The PSE assigned to the ICM port used for ADT connections (typically port 1443 or 44300).

**How to find the correct PSE:**

1. **Transaction SMICM** → Menu: **Goto** → **Services**
2. Find the HTTPS port your MCP server uses (e.g., 1443)
3. Note the **Security** column — this shows the PSE name (e.g., `SSL server port_1443` or `SSL server Standard`)
4. **Transaction STRUST** → Expand tree and select that PSE
5. **Import Certificate:**
   - Click "Import Certificate" button
   - Select `abap-mcp-ca-cert.pem` file
   - Click "Add to Certificate List"
   - Save changes (Ctrl+S)
6. **Restart SSL session:** Transaction **SMICM** → Menu: **Administration** → **ICM** → **Restart SSL Session**

**Verification:**

Check the CA appears in the "Acceptable client certificate CA names" list:
```bash
openssl s_client -connect <sap-host>:<port> -showcerts < /dev/null 2>&1 | \
  grep -A 20 "Acceptable client certificate CA names"
```

You should see `CN=ABAP MCP CA` in the list.

### Step 2: User Mapping Configuration

The MCP server generates certificates with `CN=<LANID>` (e.g., `CN=AVRG`). SAP must map this to the corresponding SAP username.

**Option A: Login Type E (Direct Mapping) — Recommended**

If `CN` exactly matches the SAP username, use Login Type E (no CERTRULE needed):

1. **Transaction SU01** → Select user
2. Navigate to **SNC** tab
3. Set **Login Type** to **E** (X.509 Certificate)
4. Save

SAP will use the certificate CN directly as the SAP username.

**Option B: CERTRULE (Pattern-Based Mapping)**

If CN transformation is needed (e.g., adding domain suffix):

1. **Transaction SM30** → Table: **VUSREXTID**
2. Click "New Entries"
3. Configure mapping:
   - **External ID Type:** X.509 Certificate
   - **External ID Pattern:** `CN=*` (wildcard for all LANIDs)
   - **SAP Username Extraction:** Use CN value as-is

### Step 3: Sample Certificates for Testing

The MCP server can save sample ephemeral certificates for each user to help SAP Basis verify the certificate format:

**Enable sample certificate generation:**
```bash
export SAVE_SAMPLE_CERT_DIR=/path/to/certificates
```

The server will create `.cer` (DER format) and `.pem` files for each user:
```
certificates/
├── sample_user_AVRG.cognito.cer
├── sample_user_AVRG.cognito.pem
├── sample_user_S0B4.entra.cer
└── sample_user_S0B4.entra.pem
```

Send these to SAP Basis to verify the certificate format before production deployment.

---

## Generating CA Certificates

### Automatic Generation (Recommended)

The deployment process automatically generates certificates if they don't exist:

```bash
./scripts/generate-ca-certificates.sh
```

The script:
1. Checks for existing certificates in `certificates/` directory
2. Generates self-signed CA if missing (RSA 4096-bit, 10-year validity)
3. Uploads to AWS Secrets Manager
4. Displays certificate details for verification
5. Continues with Docker build and deployment

### Manual Generation

**Generate CA private key:**
```bash
openssl genrsa -out certificates/abap-mcp-ca-key.pem 4096
```

**Generate self-signed CA certificate:**
```bash
openssl req -new -x509 -days 3650 \
  -key certificates/abap-mcp-ca-key.pem \
  -out certificates/abap-mcp-ca-cert.pem \
  -subj "/C=US/ST=California/L=San Francisco/O=Pacific Gas and Electric Company/OU=ABAP MCP Server/CN=ABAP MCP CA"
```

**Upload to AWS Secrets Manager:**
```bash
./scripts/create-ca-secret.sh
```

---

## Troubleshooting Certificates

### Issue: `SSLV3_ALERT_CERTIFICATE_UNKNOWN`

**Symptom:**
```
ssl.SSLError: [SSL: SSLV3_ALERT_CERTIFICATE_UNKNOWN] ssl/tls alert certificate unknown
```

**Root cause:** SAP rejects the client certificate because the CA is not trusted in the PSE assigned to the connection port.

**Diagnosis:**
1. Check which CAs SAP accepts on that port:
   ```bash
   openssl s_client -connect <sap-host>:<port> -showcerts < /dev/null 2>&1 | \
     grep -A 30 "Acceptable client certificate CA names"
   ```

2. Verify `CN=ABAP MCP CA` appears in the list

**Solution:**
- If missing: Import CA to the **correct PSE** (see Step 1 above)
- If present: Restart SSL session in SMICM
- **Common mistake:** Importing to "SSL server Standard" PSE when port 1443 uses a different PSE (e.g., "SSL server port_1443")

### Issue: Certificate CN Format Mismatch

**Symptom:** SAP accepts certificate but user mapping fails (no session created).

**Diagnosis:**
Check generated certificate format:
```bash
openssl x509 -in certificates/sample_user_AVRG.pem -noout -subject
```

Expected: `subject=C=US, O=ABAP-Accelerator, OU=Principal-Propagation, CN=AVRG`

**Solution:**
- Certificate should have `CN=<LANID>` only (no domain suffix like `@pge.com`)
- If CERTRULE is configured, ensure pattern matches the CN format
- If using Login Type E, ensure CN exactly matches SAP username

### Issue: OAuth UserInfo Returns UUID Instead of Email

**Symptom:** Certificate generated with `CN=<UUID>` instead of `CN=<LANID>`.

**Diagnosis:**
Check server logs for UserInfo resolution:
```
[INFO] OAuth: Resolved '<UUID>' → '<LANID>' via UserInfo
```

**Solution (Cognito):**
- UserInfo endpoint returns `username` (UUID) and `email` claims
- Server prioritizes `email` claim: `userinfo.get('email') or userinfo.get('username')`
- LANID extracted from email: `email.split('@')[0].upper()`

**Solution (Entra ID):**
- Graph UserInfo may return 401 if token audience is custom API
- Server falls back to JWT `preferred_username` claim
- LANID extracted: `preferred_username.split('@')[0].upper()`

### Issue: Certificate Expired

**Symptom:** SAP rejects certificate with "Certificate expired" error.

**Root cause:** Ephemeral certificates have 5-minute validity. Clock skew between MCP server and SAP can cause premature expiration.

**Solution:**
- Ensure NTP time sync on both MCP server and SAP system
- Certificates include 1-minute clock skew buffer (valid from `now - 1 minute`)
- Check server logs for certificate generation timestamps

---

## Certificate Security Best Practices

### ✅ DO

- ✅ Store CA private key only in AWS Secrets Manager (encrypted at rest)
- ✅ Use IAM roles for secret access (no hardcoded credentials)
- ✅ Monitor CA certificate expiry (rotate before 10-year deadline)
- ✅ Use minimum 4096-bit RSA for CA, 2048-bit for ephemeral certs
- ✅ Keep ephemeral certificate validity short (5 minutes)
- ✅ Protect `certificates/abap-mcp-ca-key.pem` with file permissions (chmod 600)
- ✅ Send only public CA certificate (`abap-mcp-ca-cert.pem`) to SAP Basis
- ✅ Enable audit logging for certificate generation events
- ✅ Cache user identity resolution to minimize UserInfo API calls

### ❌ DON'T

- ❌ Commit private keys to version control (protected by `.gitignore`)
- ❌ Email or Slack private keys (send only public certificate)
- ❌ Store private keys in plaintext outside Secrets Manager
- ❌ Use weak encryption (< 2048-bit RSA)
- ❌ Extend ephemeral certificate validity beyond 60 minutes
- ❌ Skip SSL/TLS verification in production (`SSL_VERIFY=false`)
- ❌ Share AWS Secrets Manager secret ARN with unauthorized users
- ❌ Import CA to wrong PSE in STRUST (verify port mapping first)

---

## Certificate Rotation

**When to rotate:**
- CA certificate approaches expiry (before 10-year deadline)
- Private key compromise suspected
- Migrating to new SAP landscape

**Rotation process:**

1. **Generate new CA certificate pair:**
   ```bash
   rm -f certificates/abap-mcp-ca-*.pem
   ./scripts/generate-ca-certificates.sh
   ```

2. **Update AWS Secrets Manager:**
   ```bash
   ./scripts/create-ca-secret.sh
   ```

3. **Import new CA to SAP STRUST:**
   - Send new `abap-mcp-ca-cert.pem` to SAP Basis
   - Import to same PSE as old certificate
   - **Keep old CA** during transition period (dual-CA support)

4. **Test with new certificates:**
   - Verify new ephemeral certificates are signed by new CA
   - Test SAP connection with new certificates

5. **Remove old CA from STRUST:**
   - After all clients use new certificates
   - Remove old CA from STRUST certificate list

**Transition period:** Run dual CAs for 1-2 weeks to ensure smooth migration.

---

## SAP Basis Configuration Procedures

This section describes the configuration steps that must be performed by the SAP Basis team to enable Principal Propagation.

### Certificate Import to STRUST

**Objective:** Import the CA certificate (`abap-mcp-ca-cert.pem`) into the correct PSE on each SAP system.

**Critical Requirement:** The certificate must be imported into the PSE assigned to the ICM port used for ADT connections (typically port 1443 or 44300).

**Procedure:**

1. **Identify the correct PSE:**
   - Run transaction **SMICM**
   - Navigate to menu: **Goto** → **Services**
   - Locate the HTTPS service listening on port 1443 (or 44300 for S/4HANA Cloud)
   - Note the PSE name displayed in the **Security** column (e.g., "SSL server port_1443" or "SSL server Standard")

2. **Import CA certificate:**
   - Run transaction **STRUST**
   - In the PSE tree (left panel), navigate to and double-click the PSE identified in step 1
   - In the "Certificate" section, click the "Import Certificate" button
   - Browse to and select the `abap-mcp-ca-cert.pem` file
   - Click "Add to Certificate List" (the certificate should now appear in the certificate list)
   - Save changes (Ctrl+S or click save icon)

3. **Activate changes:**
   - Run transaction **SMICM**
   - Navigate to menu: **Administration** → **ICM** → **Restart SSL Session**
   - This applies the new certificate without restarting the ICM

4. **Verification:**
   - From the MCP server host, run:
     ```bash
     openssl s_client -connect <sap-host>:<port> -showcerts < /dev/null 2>&1 | \
       grep -A 20 "Acceptable client certificate CA names"
     ```
   - Verify that `CN=ABAP MCP CA` appears in the list of accepted CAs

**Systems requiring configuration:**
- **DV8:** sapdv8db1.comp.pge.com:1443 (client 120)
- **MS1:** vhpgxms1ci.s4hc.pge.com:44300 (client 100)
- **MD1:** vhpgxmd1ci.s4hc.pge.com:44300 (client 100)

### User Certificate Mapping

**Objective:** Configure SAP to map certificate CN values to SAP usernames.

Ephemeral client certificates are generated with **CN=<LANID>** format (e.g., CN=AVRG, CN=S0B4, CN=T1RN).

**Option A: Login Type E (Recommended)**

Use this method when the certificate CN exactly matches the SAP username.

**Procedure:**
1. Run transaction **SU01**
2. Enter the username (e.g., AVRG)
3. Click "Change" (Edit mode)
4. Navigate to the **SNC** tab
5. Set **Login Type** to **E** (X.509 Certificate)
6. Save changes

**Advantages:**
- Simple configuration (no CERTRULE required)
- Direct CN-to-username mapping
- Works when CN=SAP username

**Option B: CERTRULE Configuration**

Use this method if certificate transformation or pattern matching is needed.

**Procedure:**
1. Run transaction **SM30**
2. Enter table name: **VUSREXTID**
3. Click "Maintain"
4. Click "New Entries"
5. Configure mapping rule:
   - **External ID Type:** X.509 Certificate (select from dropdown)
   - **External ID Pattern:** `CN=*` (wildcard matching all certificates)
   - **SAP Username:** Leave empty to use CN value as-is, or configure extraction rule
6. Save changes

**Advantages:**
- Supports pattern matching and transformation
- Centralized rule management
- Can handle complex mapping scenarios

### Sample Certificates for Testing

Sample ephemeral certificates are available in DER format (`.cer` files) for import testing:
- `sample_user_AVRG.cer`
- `sample_user_S0B4.cer`
- `sample_user_T1RN.cer`

These demonstrate the exact format of certificates the MCP server will present during TLS client authentication.

**Verification:**
```bash
# View certificate details
openssl x509 -inform DER -in sample_user_AVRG.cer -noout -text

# Confirm CN format
openssl x509 -inform DER -in sample_user_AVRG.cer -noout -subject
# Expected: subject=C=US, O=ABAP-Accelerator, OU=Principal-Propagation, CN=AVRG
```

---

# PART 2: LOCAL CERTIFICATE DEVELOPMENT

---

## Local Development Setup

This section covers certificate management for local development and testing.

### Purpose

These certificates enable **Principal Propagation** — secure, password-less authentication from MCP clients to SAP:

1. **User authenticates** with OAuth (Microsoft Entra ID or AWS Cognito)
2. **MCP server extracts LANID** from OAuth token (e.g., `avrg@pge.com` → `AVRG`)
3. **Server generates ephemeral certificate** signed by this CA with `CN=<LANID>`
4. **Certificate used for TLS client auth** to SAP ADT API
5. **SAP validates certificate** against CA imported in STRUST
6. **SAP maps CN to SAP username** (via CERTRULE or Login Type E)
7. **SAP session established** for the user

### Environment Configuration

For local development, configure `enterprise_main.py` to load certificates from the `certificates/` directory:

**.env file:**
```bash
ENABLE_PRINCIPAL_PROPAGATION=true
CA_CERT_PATH=/Users/<username>/Dev/abap-mcp-server/certificates/abap-mcp-ca-cert.pem
CA_KEY_PATH=/Users/<username>/Dev/abap-mcp-server/certificates/abap-mcp-ca-key.pem
```

**Alternative (absolute path in code):**
```python
# enterprise_main.py fallback paths
ca_cert_path = os.getenv('CA_CERT_PATH', '/path/to/certificates/abap-mcp-ca-cert.pem')
ca_key_path = os.getenv('CA_KEY_PATH', '/path/to/certificates/abap-mcp-ca-key.pem')
```

---

## Generating Certificates Locally

### Using the Provided Script (Recommended)

```bash
# From project root
./scripts/generate-ca-certificates.sh
```

The script automatically:
- Generates RSA 4096-bit CA private key
- Creates self-signed certificate (10-year validity)
- Sets correct file permissions (600 for key, 644 for cert)
- Displays certificate details for verification

### Manual Generation with OpenSSL

```bash
# Generate CA private key (RSA 4096-bit)
openssl genrsa -out abap-mcp-ca-key.pem 4096

# Generate self-signed CA certificate (10-year validity)
openssl req -new -x509 -days 3650 \
  -key abap-mcp-ca-key.pem \
  -out abap-mcp-ca-cert.pem \
  -subj "/C=US/ST=California/L=San Francisco/O=Pacific Gas and Electric Company/OU=ABAP MCP Server/CN=ABAP MCP CA"

# Set secure permissions
chmod 600 abap-mcp-ca-key.pem
chmod 644 abap-mcp-ca-cert.pem
```

### Verify Certificate

```bash
# View certificate details
openssl x509 -in abap-mcp-ca-cert.pem -noout -text

# Check it's a CA certificate
openssl x509 -in abap-mcp-ca-cert.pem -noout -text | grep "CA:TRUE"

# Verify self-signed (subject == issuer)
openssl x509 -in abap-mcp-ca-cert.pem -noout -subject -issuer
```

---

## Production Deployment to AWS

### Upload to AWS Secrets Manager

Certificates are stored in AWS Secrets Manager for production ECS deployment.

**Using the provided script (recommended):**
```bash
# From project root
./scripts/create-ca-secret.sh
```

**Manual upload:**
```bash
python3 << 'EOF'
import json, boto3

# Read certificate files
with open('certificates/abap-mcp-ca-cert.pem', 'r') as f:
    ca_cert = f.read()
with open('certificates/abap-mcp-ca-key.pem', 'r') as f:
    ca_key = f.read()

# Upload to Secrets Manager
client = boto3.client('secretsmanager', region_name='us-west-2')
client.create_secret(
    Name='mcp/abap-mcp-server/ca-certificate',
    Description='CA certificate for ABAP MCP Server principal propagation',
    SecretString=json.dumps({
        "ca_certificate": ca_cert,
        "ca_private_key": ca_key
    })
)
print("✓ Secret created successfully")
EOF
```

**Update existing secret:**
```bash
python3 << 'EOF'
import json, boto3

with open('certificates/abap-mcp-ca-cert.pem', 'r') as f:
    ca_cert = f.read()
with open('certificates/abap-mcp-ca-key.pem', 'r') as f:
    ca_key = f.read()

client = boto3.client('secretsmanager', region_name='us-west-2')
client.put_secret_value(
    SecretId='mcp/abap-mcp-server/ca-certificate',
    SecretString=json.dumps({
        "ca_certificate": ca_cert,
        "ca_private_key": ca_key
    })
)
print("✓ Secret updated")
EOF
```

**Automated workflow:**
```bash
# 1. Generate certificates
./scripts/generate-ca-certificates.sh

# 2. Upload to AWS
./scripts/create-ca-secret.sh

# 3. Build and deploy
./scripts/build-and-push-docker.sh
```

### Secret Structure

AWS Secrets Manager secret format:

```json
{
  "ca_certificate": "-----BEGIN CERTIFICATE-----\nMIIF...",
  "ca_private_key": "-----BEGIN PRIVATE KEY-----\nMIIJ..."
}
```

**Secret name:** `mcp/abap-mcp-server/ca-certificate`  
**Region:** `us-west-2` (configurable via `AWS_REGION` env var)  
**Encryption:** AWS KMS (default)

---

## Terraform Cloud Integration

TFC deployment does **NOT** read files from the `certificates/` directory. Instead:

### Mode 1: Existing Secret (Current)

TFC reads pre-existing secret from AWS Secrets Manager:

**terraform.tfvars:**
```hcl
certificate_mode = "existing"
existing_ca_secret_name = "mcp/abap-mcp-server/ca-certificate"
```

**Benefits:**
- No sensitive data in TFC variables
- Certificates validated and working before TFC run
- Fast TFC execution (no resource creation)

### Mode 2: Terraform-Managed Secret (Future)

TFC creates and manages the secret using PGE SAF 2.0 modules:

**terraform.tfvars:**
```hcl
certificate_mode = "create"
```

**TFC variables (sensitive):**
- `ca_cert_pem` — content of `abap-mcp-ca-cert.pem`
- `ca_key_pem` — content of `abap-mcp-ca-key.pem` (mark as sensitive)

**Benefits:**
- Full infrastructure-as-code
- SAF 2.0 compliance
- Integrated with PGE KMS

---

## Sharing Certificates with SAP Basis

### What to Share

✅ **Safe to share:**
- `abap-mcp-ca-cert.pem` (public certificate)
- `sample_user_*.cer` (sample ephemeral certificates)
- Certificate details (subject, issuer, expiry date)

❌ **NEVER share:**
- `abap-mcp-ca-key.pem` (private key)
- AWS Secrets Manager secret ARN or credentials
- Terraform state files

### How to Share

Provide SAP Basis team with:

**Files:**
- `abap-mcp-ca-cert.pem` (CA certificate for STRUST import)
- `sample_user_AVRG.cer` (example ephemeral certificate)

**Certificate Details:**
- Subject: CN=ABAP MCP CA, OU=ABAP MCP Server, O=Pacific Gas and Electric Company
- Type: Self-signed CA
- Validity: 10 years
- Purpose: Validates ephemeral client certificates with CN=<LANID>

**STRUST Import Instructions:**
1. Transaction SMICM → Goto → Services → Note PSE for port 1443
2. Transaction STRUST → Select that PSE → Import Certificate
3. SMICM → Administration → ICM → Restart SSL Session

**User Mapping:**
- Ephemeral certificates have CN=<LANID> (e.g., CN=AVRG)
- Recommended: Use Login Type E (SU01 → SNC tab)

---

## Local Troubleshooting

### Issue: Certificates Not Found

**Error:** `CA certificate not found at /path/to/abap-mcp-ca-cert.pem`

**Solution:**
1. Check file exists: `ls -l certificates/*.pem`
2. Generate if missing: `./scripts/generate-ca-certificates.sh`
3. Verify permissions: `chmod 600 certificates/abap-mcp-ca-key.pem && chmod 644 certificates/abap-mcp-ca-cert.pem`
4. Check environment variables: `echo $CA_CERT_PATH`

### Issue: Permission Denied

**Error:** `PermissionError: [Errno 13] Permission denied: 'abap-mcp-ca-key.pem'`

**Solution:**
```bash
# Fix permissions
chmod 600 certificates/abap-mcp-ca-key.pem

# Check ownership
ls -l certificates/abap-mcp-ca-key.pem

# Fix ownership if needed
chown $USER:$USER certificates/abap-mcp-ca-key.pem
```

### Issue: Invalid Certificate Format

**Error:** `ssl.SSLError: PEM lib`

**Solution:**
```bash
# Verify PEM format
openssl x509 -in certificates/abap-mcp-ca-cert.pem -noout -text

# Re-encode if needed
openssl x509 -in certificates/abap-mcp-ca-cert.pem -out certificates/abap-mcp-ca-cert-fixed.pem
```

### Issue: Certificate Expired

**Error:** `Certificate has expired`

**Solution:**
```bash
# Check expiry date
openssl x509 -in certificates/abap-mcp-ca-cert.pem -noout -enddate

# Generate new certificate
rm certificates/abap-mcp-ca-*.pem
./scripts/generate-ca-certificates.sh
```

---

# PART 3: OAUTH INTEGRATION IMPLEMENTATION

---

## OAuth Architecture Overview

The ABAP MCP Server supports OAuth 2.0 authentication with **Microsoft Entra ID (Azure AD)** and **AWS Cognito**. The implementation is **IdP-agnostic** — switching between identity providers requires only changing the `.env` file, with **zero code changes**.

**Key capabilities:**
- ✅ Multi-IdP support (Entra ID, Cognito) with automatic detection
- ✅ FastMCP 3.2.4+ OAuth integration (streamable-http transport)
- ✅ LANID extraction from OAuth tokens for principal propagation
- ✅ Identity caching to minimize UserInfo API calls
- ✅ Compatible with Kiro IDE, Amazon Q, and MCP Inspector

### Authentication Flow

```
┌────────────────────────────────────────────────────────────────────┐
│  1. User opens MCP client (Kiro, Amazon Q)                         │
│     Client requests tool list from MCP server                       │
└────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────────┐
│  2. MCP Server responds with 401 Unauthorized                       │
│     Returns OAuth metadata (issuer, auth endpoint, scopes)          │
└────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────────┐
│  3. Client redirects user to OAuth provider                         │
│     - Entra ID: login.microsoftonline.com                          │
│     - Cognito: *.auth.amazoncognito.com                            │
└────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────────┐
│  4. User authenticates with IdP (SSO login)                         │
│     - Entra: PG&E credentials via SSO                               │
│     - Cognito: Cognito user pool credentials                        │
└────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────────┐
│  5. IdP issues authorization code                                   │
│     Client exchanges code for access token                          │
└────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────────┐
│  6. MCP Server validates JWT token                                  │
│     - Verifies signature (JWKS)                                     │
│     - Validates issuer, audience, expiry                            │
└────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────────┐
│  7. Extract user identity from token                                │
│     - Entra: preferred_username or email claim                      │
│     - Cognito: UserInfo endpoint → email                            │
└────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────────┐
│  8. Derive LANID from identity                                      │
│     email.split('@')[0].upper()                                     │
│     Example: avrg@pge.com → AVRG                                    │
└────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────────┐
│  9. Generate ephemeral X.509 certificate                            │
│     Subject: CN=<LANID>, OU=Principal-Propagation, ...              │
│     Signed by CA, valid for 5 minutes                               │
└────────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────────┐
│  10. Use certificate for SAP authentication                         │
│      TLS client auth → SAP validates cert → maps CN to user         │
└────────────────────────────────────────────────────────────────────┘
```

### Components

**Files involved:**
- `src/aws_abap_accelerator/server/fastmcp_oauth_integration.py` — OAuth configuration and FastMCP integration
- `src/aws_abap_accelerator/auth/principal_propagation.py` — Certificate generation
- `src/aws_abap_accelerator/auth/providers/certificate_auth_provider.py` — Certificate provider implementation

**Key environment variables:**
```bash
ENABLE_OAUTH_FLOW=true
OAUTH_ISSUER=https://...
OAUTH_AUTH_ENDPOINT=https://...
OAUTH_TOKEN_ENDPOINT=https://...
OAUTH_CLIENT_ID=your-client-id
OAUTH_CLIENT_SECRET=your-client-secret
SERVER_BASE_URL=https://your-server.com
SSL_VERIFY=true
```

---

## Microsoft Entra ID Configuration

### Prerequisites

- Microsoft Entra ID tenant (formerly Azure AD)
- App registration in Entra ID
- PG&E SSO integration configured

### Step 1: Create App Registration

1. Navigate to **Azure Portal** → **Microsoft Entra ID** → **App registrations**
2. Click **"New registration"**
3. Configure:
   - **Name:** ABAP MCP Server
   - **Supported account types:** Single tenant (PG&E only)
   - **Redirect URI:** Web → `https://your-mcp-server.com/oauth/callback`
4. Click **"Register"**

### Step 2: Configure Authentication

1. Go to **Authentication** in left menu
2. **Platform configurations:**
   - Add Web platform if not already added
   - Redirect URIs: `https://your-mcp-server.com/oauth/callback`
3. **Implicit grant and hybrid flows:**
   - ✅ Enable "ID tokens" (for hybrid flow support)
4. **Advanced settings:**
   - Allow public client flows: **No**
5. Click **"Save"**

### Step 3: Generate Client Secret

1. Go to **Certificates & secrets** in left menu
2. Click **"New client secret"**
3. Configure:
   - **Description:** MCP Server Production
   - **Expires:** 24 months (or per policy)
4. Click **"Add"**
5. **Copy the secret value immediately** (won't be shown again)

### Step 4: Configure API Permissions

1. Go to **API permissions** in left menu
2. Click **"Add a permission"**
3. Select **"Microsoft Graph"**
4. Choose **"Delegated permissions"**
5. Add:
   - `User.Read` (read user profile)
   - `email` (read user email)
   - `openid` (OpenID Connect)
   - `profile` (read user profile info)
6. Click **"Add permissions"**
7. Click **"Grant admin consent for [Tenant]"** (requires admin)

### Step 5: Configure Token Claims

1. Go to **Token configuration** in left menu
2. Click **"Add optional claim"**
3. Select **"ID"** token type
4. Add claims:
   - `email` — User's email address
   - `preferred_username` — User's LANID@pge.com
   - `upn` — User principal name
5. Click **"Add"**

### Step 6: Get Configuration Values

From the **Overview** page, note:
- **Application (client) ID** → `OAUTH_CLIENT_ID`
- **Directory (tenant) ID** → used in issuer URL

**Environment configuration (.env):**
```bash
# Microsoft Entra ID OAuth
ENABLE_OAUTH_FLOW=true
OAUTH_ISSUER=https://login.microsoftonline.com/YOUR_TENANT_ID/v2.0
OAUTH_AUTH_ENDPOINT=https://login.microsoftonline.com/YOUR_TENANT_ID/oauth2/v2.0/authorize
OAUTH_TOKEN_ENDPOINT=https://login.microsoftonline.com/YOUR_TENANT_ID/oauth2/v2.0/token
OAUTH_CLIENT_ID=YOUR_CLIENT_ID
OAUTH_CLIENT_SECRET=YOUR_CLIENT_SECRET
SERVER_BASE_URL=https://your-mcp-server.com
SSL_VERIFY=true
```

### LANID Extraction (Entra ID)

The server extracts LANID from the JWT token's `preferred_username` claim:

```python
def extract_user_from_token(jwt_token: dict) -> str:
    # Entra ID returns: preferred_username = "avrg@pge.com"
    email = jwt_token.get('preferred_username') or jwt_token.get('email')
    if not email:
        raise AuthenticationError("No email in token")
    
    # Extract LANID: "avrg@pge.com" → "AVRG"
    lanid = email.split('@')[0].upper()
    return lanid
```

**Claim priority:**
1. `preferred_username` (primary)
2. `email` (fallback)
3. `upn` (last resort)

---

## AWS Cognito Configuration

### Prerequisites

- AWS Cognito User Pool
- Users imported or federated from PG&E AD

### Step 1: Create User Pool (if needed)

```bash
aws cognito-idp create-user-pool \
  --pool-name abap-mcp-users \
  --auto-verified-attributes email \
  --policies '{
    "PasswordPolicy": {
      "MinimumLength": 12,
      "RequireUppercase": true,
      "RequireLowercase": true,
      "RequireNumbers": true,
      "RequireSymbols": true
    }
  }' \
  --region us-east-1
```

### Step 2: Create App Client

```bash
aws cognito-idp create-user-pool-client \
  --user-pool-id us-east-1_XXXXXX \
  --client-name abap-mcp-server \
  --generate-secret \
  --allowed-o-auth-flows code \
  --allowed-o-auth-scopes openid email profile \
  --callback-urls https://your-mcp-server.com/oauth/callback \
  --supported-identity-providers COGNITO \
  --region us-east-1
```

**Note the output:**
- `ClientId` → `OAUTH_CLIENT_ID`
- `ClientSecret` → `OAUTH_CLIENT_SECRET`

### Step 3: Configure Domain

```bash
aws cognito-idp create-user-pool-domain \
  --user-pool-id us-east-1_XXXXXX \
  --domain abap-mcp-pge \
  --region us-east-1
```

This creates: `https://abap-mcp-pge.auth.us-east-1.amazoncognito.com`

### Step 4: Configure User Attributes

Ensure user pool has `email` attribute:

```bash
aws cognito-idp update-user-pool \
  --user-pool-id us-east-1_XXXXXX \
  --user-attribute-update-settings AttributesRequireVerificationBeforeUpdate=email \
  --region us-east-1
```

### Step 5: Get Configuration Values

**Environment configuration (.env):**
```bash
# AWS Cognito OAuth
ENABLE_OAUTH_FLOW=true
OAUTH_ISSUER=https://cognito-idp.us-east-1.amazonaws.com/us-east-1_XXXXXX
OAUTH_AUTH_ENDPOINT=https://abap-mcp-pge.auth.us-east-1.amazoncognito.com/oauth2/authorize
OAUTH_TOKEN_ENDPOINT=https://abap-mcp-pge.auth.us-east-1.amazoncognito.com/oauth2/token
OAUTH_CLIENT_ID=YOUR_CLIENT_ID
OAUTH_CLIENT_SECRET=YOUR_CLIENT_SECRET
SERVER_BASE_URL=https://your-mcp-server.com
SSL_VERIFY=true
```

### LANID Extraction (Cognito)

Cognito requires calling the UserInfo endpoint:

```python
def extract_user_from_token_cognito(access_token: str) -> str:
    # Call Cognito UserInfo endpoint
    userinfo_url = "https://abap-mcp-pge.auth.us-east-1.amazoncognito.com/oauth2/userInfo"
    response = requests.get(
        userinfo_url,
        headers={"Authorization": f"Bearer {access_token}"}
    )
    userinfo = response.json()
    
    # Cognito returns: {"sub": "uuid", "email": "avrg@pge.com", "username": "uuid"}
    email = userinfo.get('email') or userinfo.get('username')
    if not email or '@' not in email:
        raise AuthenticationError("No valid email in UserInfo")
    
    # Extract LANID: "avrg@pge.com" → "AVRG"
    lanid = email.split('@')[0].upper()
    return lanid
```

**Identity caching:**
```python
# Cache to avoid repeated UserInfo calls
_sub_identity_cache = {}

def get_cached_identity(sub_uuid: str) -> str:
    if sub_uuid in _sub_identity_cache:
        return _sub_identity_cache[sub_uuid]
    
    # Call UserInfo, extract LANID
    lanid = extract_user_from_token_cognito(access_token)
    
    # Cache for future requests
    _sub_identity_cache[sub_uuid] = lanid
    return lanid
```

---

## IdP Auto-Detection

The server automatically detects which IdP is being used based on the `OAUTH_ISSUER` URL:

```python
def detect_idp(issuer: str) -> str:
    """Auto-detect identity provider from issuer URL"""
    if 'cognito' in issuer.lower():
        return 'cognito'
    elif 'microsoftonline.com' in issuer.lower() or 'login.microsoft' in issuer.lower():
        return 'entra'
    elif 'okta.com' in issuer.lower():
        return 'okta'
    else:
        return 'unknown'
```

**IdP-specific behavior:**

| IdP | LANID Source | UserInfo Call | Special Handling |
|-----|--------------|---------------|------------------|
| **Entra ID** | JWT claim `preferred_username` | ❌ Not needed | Auto-detects audience |
| **Cognito** | UserInfo endpoint `email` | ✅ Required | Caching to minimize calls |
| **Okta** | JWT claim `preferred_username` | ❌ Not needed | Strips RFC 8707 `resource` param |

---

## Required Code Changes for OAuth

### File: `server/fastmcp_oauth_integration.py`

**Add SSL verification monkey-patch:**

```python
import httpx
import os

# Monkey-patch httpx.AsyncClient to respect SSL_VERIFY env var
_orig_init = httpx.AsyncClient.__init__

def patched_init(self, *args, **kwargs):
    ssl_verify = os.getenv('SSL_VERIFY', 'true').lower() != 'false'
    kwargs['verify'] = ssl_verify
    return _orig_init(self, *args, **kwargs)

httpx.AsyncClient.__init__ = patched_init
```

**Configure FastMCP OAuth:**

```python
from fastmcp import FastMCP

mcp = FastMCP(
    name="ABAP-Accelerator-Enterprise",
    version="3.2.4",
    transport="streamable-http",
    oauth_config={
        "issuer": os.getenv("OAUTH_ISSUER"),
        "authorization_endpoint": os.getenv("OAUTH_AUTH_ENDPOINT"),
        "token_endpoint": os.getenv("OAUTH_TOKEN_ENDPOINT"),
        "client_id": os.getenv("OAUTH_CLIENT_ID"),
        "client_secret": os.getenv("OAUTH_CLIENT_SECRET"),
        "scopes": ["openid", "email", "profile"],
        "redirect_uri": f"{os.getenv('SERVER_BASE_URL')}/oauth/callback"
    }
)
```

**Extract LANID:**

```python
def extract_lanid_from_fastmcp_token() -> str:
    """Extract LANID from FastMCP OAuth token"""
    from fastmcp import Context
    
    ctx = Context()
    jwt_token = ctx.request_context.get_oauth_token()
    
    idp = detect_idp(jwt_token.get('iss', ''))
    
    if idp == 'entra':
        # Entra ID: Use preferred_username claim
        email = jwt_token.get('preferred_username') or jwt_token.get('email')
    elif idp == 'cognito':
        # Cognito: Call UserInfo endpoint
        sub_uuid = jwt_token.get('sub')
        if sub_uuid in _sub_identity_cache:
            return _sub_identity_cache[sub_uuid]
        
        email = call_cognito_userinfo(ctx.request_context.access_token)
        lanid = email.split('@')[0].upper()
        _sub_identity_cache[sub_uuid] = lanid
        return lanid
    else:
        email = jwt_token.get('email') or jwt_token.get('preferred_username')
    
    if not email or '@' not in email:
        raise AuthenticationError("No valid email in token")
    
    lanid = email.split('@')[0].upper()
    return lanid
```

### File: `auth/providers/certificate_auth_provider.py`

**Generate ephemeral certificate:**

```python
from cryptography import x509
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from datetime import datetime, timedelta

def generate_ephemeral_certificate(lanid: str, validity_minutes: int = 5) -> tuple[str, str]:
    """Generate ephemeral X.509 certificate for SAP authentication"""
    
    # Generate RSA key pair
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048
    )
    
    # Build certificate subject
    subject = x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "ABAP-Accelerator"),
        x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "Principal-Propagation"),
        x509.NameAttribute(NameOID.COMMON_NAME, lanid),  # CN=AVRG
    ])
    
    # Calculate validity (5 minutes)
    now = datetime.utcnow()
    not_before = now - timedelta(minutes=1)  # Clock skew buffer
    not_after = now + timedelta(minutes=validity_minutes)
    
    # Load CA certificate and private key
    ca_cert = load_ca_certificate()
    ca_key = load_ca_private_key()
    
    # Build and sign certificate
    certificate = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(ca_cert.subject)
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
        .sign(private_key=ca_key, algorithm=hashes.SHA256())
    )
    
    # Serialize to PEM format
    cert_pem = certificate.public_bytes(serialization.Encoding.PEM).decode('utf-8')
    key_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    ).decode('utf-8')
    
    return cert_pem, key_pem
```

---

## OAuth Testing & Troubleshooting

### Testing with MCP Inspector

**Install MCP Inspector:**
```bash
npm install -g @modelcontextprotocol/inspector
```

**Test OAuth flow:**
```bash
npx @modelcontextprotocol/inspector \
  https://your-mcp-server.com/mcp
```

**Expected flow:**
1. Inspector opens browser for OAuth login
2. User authenticates with IdP
3. Inspector receives OAuth token
4. Inspector displays available MCP tools
5. Tool invocations include Bearer token

### Testing with Kiro IDE

**Configure Kiro:**
```json
{
  "mcpServers": {
    "abap-accelerator-pge": {
      "url": "https://your-mcp-server.com/mcp"
    }
  }
}
```

**Test flow:**
1. Open Kiro IDE
2. Kiro prompts for authentication
3. Browser opens with IdP login
4. After login, Kiro shows ABAP tools
5. Query: "List ABAP packages in DV8"

### Common Issues

**Issue: "Invalid redirect_uri"**

**Cause:** Redirect URI not registered in IdP app configuration

**Solution:**
- Entra ID: Add `https://your-server.com/oauth/callback` to Redirect URIs
- Cognito: Add to Callback URLs in App Client settings

**Issue: "Token validation failed"**

**Cause:** JWT signature verification failed

**Solution:**
- Check JWKS endpoint is accessible
- Verify `OAUTH_ISSUER` matches JWT `iss` claim exactly
- Check system time (NTP sync)

**Issue: "No email claim in token"**

**Cause:** IdP not configured to include email in token

**Solution:**
- Entra ID: Add `email` as optional claim in Token configuration
- Cognito: Ensure `email` attribute is set for users

**Issue: UserInfo returns 401 (Cognito)**

**Cause:** Access token doesn't have UserInfo scope

**Solution:**
- Add `openid` and `email` to allowed OAuth scopes in App Client

---

## OAuth Security Considerations

### Token Storage

**✅ DO:**
- ✅ Store tokens in memory only (FastMCP handles this)
- ✅ Use HTTPS for all OAuth endpoints
- ✅ Validate JWT signatures with JWKS
- ✅ Check token expiry before use
- ✅ Use short-lived access tokens (< 1 hour)

**❌ DON'T:**
- ❌ Store tokens in cookies without HttpOnly/Secure flags
- ❌ Log access tokens or refresh tokens
- ❌ Share tokens between users
- ❌ Skip SSL/TLS verification (`SSL_VERIFY=false` in production)

### Client Secret Protection

**✅ DO:**
- ✅ Store client secret in AWS Secrets Manager
- ✅ Use IAM roles to access secrets
- ✅ Rotate secrets every 6-12 months
- ✅ Use different secrets for dev/test/prod

**❌ DON'T:**
- ❌ Commit secrets to version control
- ❌ Email or Slack secrets
- ❌ Use the same secret across environments

### Redirect URI Validation

**✅ DO:**
- ✅ Use exact match for redirect URIs (no wildcards)
- ✅ Use HTTPS for all redirect URIs
- ✅ Validate `state` parameter to prevent CSRF

**❌ DON'T:**
- ❌ Use HTTP redirect URIs in production
- ❌ Allow dynamic redirect URIs
- ❌ Skip state validation

### LANID Extraction Security

**✅ DO:**
- ✅ Validate email format before extracting LANID
- ✅ Uppercase LANID consistently
- ✅ Cache identity mappings to minimize API calls
- ✅ Log LANID extraction for audit trail

**❌ DON'T:**
- ❌ Trust email claim without validation
- ❌ Allow arbitrary characters in LANID
- ❌ Skip validation of JWT signature

---

# PART 4: UTILITY SCRIPTS DOCUMENTATION

---

## Scripts Overview

The `scripts/` directory contains deployment and management utilities for the ABAP MCP Server.

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `generate-ca-certificates.sh` | Generate self-signed CA certificate for principal propagation | Once during initial setup (or when rotating certs) |
| `create-ca-secret.sh` | Upload CA certificates to AWS Secrets Manager | After generating certificates |
| `create-jwt-secret.sh` | Generate JWT signing key and upload to AWS Secrets Manager | Once during OAuth setup (Phase 2) |
| `create-aws-secrets.sh` | Create SAP credentials in AWS Secrets Manager | Initial setup (deprecated with principal propagation) |
| `build-and-push-docker.sh` | Build Docker image and push to ECR | Every code change deployment |
| `cleanup-ecr.sh` | Delete ECR images and repository | After infrastructure teardown |

---

## Certificate Generation Script

### `generate-ca-certificates.sh`

**Purpose:** Generate self-signed CA certificate and private key for Principal Propagation.

**Prerequisites:**
- OpenSSL installed (`openssl version`)

**Usage:**
```bash
# Generate new CA certificates
./scripts/generate-ca-certificates.sh

# Will prompt if certificates already exist
```

**Output:**
- `certificates/abap-mcp-ca-cert.pem` - Public CA certificate (4KB, safe to share)
- `certificates/abap-mcp-ca-key.pem` - Private key (3KB, never share)

**Certificate Properties:**
- Subject: `CN=ABAP MCP CA, OU=ABAP MCP Server, O=Pacific Gas and Electric Company`
- Key: RSA 4096-bit
- Validity: 10 years
- Type: Self-signed CA
- Signature: SHA256

**Next Steps After Generation:**
1. Upload to AWS Secrets Manager: `./scripts/create-ca-secret.sh`
2. Send public cert to SAP Basis team
3. SAP Basis imports to STRUST (transaction STRUST)

**Script Behavior:**
- Checks for existing certificates before overwriting
- Prompts for confirmation if certificates exist
- Sets correct file permissions (600 for key, 644 for cert)
- Displays certificate details after generation

---

## CA Secret Upload Script

### `create-ca-secret.sh`

**Purpose:** Upload existing CA certificate and private key to AWS Secrets Manager.

**Prerequisites:**
- CA certificates already generated (`generate-ca-certificates.sh`)
- AWS CLI configured with Secrets Manager permissions
- jq installed (`brew install jq` on macOS)

**Usage:**
```bash
# Upload certificates to AWS
./scripts/create-ca-secret.sh

# Custom AWS profile
AWS_PROFILE=my-profile ./scripts/create-ca-secret.sh
```

**Creates Secret:**
- Name: `mcp/abap-mcp-server/ca-certificate`
- Format: JSON with keys `ca_certificate` and `ca_private_key`
- Region: us-west-2 (configurable)

**Verify:**
```bash
aws secretsmanager describe-secret \
  --secret-id mcp/abap-mcp-server/ca-certificate \
  --region us-west-2
```

**Script Behavior:**
- Reads certificate files from `certificates/` directory
- Creates or updates the secret (idempotent)
- Validates AWS credentials before uploading
- Uses correct JSON keys expected by application code

---

## JWT Signing Key Script

### `create-jwt-secret.sh`

**Purpose:** Generate a secure JWT signing key and upload to AWS Secrets Manager for FastMCP OAuth token issuance.

**Prerequisites:**
- AWS CLI configured with admin permissions
- openssl installed (typically pre-installed on macOS/Linux)

**Usage:**
```bash
# Interactive - generates key and prompts for upload
./scripts/create-jwt-secret.sh

# Custom AWS profile/region
AWS_PROFILE=my-profile AWS_REGION=us-west-2 ./scripts/create-jwt-secret.sh
```

**What it does:**
1. Generates cryptographically secure 256-bit (32 bytes) random key using OpenSSL
2. Displays key preview (first 16 characters)
3. Prompts for confirmation before upload
4. Creates or updates secret in AWS Secrets Manager

**Creates Secret:**
- Name: `mcp/abap-mcp-server/jwt-signing-key`
- Value: 64-character hexadecimal string (256 bits)
- Region: us-west-2 (configurable)

**Key Properties:**
- Length: 64 characters (256 bits)
- Format: Hexadecimal
- Algorithm: OpenSSL cryptographically secure random generator

**Verify:**
```bash
aws secretsmanager get-secret-value \
  --secret-id mcp/abap-mcp-server/jwt-signing-key \
  --region us-west-2
```

**Local Testing:**
After running the script, it displays the generated key for local use:
```bash
# Add to .env file
JWT_SIGNING_KEY=your-generated-key-here
```

**Why This Is Needed:**

FastMCP (v2.13+) issues its own JWT tokens to MCP clients after OAuth authentication. The `JWT_SIGNING_KEY` signs these tokens:

- **Without key:** Ephemeral keys used (tokens don't survive restarts)
- **With key:** Persistent tokens (users stay logged in across restarts)

**Production Deployment:**

1. Run this script to create the secret
2. Update ECS task definition in Terraform:
   ```hcl
   environment = [
     {
       name  = "JWT_SIGNING_KEY"
       value = data.aws_secretsmanager_secret_version.jwt_key.secret_string
     }
   ]
   ```
3. Restart MCP server to apply

**Security Notes:**
- Key is cryptographically secure random (256 bits)
- Never commit key to git
- Use different keys for dev/test/prod
- Users must re-authenticate after key rotation

---

## SAP Credentials Script

### `create-aws-secrets.sh`

**Purpose:** Create AWS Secrets Manager secrets for SAP system credentials.

**Status:** ⚠️ Deprecated for Phase 2 (Principal Propagation). Still used for Phase 1 (static credentials).

**Prerequisites:**
- AWS CLI configured with admin permissions
- jq installed (`brew install jq` on macOS)

**Usage:**
```bash
# Interactive prompts for each system
./scripts/create-aws-secrets.sh

# Custom AWS profile
AWS_PROFILE=my-profile ./scripts/create-aws-secrets.sh
```

**Creates:**
- `mcp/abap-mcp-server/DV8` - SAP credentials for DV8 (Client 120)
- `mcp/abap-mcp-server/MS1` - SAP credentials for MS1 (Client 100)
- `mcp/abap-mcp-server/MD1` - SAP credentials for MD1 (Client 100)

**Secret Format:**
```json
{
  "SAP_USERNAME": "your-username",
  "SAP_PASSWORD": "your-password"
}
```

**Verify:**
```bash
aws secretsmanager list-secrets --region us-west-2 --profile YOUR_PROFILE
```

---

## Docker Build and Push Script

### `build-and-push-docker.sh`

**Purpose:** Build Docker image for linux/amd64 (ECS Fargate) and push to ECR.

**Prerequisites:**
- Docker installed and running
- AWS CLI configured with profile
- ECR repository exists (script creates it if needed)

**Usage:**
```bash
# Default (uses timestamp tag)
./scripts/build-and-push-docker.sh

# Custom tag
IMAGE_TAG=v1.2.3 ./scripts/build-and-push-docker.sh

# Custom AWS profile
AWS_PROFILE=my-profile ./scripts/build-and-push-docker.sh
```

**Output:**
- Docker image built: `abap-mcp-server:TAG`
- Image pushed to: `064160142714.dkr.ecr.us-west-2.amazonaws.com/abap-mcp-server:TAG`
- Shows commands to update terraform.tfvars

**Script Behavior:**
- Authenticates to ECR
- Builds multi-platform image (linux/amd64)
- Tags with provided or timestamp tag
- Pushes to ECR repository
- **Does NOT run Terraform** (TFC handles that)

**Note:** This script does NOT run Terraform. TFC handles deployment.

---

## ECR Cleanup Script

### `cleanup-ecr.sh`

**Purpose:** Delete all images from ECR repository and optionally delete the repository itself.

**Prerequisites:**
- AWS CLI configured
- Infrastructure already destroyed via TFC

**Usage:**
```bash
# Interactive cleanup
./scripts/cleanup-ecr.sh

# Custom repository
ECR_REPOSITORY=my-repo ./scripts/cleanup-ecr.sh
```

**What it does:**
1. Lists all images in the repository
2. Prompts for confirmation
3. Deletes all images using `batch-delete-image`
4. Optionally deletes the repository itself

**Note:** Always destroy infrastructure via TFC first, then run this script.

---

## Typical Deployment Workflows

### Initial Setup (One Time)

```bash
# 1. Generate CA certificates for Principal Propagation
./scripts/generate-ca-certificates.sh

# 2. Upload CA certificate to AWS Secrets Manager
./scripts/create-ca-secret.sh

# 3. Generate JWT signing key for OAuth (Phase 2)
./scripts/create-jwt-secret.sh

# 4. (Optional) Create AWS Secrets for SAP credentials (Phase 1 only)
#    Note: With principal propagation (Phase 2), this is not needed
./scripts/create-aws-secrets.sh

# 5. Build and push initial Docker image
./scripts/build-and-push-docker.sh

# 6. Update terraform/terraform.tfvars with image URI (manual or script will show you how)

# 7. Configure TFC workspace and deploy
# (See terraform/TFC-DEPLOYMENT.md for details)
```

### Regular Updates (Code Changes)

```bash
# 1. Build and push new Docker image
./scripts/build-and-push-docker.sh

# 2. Update terraform/terraform.tfvars with new image tag
cd terraform
sed -i '' 's|container_image = ".*"|container_image = "064160142714.dkr.ecr.us-west-2.amazonaws.com/abap-mcp-server:NEW_TAG"|g' terraform.tfvars

# 3. Commit and push (TFC auto-deploys)
git add terraform.tfvars
git commit -m "chore: update container image to NEW_TAG"
git push origin dev

# TFC will automatically detect the change and deploy
```

### Teardown

```bash
# 1. Destroy infrastructure via TFC
# - Go to TFC UI → Workspace → Settings → Destruction and Deletion
# - Queue destroy plan
# - Confirm destruction

# 2. Clean up ECR (optional)
./scripts/cleanup-ecr.sh
```

### Certificate Rotation

```bash
# 1. Generate new CA certificates
rm -f certificates/abap-mcp-ca-*.pem
./scripts/generate-ca-certificates.sh

# 2. Upload to AWS Secrets Manager
./scripts/create-ca-secret.sh

# 3. Send new certificate to SAP Basis
# 4. SAP Basis imports to STRUST (keep old CA during transition)
# 5. Test with new certificates
# 6. Remove old CA from STRUST after transition period
```

---

## Environment Variables

All scripts support these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_REGION` | `us-west-2` | AWS region |
| `AWS_ACCOUNT` | `064160142714` | AWS account ID |
| `AWS_PROFILE` | `CloudAdminNonProdAccess-064160142714` | AWS CLI profile |
| `ECR_REPOSITORY` | `abap-mcp-server` | ECR repository name |
| `IMAGE_TAG` | `$(date +%Y%m%d%H%M%S)` | Docker image tag |

**Example:**
```bash
AWS_REGION=us-east-1 IMAGE_TAG=v2.0.0 ./scripts/build-and-push-docker.sh
```

---

## Migration from deploy.sh/undeploy.sh

If you previously used `deploy.sh` and `undeploy.sh`, here's the mapping:

| Old Script | New Approach | Notes |
|------------|--------------|-------|
| `./deploy.sh` | `./scripts/build-and-push-docker.sh` + TFC | Split Docker and Terraform |
| `./undeploy.sh` | TFC Destroy + `./scripts/cleanup-ecr.sh` | TFC handles Terraform |

---

## References

### External Resources
- **OpenSSL Documentation:** https://www.openssl.org/docs/
- **AWS Secrets Manager:** https://docs.aws.amazon.com/secretsmanager/
- **FastMCP OAuth Documentation:** https://gofastmcp.com/docs/oauth
- **Microsoft Entra ID OAuth:** https://learn.microsoft.com/en-us/entra/identity-platform/
- **AWS Cognito OAuth:** https://docs.aws.amazon.com/cognito/latest/developerguide/authorization-endpoint.html
- **MCP Protocol Specification:** https://modelcontextprotocol.io/
- **OAuth 2.0 RFC:** https://datatracker.ietf.org/doc/html/rfc6749
- **X.509 Certificates:** https://en.wikipedia.org/wiki/X.509
- **SAP STRUST Transaction:** SAP Help Portal
- **Principal Propagation:** SAP documentation on certificate-based authentication

---

© 2026 Pacific Gas and Electric Company. All rights reserved.

This software is proprietary and confidential. Unauthorized copying, distribution, or use of this software, via any medium, is strictly prohibited.

**For internal use by authorized PG&E personnel only.**
