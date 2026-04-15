# Deployment Guide for ABAP Accelerator on AWS ECS Fargate

## Overview

This guide walks you through deploying the ABAP Accelerator MCP Server to AWS ECS Fargate using a **multi-account setup** similar to your existing EKS deployment pattern.

## Multi-Account Architecture

**Account Separation:**
- **Application Account (064...)**: ECS Fargate, ALB, ECR, Secrets Manager, CloudWatch
- **Route53 Account (514...)**: DNS, hosted zones, Route53 records

**Benefits:**
- Centralized DNS management
- Separation of concerns
- Compliance with PGE multi-account strategy

## Prerequisites

✅ AWS CLI configured with **two profiles**:
   - `CloudAdminNonProdAccess-064160142714` (Application)
   - `CloudAdminNonProdAccess-514712703977` (Route53)
✅ Terraform >= 1.0 installed
✅ Docker installed
✅ Route53 Hosted Zone exists: `nonprod.pge.com`
✅ VPC with public and private subnets in application account

## Step-by-Step Deployment

### Step 1: Prepare terraform.tfvars

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
# AWS Accounts
region          = "us-west-2"
profile         = "CloudAdminNonProdAccess-064160142714"  # Application account
route53_profile = "CloudAdminNonProdAccess-514712703977"  # Route53 account

# Domain Configuration
route53_hosted_zone_name = "nonprod.pge.com"
application_hostname     = "abap-mcp"  # Creates: abap-mcp-server.nonprod.pge.com
use_private_zone         = false       # Use public zone for external access

# Network (from application account)
vpc_id = "vpc-xxxxx"
private_subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]
public_subnet_ids  = ["subnet-zzzzz", "subnet-aaaaa"]

# SAP Systems
sap_endpoints_json = <<-EOT
{
  "S4H-100": {
    "host": "sap-dev.pge.com",
    "port": "44300",
    "client": "100",
    "description": "S/4HANA Dev"
  }
}
EOT

# Security
allowed_cidr_blocks = ["10.0.0.0/8"]  # PGE internal network

# ECS
container_cpu    = 512
container_memory = 1024
desired_count    = 2

# Tags (match your existing pattern)
tags = {
  Project            = "ABAP-Accelerator"
  Env                = "dev"
  AppID              = "APP-ABAP-001"
  Order              = "ORD_123456"
  Environment        = "NonProd"
  Compliance         = "None"
  DataClassification = "Internal"
  CRIS               = "Low"
  Notify             = "your-email@pge.com"
}
```

### Step 2: Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Preview changes (verify both accounts will be used)
terraform plan

# Deploy (takes 5-10 minutes)
terraform apply -auto-approve
```

**What gets created:**
- **Application Account (064):**
  - ECR repository
  - ECS Fargate cluster and service (2 tasks)
  - Application Load Balancer
  - ACM SSL certificate
  - Security groups
  - IAM roles
  - CloudWatch log groups
  - Secrets Manager secrets
  - Parameter Store parameters

- **Route53 Account (514):**
  - ACM certificate validation records (public zone)
  - Application A record (public or private zone)

### Step 3: Build and Push Docker Image

```bash
# Get ECR repository URL from Terraform output
ECR_REPO=$(terraform output -raw ecr_repository_url)
echo $ECR_REPO

# Navigate to project root
cd ..

# Login to ECR (using application account profile)
aws ecr get-login-password --region us-west-2 --profile CloudAdminNonProdAccess-064160142714 | \
  docker login --username AWS --password-stdin $ECR_REPO

# Build image
docker build -f Dockerfile.simple -t abap-mcp-server .

# Tag and push
docker tag abap-mcp-server:latest $ECR_REPO:latest
docker push $ECR_REPO:latest
```

### Step 4: Wait for Service to Start

```bash
cd terraform

# Watch service status
watch -n 5 'aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services $(terraform output -raw ecs_service_name) \
  --profile CloudAdminNonProdAccess-064160142714 \
  --query "services[0].{Desired:desiredCount,Running:runningCount,Status:status}"'

# View logs
aws logs tail $(terraform output -raw log_group_name) \
  --follow \
  --profile CloudAdminNonProdAccess-064160142714
```

Wait for `Running: 2` (both tasks healthy)

### Step 5: Populate Secrets (Optional - for Principal Propagation)

If using Principal Propagation (certificate auth):

```bash
# CA Certificate (in application account)
aws secretsmanager put-secret-value \
  --secret-id $(terraform output -raw ca_certificate_secret_name) \
  --secret-string '{"ca_cert":"-----BEGIN CERTIFICATE-----\n...","ca_key":"-----BEGIN PRIVATE KEY-----\n..."}' \
  --profile CloudAdminNonProdAccess-064160142714

# OAuth Secret (in application account)
aws secretsmanager put-secret-value \
  --secret-id $(terraform output -raw oauth_secret_name) \
  --secret-string '{"client_id":"your-oauth-client-id","client_secret":"your-oauth-client-secret"}' \
  --profile CloudAdminNonProdAccess-064160142714
```

### Step 6: Verify Deployment

```bash
# Get MCP endpoint URL
terraform output -raw mcp_endpoint_url

# Test health endpoint
curl https://abap-mcp-server.nonprod.pge.com/health

# Expected output:
# {"status":"healthy","timestamp":"2026-03-20T...","service":"ABAP-Accelerator-Enterprise"}

# Verify DNS resolution
nslookup abap-mcp-server.nonprod.pge.com

# Verify Route53 records (in Route53 account)
aws route53 list-resource-record-sets \
  --hosted-zone-id $(terraform output -raw route53_zone_id_public) \
  --profile CloudAdminNonProdAccess-514712703977 \
  | grep -A 5 "abap-mcp"
```

### Step 7: Provide Configuration to Ravikanth

Get the Q Developer configuration:

```bash
terraform output -json q_developer_config | jq -r
```

Send this to Ravikanth:

```json
{
  "mcpServers": {
    "abap-mcp-server": {
      "url": "https://abap-mcp-server.nonprod.pge.com/mcp",
      "transport": "streamable-http",
      "headers": {
        "x-sap-system-id": "S4H-100",
        "x-sap-username": "RAVIKANTH_USERNAME",
        "x-sap-password": "RAVIKANTH_PASSWORD"
      }
    }
  }
}
```

**Instructions for Ravikanth:**
1. Add this configuration to Amazon Q Developer MCP settings
2. Replace `RAVIKANTH_USERNAME` with his SAP username
3. Replace `RAVIKANTH_PASSWORD` with his SAP password
4. Set `x-sap-system-id` to the SAP system he wants to connect to (e.g., S4H-100)

## Understanding Multi-Account Setup

### How ACM Certificate Validation Works Across Accounts

1. **Certificate Creation** (Application Account 064):
   ```
   ACM Certificate → Domain: abap-mcp-server.nonprod.pge.com
   Validation Method: DNS
   ```

2. **DNS Validation** (Route53 Account 514):
   ```
   Terraform creates validation records in public hosted zone
   _acme-challenge.abap-mcp-server.nonprod.pge.com → CNAME → ...
   ```

3. **DNS Record** (Route53 Account 514):
   ```
   abap-mcp-server.nonprod.pge.com → A (ALIAS) → ALB DNS name
   ```

### Verifying Multi-Account Configuration

```bash
# Check resources in Application Account (064)
aws ecs list-clusters --profile CloudAdminNonProdAccess-064160142714
aws elbv2 describe-load-balancers --profile CloudAdminNonProdAccess-064160142714
aws acm list-certificates --profile CloudAdminNonProdAccess-064160142714

# Check resources in Route53 Account (514)
aws route53 list-hosted-zones --profile CloudAdminNonProdAccess-514712703977
aws route53 list-resource-record-sets \
  --hosted-zone-id $(terraform output -raw route53_zone_id_public) \
  --profile CloudAdminNonProdAccess-514712703977
```

## Monitoring

### View Logs
```bash
aws logs tail /ecs/abap-mcp-server-dev \
  --follow \
  --profile CloudAdminNonProdAccess-064160142714
```

### Check Service Health
```bash
aws ecs describe-services \
  --cluster abap-mcp-server-dev-cluster \
  --services abap-mcp-server-dev-service \
  --profile CloudAdminNonProdAccess-064160142714
```

### Check ALB Target Health
```bash
TG_ARN=$(terraform output -raw module.alb.target_group_arn)
aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --profile CloudAdminNonProdAccess-064160142714
```

## Updating the Application

When code changes:

```bash
# Build new image
docker build -f Dockerfile.simple -t abap-mcp-server .

# Tag with version
docker tag abap-mcp-server:latest $ECR_REPO:v1.0.1
docker push $ECR_REPO:v1.0.1

# Update task definition in Terraform
# Edit terraform.tfvars:
# container_image = "<ecr-repo-url>:v1.0.1"

# Apply changes
terraform apply
```

ECS will perform rolling update (zero downtime).

## Troubleshooting

### Issue: Certificate validation stuck

```bash
# Check DNS records in Route53 account
aws route53 list-resource-record-sets \
  --hosted-zone-id $(terraform output -raw route53_zone_id_public) \
  --profile CloudAdminNonProdAccess-514712703977 \
  | grep -A 5 "_acme-challenge"

# Wait up to 30 minutes for DNS propagation
# Verify from external DNS:
dig _acme-challenge.abap-mcp-server.nonprod.pge.com
```

### Issue: Can't access via custom domain

```bash
# Verify A record exists
dig abap-mcp-server.nonprod.pge.com

# Check if using private zone
# If use_private_zone=true, domain only resolves inside VPC
# Test from EC2 instance inside VPC
```

### Issue: Cross-account permission errors

```bash
# Verify AWS profiles are configured correctly
aws sts get-caller-identity --profile CloudAdminNonProdAccess-064160142714
aws sts get-caller-identity --profile CloudAdminNonProdAccess-514712703977

# Ensure both profiles have necessary permissions
```

## Cleanup

To remove all resources:

```bash
terraform destroy -auto-approve
```

**Note:** This removes resources from both accounts. ECR images and CloudWatch logs are retained. Delete manually if needed.

## Cost Estimate

**Monthly cost for dev environment:**
- ECS Fargate (2 tasks × 0.5 vCPU, 1 GB): ~$70
- Application Load Balancer: ~$20
- CloudWatch Logs (30 days, 10 GB): ~$5
- Secrets Manager (2 secrets): ~$1
- Route53 (hosted zone): $0 (already exists)
- **Total: ~$96/month**

## Next Steps

✅ Deploy infrastructure to both accounts
✅ Build and push Docker image
✅ Verify health endpoint
✅ Provide URL to Ravikanth: `https://abap-mcp-server.nonprod.pge.com/mcp`
⬜ Register with Portkey (optional)
⬜ Monitor usage and performance
⬜ Configure auto-scaling if needed
