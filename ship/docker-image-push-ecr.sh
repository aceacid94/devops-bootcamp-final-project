#!/bin/bash
set -e

# --- Config ---
AWS_ACCOUNT_ID="534883914134"
AWS_REGION="ap-southeast-1"
ECR_REPO="finalproject-abdulhakim"
IMAGE_NAME="finalproject"
IMAGE_TAG="${1:-latest}"   # pass a tag as first argument, defaults to "latest"

ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"

echo "==> Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "==> Building image..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

echo "==> Tagging image..."
docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${ECR_URI}:${IMAGE_TAG}"

echo "==> Pushing image to ECR..."
docker push "${ECR_URI}:${IMAGE_TAG}"

echo "==> Done! Pushed: ${ECR_URI}:${IMAGE_TAG}"