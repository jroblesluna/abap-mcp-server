# OAuth Integration — Findings & Lessons Learned

## Context

Enterprise mode (`ENABLE_ENTERPRISE_MODE=true`).  
Transport: **streamable-http** (FastMCP 3.2.3).  
Client tested: **Kiro IDE** via `~/.kiro/settings/mcp.json`.

No code changes are needed to switch between IdPs — only swap the `.env` file.

---

## Scenario 1: AWS Cognito

### Full `.env`

```env
# Server
SERVER_HOST=0.0.0.0
SERVER_PORT=8000
SERVER_BASE_URL=http://localhost:8000

# Enterprise
ENABLE_ENTERPRISE_MODE=true
ENABLE_PRINCIPAL_PROPAGATION=false

# OAuth — AWS Cognito
ENABLE_OAUTH_FLOW=true

OAUTH_ISSUER=https://cognito-idp.{region}.amazonaws.com/{user-pool-id}
OAUTH_AUTH_ENDPOINT=https://{domain}.auth.{region}.amazoncognito.com/oauth2/authorize
OAUTH_TOKEN_ENDPOINT=https://{domain}.auth.{region}.amazoncognito.com/oauth2/token

OAUTH_CLIENT_ID={cognito-app-client-id}
OAUTH_CLIENT_SECRET={cognito-app-client-secret}
# OAUTH_AUDIENCE — do NOT set (Cognito access tokens have no 'aud' claim; omitting disables audience validation)

# SAP Connection
DEFAULT_SAP_SYSTEM_ID=DEV
CREDENTIAL_PROVIDER=env
SAP_HOST=localhost
SAP_CLIENT=100
SAP_USERNAME=dummy
SAP_PASSWORD=dummy
SAP_LANGUAGE=EN
SAP_SECURE=false
SSL_VERIFY=false

# AWS
AWS_REGION=us-west-2
```

---

## Scenario 2: Microsoft Entra ID (Azure AD)

### Azure Portal Setup (one-time, per app registration)

1. **App Registration → Authentication** → Add redirect URI: `http://localhost:8000/oauth/callback`
2. **Manifest** → set `"requestedAccessTokenVersion": 2`  
   _Azure defaults to `null` (= V1 tokens, issuer `sts.windows.net`). Setting `2` issues V2 tokens with the correct issuer. Without this, authentication fails with `Bearer token rejected`._
3. **Expose an API** → confirm Application ID URI is `api://{client_id}` → add scope named `access` (delegated, Admins and users)
4. **API permissions** → add the `access` scope you just created (delegated)

### Full `.env`

```env
# Server
SERVER_HOST=0.0.0.0
SERVER_PORT=8000
SERVER_BASE_URL=http://localhost:8000

# Enterprise
ENABLE_ENTERPRISE_MODE=true
ENABLE_PRINCIPAL_PROPAGATION=false

# OAuth — Microsoft Entra ID (Azure AD)
ENABLE_OAUTH_FLOW=true

OAUTH_ISSUER=https://login.microsoftonline.com/{tenant-id}/v2.0
OAUTH_AUTH_ENDPOINT=https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/authorize
OAUTH_TOKEN_ENDPOINT=https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token

OAUTH_CLIENT_ID={client-id}
OAUTH_CLIENT_SECRET={client-secret}
OAUTH_AUDIENCE={client-id}   # bare GUID — no api:// prefix (Azure V2 tokens put bare GUID in 'aud')

# SAP Connection
DEFAULT_SAP_SYSTEM_ID=DEV
CREDENTIAL_PROVIDER=env
SAP_HOST=localhost
SAP_CLIENT=100
SAP_USERNAME=dummy
SAP_PASSWORD=dummy
SAP_LANGUAGE=EN
SAP_SECURE=false
SSL_VERIFY=false

# AWS
AWS_REGION=us-west-2
```

---

## How the Server Auto-Detects the IdP

The server detects the IdP from `OAUTH_ISSUER` and adjusts behavior automatically — no code changes needed when switching `.env` files:

| Behavior | Azure AD | AWS Cognito |
|---|---|---|
| Audience validation | `OAUTH_AUDIENCE` (bare GUID) | Skipped — `OAUTH_AUDIENCE` not set |
| Custom API scope | `api://{client_id}/access` added | Not added |
| `offline_access` scope | Included | Excluded (Cognito rejects it) |
| `aud` in access token | `{client_id}` (bare GUID) | No `aud` claim |
| `iss` in access token | `https://login.microsoftonline.com/{tenant}/v2.0` | `https://cognito-idp.{region}.amazonaws.com/{pool}` |
| Manifest requirement | `requestedAccessTokenVersion: 2` | N/A |

**Key rules:**
- Set `OAUTH_AUDIENCE` → audience validation enabled (required for Azure)
- Omit `OAUTH_AUDIENCE` → audience validation skipped (required for Cognito)
- Issuer contains `login.microsoftonline.com` → `offline_access` and `api://{audience}/access` added automatically
- Issuer contains `cognito` → `offline_access` excluded automatically (Cognito rejects it)

---

## Required Code Changes (vs base commit `8d715c9`)

6 lines changed across 2 files. Apply these before deploying to a new instance.

### `auth/keychain_manager.py` — Move `_memory_store` init

**Why:** On Mac, `_initialize_keyring()` takes the non-Docker path and never sets `_memory_store`, causing `AttributeError` on startup.

```diff
 def __init__(self):
     self.service_name = "sap-abap-accelerator-mcp"
     self._keyring = None
+    self._memory_store = {}
     self._initialize_keyring()

 def _initialize_keyring(self):
     ...
     self._keyring = None
-    self._memory_store = {}
     return
```

---

### `server/fastmcp_oauth_integration.py` — 4 changes

#### Change 1 — Ignore `OAUTH_AUDIENCE` for Cognito

**Why:** Cognito access tokens have no `aud` claim. If `OAUTH_AUDIENCE` is set (even accidentally), it must not be passed to `JWTVerifier` for Cognito or validation always fails.

```diff
-if configured_audience:
+if configured_audience and 'cognito' not in issuer.lower():
     audience = configured_audience
```

#### Change 2 — Skip audience in `JWTVerifier` for Cognito

**Why:** Passing `audience` to `JWTVerifier` when the token has no `aud` claim causes a permanent `Bearer token rejected` loop.

```diff
 token_verifier = JWTVerifier(
     jwks_uri=jwks_uri,
     issuer=issuer,
-    audience=audience
+    **({'audience': audience} if audience and 'cognito' not in issuer.lower() else {})
 )
```

#### Change 3 — IdP-aware `valid_scopes`

**Why:** Cognito rejects `offline_access` with `invalid_scope`. Azure requires `api://{client_id}/access` to target the token at this app (otherwise Azure issues a Microsoft Graph token with a different `aud`).

```diff
-"valid_scopes": ["openid", "email", "profile", "offline_access"],
+"valid_scopes": ["openid", "email", "profile"] + ([] if 'cognito' in issuer.lower() else ["offline_access"]) + ([f"api://{audience}/access"] if audience and 'login.microsoftonline.com' in issuer else []),
```

#### Change 4 — Sync `default_scopes` with `valid_scopes`

**Why:** `default_scopes` was a hardcoded list that diverged from `valid_scopes` after Change 3, causing Kiro to receive inconsistent scopes during registration fallback.

```diff
-default_scopes = ["openid", "email", "profile", "offline_access"]
+default_scopes = oauth_kwargs["valid_scopes"]
```

---

## Transport & Tooling Notes

### Clients

This server uses **streamable-http** transport. **Hoot** only supports legacy SSE — do not use it (returns 405).

Use instead:
- `npx @modelcontextprotocol/inspector` — supports streamable-http + OAuth
- **Kiro IDE** — confirmed working for both Cognito and Azure

### Kiro `mcp.json`

```json
{
  "mcpServers": {
    "abap-accelerator": {
      "url": "http://localhost:8000/mcp"
    }
  }
}
```

No `transport` field needed — Kiro auto-detects streamable-http.

### Resetting Kiro Token Cache

If Kiro doesn't prompt for login (reuses old cached token), rename the server key in `mcp.json` (e.g., `abap-accelerator-v2`) to force new registration and a fresh OAuth flow.
