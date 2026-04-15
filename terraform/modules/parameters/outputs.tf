output "sap_endpoints_parameter_name" {
  description = "Name of SAP endpoints parameter"
  value       = var.sap_endpoints_json != "" ? aws_ssm_parameter.sap_endpoints[0].name : "Not created"
}

output "sap_endpoints_parameter_arn" {
  description = "ARN of SAP endpoints parameter"
  value       = var.sap_endpoints_json != "" ? aws_ssm_parameter.sap_endpoints[0].arn : ""
}

output "user_exceptions_parameter_name" {
  description = "Name of user exceptions parameter"
  value       = var.user_exceptions_json != "" ? aws_ssm_parameter.user_exceptions[0].name : "Not created"
}
