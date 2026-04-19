variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "container_image" {
  description = "Docker image URL"
  type        = string
}

variable "container_cpu" {
  description = "CPU units for Fargate task"
  type        = number
}

variable "container_memory" {
  description = "Memory for Fargate task in MB"
  type        = number
}

variable "container_port" {
  description = "Container port"
  type        = number
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
}

variable "task_execution_role_arn" {
  description = "ARN of the task execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the task role"
  type        = string
}

variable "ecs_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "target_group_arn" {
  description = "ARN of the ALB target group"
  type        = string
}

variable "alb_listener_http_arn" {
  description = "ARN of the ALB HTTP listener"
  type        = string
}

variable "alb_listener_https_arn" {
  description = "ARN of the ALB HTTPS listener"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name"
  type        = string
}

variable "enable_enterprise_mode" {
  description = "Enable enterprise mode"
  type        = bool
}

variable "enable_principal_propagation" {
  description = "Enable principal propagation"
  type        = bool
}

variable "enable_oauth_flow" {
  description = "Enable OAuth authentication flow"
  type        = bool
}

variable "credential_provider" {
  description = "Credential provider"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "ca_certificate_secret_arn" {
  description = "ARN of CA certificate secret"
  type        = string
  default     = ""
}

variable "ca_secret_name" {
  description = "Name of CA certificate secret (for application to load from Secrets Manager)"
  type        = string
  default     = ""
}

variable "sap_endpoints_parameter" {
  description = "SSM Parameter Store path for SAP endpoints configuration"
  type        = string
}

variable "user_exceptions_parameter" {
  description = "SSM Parameter Store path for user exceptions mapping"
  type        = string
}

variable "oauth_secret_arn" {
  description = "ARN of OAuth secret"
  type        = string
}

variable "jwt_signing_key_secret_arn" {
  description = "ARN of JWT signing key secret"
  type        = string
}

variable "sap_credentials_secret_arn" {
  description = "ARN of SAP credentials secret (mcp/abap-mcp-server)"
  type        = string
}

variable "enable_container_insights" {
  description = "Enable Container Insights"
  type        = bool
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
}

variable "sap_host" {
  description = "SAP system host"
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
  description = "SAP language"
  type        = string
}

variable "sap_secure" {
  description = "Use HTTPS for SAP connection"
  type        = string
}

variable "ssl_verify" {
  description = "Verify SSL certificates"
  type        = string
}

variable "sap_port" {
  description = "SAP system port"
  type        = string
}

variable "log_level" {
  description = "Application log level"
  type        = string
}

variable "enable_http_request_logging" {
  description = "Enable HTTP request logging"
  type        = string
}

variable "oauth_auth_endpoint" {
  description = "OAuth authorization endpoint"
  type        = string
  default     = ""
}

variable "oauth_token_endpoint" {
  description = "OAuth token endpoint"
  type        = string
  default     = ""
}

variable "oauth_client_id" {
  description = "OAuth client ID"
  type        = string
  default     = ""
}

variable "oauth_issuer" {
  description = "OAuth issuer URL"
  type        = string
  default     = ""
}

variable "server_base_url" {
  description = "Server base URL for OAuth callbacks"
  type        = string
  default     = ""
}
