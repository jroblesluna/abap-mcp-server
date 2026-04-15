variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "enable_principal_propagation" {
  description = "Enable principal propagation (creates CA certificate secret)"
  type        = bool
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
}
