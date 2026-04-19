terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ============================================================================
# Reference Existing CA Certificate Secret
# ============================================================================
# NOTE: CA certificates are managed externally (separate team/process)
# This module only references the existing Secrets Manager secret

data "aws_secretsmanager_secret" "ca_cert" {
  name = var.existing_secret_name
}

data "aws_secretsmanager_secret_version" "ca_cert" {
  secret_id = data.aws_secretsmanager_secret.ca_cert.id
}
