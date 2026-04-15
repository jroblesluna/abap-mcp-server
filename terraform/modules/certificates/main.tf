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
# MODE: EXISTING - Read existing secret from AWS Secrets Manager
# ============================================================================

# Data source to read existing secret (when certificate_mode = "existing")
data "aws_secretsmanager_secret" "existing_ca_cert" {
  count = var.certificate_mode == "existing" ? 1 : 0
  name  = var.existing_secret_name
}

data "aws_secretsmanager_secret_version" "existing_ca_cert" {
  count     = var.certificate_mode == "existing" ? 1 : 0
  secret_id = data.aws_secretsmanager_secret.existing_ca_cert[0].id
}

# ============================================================================
# MODE: CREATE - Create new secret using PGE module
# ============================================================================

# Read CA certificate from file (when certificate_mode = "create")
locals {
  ca_cert_file = "${path.root}/certificates/abap-mcp-ca-cert.pem"
  ca_key_file  = "${path.root}/certificates/abap-mcp-ca-key.pem"

  # Check if files exist
  ca_cert_exists = fileexists(local.ca_cert_file)
  ca_key_exists  = fileexists(local.ca_key_file)

  # Read certificate from file (only for "create" mode)
  ca_cert_content = var.certificate_mode == "create" ? (local.ca_cert_exists ? file(local.ca_cert_file) : var.ca_cert_pem) : ""

  # Read private key from variable (TFC sensitive var) OR file (local)
  # Priority: 1. Variable (TFC), 2. File (local)
  ca_key_content = var.certificate_mode == "create" ? (var.ca_key_pem != "" ? var.ca_key_pem : (local.ca_key_exists ? file(local.ca_key_file) : "")) : ""
}

# Create secret in AWS Secrets Manager using PGE module (when certificate_mode = "create")
module "ca_certificate_secret" {
  count   = var.certificate_mode == "create" ? 1 : 0
  source  = "app.terraform.io/pgetech/secretsmanager/aws"
  version = "0.1.2"

  secretsmanager_name        = "mcp/${var.project_name}/ca-certificate"
  secretsmanager_description = "CA certificate and private key for Principal Propagation (ABAP MCP Server)"

  # Secret value (JSON with ca_cert and ca_key)
  secret_string = jsonencode({
    ca_cert = local.ca_cert_content
    ca_key  = local.ca_key_content
  })
  secret_version_enabled = true

  # Recovery window (7 days allows recovery if deleted accidentally)
  recovery_window_in_days = var.recovery_window_in_days

  # Custom policy (empty JSON object = use only PGE compliance policy)
  custom_policy = "{}"

  # KMS encryption (optional for Internal data classification)
  kms_key_id = var.kms_key_id

  # PGE required tags
  tags = var.tags
}
