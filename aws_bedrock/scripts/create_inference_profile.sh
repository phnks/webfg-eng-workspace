#!/bin/bash

# Create inference profiles using AWS CLI directly
# Usage: ./create_inference_profile.sh [environment]
# Environment options: dev, qa, prod (default: dev)

set -e

ENV=${1:-dev}

# Validate environment parameter
if [[ ! "$ENV" =~ ^(dev|qa|prod)$ ]]; then
    echo "Error: Invalid environment. Use dev, qa, or prod."
    exit 1
fi

echo "Creating inference profiles for $ENV environment..."

# Set model ID based on environment
MODEL_ID="anthropic.claude-opus-4-20250514-v1:0"  # Using Claude Opus 4 for all environments

# Create main inference profile
MAIN_PROFILE_NAME="coding-agent-inference-profile-${ENV}"
echo "Creating main inference profile: $MAIN_PROFILE_NAME"

aws bedrock create-inference-profile \
    --inference-profile-name "$MAIN_PROFILE_NAME" \
    --model-source copyFrom="$MODEL_ID" \
    --tags "[{\"key\":\"Environment\",\"value\":\"$ENV\"},{\"key\":\"Project\",\"value\":\"WebFG-Coding-Agent\"}]"

# Get the main inference profile ARN
MAIN_PROFILE_ARN=$(aws bedrock list-inference-profiles --query "inferenceProfileSummaries[?inferenceProfileName=='$MAIN_PROFILE_NAME'].inferenceProfileArn" --output text)
echo "Created main inference profile with ARN: $MAIN_PROFILE_ARN"

# Create embedding profile
EMBEDDING_PROFILE_NAME="coding-agent-embedding-profile-${ENV}"
echo "Creating embedding profile: $EMBEDDING_PROFILE_NAME"

aws bedrock create-inference-profile \
    --inference-profile-name "$EMBEDDING_PROFILE_NAME" \
    --model-source copyFrom="amazon.titan-embed-text-v2:0" \
    --tags "[{\"key\":\"Environment\",\"value\":\"$ENV\"},{\"key\":\"Project\",\"value\":\"WebFG-Coding-Agent\"}]"

# Get the embedding profile ARN
EMBEDDING_PROFILE_ARN=$(aws bedrock list-inference-profiles --query "inferenceProfileSummaries[?inferenceProfileName=='$EMBEDDING_PROFILE_NAME'].inferenceProfileArn" --output text)
echo "Created embedding profile with ARN: $EMBEDDING_PROFILE_ARN"

# Store profile ARNs in SSM for reference by other resources
aws ssm put-parameter \
    --name "/coding-agent/$ENV/inference-profile-arn" \
    --type "String" \
    --value "$MAIN_PROFILE_ARN" \
    --overwrite

aws ssm put-parameter \
    --name "/coding-agent/$ENV/embedding-profile-arn" \
    --type "String" \
    --value "$EMBEDDING_PROFILE_ARN" \
    --overwrite

echo "Inference profiles created and ARNs stored in SSM parameters."