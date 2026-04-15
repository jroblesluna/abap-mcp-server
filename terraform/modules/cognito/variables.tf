# ============================================================================
# Cognito Module Variables
# ============================================================================

variable "user_pool_name" {
  description = "Name of the Cognito User Pool"
  type        = string
}

variable "app_client_name" {
  description = "Name of the Cognito App Client"
  type        = string
}

variable "cognito_domain_prefix" {
  description = "Domain prefix for Cognito Hosted UI (must be unique across AWS)"
  type        = string
}

variable "callback_urls" {
  description = "List of allowed callback URLs for OAuth"
  type        = list(string)
}

variable "oauth_secret_name" {
  description = "Name of the Secrets Manager secret for OAuth credentials"
  type        = string
  default     = "mcp/abap-mcp-server/oauth-credentials"
}

variable "create_oauth_secret" {
  description = "Create new Secrets Manager secret (false = update existing secret)"
  type        = bool
  default     = false
}

variable "oauth_secret_recovery_window" {
  description = "Recovery window in days for OAuth secret (0 = immediate deletion)"
  type        = number
  default     = 0
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "sns_caller_arn" {
  description = "ARN of IAM role for SNS (SMS configuration). Leave empty to disable SMS."
  type        = string
  default     = ""
}

variable "sns_external_id" {
  description = "External ID for SNS role"
  type        = string
  default     = ""
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on User Pool (false = allow terraform destroy)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
