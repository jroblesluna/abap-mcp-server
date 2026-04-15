# Terraform Cloud Deployment Guide

This guide explains how to deploy the ABAP Accelerator MCP Server using Terraform Cloud (TFC).

## Prerequisites

1. ✅ Terraform Cloud account with organization: `pgetech`
2. ✅ AWS credentials configured in TFC workspace
3. ✅ CA certificates generated (already done - in `certificates/` directory)

## Architecture

```
TFC Workspace
  │
  ├─ Reads: terraform/certificates/abap-mcp-ca-cert.pem (public cert, in repo)
  ├─ Reads: TFC Variable "ca_key_pem" (private key, sensitive)
  │
  └─ Creates: AWS Secrets Manager secret
       └─ abap-mcp-server/ca-certificate (contains both cert + key)
```

## Step 1: Destroy Local Infrastructure

```bash
cd terraform
terraform destroy
```

**What gets destroyed:**
- ✅ ECS cluster and service
- ✅ ALB and target groups
- ✅ Security groups
- ✅ CloudWatch logs
- ✅ Route53 records
- ✅ IAM roles

**What does NOT get destroyed:**
- ✅ ECR repository (managed separately)
- ✅ SAP credentials in Secrets Manager (`mcp/abap-mcp-server`)
- ✅ VPC and subnets (existing infrastructure)
- ⚠️ CA certificate secret WILL be deleted if it was managed by old `secrets` module

## Step 2: Configure TFC Backend

Create or update `terraform/backend.tf`:

```hcl
terraform {
  cloud {
    organization = "pgetech"

    workspaces {
      name = "abap-mcp-server-dev"
    }
  }
}
```

## Step 3: Create TFC Workspace

### Option A: Via TFC UI (Recommended)

1. Go to: https://app.terraform.io
2. Navigate to organization: `pgetech`
3. Click "New Workspace"
4. Choose workflow type:
   - **VCS-driven**: Connect to GitHub repo (automatic runs on push)
   - **CLI-driven**: Manual runs via `terraform` CLI
5. Name: `abap-mcp-server-dev`
6. Advanced settings:
   - Terraform Working Directory: `terraform/`
   - Auto-apply: OFF (manual approval recommended)

### Option B: Via Terraform CLI

```bash
terraform login app.terraform.io
cd terraform
terraform init  # Will prompt to migrate state to TFC
```

## Step 4: Configure TFC Variables

In TFC workspace → Variables → Add variables:

### Terraform Variables (from terraform.tfvars)

All variables in `terraform.tfvars` can be auto-loaded, but sensitive ones should be set separately:

**Sensitive Variables (mark as sensitive):**
- `ca_key_pem` = (paste content of `certificates/abap-mcp-ca-key.pem`)
  - **IMPORTANT**: This is the private key, mark as SENSITIVE in TFC
  - Copy content with: `cat terraform/certificates/abap-mcp-ca-key.pem`

**Optional Variables (if you want to override terraform.tfvars):**
- `region` = `us-west-2`
- `environment` = `dev`
- `project_name` = `abap-mcp-server`
- `profile` = `CloudAdminNonProdAccess-064160142714`
- `route53_profile` = `CloudAdminNonProdAccess-514712703977`
- ... (all others from terraform.tfvars)

### Environment Variables (AWS Authentication)

Choose one authentication method:

#### Method 1: IAM User Credentials (simpler, less secure)

- `AWS_ACCESS_KEY_ID` = (your access key) - **Sensitive**
- `AWS_SECRET_ACCESS_KEY` = (your secret key) - **Sensitive**
- `AWS_DEFAULT_REGION` = `us-west-2`

#### Method 2: OIDC with IAM Role (recommended, more secure)

1. Create IAM Identity Provider in AWS for TFC
2. Create IAM Role with trust policy for TFC
3. In TFC workspace:
   - `TFC_AWS_PROVIDER_AUTH` = `true` (Environment variable)
   - `TFC_AWS_RUN_ROLE_ARN` = `arn:aws:iam::064160142714:role/TerraformCloudRole` (Environment variable)

See: https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration

## Step 5: Upload CA Private Key to TFC

### Option A: Via TFC UI (Recommended)

1. Go to workspace → Variables
2. Click "Add variable"
3. Category: **Terraform variable**
4. Key: `ca_key_pem`
5. Value: (paste content of `terraform/certificates/abap-mcp-ca-key.pem`)
6. ✅ Check "Sensitive"
7. Click "Add variable"

### Option B: Via Terraform CLI

```bash
# Read private key content
CA_KEY=$(cat terraform/certificates/abap-mcp-ca-key.pem)

# Set as TFC variable (requires TFC CLI or API)
# This is more complex, recommend using UI
```

## Step 6: Commit Changes to Git

```bash
cd /Users/AVRG/Dev/abap-mcp-server-terraform

# Check what will be committed
git status

# You should see:
# - terraform/certificates/abap-mcp-ca-cert.pem (public cert - safe to commit)
# - terraform/certificates/.gitignore (protects private key)
# - terraform/certificates/README.md
# - terraform/modules/certificates/ (new module)
# - terraform/main.tf (modified)
# - terraform/variables.tf (modified)
# - terraform/terraform.tfvars (modified)
#
# You should NOT see:
# - terraform/certificates/abap-mcp-ca-key.pem (protected by .gitignore)

# Commit changes
git add terraform/
git commit -m "feat: migrate certificate management to TFC-compatible module

- Add certificates module using PGE secretsmanager module
- Move certificates to terraform/certificates/ for TFC access
- Protect private key with .gitignore
- Update main.tf to use certificates module
- Remove hardcoded secret ARN
- Add TFC deployment guide"

git push origin dev
```

## Step 7: Run Terraform Plan in TFC

### Option A: Via TFC UI

1. Go to workspace → Runs
2. Click "Queue plan manually"
3. Optional: Add message describing the run
4. Click "Queue plan"
5. Wait for plan to complete
6. Review changes (should create CA certificate secret)

### Option B: Via Terraform CLI

```bash
cd terraform
terraform init  # Migrate state to TFC
terraform plan  # Runs in TFC
terraform apply # After reviewing plan
```

## Step 8: Verify Deployment

### Check Secret in AWS

```bash
aws secretsmanager get-secret-value \
  --secret-id abap-mcp-server/ca-certificate \
  --region us-west-2 \
  --query 'SecretString' \
  --output text | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
print(f'✅ CA Cert: {len(data[\"ca_cert\"])} bytes')
print(f'✅ CA Key:  {len(data[\"ca_key\"])} bytes')
"
```

### Check ECS Service

```bash
aws ecs describe-services \
  --cluster abap-mcp-server-dev-cluster \
  --services abap-mcp-server-dev-service \
  --region us-west-2 \
  --query 'services[0].{status:status,running:runningCount,desired:desiredCount}'
```

### Test Endpoint

```bash
curl https://abap-mcp-server.nonprod.pge.com/health
```

## Updating Certificates (Renewal or KeyFactor Migration)

### Step 1: Generate New Certificates

**For Self-Signed (Renewal):**
```bash
cd certificates/
openssl genrsa -out abap-mcp-ca-key.pem 4096
openssl req -new -x509 -days 3650 \
  -key abap-mcp-ca-key.pem \
  -out abap-mcp-ca-cert.pem \
  -subj "/C=US/ST=California/L=San Francisco/O=Pacific Gas and Electric Company/OU=ABAP MCP Server/CN=ABAP MCP CA"
```

**For KeyFactor (PGE CA):**
```bash
# See CLAUDE.md section "Certificate Strategy for Principal Propagation"
# Generate CSR, upload to KeyFactor, download signed certificate
```

### Step 2: Update Files

```bash
# Copy new certificates to terraform directory
cp certificates/abap-mcp-ca-cert.pem terraform/certificates/
cp certificates/abap-mcp-ca-key.pem terraform/certificates/
```

### Step 3: Update TFC Variable

1. Go to TFC workspace → Variables
2. Find variable: `ca_key_pem`
3. Click "Edit"
4. Paste new private key content
5. Click "Save variable"

### Step 4: Commit and Deploy

```bash
git add terraform/certificates/abap-mcp-ca-cert.pem
git commit -m "chore: renew CA certificate"
git push origin dev

# TFC will automatically trigger a plan (if VCS-driven)
# Or manually: terraform apply
```

### Step 5: Send to BASIS Team

```bash
# Email new certificate to SAP BASIS team
# They need to import to STRUST again
mail -s "ABAP MCP CA Certificate Renewal" basis-team@pge.com < terraform/certificates/abap-mcp-ca-cert.pem
```

## Troubleshooting

### Issue: "ca_key_pem variable not set"

**Solution:** Set the TFC variable:
1. Go to TFC workspace → Variables
2. Add `ca_key_pem` (Terraform variable, Sensitive)
3. Paste content of `terraform/certificates/abap-mcp-ca-key.pem`

### Issue: "File not found: abap-mcp-ca-cert.pem"

**Solution:** Ensure file exists in repo:
```bash
ls -la terraform/certificates/
# Should show abap-mcp-ca-cert.pem
```

### Issue: "Secret already exists"

**Solution:** Terraform will update the existing secret. If you need to start fresh:
```bash
aws secretsmanager delete-secret \
  --secret-id abap-mcp-server/ca-certificate \
  --force-delete-without-recovery \
  --region us-west-2
```

Then run `terraform apply` again.

### Issue: "Access denied to secretsmanager"

**Solution:** Verify IAM permissions in TFC workspace:
- IAM user/role needs `secretsmanager:CreateSecret`, `secretsmanager:PutSecretValue`, etc.
- Check ECS task role has `secretsmanager:GetSecretValue`

## Rollback Plan

If TFC deployment fails:

### Option 1: Local Deployment (Temporary)

```bash
cd terraform
# Remove TFC backend temporarily
mv backend.tf backend.tf.backup

terraform init -migrate-state  # Migrate state back to local
terraform apply

# Restore TFC backend
mv backend.tf.backup backend.tf
```

### Option 2: Use Previous State

In TFC UI:
1. Go to workspace → States
2. Find previous working state
3. Click "..." → Restore

## Security Notes

- ✅ Public certificate (`abap-mcp-ca-cert.pem`) is committed to repo (safe)
- ✅ Private key (`abap-mcp-ca-key.pem`) is protected by .gitignore
- ✅ Private key in TFC is marked as sensitive (encrypted at rest)
- ✅ Private key in AWS Secrets Manager is encrypted
- ✅ Never commit private key to version control
- ✅ Use IAM roles with least privilege for TFC

## References

- **Terraform Cloud Docs**: https://developer.hashicorp.com/terraform/cloud-docs
- **PGE Terraform Modules**: https://github.com/pgetech/pge-terraform-modules
- **AWS Secrets Manager**: https://docs.aws.amazon.com/secretsmanager/
- **CERTIFICATES.md**: Complete certificate management documentation
- **CLAUDE.md**: Project overview and architectural decisions
