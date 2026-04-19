#!/bin/bash

# Create OAuth credentials secret in AWS Secrets Manager
# This script stores OAuth client secret for Entra ID (or Cognito) authentication

set -e  # Exit on error

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

PROFILE="${AWS_PROFILE:-CloudAdminNonProdAccess-064160142714}"
REGION="${AWS_REGION:-us-west-2}"
SECRET_NAME="mcp/abap-mcp-server/oauth-credentials"

echo "=========================================="
echo "🔐 OAuth Credentials Secret Setup"
echo "=========================================="
echo "Project Root: ${PROJECT_ROOT}"
echo "AWS Profile:  ${PROFILE}"
echo "AWS Region:   ${REGION}"
echo "Secret Name:  ${SECRET_NAME}"
echo "=========================================="
echo ""

# Prompt for OAuth client secret
echo "Enter OAuth Client Secret (from Entra ID/Cognito app registration):"
read -s OAUTH_CLIENT_SECRET
echo ""

if [ -z "$OAUTH_CLIENT_SECRET" ]; then
  echo "❌ Error: OAuth client secret cannot be empty"
  exit 1
fi

# Create JSON secret value
# Note: Key must match what ECS expects: client_secret
SECRET_VALUE=$(jq -n \
  --arg secret "$OAUTH_CLIENT_SECRET" \
  '{client_secret: $secret}')

echo "Creating secret: ${SECRET_NAME}"
aws secretsmanager create-secret \
  --name "${SECRET_NAME}" \
  --description "OAuth client secret for Entra ID authentication (ABAP MCP Server)" \
  --secret-string "${SECRET_VALUE}" \
  --region ${REGION} \
  --profile ${PROFILE} 2>&1

if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Secret created successfully"
else
  echo ""
  echo "⚠️  Secret may already exist. Updating..."
  aws secretsmanager put-secret-value \
    --secret-id "${SECRET_NAME}" \
    --secret-string "${SECRET_VALUE}" \
    --region ${REGION} \
    --profile ${PROFILE}

  echo "✅ Secret updated successfully"
fi

echo ""
echo "=========================================="
echo "✅ OAuth Credentials Secret Setup Complete"
echo "=========================================="
echo ""
echo "📋 Secret Details:"
echo "  Name: ${SECRET_NAME}"
echo "  Region: ${REGION}"
echo "  Format: {\"client_secret\": \"<value>\"}"
echo ""
echo "🔍 Verify secret:"
echo "  aws secretsmanager describe-secret --secret-id ${SECRET_NAME} --region ${REGION} --profile ${PROFILE}"
echo ""
echo "🚀 Next Steps:"
echo "  1. Verify secret was created"
echo "  2. Force ECS service deployment:"
echo "     aws ecs update-service --cluster abap-mcp-server-Dev-cluster \\"
echo "       --service abap-mcp-server-Dev-service \\"
echo "       --task-definition abap-mcp-server-Dev-task:25 \\"
echo "       --force-new-deployment --region ${REGION} --profile ${PROFILE}"
echo ""
