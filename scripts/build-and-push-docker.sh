#!/bin/bash

# Build and Push Docker Image to ECR
# For TFC Deployments: This script ONLY handles Docker build/push
# Terraform deployment is handled by TFC automatically

set -e  # Exit on error

# Configuration
AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_ACCOUNT="${AWS_ACCOUNT:-064160142714}"
AWS_PROFILE="${AWS_PROFILE:-CloudAdminNonProdAccess-064160142714}"
ECR_REPOSITORY="${ECR_REPOSITORY:-abap-mcp-server}"
IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d%H%M%S)}"

ECR_REGISTRY="${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"
FULL_IMAGE_NAME="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

echo "=========================================="
echo "🐳 Docker Build & Push to ECR"
echo "=========================================="
echo "AWS Account:  ${AWS_ACCOUNT}"
echo "AWS Region:   ${AWS_REGION}"
echo "AWS Profile:  ${AWS_PROFILE}"
echo "ECR Registry: ${ECR_REGISTRY}"
echo "Repository:   ${ECR_REPOSITORY}"
echo "Image Tag:    ${IMAGE_TAG}"
echo "Full Image:   ${FULL_IMAGE_NAME}"
echo "=========================================="

# Step 1: Create ECR repository if it doesn't exist
echo ""
echo "Step 1/4: Checking ECR repository..."
if ! aws ecr describe-repositories \
    --repository-names ${ECR_REPOSITORY} \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE} &>/dev/null; then

    echo "Creating ECR repository: ${ECR_REPOSITORY}"
    aws ecr create-repository \
        --repository-name ${ECR_REPOSITORY} \
        --region ${AWS_REGION} \
        --profile ${AWS_PROFILE} \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256

    echo "✅ ECR repository created"
else
    echo "✅ ECR repository already exists"
fi

# Step 2: Build Docker image
echo ""
echo "Step 2/4: Building Docker image..."
echo "Platform: linux/amd64 (ECS Fargate requirement)"

docker buildx build \
    --platform linux/amd64 \
    -f Dockerfile \
    -t ${ECR_REPOSITORY}:${IMAGE_TAG} \
    -t ${ECR_REPOSITORY}:latest \
    -t ${FULL_IMAGE_NAME} \
    .

echo "✅ Docker image built successfully"

# Step 3: Authenticate to ECR
echo ""
echo "Step 3/4: Authenticating to ECR..."

aws ecr get-login-password \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE} | \
    docker login \
    --username AWS \
    --password-stdin ${ECR_REGISTRY}

echo "✅ Authenticated to ECR"

# Step 4: Push image to ECR
echo ""
echo "Step 4/4: Pushing image to ECR..."

docker push ${FULL_IMAGE_NAME}

echo "✅ Image pushed to ECR: ${FULL_IMAGE_NAME}"

# Summary
echo ""
echo "=========================================="
echo "✅ Docker Build & Push Complete"
echo "=========================================="
echo ""
echo "📋 Image Details:"
echo "  Repository: ${ECR_REPOSITORY}"
echo "  Tag:        ${IMAGE_TAG}"
echo "  Full URI:   ${FULL_IMAGE_NAME}"
echo ""
echo "📝 Next Steps for TFC:"
echo ""
echo "  1. Update terraform/terraform.tfvars:"
echo "     container_image = \"${FULL_IMAGE_NAME}\""
echo "     image_tag = \"${IMAGE_TAG}\""
echo ""
echo "  2. Commit and push to trigger TFC deployment:"
echo "     cd terraform"
echo "     sed -i '' 's|container_image = \".*\"|container_image = \"${FULL_IMAGE_NAME}\"|g' terraform.tfvars"
echo "     sed -i '' 's|image_tag = \".*\"|image_tag = \"${IMAGE_TAG}\"|g' terraform.tfvars"
echo "     git add terraform.tfvars"
echo "     git commit -m \"chore: update container image to ${IMAGE_TAG}\""
echo "     git push origin dev"
echo ""
echo "  3. TFC will automatically deploy the new image"
echo ""
