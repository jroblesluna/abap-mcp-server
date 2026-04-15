variable "certificate_mode" {
  description = "Certificate management mode: 'existing' = use existing secret in AWS, 'create' = create new secret with PGE module"
  type        = string
  default     = "existing"
  validation {
    condition     = contains(["existing", "create"], var.certificate_mode)
    error_message = "certificate_mode must be either 'existing' or 'create'"
  }
}

variable "existing_secret_name" {
  description = "Name of existing secret in AWS Secrets Manager (used when certificate_mode = 'existing')"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project name for resource naming (used when certificate_mode = 'create')"
  type        = string
}

variable "ca_cert_pem" {
  description = "CA certificate in PEM format (used when certificate_mode = 'create')"
  type        = string
  default     = ""
}

variable "ca_key_pem" {
  description = "CA private key in PEM format (used when certificate_mode = 'create')"
  type        = string
  default     = ""
  sensitive   = true
}

variable "kms_key_id" {
  description = "KMS key ID for encrypting the secret (used when certificate_mode = 'create')"
  type        = string
  default     = null
}

variable "recovery_window_in_days" {
  description = "Recovery window for secret deletion (used when certificate_mode = 'create')"
  type        = number
  default     = 7
}

variable "tags" {
  description = "PGE required tags"
  type        = map(string)
}
