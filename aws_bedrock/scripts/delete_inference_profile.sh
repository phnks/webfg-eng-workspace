#!/bin/bash

# Delete inference profiles using AWS CLI directly
# Usage: ./delete_inference_profile.sh [environment]
# Environment options: dev, qa, prod (default: dev)

set -e

ENV=${1:-dev}

# Validate environment parameter
if [[ ! "$ENV" =~ ^(dev|qa|prod)$ ]]; then
    echo "Error: Invalid environment. Use dev, qa, or prod."
    exit 1
fi

echo "Deleting inference profiles for $ENV environment..."

# Confirm deletion
echo "WARNING: You are about to delete inference profiles for the $ENV environment."
echo "This action cannot be undone."
read -p "Are you sure you want to proceed? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Deletion cancelled."
    exit 0
fi

# Get profile names
MAIN_PROFILE_NAME="coding-agent-inference-profile-${ENV}"
EMBEDDING_PROFILE_NAME="coding-agent-embedding-profile-${ENV}"

# Get profile ARNs
MAIN_PROFILE_ARN=$(aws bedrock list-inference-profiles --query "inferenceProfileSummaries[?inferenceProfileName=='$MAIN_PROFILE_NAME'].inferenceProfileArn" --output text)
EMBEDDING_PROFILE_ARN=$(aws bedrock list-inference-profiles --query "inferenceProfileSummaries[?inferenceProfileName=='$EMBEDDING_PROFILE_NAME'].inferenceProfileArn" --output text)

# Delete main inference profile if it exists
if [ ! -z "$MAIN_PROFILE_ARN" ]; then
    echo "Deleting main inference profile: $MAIN_PROFILE_NAME"
    aws bedrock delete-inference-profile --inference-profile-arn "$MAIN_PROFILE_ARN"
    echo "Main inference profile deleted."
else
    echo "Main inference profile not found."
fi

# Delete embedding profile if it exists
if [ ! -z "$EMBEDDING_PROFILE_ARN" ]; then
    echo "Deleting embedding profile: $EMBEDDING_PROFILE_NAME"
    aws bedrock delete-inference-profile --inference-profile-arn "$EMBEDDING_PROFILE_ARN"
    echo "Embedding profile deleted."
else
    echo "Embedding profile not found."
fi

# Delete SSM parameters
echo "Deleting SSM parameters..."
aws ssm delete-parameter --name "/coding-agent/$ENV/inference-profile-arn" || true
aws ssm delete-parameter --name "/coding-agent/$ENV/embedding-profile-arn" || true

echo "Inference profiles and parameters deleted successfully."