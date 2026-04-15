variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "sap_endpoints_json" {
  description = "JSON string containing SAP system endpoints"
  type        = string
  default     = ""
  sensitive   = true
}

variable "user_exceptions_json" {
  description = "JSON string containing user exception mappings"
  type        = string
  default     = ""
}

variable "sap_systems_yaml" {
  description = "YAML string containing SAP systems configuration (without credentials)"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
}
