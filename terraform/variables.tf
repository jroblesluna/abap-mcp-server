# ============================================================================
# Terraform Variables for ABAP Accelerator MCP Server
# All values must be provided in terraform.tfvars
# ============================================================================

# ============================================================================
# PGE Standard Variables (for TFC)
# ============================================================================

variable "account_num" {
  type        = string
  description = "AWS account number for application account"
}

variable "aws_role" {
  type        = string
  description = "AWS role to assume for Terraform operations"
}

variable "account_num_r53" {
  type        = string
  description = "AWS account number for Route53 (cross-account)"
}

variable "aws_r53_role" {
  type        = string
  description = "AWS role to assume for Route53 operations (cross-account)"
}

# ============================================================================
# AWS Configuration
# ============================================================================

variable "region" {
  description = "AWS region for deployment"
  type        = string
}

variable "profile" {
  description = "AWS CLI profile for application account (064...) - used for local dev only, not in TFC"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

# ============================================================================
# Network Configuration
# ============================================================================

variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks and internal ALB (must have NAT gateway access for outbound)"
  type        = list(string)
}

# ============================================================================
# ECS Configuration
# ============================================================================

variable "container_image" {
  description = "Docker image URL (ECR repository:tag). Leave empty to use newly created ECR repo."
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL (without tag) - for outputs only"
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "Docker image tag - for outputs only"
  type        = string
  default     = ""
}

variable "container_cpu" {
  description = "CPU units for Fargate task (256, 512, 1024, 2048, 4096)"
  type        = number
}

variable "container_memory" {
  description = "Memory for Fargate task in MB (512, 1024, 2048, 4096, 8192)"
  type        = number
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
}

variable "container_port" {
  description = "Container port for the application"
  type        = number
}

# ============================================================================
# Application Configuration
# ============================================================================

variable "enable_enterprise_mode" {
  description = "Enable enterprise multi-tenant mode"
  type        = bool
}

variable "enable_principal_propagation" {
  description = "Enable certificate-based authentication with IAM Identity Center"
  type        = bool
}

variable "enable_oauth_flow" {
  description = "Enable OAuth authentication flow"
  type        = bool
}

variable "ca_secret_name" {
  description = "Name of CA certificate secret in AWS Secrets Manager (managed externally)"
  type        = string
}

variable "sap_endpoints_parameter" {
  description = "SSM Parameter Store path for SAP endpoints configuration"
  type        = string
}

variable "user_exceptions_parameter" {
  description = "SSM Parameter Store path for user exceptions mapping"
  type        = string
}

variable "credential_provider" {
  description = "Credential provider (aws_secrets, env, keychain)"
  type        = string
}

# ============================================================================
# Route53 and Domain Configuration (Multi-Account)
# ============================================================================

variable "route53_profile" {
  description = "AWS CLI profile for Route53 account (514...) - used for local dev only, not in TFC"
  type        = string
  default     = ""
}

variable "route53_hosted_zone_name" {
  description = "Route53 hosted zone name (e.g., nonprod.pge.com)"
  type        = string
}

variable "application_hostname" {
  description = "Hostname for the application (e.g., abap-mcp). Combined with route53_hosted_zone_name to form FQDN."
  type        = string
}

variable "use_private_zone" {
  description = "Create DNS record in private hosted zone (for internal access only)"
  type        = bool
}

# ============================================================================
# SAP System Configuration
# ============================================================================

variable "sap_host" {
  description = "SAP system host - not used in enterprise mode (systems in Parameter Store)"
  type        = string
  default     = ""
}

variable "sap_instance_number" {
  description = "SAP instance number - not used in enterprise mode"
  type        = string
  default     = "00"
}

variable "sap_client" {
  description = "SAP client number - not used in enterprise mode"
  type        = string
  default     = "100"
}

variable "sap_language" {
  description = "SAP language code - not used in enterprise mode"
  type        = string
  default     = "EN"
}

variable "sap_secure" {
  description = "Use HTTPS for SAP connection - not used in enterprise mode"
  type        = string
  default     = "true"
}

variable "ssl_verify" {
  description = "Verify SSL certificates (true/false)"
  type        = string
}

variable "sap_port" {
  description = "SAP system port - not used in enterprise mode"
  type        = string
  default     = "44300"
}

variable "log_level" {
  description = "Application log level (INFO, DEBUG, WARNING, ERROR)"
  type        = string
}

# ============================================================================
# OAuth Configuration
# ============================================================================

variable "oauth_auth_endpoint" {
  description = "OAuth authorization endpoint - Examples: Cognito: https://domain.auth.region.amazoncognito.com/oauth2/authorize, Entra ID: https://login.microsoftonline.com/<tenant>/oauth2/v2.0/authorize, Okta: https://domain.okta.com/oauth2/v1/authorize"
  type        = string
}

variable "oauth_token_endpoint" {
  description = "OAuth token endpoint - Examples: Cognito: https://domain.auth.region.amazoncognito.com/oauth2/token, Entra ID: https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token, Okta: https://domain.okta.com/oauth2/v1/token"
  type        = string
}

variable "oauth_client_id" {
  description = "OAuth client ID (application ID from your OAuth provider: Cognito, Entra ID, Okta, etc.)"
  type        = string
}

variable "oauth_issuer" {
  description = "OAuth issuer URL for OIDC discovery - Examples: Cognito: https://cognito-idp.region.amazonaws.com/pool-id, Entra ID: https://login.microsoftonline.com/<tenant>/v2.0, Okta: https://domain.okta.com"
  type        = string
}

variable "server_base_url" {
  description = "Server base URL for OAuth callbacks (e.g., https://abap-mcp-server.nonprod.pge.com) - Required for OAuth redirect URIs"
  type        = string
}

variable "oauth_secret_name" {
  description = "Name of OAuth credentials secret in AWS Secrets Manager (contains client_secret)"
  type        = string
}

variable "jwt_signing_key_secret_name" {
  description = "Name of JWT signing key secret in AWS Secrets Manager"
  type        = string
}

variable "enable_http_request_logging" {
  description = "Enable HTTP request logging (true/false)"
  type        = string
}

# NOTE: All OAuth providers (Cognito, Entra ID, Okta) are managed externally
# Configuration is provided via oauth_* variables above - no additional variables needed

# ============================================================================
# Security Configuration
# ============================================================================

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the ALB (e.g., corporate VPN)"
  type        = list(string)
}

# ============================================================================
# Monitoring and Logging
# ============================================================================

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
}

# ============================================================================
# Tags
# ============================================================================

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
}
