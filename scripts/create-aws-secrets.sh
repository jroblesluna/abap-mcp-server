#!/bin/bash

# Create AWS Secrets Manager secrets for SAP credentials
# This script creates secrets for each SAP system defined in sap-systems.yaml

set -e  # Exit on error

PROFILE="${AWS_PROFILE:-CloudAdminNonProdAccess-064160142714}"
REGION="${AWS_REGION:-us-west-2}"

echo "=========================================="
echo "🔐 AWS Secrets Manager Setup"
echo "=========================================="
echo "AWS Profile: ${PROFILE}"
echo "AWS Region:  ${REGION}"
echo "=========================================="
echo ""

# DV8 System
echo "=== DV8 System ==="
echo "SAP Development System DV8 Client 120"
echo ""
read -p "Username for DV8: " DV8_USER
read -sp "Password for DV8: " DV8_PASS
echo ""

if [ -n "$DV8_USER" ] && [ -n "$DV8_PASS" ]; then
  SECRET=$(jq -n --arg u "$DV8_USER" --arg p "$DV8_PASS" '{SAP_USERNAME: $u, SAP_PASSWORD: $p}')

  echo "Creating secret: mcp/abap-mcp-server/DV8"
  aws secretsmanager create-secret \
    --name mcp/abap-mcp-server/DV8 \
    --description "SAP credentials for DV8 system (Client 120)" \
    --secret-string "${SECRET}" \
    --region ${REGION} \
    --profile ${PROFILE} 2>/dev/null && echo "✅ DV8 secret created" || echo "⚠️  DV8 secret may already exist"
fi

echo ""

# MS1 System
echo "=== MS1 System ==="
echo "SAP System MS1 Client 100"
echo ""
read -p "Username for MS1: " MS1_USER
read -sp "Password for MS1: " MS1_PASS
echo ""

if [ -n "$MS1_USER" ] && [ -n "$MS1_PASS" ]; then
  SECRET=$(jq -n --arg u "$MS1_USER" --arg p "$MS1_PASS" '{SAP_USERNAME: $u, SAP_PASSWORD: $p}')

  echo "Creating secret: mcp/abap-mcp-server/MS1"
  aws secretsmanager create-secret \
    --name mcp/abap-mcp-server/MS1 \
    --description "SAP credentials for MS1 system (Client 100)" \
    --secret-string "${SECRET}" \
    --region ${REGION} \
    --profile ${PROFILE} 2>/dev/null && echo "✅ MS1 secret created" || echo "⚠️  MS1 secret may already exist"
fi

echo ""

# MD1 System
echo "=== MD1 System ==="
echo "SAP System MD1 Client 100"
echo ""
read -p "Username for MD1: " MD1_USER
read -sp "Password for MD1: " MD1_PASS
echo ""

if [ -n "$MD1_USER" ] && [ -n "$MD1_PASS" ]; then
  SECRET=$(jq -n --arg u "$MD1_USER" --arg p "$MD1_PASS" '{SAP_USERNAME: $u, SAP_PASSWORD: $p}')

  echo "Creating secret: mcp/abap-mcp-server/MD1"
  aws secretsmanager create-secret \
    --name mcp/abap-mcp-server/MD1 \
    --description "SAP credentials for MD1 system (Client 100)" \
    --secret-string "${SECRET}" \
    --region ${REGION} \
    --profile ${PROFILE} 2>/dev/null && echo "✅ MD1 secret created" || echo "⚠️  MD1 secret may already exist"
fi

echo ""
echo "=========================================="
echo "✅ Secrets Setup Complete"
echo "=========================================="
echo ""
echo "📋 Secrets Created:"
echo "  - mcp/abap-mcp-server/DV8"
echo "  - mcp/abap-mcp-server/MS1"
echo "  - mcp/abap-mcp-server/MD1"
echo ""
echo "🔍 Verify secrets:"
echo "  aws secretsmanager list-secrets --region ${REGION} --profile ${PROFILE}"
echo ""
