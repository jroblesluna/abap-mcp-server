# Cognito User Pool Setup for ABAP MCP Server

This guide explains how to set up AWS Cognito User Pool for OAuth authentication with the ABAP MCP Server.

## Overview

The Cognito module creates:
- **User Pool**: Manages user authentication and profiles
- **Hosted UI**: Pre-built login pages (domain auto-configured)
- **App Client**: OAuth 2.0 client (confidential with client secret)
- **Secrets Manager**: Auto-stores OAuth credentials for the MCP server

## Quick Start

### 1. Enable Cognito in terraform.tfvars

```hcl
# Enable Terraform-managed Cognito User Pool
enable_cognito          = true
cognito_user_pool_name  = "abap-mcp-server-user-pool"
cognito_app_client_name = "abap-mcp-server"
cognito_domain_prefix   = "abap-mcp-dev-20260411"  # Must be globally unique
cognito_callback_urls   = ["https://abap-mcp-server.nonprod.pge.com/oauth/callback"]
```

### 2. Deploy with Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 3. Create Test User

After deployment, create a test user:

```bash
# Get commands from Terraform output
terraform output -raw cognito_setup_commands

# Or manually:
aws cognito-idp admin-create-user \
  --user-pool-id <from-output> \
  --username testuser@example.com \
  --user-attributes Name=email,Value=testuser@example.com Name=email_verified,Value=true \
  --temporary-password TempPassword123! \
  --region us-west-2

# Set permanent password
aws cognito-idp admin-set-user-password \
  --user-pool-id <from-output> \
  --username testuser@example.com \
  --password YourPassword123! \
  --permanent \
  --region us-west-2
```

### 4. Test Hosted UI

```bash
# Get Hosted UI URL from Terraform output
terraform output cognito_hosted_ui_url

# Open in browser - you should see login page (not "Login pages unavailable")
```

## Configuration Options

### Cognito Domain Prefix

The `cognito_domain_prefix` must be **globally unique** across all AWS accounts. If you get an error like "Domain already exists", try:

```hcl
cognito_domain_prefix = "abap-mcp-${var.environment}-${random_id.suffix.hex}"
```

Or manually add a random suffix:

```hcl
cognito_domain_prefix = "abap-mcp-dev-a1b2c3"
```

### Callback URLs

Add all URLs where OAuth can redirect after authentication:

```hcl
cognito_callback_urls = [
  "https://abap-mcp-server.nonprod.pge.com/oauth/callback",
  "http://localhost:3000/callback"  # For local development
]
```

### SMS Configuration (Optional)

If you need SMS verification (phone_number attribute):

1. Create SNS IAM role (already exists: `CognitoIdpSNSServiceRole`)
2. Enable in terraform.tfvars:

```hcl
cognito_sns_caller_arn  = "arn:aws:iam::064160142714:role/service-role/CognitoIdpSNSServiceRole"
cognito_sns_external_id = "<external-id>"
```

If you don't need SMS, leave these empty (default).

## Using Existing User Pool

If you already have a Cognito User Pool and don't want Terraform to manage it:

```hcl
enable_cognito = false

# Manually specify OAuth endpoints
oauth_auth_endpoint  = "https://your-domain.auth.us-west-2.amazoncognito.com/oauth2/authorize"
oauth_token_endpoint = "https://your-domain.auth.us-west-2.amazoncognito.com/oauth2/token"
oauth_client_id      = "your-client-id"
oauth_issuer         = "https://cognito-idp.us-west-2.amazonaws.com/us-west-2_YourPoolId"
oauth_secret_arn     = "arn:aws:secretsmanager:us-west-2:064160142714:secret:your-secret"
```

## Outputs

After deployment, Terraform provides:

```bash
# View all Cognito outputs
terraform output | grep cognito

# Key outputs:
terraform output cognito_user_pool_id
terraform output cognito_app_client_id
terraform output cognito_hosted_ui_url
```

## Integration with MCP Server

The module automatically:

1. ✅ Creates OAuth credentials (Client ID + Secret)
2. ✅ Stores them in Secrets Manager (`mcp/abap-mcp-server/oauth-credentials`)
3. ✅ Configures ECS task definition to read from Secrets Manager
4. ✅ Sets OAuth environment variables in the container

**No manual configuration needed!** The MCP server will automatically:
- Read OAuth credentials from Secrets Manager
- Use Cognito endpoints for authentication
- Validate JWT tokens from Cognito

## User Management

### Create User (Admin-Only Mode)

The User Pool is configured for **admin-only user creation**:

```bash
aws cognito-idp admin-create-user \
  --user-pool-id us-west-2_YourPoolId \
  --username user@example.com \
  --user-attributes \
    Name=email,Value=user@example.com \
    Name=email_verified,Value=true \
  --region us-west-2
```

### Reset Password

```bash
aws cognito-idp admin-set-user-password \
  --user-pool-id us-west-2_YourPoolId \
  --username user@example.com \
  --password NewPassword123! \
  --permanent \
  --region us-west-2
```

### Delete User

```bash
aws cognito-idp admin-delete-user \
  --user-pool-id us-west-2_YourPoolId \
  --username user@example.com \
  --region us-west-2
```

## Troubleshooting

### "Login pages unavailable" Error

This was the original problem! If you see this error:

1. **Verify App Client settings**:
   ```bash
   aws cognito-idp describe-user-pool-client \
     --user-pool-id <pool-id> \
     --client-id <client-id> \
     --region us-west-2
   ```

   Ensure:
   - `AllowedOAuthFlowsUserPoolClient: true`
   - `ExplicitAuthFlows` includes required flows
   - `CallbackURLs` is not empty

2. **Verify domain is active**:
   ```bash
   aws cognito-idp describe-user-pool-domain \
     --domain <domain-prefix> \
     --region us-west-2 | jq '.DomainDescription.Status'
   ```

   Should show: `"ACTIVE"`

3. **Wait for propagation**: New User Pools can take 1-2 minutes to fully activate

### Domain Already Exists

If you get "Domain prefix already in use":

1. Choose a different `cognito_domain_prefix`
2. Or delete the existing domain:
   ```bash
   aws cognito-idp delete-user-pool-domain \
     --domain <domain-prefix> \
     --region us-west-2
   ```

### Cannot Destroy User Pool

Deletion protection is enabled by default. To destroy:

```bash
# 1. Disable deletion protection
aws cognito-idp update-user-pool \
  --user-pool-id <pool-id> \
  --deletion-protection INACTIVE \
  --region us-west-2

# 2. Run terraform destroy
terraform destroy
```

### Schema Attributes Error

User Pool schema **cannot be changed after creation**. If you need different attributes:

1. Destroy the User Pool
2. Update `terraform/modules/cognito/main.tf` schema blocks
3. Recreate with `terraform apply`

## Architecture Decisions

### Why Required Attributes?

The working User Pool (`abap-mcp-server-user-pool`) has all OIDC standard claims marked as **required**. This ensures:
- Complete user profiles for enterprise applications
- All OIDC claims available in JWT tokens
- Consistency with working configuration

### Why Admin-Only User Creation?

For enterprise security:
- Prevents self-service registration
- Admins control who has access
- Integrates with existing user provisioning workflows

### Why Separate Module?

The Cognito module is separate for:
- Reusability across environments
- Optional deployment (use existing User Pool)
- Clear separation of concerns

## Migration from Existing User Pool

If you're migrating from `mlaas-user-pool` to the new Terraform-managed User Pool:

1. **Export existing users** (AWS doesn't provide direct export):
   ```bash
   aws cognito-idp list-users \
     --user-pool-id us-west-2_OldPoolId \
     --region us-west-2 > users.json
   ```

2. **Create new User Pool** with Terraform:
   ```bash
   terraform apply
   ```

3. **Recreate users** in new pool (requires password reset):
   ```bash
   # Script to bulk create users from users.json
   # (Not provided - varies by use case)
   ```

4. **Update OAuth configuration** in MCP clients (Q Developer, Kiro):
   - New User Pool ID
   - New App Client ID
   - New domain prefix

5. **Test thoroughly** before decommissioning old pool

## References

- [Cognito User Pools Documentation](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-identity-pools.html)
- [OAuth 2.0 with Cognito](https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-app-integration.html)
- [Terraform AWS Cognito Resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool)
