#!/bin/bash

# Create AWS Systems Manager Parameter Store parameters
# - SAP endpoints configuration
# - User exceptions mapping

set -e

PROFILE="${AWS_PROFILE:-CloudAdminNonProdAccess-064160142714}"
REGION="${AWS_REGION:-us-west-2}"

echo "=========================================="
echo "📋 AWS Parameter Store Setup"
echo "=========================================="
echo "AWS Profile:     ${PROFILE}"
echo "AWS Region:      ${REGION}"
echo "=========================================="
echo ""

# ============================================================================
# 1. SAP Endpoints Parameter
# ============================================================================

PARAMETER_NAME="/mcp/abap-mcp-server/sap-endpoints"

SAP_ENDPOINTS_YAML=$(cat <<'EOF'
endpoints:
  DV8:
    host: sapdv8db1.comp.pge.com
    port: 1443
    client: "120"
    description: SAP Development System DV8 Client 120
  MS1:
    host: vhpgxms1ci.s4hc.pge.com
    port: 44300
    client: "100"
    description: SAP Development System MS1 Client 100
  MD1:
    host: vhpgxmd1ci.s4hc.pge.com
    port: 44300
    client: "100"
    description: SAP Development System MD1 Client 100
EOF
)

echo "Creating parameter: ${PARAMETER_NAME}"
aws ssm put-parameter \
  --name "${PARAMETER_NAME}" \
  --description "SAP endpoint configurations for Principal Propagation (ABAP MCP Server)" \
  --value "${SAP_ENDPOINTS_YAML}" \
  --type "String" \
  --region ${REGION} \
  --profile ${PROFILE} \
  --overwrite 2>&1

if [ $? -eq 0 ]; then
  echo "✅ SAP endpoints parameter created"
else
  echo "❌ Failed to create SAP endpoints parameter"
  exit 1
fi

echo ""

# ============================================================================
# 2. User Exceptions Parameter
# ============================================================================

PARAMETER_NAME="/mcp/abap-mcp-server/user-exceptions"

USER_EXCEPTIONS_YAML=$(cat <<'EOF'
exceptions: {}
EOF
)

echo "Creating parameter: ${PARAMETER_NAME}"
aws ssm put-parameter \
  --name "${PARAMETER_NAME}" \
  --description "User exceptions mapping for ABAP MCP Server (empty structure)" \
  --value "${USER_EXCEPTIONS_YAML}" \
  --type "String" \
  --region ${REGION} \
  --profile ${PROFILE} \
  --overwrite 2>&1

if [ $? -eq 0 ]; then
  echo "✅ User exceptions parameter created"
else
  echo "❌ Failed to create user exceptions parameter"
  exit 1
fi

echo ""
echo "=========================================="
echo "✅ Parameter Store Setup Complete"
echo "=========================================="
echo ""
echo "📋 Parameters Created:"
echo "  /mcp/abap-mcp-server/sap-endpoints"
echo "  /mcp/abap-mcp-server/user-exceptions"
echo ""
echo "🔍 Verify parameters:"
echo "  aws ssm get-parameter --name /mcp/abap-mcp-server/sap-endpoints --region ${REGION} --profile ${PROFILE}"
echo "  aws ssm get-parameter --name /mcp/abap-mcp-server/user-exceptions --region ${REGION} --profile ${PROFILE}"
echo ""
