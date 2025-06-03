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
if [ "$ENV" = "dev" ] || [ "$ENV" = "qa" ]; then
    MODEL_ID="anthropic.claude-3-haiku-20240307-v1:0"  # Using Haiku for dev/qa
else
    MODEL_ID="anthropic.claude-3-5-sonnet-20240620-v1:0"  # Using Sonnet for production
fi

# Create main inference profile
MAIN_PROFILE_NAME="coding-agent-inference-profile-${ENV}"
echo "Creating main inference profile: $MAIN_PROFILE_NAME"

aws bedrock create-inference-profile \
    --inference-profile-name "$MAIN_PROFILE_NAME" \
    --model-configuration modelId="$MODEL_ID" \
    --tags Key=Environment,Value=$ENV Key=Project,Value=WebFG-Coding-Agent

# Get the main inference profile ARN
MAIN_PROFILE_ARN=$(aws bedrock list-inference-profiles --query "inferenceProfileSummaries[?inferenceProfileName=='$MAIN_PROFILE_NAME'].inferenceProfileArn" --output text)
echo "Created main inference profile with ARN: $MAIN_PROFILE_ARN"

# Create embedding profile
EMBEDDING_PROFILE_NAME="coding-agent-embedding-profile-${ENV}"
echo "Creating embedding profile: $EMBEDDING_PROFILE_NAME"

aws bedrock create-inference-profile \
    --inference-profile-name "$EMBEDDING_PROFILE_NAME" \
    --model-configuration modelId="amazon.titan-embed-text-v2:0" \
    --tags Key=Environment,Value=$ENV Key=Project,Value=WebFG-Coding-Agent

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