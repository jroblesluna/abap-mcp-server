output "secret_arn" {
  description = "ARN of the CA certificate secret in Secrets Manager"
  value       = data.aws_secretsmanager_secret.ca_cert.arn
}

output "secret_name" {
  description = "Name of the CA certificate secret"
  value       = data.aws_secretsmanager_secret.ca_cert.name
}

output "secret_id" {
  description = "ID of the CA certificate secret"
  value       = data.aws_secretsmanager_secret.ca_cert.id
}
