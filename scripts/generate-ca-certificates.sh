#!/bin/bash

# Generate CA Certificate for Principal Propagation
# This script generates a self-signed CA certificate and private key

set -e  # Exit on error

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

CERT_DIR="${PROJECT_ROOT}/certificates"
CERT_FILE="${CERT_DIR}/abap-mcp-ca-cert.pem"
KEY_FILE="${CERT_DIR}/abap-mcp-ca-key.pem"

# Certificate parameters
VALIDITY_DAYS=3650  # 10 years
KEY_SIZE=4096
SUBJECT="/C=US/ST=California/L=San Francisco/O=Pacific Gas and Electric Company/OU=ABAP MCP Server/CN=ABAP MCP CA"

echo "=========================================="
echo "🔐 CA Certificate Generation"
echo "=========================================="
echo "Project Root: ${PROJECT_ROOT}"
echo "Certificate Directory: ${CERT_DIR}"
echo "Output Files:"
echo "  - ${CERT_FILE} (public certificate)"
echo "  - ${KEY_FILE} (private key)"
echo "=========================================="
echo ""

# Check if certificates already exist
if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    echo "⚠️  CA certificates already exist!"
    echo ""
    echo "Existing certificate details:"
    openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates
    echo ""
    read -p "Overwrite existing certificates? (yes/no): " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted. Using existing certificates."
        exit 0
    fi

    echo ""
    echo "⚠️  WARNING: Overwriting certificates will invalidate existing ephemeral certificates!"
    echo "⚠️  You will need to update AWS Secrets Manager and re-import to SAP STRUST."
    echo ""
    read -p "Are you sure? Type 'yes' to continue: " FINAL_CONFIRM

    if [ "$FINAL_CONFIRM" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi
fi

# Create certificates directory if it doesn't exist
mkdir -p "$CERT_DIR"

echo "Generating CA private key (RSA ${KEY_SIZE}-bit)..."
openssl genrsa -out "$KEY_FILE" ${KEY_SIZE} 2>/dev/null

# Set restrictive permissions on private key
chmod 600 "$KEY_FILE"
echo "✅ Private key generated: ${KEY_FILE}"

echo ""
echo "Generating self-signed CA certificate (valid ${VALIDITY_DAYS} days)..."
openssl req -new -x509 -days ${VALIDITY_DAYS} \
    -key "$KEY_FILE" \
    -out "$CERT_FILE" \
    -subj "$SUBJECT" \
    -sha256

# Set readable permissions on certificate
chmod 644 "$CERT_FILE"
echo "✅ Certificate generated: ${CERT_FILE}"

echo ""
echo "=========================================="
echo "✅ CA Certificate Generation Complete"
echo "=========================================="
echo ""

# Display certificate details
echo "📋 Certificate Details:"
openssl x509 -in "$CERT_FILE" -noout -text | grep -A 3 "Subject:"
openssl x509 -in "$CERT_FILE" -noout -text | grep -A 1 "Validity"
openssl x509 -in "$CERT_FILE" -noout -text | grep "CA:TRUE"

echo ""
echo "📋 File Sizes:"
ls -lh "$CERT_FILE" "$KEY_FILE" | awk '{print "  " $9 ": " $5}'

echo ""
echo "=========================================="
echo "📧 Next Steps"
echo "=========================================="
echo ""
echo "1. Upload to AWS Secrets Manager:"
echo "   cd ${SCRIPT_DIR}"
echo "   ./create-ca-secret.sh"
echo ""
echo "2. Send public certificate to SAP Basis team:"
echo "   File to share: ${CERT_FILE}"
echo "   Email template: See CERTIFICATES.md"
echo ""
echo "3. SAP Basis imports to STRUST:"
echo "   Transaction: STRUST"
echo "   PSE: SSL server (port 1443/44300)"
echo "   Import: ${CERT_FILE}"
echo ""
echo "4. Test certificate generation:"
echo "   # Start server with SAVE_SAMPLE_CERT_DIR set"
echo "   export SAVE_SAMPLE_CERT_DIR=${CERT_DIR}"
echo "   python src/aws_abap_accelerator/enterprise_main.py"
echo ""
