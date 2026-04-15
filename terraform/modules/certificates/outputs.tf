output "secret_arn" {
  description = "ARN of the CA certificate secret in Secrets Manager"
  value = var.certificate_mode == "existing" ? (
    data.aws_secretsmanager_secret.existing_ca_cert[0].arn
    ) : (
    module.ca_certificate_secret[0].arn
  )
}

output "secret_name" {
  description = "Name of the CA certificate secret"
  value = var.certificate_mode == "existing" ? (
    data.aws_secretsmanager_secret.existing_ca_cert[0].name
    ) : (
    module.ca_certificate_secret[0].aws_secretsmanager_secret.name
  )
}

output "secret_id" {
  description = "ID of the CA certificate secret"
  value = var.certificate_mode == "existing" ? (
    data.aws_secretsmanager_secret.existing_ca_cert[0].id
    ) : (
    module.ca_certificate_secret[0].aws_secretsmanager_secret.id
  )
}
