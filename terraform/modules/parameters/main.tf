# ============================================================================
# AWS Systems Manager Parameter Store - Non-Sensitive Configuration
# ============================================================================

# SAP System Endpoints Configuration
resource "aws_ssm_parameter" "sap_endpoints" {
  count = var.sap_endpoints_json != "" ? 1 : 0

  name        = "/${var.name_prefix}/sap-endpoints"
  description = "SAP system endpoints configuration"
  type        = "String"
  value       = var.sap_endpoints_json

  tags = merge(
    var.common_tags,
    {
      Name = "${var.name_prefix}-sap-endpoints"
    }
  )
}

# User Exception Mappings (IAM identity -> SAP username)
resource "aws_ssm_parameter" "user_exceptions" {
  count = var.user_exceptions_json != "" ? 1 : 0

  name        = "/${var.name_prefix}/user-exceptions"
  description = "User exception mappings for Principal Propagation"
  type        = "String"
  value       = var.user_exceptions_json

  tags = merge(
    var.common_tags,
    {
      Name = "${var.name_prefix}-user-exceptions"
    }
  )
}

# SAP Systems Configuration (YAML format, without credentials)
resource "aws_ssm_parameter" "sap_systems_config" {
  count = var.sap_systems_yaml != "" ? 1 : 0

  name        = "/${var.name_prefix}/sap-systems-config"
  description = "SAP systems configuration (YAML format, credentials in Secrets Manager)"
  type        = "String"
  value       = var.sap_systems_yaml

  tags = merge(
    var.common_tags,
    {
      Name = "${var.name_prefix}-sap-systems-config"
    }
  )
}

# NOTE: You can also populate these manually:
#
# SAP Endpoints Example:
# aws ssm put-parameter \
#   --name /${var.name_prefix}/sap-endpoints \
#   --type String \
#   --value '{
#     "S4H-100": {
#       "host": "sap-dev.company.com",
#       "port": "44300",
#       "client": "100",
#       "description": "S/4HANA Development"
#     },
#     "S4H-QAS": {
#       "host": "sap-qas.company.com",
#       "port": "44300",
#       "client": "200",
#       "description": "S/4HANA Quality Assurance"
#     }
#   }'
#
# User Exceptions Example:
# aws ssm put-parameter \
#   --name /${var.name_prefix}/user-exceptions \
#   --type String \
#   --value '{
#     "exceptions": {
#       "john.doe@company.com": "JDOE",
#       "jane.smith@company.com": "JSMITH"
#     }
#   }'
