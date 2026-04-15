#!/bin/bash

# Cleanup ECR Repository
# This script deletes all images and optionally the repository itself
# Use this after destroying infrastructure via TFC

set -e  # Exit on error

# Configuration
AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_ACCOUNT="${AWS_ACCOUNT:-064160142714}"
AWS_PROFILE="${AWS_PROFILE:-CloudAdminNonProdAccess-064160142714}"
ECR_REPOSITORY="${ECR_REPOSITORY:-abap-mcp-server}"

echo "=========================================="
echo "🧹 ECR Cleanup"
echo "=========================================="
echo "AWS Account:  ${AWS_ACCOUNT}"
echo "AWS Region:   ${AWS_REGION}"
echo "AWS Profile:  ${AWS_PROFILE}"
echo "Repository:   ${ECR_REPOSITORY}"
echo "=========================================="
echo ""

# Check if repository exists
if ! aws ecr describe-repositories \
    --repository-names ${ECR_REPOSITORY} \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE} &>/dev/null; then

    echo "❌ Repository ${ECR_REPOSITORY} does not exist"
    exit 0
fi

echo "⚠️  WARNING: This will delete ALL images in ${ECR_REPOSITORY}"
echo ""
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted"
    exit 0
fi

# Get all image IDs
echo ""
echo "Fetching image list..."
IMAGE_IDS=$(aws ecr list-images \
    --repository-name ${ECR_REPOSITORY} \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE} \
    --query 'imageIds[*]' \
    --output json)

IMAGE_COUNT=$(echo ${IMAGE_IDS} | jq '. | length')

if [ "$IMAGE_COUNT" -eq "0" ]; then
    echo "No images to delete"
else
    echo "Found ${IMAGE_COUNT} images"
    echo "Deleting images..."

    aws ecr batch-delete-image \
        --repository-name ${ECR_REPOSITORY} \
        --region ${AWS_REGION} \
        --profile ${AWS_PROFILE} \
        --image-ids "${IMAGE_IDS}"

    echo "✅ Deleted ${IMAGE_COUNT} images"
fi

echo ""
read -p "Delete the repository itself? (yes/no): " DELETE_REPO

if [ "$DELETE_REPO" = "yes" ]; then
    echo "Deleting repository..."
    aws ecr delete-repository \
        --repository-name ${ECR_REPOSITORY} \
        --region ${AWS_REGION} \
        --profile ${AWS_PROFILE} \
        --force

    echo "✅ Repository deleted"
else
    echo "Repository kept (images deleted)"
fi

echo ""
echo "=========================================="
echo "✅ Cleanup Complete"
echo "=========================================="
