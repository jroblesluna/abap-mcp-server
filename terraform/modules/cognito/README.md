# Cognito User Pool Module

This module creates an AWS Cognito User Pool with OAuth/OIDC support for the ABAP MCP Server.

## Features

- **User Pool**: Configured for OAuth 2.0 Authorization Code Grant flow
- **Hosted UI**: Cognito-managed login pages (domain auto-configured)
- **App Client**: Confidential client with client secret for server-side authentication
- **OAuth Scopes**: `openid`, `email`, `phone`, `profile`
- **Token Management**: Automatic storage of Client ID and Secret in AWS Secrets Manager
- **Security**: Password policy, email verification, deletion protection enabled

## Usage

```hcl
module "cognito" {
  source = "./modules/cognito"

  user_pool_name       = "abap-mcp-server-user-pool"
  app_client_name      = "abap-mcp-server"
  cognito_domain_prefix = "abap-mcp-server-${var.environment}"  # Must be globally unique
  callback_urls        = [
    "https://abap-mcp-server.nonprod.pge.com/oauth/callback"
  ]

  aws_region         = var.region
  oauth_secret_name  = "mcp/abap-mcp-server/oauth-credentials"

  tags = var.tags
}
```

## Outputs

- `user_pool_id`: Cognito User Pool ID
- `user_pool_arn`: ARN of the User Pool
- `app_client_id`: OAuth Client ID
- `app_client_secret`: OAuth Client Secret (sensitive)
- `oauth_secret_arn`: ARN of the Secrets Manager secret containing credentials
- `oauth_auth_endpoint`: OAuth authorization endpoint URL
- `oauth_token_endpoint`: OAuth token endpoint URL
- `oauth_issuer`: OIDC issuer URL
- `hosted_ui_url`: Direct link to test Hosted UI

## Important Notes

### Schema Attributes

This module creates a User Pool with all OIDC standard claims marked as **required**. This is intentional to match the working configuration. However, note that:

1. **Schema cannot be changed after creation** - If you need different attributes, you must destroy and recreate the User Pool
2. All users must provide all required attributes when signing up
3. This matches the configuration of the working `abap-mcp-server-user-pool` created manually

### Cognito Domain

The `cognito_domain_prefix` must be **globally unique** across all AWS accounts. Consider using a pattern like:

```
abap-mcp-server-${environment}-${random_suffix}
```

### SMS Configuration (Optional)

SMS is configured but requires an SNS IAM role with proper permissions. If SMS is not needed:
- Leave `sns_caller_arn` empty (default)
- SMS configuration will be skipped
- Phone number verification will use email instead

### Deletion Protection

Deletion protection is **enabled** by default. To destroy the User Pool, you must:

1. Disable deletion protection:
   ```bash
   aws cognito-idp update-user-pool \
     --user-pool-id <pool-id> \
     --deletion-protection INACTIVE \
     --region us-west-2
   ```

2. Then run `terraform destroy`

### Creating Users

The User Pool is configured for **admin-only user creation** (`allow_admin_create_user_only = true`). Create users via:

```bash
aws cognito-idp admin-create-user \
  --user-pool-id <pool-id> \
  --username user@example.com \
  --user-attributes Name=email,Value=user@example.com Name=email_verified,Value=true \
  --region us-west-2
```

## Testing Hosted UI

After deployment, test the Hosted UI using the `hosted_ui_url` output:

```bash
terraform output hosted_ui_url
```

Open the URL in a browser - you should see the Cognito login page (not "Login pages unavailable").

## Integration with MCP Server

The module automatically:

1. Creates OAuth credentials (Client ID + Secret)
2. Stores them in AWS Secrets Manager at `mcp/abap-mcp-server/oauth-credentials`
3. Provides OAuth endpoints for the MCP server configuration

Update your `terraform.tfvars`:

```hcl
oauth_auth_endpoint  = module.cognito.oauth_auth_endpoint
oauth_token_endpoint = module.cognito.oauth_token_endpoint
oauth_client_id      = module.cognito.app_client_id
oauth_issuer         = module.cognito.oauth_issuer
oauth_secret_arn     = module.cognito.oauth_secret_arn
```

## Troubleshooting

### "Login pages unavailable" Error

If you see this error when accessing Hosted UI:

1. Verify the App Client has all required settings:
   - `allowed_oauth_flows_user_pool_client = true`
   - `explicit_auth_flows` includes required flows
   - `callback_urls` is not empty

2. Check the Cognito domain is active:
   ```bash
   aws cognito-idp describe-user-pool-domain \
     --domain <domain-prefix> \
     --region us-west-2
   ```

3. Wait 1-2 minutes for propagation after creation

### User Creation Fails

Ensure all required attributes are provided when creating users. Check the schema in the AWS Console to see which attributes are marked as required.
