#!/bin/bash

# Create AWS Secrets Manager secret for JWT signing key
# This script generates a secure JWT signing key and uploads it to AWS Secrets Manager

set -e  # Exit on error

PROFILE="${AWS_PROFILE:-CloudAdminNonProdAccess-064160142714}"
REGION="${AWS_REGION:-us-west-2}"
SECRET_NAME="mcp/abap-mcp-server/jwt-signing-key"

echo "=========================================="
echo "🔐 JWT Signing Key Setup"
echo "=========================================="
echo "AWS Profile: ${PROFILE}"
echo "AWS Region:  ${REGION}"
echo "Secret Name: ${SECRET_NAME}"
echo "=========================================="
echo ""

# Check if openssl is available
if ! command -v openssl &> /dev/null; then
    echo "❌ Error: openssl not found"
    echo "   Please install openssl to generate secure keys"
    exit 1
fi

echo "📝 Generating JWT signing key..."
echo ""

# Generate a secure 256-bit (32 bytes) random key
JWT_KEY=$(openssl rand -hex 32)

if [ -z "$JWT_KEY" ]; then
    echo "❌ Error: Failed to generate JWT key"
    exit 1
fi

echo "✅ JWT signing key generated: ${JWT_KEY:0:16}... (64 characters)"
echo ""
echo "🔍 Key Details:"
echo "   Length: 64 characters (256 bits)"
echo "   Format: Hexadecimal"
echo "   Algorithm: Cryptographically secure random"
echo ""

# Confirm before uploading
read -p "Upload this key to AWS Secrets Manager? [y/N]: " CONFIRM
echo ""

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "❌ Upload cancelled"
    echo ""
    echo "💡 To use this key locally, add to your .env file:"
    echo "   JWT_SIGNING_KEY=${JWT_KEY}"
    echo ""
    exit 0
fi

echo "📤 Uploading to AWS Secrets Manager..."
echo ""

# Try to create the secret
if aws secretsmanager create-secret \
    --name "${SECRET_NAME}" \
    --description "JWT signing key for FastMCP OAuth token issuance" \
    --secret-string "${JWT_KEY}" \
    --region ${REGION} \
    --profile ${PROFILE} 2>/dev/null; then
    echo "✅ Secret created successfully"
else
    echo "⚠️  Secret already exists. Updating..."

    # If secret exists, update it
    if aws secretsmanager update-secret \
        --secret-id "${SECRET_NAME}" \
        --secret-string "${JWT_KEY}" \
        --region ${REGION} \
        --profile ${PROFILE} 2>/dev/null; then
        echo "✅ Secret updated successfully"
    else
        echo "❌ Failed to update secret"
        echo ""
        echo "💡 Manual steps:"
        echo "   1. Delete existing secret:"
        echo "      aws secretsmanager delete-secret --secret-id ${SECRET_NAME} --region ${REGION} --profile ${PROFILE}"
        echo ""
        echo "   2. Re-run this script"
        exit 1
    fi
fi

echo ""
echo "=========================================="
echo "✅ JWT Signing Key Setup Complete"
echo "=========================================="
echo ""
echo "📋 Secret Details:"
echo "   Name: ${SECRET_NAME}"
echo "   Region: ${REGION}"
echo "   Key Length: 64 characters (256 bits)"
echo ""
echo "🔍 Verify secret:"
echo "   aws secretsmanager get-secret-value --secret-id ${SECRET_NAME} --region ${REGION} --profile ${PROFILE}"
echo ""
echo "📝 Next Steps:"
echo ""
echo "   1. Add to your local .env file for testing:"
echo "      JWT_SIGNING_KEY=${JWT_KEY}"
echo ""
echo "   2. Update ECS task definition to use this secret:"
echo "      - Add to environment variables in Terraform"
echo "      - Reference secret ARN from Secrets Manager"
echo ""
echo "   3. Restart MCP server to apply the new key"
echo ""
echo "⚠️  IMPORTANT:"
echo "   - Keep this key secure and never commit to git"
echo "   - Users will need to re-authenticate after key rotation"
echo "   - Use different keys for dev/test/prod environments"
echo ""
