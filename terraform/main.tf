# ============================================================================
# Main Terraform Configuration for ABAP Accelerator MCP Server
# ECS Fargate Deployment with Multi-Account Route53
# ============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration - configure in backend.tf or via CLI
  # backend "s3" {}
}

# Default provider for application account (064...)
provider "aws" {
  region = var.region

  # Role chaining for TFC: TFC OIDC → CloudAdmin role in application account
  assume_role {
    role_arn = "arn:aws:iam::${var.account_num}:role/${var.aws_role}"
  }

  default_tags {
    tags = merge(
      var.tags,
      {
        Environment = var.environment
      }
    )
  }
}

# Provider for Route53 account (514...) - cross-account access for DNS
provider "aws" {
  alias  = "route53"
  region = var.region

  # Role chaining for TFC: TFC OIDC → TFCBR53Role in Route53 account
  assume_role {
    role_arn = "arn:aws:iam::${var.account_num_r53}:role/${var.aws_r53_role}"
  }
}

# ============================================================================
# Local Variables
# ============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Construct application FQDN from hostname and hosted zone
  application_fqdn = "${var.application_hostname}.${var.route53_hosted_zone_name}"

  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      Name        = local.name_prefix
    }
  )
}

# ============================================================================
# Data Sources
# ============================================================================

data "aws_caller_identity" "current" {}

# Data source for public hosted zone (for ACM validation records)
data "aws_route53_zone" "nonprod_public" {
  provider     = aws.route53
  name         = "${var.route53_hosted_zone_name}."
  private_zone = false
}

# Data source for private hosted zone (for application CNAME record)
data "aws_route53_zone" "nonprod_private" {
  count        = var.use_private_zone ? 1 : 0
  provider     = aws.route53
  name         = "${var.route53_hosted_zone_name}."
  private_zone = true
}

# Data source for SAP credentials secret (only for non-enterprise mode)
# In enterprise mode, each system has its own secret (mcp/abap-mcp-server/DV8, etc.)
data "aws_secretsmanager_secret" "sap_credentials" {
  count = var.enable_enterprise_mode ? 0 : 1
  name  = "mcp/abap-mcp-server"
}

# ============================================================================
# CloudWatch Log Group
# ============================================================================

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ============================================================================
# ACM Certificate (Application Account)
# ============================================================================

resource "aws_acm_certificate" "app" {
  domain_name       = local.application_fqdn
  validation_method = "DNS"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-certificate"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation records in Route53 account (PUBLIC zone for ACM validation)
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  provider        = aws.route53
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.nonprod_public.zone_id # Use public zone for ACM validation
}

# ACM Certificate validation
resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ============================================================================
# Module: IAM Roles
# ============================================================================

module "iam" {
  source = "./modules/iam"

  name_prefix = local.name_prefix
  aws_region  = var.region
  account_id  = data.aws_caller_identity.current.account_id
  common_tags = local.common_tags
}

# ============================================================================
# Module: Security Groups
# ============================================================================

module "security_groups" {
  source = "./modules/security_groups"

  name_prefix         = local.name_prefix
  vpc_id              = var.vpc_id
  container_port      = var.container_port
  allowed_cidr_blocks = var.allowed_cidr_blocks
  common_tags         = local.common_tags
}

# ============================================================================
# Module: Application Load Balancer
# ============================================================================

module "alb" {
  source = "./modules/alb"

  name_prefix           = local.name_prefix
  vpc_id                = var.vpc_id
  private_subnet_ids    = var.private_subnet_ids # Internal ALB in private subnets
  alb_security_group_id = module.security_groups.alb_security_group_id
  certificate_arn       = aws_acm_certificate_validation.app.certificate_arn
  common_tags           = local.common_tags

  depends_on = [aws_acm_certificate_validation.app]
}

# ============================================================================
# Module: CA Certificates for Principal Propagation
# ============================================================================

module "certificates" {
  source = "./modules/certificates"

  # Certificate mode: "existing" = use existing AWS secret, "create" = create new secret with PGE module
  certificate_mode     = var.certificate_mode
  existing_secret_name = var.existing_ca_secret_name # Used when certificate_mode = "existing"

  # Parameters for "create" mode (when switching to prod)
  project_name            = var.project_name
  ca_cert_pem             = var.ca_cert_pem # Optional: fallback if file doesn't exist
  ca_key_pem              = var.ca_key_pem  # Optional: from TFC sensitive variable
  recovery_window_in_days = var.cert_recovery_window_days
  tags                    = local.common_tags
}

# ============================================================================
# Module: Cognito User Pool (OAuth Authentication)
# ============================================================================

module "cognito" {
  count  = var.enable_cognito ? 1 : 0
  source = "./modules/cognito"

  user_pool_name        = var.cognito_user_pool_name
  app_client_name       = var.cognito_app_client_name
  cognito_domain_prefix = var.cognito_domain_prefix
  callback_urls         = var.cognito_callback_urls
  oauth_secret_name            = "mcp/abap-mcp-server/oauth-credentials"
  create_oauth_secret          = true  # Create new secret with Cognito credentials
  enable_deletion_protection   = false # Allow terraform destroy to delete User Pool
  oauth_secret_recovery_window = 0     # Immediate deletion without recovery window

  aws_region = var.region

  # Optional SMS configuration
  sns_caller_arn  = var.cognito_sns_caller_arn
  sns_external_id = var.cognito_sns_external_id

  tags = local.common_tags
}

# ============================================================================
# Module: Parameter Store (SAP Endpoints)
# ============================================================================

module "parameters" {
  source = "./modules/parameters"

  name_prefix          = local.name_prefix
  sap_endpoints_json   = var.sap_endpoints_json
  user_exceptions_json = var.user_exceptions_json
  common_tags          = local.common_tags
}

# ============================================================================
# Module: ECS Cluster and Service
# ============================================================================

module "ecs" {
  source = "./modules/ecs"

  name_prefix        = local.name_prefix
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  container_image    = var.container_image
  container_cpu      = var.container_cpu
  container_memory   = var.container_memory
  container_port     = var.container_port
  desired_count      = var.desired_count

  # IAM
  task_execution_role_arn = module.iam.task_execution_role_arn
  task_role_arn           = module.iam.task_role_arn

  # Security
  ecs_security_group_id = module.security_groups.ecs_security_group_id

  # Load Balancer
  target_group_arn       = module.alb.target_group_arn
  alb_listener_http_arn  = module.alb.listener_http_arn
  alb_listener_https_arn = module.alb.listener_https_arn

  # Logging
  log_group_name = aws_cloudwatch_log_group.app.name

  # Application Config
  enable_enterprise_mode       = var.enable_enterprise_mode
  enable_principal_propagation = var.enable_principal_propagation
  credential_provider          = var.credential_provider
  aws_region                   = var.region

  # SAP Connection
  sap_host                    = var.sap_host
  sap_instance_number         = var.sap_instance_number
  sap_client                  = var.sap_client
  sap_language                = var.sap_language
  sap_secure                  = var.sap_secure
  ssl_verify                  = var.ssl_verify
  sap_port                    = var.sap_port
  log_level                   = var.log_level
  enable_http_request_logging = var.enable_http_request_logging
  sap_systems_yaml            = var.sap_systems_yaml

  # OAuth Configuration (use Cognito module if enabled, otherwise use vars)
  oauth_auth_endpoint  = var.enable_cognito ? module.cognito[0].oauth_auth_endpoint : var.oauth_auth_endpoint
  oauth_token_endpoint = var.enable_cognito ? module.cognito[0].oauth_token_endpoint : var.oauth_token_endpoint
  oauth_client_id      = var.enable_cognito ? module.cognito[0].app_client_id : var.oauth_client_id
  oauth_issuer         = var.enable_cognito ? module.cognito[0].oauth_issuer : var.oauth_issuer
  server_base_url      = var.server_base_url

  # Secrets
  ca_certificate_secret_arn  = module.certificates.secret_arn
  sap_credentials_secret_arn = var.enable_enterprise_mode ? "" : data.aws_secretsmanager_secret.sap_credentials[0].arn
  oauth_secret_arn           = var.enable_cognito ? module.cognito[0].oauth_secret_arn : var.oauth_secret_arn

  enable_container_insights = var.enable_container_insights
  common_tags               = local.common_tags

  # ECS service must wait for ALB listeners to connect target group to load balancer
  depends_on = [module.alb]
}

# ============================================================================
# Route53 DNS Record in Route53 Account
# ============================================================================

# CNAME record pointing to ALB (uses appropriate zone based on use_private_zone)
# Using CNAME instead of A+ALIAS for better Transit Gateway compatibility
resource "aws_route53_record" "app" {
  provider = aws.route53
  zone_id  = var.use_private_zone ? data.aws_route53_zone.nonprod_private[0].zone_id : data.aws_route53_zone.nonprod_public.zone_id
  name     = local.application_fqdn
  type     = "CNAME"
  ttl      = 300
  records  = [module.alb.alb_dns_name]
}
