#!/bin/bash

# Create CA certificate secret in AWS Secrets Manager
# This script uploads existing CA certificate and private key to AWS Secrets Manager

set -e  # Exit on error

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

PROFILE="${AWS_PROFILE:-CloudAdminNonProdAccess-064160142714}"
REGION="${AWS_REGION:-us-west-2}"
SECRET_NAME="mcp/abap-mcp-server/ca-certificate"

CERT_FILE="${PROJECT_ROOT}/certificates/abap-mcp-ca-cert.pem"
KEY_FILE="${PROJECT_ROOT}/certificates/abap-mcp-ca-key.pem"

echo "=========================================="
echo "🔐 CA Certificate Secret Setup"
echo "=========================================="
echo "Project Root: ${PROJECT_ROOT}"
echo "AWS Profile:  ${PROFILE}"
echo "AWS Region:   ${REGION}"
echo "Secret Name:  ${SECRET_NAME}"
echo "=========================================="
echo ""

# Check if certificate files exist
if [ ! -f "$CERT_FILE" ]; then
  echo "❌ Error: Certificate file not found: $CERT_FILE"
  echo ""
  echo "💡 To generate certificates, see: ${PROJECT_ROOT}/certificates/README.md"
  exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
  echo "❌ Error: Private key file not found: $KEY_FILE"
  echo ""
  echo "💡 To generate certificates, see: ${PROJECT_ROOT}/certificates/README.md"
  exit 1
fi

echo "✅ Certificate files found"
echo ""

# Read certificate and key files
echo "Reading certificate and private key..."
CA_CERT=$(cat "$CERT_FILE")
CA_KEY=$(cat "$KEY_FILE")

# Create JSON secret value
# Note: Keys must match what the code expects: ca_certificate and ca_private_key
SECRET_VALUE=$(jq -n \
  --arg cert "$CA_CERT" \
  --arg key "$CA_KEY" \
  '{ca_certificate: $cert, ca_private_key: $key}')

echo "Creating secret: ${SECRET_NAME}"
aws secretsmanager create-secret \
  --name "${SECRET_NAME}" \
  --description "CA certificate and private key for Principal Propagation (ABAP MCP Server)" \
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
echo "✅ CA Certificate Secret Setup Complete"
echo "=========================================="
echo ""
echo "📋 Secret Details:"
echo "  Name: ${SECRET_NAME}"
echo "  Region: ${REGION}"
echo ""
echo "🔍 Verify secret:"
echo "  aws secretsmanager describe-secret --secret-id ${SECRET_NAME} --region ${REGION} --profile ${PROFILE}"
echo ""
