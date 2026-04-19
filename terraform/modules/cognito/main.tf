# ============================================================================
# Cognito User Pool for ABAP MCP Server OAuth Authentication
# ============================================================================

resource "aws_cognito_user_pool" "main" {
  name = var.user_pool_name

  # Password Policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # Sign In Policy
  # Note: This is configured at the CLI level, not available in Terraform resource yet
  # You may need to configure via AWS CLI: AllowedFirstAuthFactors = ["PASSWORD"]

  # Username Configuration
  username_configuration {
    case_sensitive = false
  }

  # Use email as username (no separate username field)
  # This makes the user creation form consistent with mlaas-user-pool
  username_attributes = ["email"]

  # Auto-verified attributes
  auto_verified_attributes = ["email"]

  # Email verification
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # SMS configuration (optional, requires SNS role)
  dynamic "sms_configuration" {
    for_each = var.sns_caller_arn != "" ? [1] : []
    content {
      external_id    = var.sns_external_id
      sns_caller_arn = var.sns_caller_arn
      sns_region     = var.aws_region
    }
  }

  # Admin create user config
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  # User invitation config
  user_attribute_update_settings {
    attributes_require_verification_before_update = []
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
    recovery_mechanism {
      name     = "verified_phone_number"
      priority = 2
    }
  }

  # Deletion protection (set to INACTIVE for dev to allow terraform destroy)
  deletion_protection = var.enable_deletion_protection ? "ACTIVE" : "INACTIVE"

  # MFA configuration
  mfa_configuration = "OFF"

  # User pool tier
  # Note: user_pool_tier is not available in Terraform AWS provider yet
  # Default is ESSENTIALS

  # Schema attributes (OIDC standard claims)
  # Note: Only email is required (used as username)
  # All other attributes are optional for simpler user creation
  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "given_name"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "family_name"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "middle_name"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "nickname"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "preferred_username"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "profile"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "picture"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "website"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "gender"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "birthdate"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 10
      max_length = 10
    }
  }

  schema {
    name                = "zoneinfo"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "locale"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "phone_number"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "address"
    attribute_data_type = "String"
    mutable             = true
    required            = false
    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                = "updated_at"
    attribute_data_type = "Number"
    mutable             = true
    required            = true
    number_attribute_constraints {
      min_value = 0
    }
  }

  tags = var.tags
}

# ============================================================================
# Cognito User Pool Domain (for Hosted UI)
# ============================================================================

resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.main.id

  # Force recreation to get ManagedLoginVersion 2
  # AWS assigns ManagedLoginVersion based on creation date
  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# Managed Login v2 Configuration (via Lambda)
# ============================================================================
#
# Terraform AWS provider doesn't support setting ManagedLoginVersion directly.
# Use Lambda function to configure Managed Login v2 after domain creation.
#
# This approach works in Terraform Cloud because:
# - Lambda is created via Terraform AWS provider (no CLI needed)
# - Lambda invocation uses Terraform AWS provider (no CLI needed)
# - Lambda runs with IAM role credentials (no local credentials needed)
# ============================================================================

# IAM role for Lambda execution
resource "aws_iam_role" "configure_managed_login" {
  name = "${var.user_pool_name}-configure-managed-login"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for Lambda to access Cognito and CloudWatch Logs
resource "aws_iam_role_policy" "configure_managed_login" {
  name = "cognito-access"
  role = aws_iam_role.configure_managed_login.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:UpdateUserPoolDomain",
          "cognito-idp:DescribeUserPoolDomain",
          "cognito-idp:CreateManagedLoginBranding"
        ]
        Resource = [
          aws_cognito_user_pool.main.arn,
          "${aws_cognito_user_pool.main.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      }
    ]
  })
}

# Lambda function to configure Managed Login v2
data "archive_file" "configure_managed_login" {
  type        = "zip"
  source_file = "${path.module}/lambda_configure_managed_login.py"
  output_path = "${path.module}/lambda_configure_managed_login.zip"
}

resource "aws_lambda_function" "configure_managed_login" {
  filename         = data.archive_file.configure_managed_login.output_path
  function_name    = "${var.user_pool_name}-configure-managed-login"
  role             = aws_iam_role.configure_managed_login.arn
  handler          = "lambda_configure_managed_login.lambda_handler"
  source_code_hash = data.archive_file.configure_managed_login.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      USER_POOL_ID  = aws_cognito_user_pool.main.id
      APP_CLIENT_ID = aws_cognito_user_pool_client.main.id
      DOMAIN        = var.cognito_domain_prefix
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy.configure_managed_login,
    aws_cognito_user_pool_domain.main
  ]
}

# Invoke Lambda to configure Managed Login v2
# This runs automatically after domain creation
data "aws_lambda_invocation" "configure_managed_login" {
  function_name = aws_lambda_function.configure_managed_login.function_name

  input = jsonencode({
    user_pool_id  = aws_cognito_user_pool.main.id
    app_client_id = aws_cognito_user_pool_client.main.id
    domain        = var.cognito_domain_prefix
  })

  depends_on = [
    aws_lambda_function.configure_managed_login,
    aws_cognito_user_pool_domain.main
  ]
}

# Output Lambda execution result for debugging
output "managed_login_configuration_result" {
  description = "Result of Managed Login v2 configuration (from Lambda)"
  value       = jsondecode(data.aws_lambda_invocation.configure_managed_login.result)
}

# ============================================================================
# Cognito User Pool Client (App Client)
# ============================================================================

resource "aws_cognito_user_pool_client" "main" {
  name         = var.app_client_name
  user_pool_id = aws_cognito_user_pool.main.id

  # Generate client secret
  generate_secret = true

  # Token validity
  refresh_token_validity = 5
  access_token_validity  = 60
  id_token_validity      = 60

  token_validity_units {
    refresh_token = "days"
    access_token  = "minutes"
    id_token      = "minutes"
  }

  # Explicit auth flows (for direct API authentication)
  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  # OAuth configuration
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = var.callback_urls
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "phone", "profile"]
  allowed_oauth_flows_user_pool_client = true

  # Security
  prevent_user_existence_errors                 = "ENABLED"
  enable_token_revocation                       = true
  enable_propagate_additional_user_context_data = false

  # Auth session validity (minutes)
  auth_session_validity = 3
}


# ============================================================================
# Store OAuth Credentials in Secrets Manager
# ============================================================================

# Data source for existing secret (if not creating new one)
data "aws_secretsmanager_secret" "oauth_credentials_existing" {
  count = var.create_oauth_secret ? 0 : 1
  name  = var.oauth_secret_name
}

# Create new secret only if it doesn't exist
resource "aws_secretsmanager_secret" "oauth_credentials" {
  count = var.create_oauth_secret ? 1 : 0

  name                    = var.oauth_secret_name
  description             = "OAuth credentials for ABAP MCP Server (Client ID and Client Secret)"
  recovery_window_in_days = var.oauth_secret_recovery_window

  tags = var.tags
}

# Update secret value (works for both new and existing secrets)
resource "aws_secretsmanager_secret_version" "oauth_credentials" {
  secret_id = var.create_oauth_secret ? aws_secretsmanager_secret.oauth_credentials[0].id : data.aws_secretsmanager_secret.oauth_credentials_existing[0].id

  secret_string = jsonencode({
    client_id     = aws_cognito_user_pool_client.main.id
    client_secret = aws_cognito_user_pool_client.main.client_secret
  })
}
