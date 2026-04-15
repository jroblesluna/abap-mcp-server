# Terraform Infrastructure for ABAP Accelerator MCP Server

This directory contains Terraform configuration for deploying the ABAP Accelerator MCP Server to AWS ECS Fargate.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Modules](#modules)
- [Deployment](#deployment)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

## 🎯 Overview

This Terraform configuration deploys a production-ready ABAP MCP Server with:

- **ECS Fargate** - Serverless container orchestration
- **Internal ALB** - HTTPS load balancing (VPC-only access)
- **Route53** - Private hosted zone DNS
- **CloudWatch** - Centralized logging and monitoring
- **Secrets Manager** - Secure credential storage
- **IAM** - Least-privilege access control
- **Security Groups** - Network isolation

### Infrastructure Diagram

```
┌──────────────────────────────────────────────────────────┐
│                     AWS Account                          │
│                                                           │
│  ┌────────────────────────────────────────────────────┐  │
│  │           VPC (vpc-0f991a507e8e58aa1)             │  │
│  │                                                    │  │
│  │  ┌──────────────────────────────────────────┐    │  │
│  │  │       Private Subnets (3 AZs)            │    │  │
│  │  │                                          │    │  │
│  │  │  ┌──────────────────────────────────┐   │    │  │
│  │  │  │   Internal ALB                   │   │    │  │
│  │  │  │   (HTTPS/443, HTTP/80→443)      │   │    │  │
│  │  │  └──────────┬───────────────────────┘   │    │  │
│  │  │             │                            │    │  │
│  │  │  ┌──────────▼───────────────────────┐   │    │  │
│  │  │  │   ECS Fargate Service            │   │    │  │
│  │  │  │   - Cluster: abap-mcp-server-*  │   │    │  │
│  │  │  │   - Task: enterprise_main.py     │   │    │  │
│  │  │  │   - Count: 1 (configurable)      │   │    │  │
│  │  │  └──────────┬───────────────────────┘   │    │  │
│  │  │             │                            │    │  │
│  │  └─────────────┼────────────────────────────┘    │  │
│  │                │                                  │  │
│  └────────────────┼──────────────────────────────────┘  │
│                   │                                      │
│  ┌────────────────┼──────────────────────────────────┐  │
│  │  AWS Services  │                                  │  │
│  │                │                                  │  │
│  │  ┌─────────────▼──────────┐  ┌──────────────┐   │  │
│  │  │ Secrets Manager        │  │  ECR         │   │  │
│  │  │ - SAP Credentials      │  │  - Images    │   │  │
│  │  │ - CA Certificate       │  └──────────────┘   │  │
│  │  └────────────────────────┘                     │  │
│  │                                                  │  │
│  │  ┌────────────────────────┐  ┌──────────────┐   │  │
│  │  │ CloudWatch Logs        │  │  Route53     │   │  │
│  │  │ - /ecs/abap-acc...-dev │  │  - Private   │   │  │
│  │  └────────────────────────┘  └──────────────┘   │  │
│  └──────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

## 🔑 Prerequisites

### Required Tools

- **AWS CLI** - Version 2.x
- **Terraform** - Version 1.0 or higher
- **Docker** - For building images (handled by deploy.sh)
- **jq** - For JSON processing (optional but recommended)

### AWS Permissions

Your AWS profile must have permissions for:

- ECS (clusters, services, task definitions)
- ECR (repositories, images)
- EC2 (VPC, subnets, security groups, load balancers)
- Route53 (hosted zones, records)
- ACM (certificates, validation)
- IAM (roles, policies)
- CloudWatch (log groups, metrics)
- Secrets Manager (secrets)
- SSM Parameter Store (parameters)

### AWS Configuration

```bash
# Configure AWS CLI profile
aws configure --profile CloudAdminNonProdAccess-064160142714

# Verify access
aws sts get-caller-identity --profile CloudAdminNonProdAccess-064160142714
```

## ⚡ Quick Start

### 1. Configure Variables

Edit `terraform.tfvars`:

```hcl
# Region and Account
region  = "us-west-2"
profile = "CloudAdminNonProdAccess-064160142714"

# Project Settings
project_name = "abap-mcp-server"
environment  = "dev"

# Network
vpc_id             = "vpc-0f991a507e8e58aa1"
private_subnet_ids = [
  "subnet-009076f40b21b0adf",
  "subnet-075d0438fa8ebac6a",
  "subnet-0a22706e08d2a983f"
]

# SAP Systems Configuration
sap_systems_yaml = <<-EOT
systems:
  DV8:
    host: sapdv8db1.comp.pge.com
    port: 1443
    client: 120
    # ... other settings
EOT

# Tags
tags = {
  Project = "ABAP-Accelerator"
  AppID   = "APP-3601"
  Order   = "70053108"
  # ... other tags
}
```

### 2. Initialize Terraform

```bash
cd terraform
terraform init
```

### 3. Plan Deployment

```bash
terraform plan -out=tfplan
```

Review the plan output carefully.

### 4. Deploy

```bash
terraform apply tfplan
```

Or use the automated deployment script from project root:

```bash
cd ..
./scripts/build-and-push-docker.sh
```

## ⚙️ Configuration

### terraform.tfvars

Main configuration file with all deployment parameters.

#### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `region` | AWS region | `us-west-2` |
| `profile` | AWS CLI profile | `CloudAdminNonProdAccess-064160142714` |
| `project_name` | Project name prefix | `abap-mcp-server` |
| `environment` | Environment name | `dev` |
| `vpc_id` | VPC ID | `vpc-0f991a507e8e58aa1` |
| `private_subnet_ids` | Private subnet IDs | `["subnet-...", ...]` |
| `container_image` | ECR image URI | `<account>.dkr.ecr.<region>.amazonaws.com/abap-mcp-server:tag` |

#### SAP Configuration

```hcl
# Single System (Legacy)
sap_host            = "sap.company.com:44300"
sap_client          = "100"
sap_instance_number = "00"

# Multi-System (Recommended)
sap_systems_yaml = <<-EOT
systems:
  SYSTEM_ID:
    host: hostname
    port: 44300
    client: 100
    instance_number: "00"
    language: EN
    secure: true
    ssl_verify: true
    description: System Description
EOT
```

#### Authentication Configuration

```hcl
# Credential provider
credential_provider = "aws_secrets"  # Options: env, keychain, aws_secrets

# Enterprise features
enable_enterprise_mode = true
enable_principal_propagation = false  # Set true for certificate auth

# Principal Propagation (if enabled)
# Store CA certificate in Secrets Manager:
# aws secretsmanager create-secret \
#   --name mcp/abap-mcp-server/ca-certificate \
#   --secret-string '{"ca_cert":"...","ca_key":"..."}'
```

#### Container Configuration

```hcl
container_cpu    = 512    # 0.5 vCPU
container_memory = 1024   # 1 GB
desired_count    = 1      # Number of tasks
```

#### Networking

```hcl
# Route53
route53_hosted_zone_name = "nonprod.pge.com"
application_hostname     = "abap-mcp"
use_private_zone        = true

# Resulting FQDN: abap-mcp-server.nonprod.pge.com

# CIDR blocks (ALB is internal, so this is additional layer)
allowed_cidr_blocks = ["0.0.0.0/0"]
```

#### Logging

```hcl
log_level                   = "INFO"
log_retention_days          = 30
enable_container_insights   = true
enable_http_request_logging = "false"
```

### variables.tf

Defines all input variables with descriptions, types, and default values.

### outputs.tf

Defines output values for:
- ALB DNS name and URL
- ECS cluster and service names
- Route53 DNS records
- Monitoring commands
- Deployment summary

## 📦 Modules

### modules/alb/

Application Load Balancer configuration.

**Resources:**
- `aws_lb` - Internal ALB in private subnets
- `aws_lb_target_group` - Target group for ECS tasks
- `aws_lb_listener` (HTTP) - Redirects to HTTPS
- `aws_lb_listener` (HTTPS) - HTTPS listener with ACM certificate

**Outputs:**
- `alb_dns_name` - ALB DNS name
- `target_group_arn` - Target group ARN
- `listener_http_arn`, `listener_https_arn` - Listener ARNs

### modules/ecs/

ECS Fargate cluster, service, and task definition.

**Resources:**
- `aws_ecs_cluster` - ECS cluster
- `aws_ecs_task_definition` - Fargate task definition
- `aws_ecs_service` - ECS service with load balancer integration
- `aws_appautoscaling_target` - Auto-scaling target
- `aws_appautoscaling_policy` - CPU and memory-based scaling policies

**Key Features:**
- Rolling deployments (200% max, 100% min healthy)
- Circuit breaker with rollback
- Health checks (60s grace period)
- Container Insights enabled
- Environment variables and secrets injection

### modules/iam/

IAM roles and policies for ECS tasks.

**Resources:**
- Task Execution Role (ECR pull, CloudWatch Logs, Secrets Manager)
- Task Role (application runtime permissions)
- Inline policies for Secrets Manager, Parameter Store, CloudWatch

**Key Permissions:**
- Read secrets: `mcp/abap-mcp-server/*`
- Read parameters: `/${project_name}/${environment}/*`
- Write CloudWatch Logs
- Pull ECR images

### modules/security_groups/

Security groups for ALB and ECS tasks.

**Resources:**
- ALB security group (ingress 80/443, egress all)
- ECS security group (ingress from ALB on 8000, egress all)

**Rules:**
- ALB accepts HTTP/HTTPS from allowed CIDR blocks
- ECS tasks only accept traffic from ALB
- Both allow all egress (NAT gateway handles internet access)

### modules/secrets/

Secrets Manager secrets for sensitive data.

**Resources:**
- CA certificate secret (for Principal Propagation)
- OAuth secret (if OAuth enabled)

**Note:** SAP credentials are created externally using `create-secrets.sh`

### modules/parameters/

SSM Parameter Store for configuration.

**Resources:**
- SAP endpoints parameter (JSON)
- User exceptions parameter (JSON)

**Usage:** Loaded by application at runtime for dynamic configuration.

## 🚀 Deployment

### Automated Deployment (Recommended)

From project root:

```bash
./scripts/build-and-push-docker.sh
```

This script handles:
1. ECR repository creation
2. Docker image build (linux/amd64)
3. Image push to ECR
4. Terraform variable updates
5. Terraform plan and apply

### Manual Deployment

```bash
# 1. Build and push Docker image
IMAGE_TAG=$(date +%Y%m%d%H%M%S)
docker build --platform linux/amd64 -t abap-mcp-server:${IMAGE_TAG} .

aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin \
  <account>.dkr.ecr.us-west-2.amazonaws.com

docker tag abap-mcp-server:${IMAGE_TAG} \
  <account>.dkr.ecr.us-west-2.amazonaws.com/abap-mcp-server:${IMAGE_TAG}

docker push <account>.dkr.ecr.us-west-2.amazonaws.com/abap-mcp-server:${IMAGE_TAG}

# 2. Update terraform.tfvars
# Edit container_image variable

# 3. Deploy infrastructure
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Update Deployment

To update the running service:

```bash
# Update code, rebuild image
./scripts/build-and-push-docker.sh

# Or just update configuration
cd terraform
# Edit terraform.tfvars
terraform apply
```

### Rollback

```bash
# Option 1: Update image tag in terraform.tfvars
cd terraform
# Edit container_image to previous tag
terraform apply

# Option 2: Redeploy specific image
IMAGE_TAG=20260324120000 ./scripts/build-and-push-docker.sh
```

### Teardown

**For TFC Deployments:**
1. Go to TFC UI → Workspace → Settings → Destruction and Deletion
2. Queue destroy plan
3. Confirm destruction
4. Clean up ECR: `../scripts/cleanup-ecr.sh`

**For Local Terraform:**
```bash
cd terraform
terraform destroy
```

This script will:
1. Destroy all Terraform resources
2. Delete all ECR images
3. Delete ECR repository

**Warning:** This is destructive and requires confirmation.

## 📊 Monitoring

### CloudWatch Logs

```bash
# Tail logs
aws logs tail /ecs/abap-mcp-server-dev --follow --region us-west-2

# Filter logs
aws logs tail /ecs/abap-mcp-server-dev \
  --since 1h \
  --filter-pattern "ERROR" \
  --region us-west-2

# CloudWatch Insights query
aws logs start-query \
  --log-group-name /ecs/abap-mcp-server-dev \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc'
```

### ECS Service Status

```bash
# Describe service
aws ecs describe-services \
  --cluster abap-mcp-server-dev-cluster \
  --services abap-mcp-server-dev-service \
  --region us-west-2

# Task details
aws ecs list-tasks \
  --cluster abap-mcp-server-dev-cluster \
  --service-name abap-mcp-server-dev-service \
  --region us-west-2

# Get task ARN and describe
TASK_ARN=$(aws ecs list-tasks --cluster abap-mcp-server-dev-cluster --service-name abap-mcp-server-dev-service --region us-west-2 --query 'taskArns[0]' --output text)

aws ecs describe-tasks \
  --cluster abap-mcp-server-dev-cluster \
  --tasks $TASK_ARN \
  --region us-west-2
```

### ALB Target Health

```bash
# Get target group ARN from Terraform output
cd terraform
TARGET_GROUP_ARN=$(terraform output -raw target_group_arn)

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN \
  --region us-west-2
```

### Metrics

```bash
# CPU utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=abap-mcp-server-dev-cluster \
              Name=ServiceName,Value=abap-mcp-server-dev-service \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region us-west-2

# Memory utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ClusterName,Value=abap-mcp-server-dev-cluster \
              Name=ServiceName,Value=abap-mcp-server-dev-service \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region us-west-2
```

### Health Checks

```bash
# Application health
curl https://abap-mcp-server.nonprod.pge.com/health

# MCP endpoint
curl -X POST https://abap-mcp-server.nonprod.pge.com/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "x-sap-system-id: DV8" \
  -H "x-session-id: test-123" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

## 🔧 Troubleshooting

### Issue: Terraform state lock error

**Solution:**
```bash
# If state is actually not locked (e.g., previous operation crashed)
terraform force-unlock <lock-id>
```

### Issue: Service deployment fails

**Check:**
```bash
# Service events
aws ecs describe-services \
  --cluster abap-mcp-server-dev-cluster \
  --services abap-mcp-server-dev-service \
  --region us-west-2 \
  --query 'services[0].events[:10]'

# Task stopped reason
aws ecs describe-tasks \
  --cluster abap-mcp-server-dev-cluster \
  --tasks <task-arn> \
  --region us-west-2 \
  --query 'tasks[0].stoppedReason'
```

### Issue: Container keeps restarting

**Check logs:**
```bash
aws logs tail /ecs/abap-mcp-server-dev --since 10m --region us-west-2
```

**Common causes:**
- Missing environment variables
- Invalid SAP credentials
- Wrong Docker image entry point
- Health check failures

### Issue: Cannot reach ALB

**Verify:**
1. ALB is internal - requires VPN or Transit Gateway
2. Security group allows traffic
3. Target group has healthy targets

```bash
# Check ALB
aws elbv2 describe-load-balancers \
  --names abap-mcp-server-dev-alb \
  --region us-west-2

# Check targets
aws elbv2 describe-target-health \
  --target-group-arn <arn> \
  --region us-west-2
```

### Issue: Secrets not found

**Verify secrets exist:**
```bash
# List secrets
aws secretsmanager list-secrets \
  --filters Key=name,Values=mcp/abap-mcp-server \
  --region us-west-2

# Get secret value (check IAM permissions)
aws secretsmanager get-secret-value \
  --secret-id mcp/abap-mcp-server/DV8 \
  --region us-west-2
```

### Issue: Task IAM role permissions denied

**Check:**
- Task role has correct inline policies
- Secret ARNs match in IAM policy
- Parameter Store paths match

```bash
# Get task role
cd terraform
TASK_ROLE=$(terraform output -raw task_role_arn)

# Check role policies
aws iam list-role-policies \
  --role-name $(echo $TASK_ROLE | cut -d'/' -f2) \
  --region us-west-2
```

## 📚 Additional Resources

- **[Main README](../README.md)** - Project overview and quick start
- **[CLAUDE.md](../CLAUDE.md)** - Developer guide
- **[Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)** - AWS provider documentation
- **[ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)** - AWS ECS best practices

## 📞 Support

- **Project Team:** avrg@pge.com, m7k3@pge.com, mq28@pge.com
- **Project:** Propel Initiative
- **AppID:** APP-3601
- **Order:** 70053108

---

**Infrastructure as Code with Terraform**

Current Deployment: ECS Fargate | us-west-2 | abap-mcp-server-dev
