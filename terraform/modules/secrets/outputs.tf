output "ca_certificate_secret_arn" {
  description = "ARN of CA certificate secret"
  value       = var.enable_principal_propagation ? aws_secretsmanager_secret.ca_certificate[0].arn : ""
}

output "ca_certificate_secret_name" {
  description = "Name of CA certificate secret"
  value       = var.enable_principal_propagation ? aws_secretsmanager_secret.ca_certificate[0].name : ""
}
