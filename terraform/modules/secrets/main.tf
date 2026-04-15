# ============================================================================
# AWS Secrets Manager - Sensitive Configuration
# ============================================================================

# CA Certificate for Principal Propagation (X.509 certificates)
resource "aws_secretsmanager_secret" "ca_certificate" {
  count = var.enable_principal_propagation ? 1 : 0

  name                    = "${var.name_prefix}/ca-certificate"
  description             = "CA certificate and private key for Principal Propagation"
  recovery_window_in_days = 0  # Force immediate deletion without recovery period

  tags = merge(
    var.common_tags,
    {
      Name = "${var.name_prefix}-ca-certificate"
    }
  )
}

# NOTE: Secret values must be populated manually or via CI/CD:
#
# For CA Certificate (Principal Propagation):
# aws secretsmanager put-secret-value \
#   --secret-id ${aws_secretsmanager_secret.ca_certificate[0].id} \
#   --secret-string '{
#     "ca_cert": "-----BEGIN CERTIFICATE-----\n...",
#     "ca_key": "-----BEGIN PRIVATE KEY-----\n..."
#   }'
