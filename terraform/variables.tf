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
  default     = "CloudAdmin"
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
  description = "ECR repository URL (without tag)"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "working"
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

variable "certificate_mode" {
  description = "Certificate management mode: 'existing' = use existing secret in AWS (dev), 'create' = create new secret with PGE module (prod)"
  type        = string
  default     = "existing"
  validation {
    condition     = contains(["existing", "create"], var.certificate_mode)
    error_message = "certificate_mode must be either 'existing' or 'create'"
  }
}

variable "existing_ca_secret_name" {
  description = "Name of existing CA certificate secret in AWS Secrets Manager (used when certificate_mode = 'existing')"
  type        = string
  default     = ""
}

variable "ca_cert_pem" {
  description = "CA certificate in PEM format (used when certificate_mode = 'create')"
  type        = string
  default     = ""
}

variable "ca_key_pem" {
  description = "CA private key in PEM format (used when certificate_mode = 'create', use TFC sensitive variable)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cert_recovery_window_days" {
  description = "Recovery window in days for CA certificate secret deletion (used when certificate_mode = 'create')"
  type        = number
  default     = 7
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

variable "sap_endpoints_json" {
  description = "JSON string containing SAP system endpoints (will be stored in Parameter Store)"
  type        = string
  sensitive   = true
}

variable "user_exceptions_json" {
  description = "JSON string containing user exception mappings (optional)"
  type        = string
  default     = ""
}

variable "sap_systems_yaml" {
  description = "YAML string containing SAP systems configuration for multi-system mode (credentials stored separately in Secrets Manager)"
  type        = string
  default     = ""
}

variable "sap_host" {
  description = "SAP system host (for direct environment variable configuration)"
  type        = string
}

variable "sap_instance_number" {
  description = "SAP instance number"
  type        = string
}

variable "sap_client" {
  description = "SAP client number"
  type        = string
}

variable "sap_language" {
  description = "SAP language code (e.g., EN, DE, ES)"
  type        = string
}

variable "sap_secure" {
  description = "Use HTTPS for SAP connection (true/false)"
  type        = string
}

variable "ssl_verify" {
  description = "Verify SSL certificates (true/false)"
  type        = string
}

variable "sap_port" {
  description = "SAP system port"
  type        = string
}

variable "log_level" {
  description = "Application log level (INFO, DEBUG, WARNING, ERROR)"
  type        = string
}

# ============================================================================
# OAuth Configuration
# ============================================================================

variable "oauth_auth_endpoint" {
  description = "OAuth authorization endpoint (e.g., https://cognito-domain.auth.region.amazoncognito.com/oauth2/authorize)"
  type        = string
  default     = ""
}

variable "oauth_token_endpoint" {
  description = "OAuth token endpoint (e.g., https://cognito-domain.auth.region.amazoncognito.com/oauth2/token)"
  type        = string
  default     = ""
}

variable "oauth_client_id" {
  description = "OAuth client ID"
  type        = string
  default     = ""
}

variable "oauth_issuer" {
  description = "OAuth issuer URL for OIDC discovery (e.g., https://cognito-idp.region.amazonaws.com/pool-id)"
  type        = string
  default     = ""
}

variable "server_base_url" {
  description = "Server base URL for OAuth callbacks (e.g., https://abap-mcp-server.nonprod.pge.com)"
  type        = string
  default     = ""
}

variable "oauth_secret_arn" {
  description = "ARN of OAuth credentials secret in AWS Secrets Manager (contains client_id and client_secret)"
  type        = string
  default     = ""
}

variable "enable_http_request_logging" {
  description = "Enable HTTP request logging (true/false)"
  type        = string
}

# ============================================================================
# Cognito Configuration (Optional - for managed User Pool)
# ============================================================================

variable "enable_cognito" {
  description = "Enable Cognito User Pool creation (set to false to use existing User Pool)"
  type        = bool
  default     = false
}

variable "cognito_user_pool_name" {
  description = "Name of the Cognito User Pool to create"
  type        = string
  default     = "abap-mcp-server-user-pool"
}

variable "cognito_app_client_name" {
  description = "Name of the Cognito App Client to create"
  type        = string
  default     = "abap-mcp-server"
}

variable "cognito_domain_prefix" {
  description = "Domain prefix for Cognito Hosted UI (must be globally unique)"
  type        = string
  default     = ""
}

variable "cognito_callback_urls" {
  description = "List of allowed OAuth callback URLs"
  type        = list(string)
  default     = []
}

variable "cognito_sns_caller_arn" {
  description = "ARN of IAM role for SNS (SMS configuration). Leave empty to disable SMS."
  type        = string
  default     = ""
}

variable "cognito_sns_external_id" {
  description = "External ID for SNS role"
  type        = string
  default     = ""
}

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
