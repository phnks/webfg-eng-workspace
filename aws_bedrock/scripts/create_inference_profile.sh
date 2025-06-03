#!/bin/bash

# Create inference profiles using AWS CLI directly
# Usage: ./create_inference_profile.sh [environment] [--dry-run]
# Environment options: dev, qa, prod (default: dev)
# --dry-run: Validate parameters without creating resources

set -e

ENV=${1:-dev}
DRY_RUN=${2:-""}

# Check if --dry-run flag is set
if [[ "$DRY_RUN" == "--dry-run" ]]; then
    echo "Running in dry-run mode. Will validate but not create resources."
    DRY_RUN_FLAG="--dry-run"
else
    DRY_RUN_FLAG=""
fi

# Validate environment parameter
if [[ ! "$ENV" =~ ^(dev|qa|prod|test)$ ]]; then
    echo "Error: Invalid environment. Use dev, qa, prod, or test."
    exit 1
fi

echo "Creating inference profiles for $ENV environment..."

# Set model ARN based on environment
# Using the direct Claude Opus 4 foundation model ARN
# Note: Claude Opus 4 only supports INFERENCE_PROFILE type, not ON_DEMAND
MODEL_ARN="arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-opus-4-20250514-v1:0"  # Using Claude Opus 4 model ARN
# For embedding model, we need one that supports ON_DEMAND type
EMBEDDING_MODEL_ARN="arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-embed-text-v2:0"  # Using Titan Embed Text for embeddings (supports ON_DEMAND)

# Note: Claude Opus 4 only supports INFERENCE_PROFILE and not ON_DEMAND

# Create a custom inference profile for Claude Opus 4
MAIN_PROFILE_NAME="coding-agent-inference-profile-${ENV}"
echo "Creating custom inference profile: $MAIN_PROFILE_NAME"

# Create inference profile for Claude Opus 4
aws bedrock create-inference-profile \
    --inference-profile-name "$MAIN_PROFILE_NAME" \
    --model-source copyFrom="$MODEL_ARN" \
    --tags "[{\"key\":\"Environment\",\"value\":\"$ENV\"},{\"key\":\"Project\",\"value\":\"WebFG-Coding-Agent\"}]" \
    $DRY_RUN_FLAG

# Get the main inference profile ARN if not in dry-run mode
if [[ "$DRY_RUN" != "--dry-run" ]]; then
    MAIN_PROFILE_ARN=$(aws bedrock list-inference-profiles --query "inferenceProfileSummaries[?inferenceProfileName=='$MAIN_PROFILE_NAME'].inferenceProfileArn" --output text)
    echo "Created main inference profile with ARN: $MAIN_PROFILE_ARN"
else
    echo "[Dry run] Would create main inference profile: $MAIN_PROFILE_NAME"
    # Use a placeholder ARN for dry run
    MAIN_PROFILE_ARN="arn:aws:bedrock:us-west-2:123456789012:inference-profile/sample-profile-id"
fi

# Create embedding profile
EMBEDDING_PROFILE_NAME="coding-agent-embedding-profile-${ENV}"
echo "Creating embedding profile: $EMBEDDING_PROFILE_NAME"

aws bedrock create-inference-profile \
    --inference-profile-name "$EMBEDDING_PROFILE_NAME" \
    --model-source copyFrom="$EMBEDDING_MODEL_ARN" \
    --tags "[{\"key\":\"Environment\",\"value\":\"$ENV\"},{\"key\":\"Project\",\"value\":\"WebFG-Coding-Agent\"}]" \
    $DRY_RUN_FLAG

# Get the embedding profile ARN if not in dry-run mode
if [[ "$DRY_RUN" != "--dry-run" ]]; then
    EMBEDDING_PROFILE_ARN=$(aws bedrock list-inference-profiles --query "inferenceProfileSummaries[?inferenceProfileName=='$EMBEDDING_PROFILE_NAME'].inferenceProfileArn" --output text)
    echo "Created embedding profile with ARN: $EMBEDDING_PROFILE_ARN"
else
    echo "[Dry run] Would create embedding profile: $EMBEDDING_PROFILE_NAME"
    # Use a placeholder ARN for dry run
    EMBEDDING_PROFILE_ARN="arn:aws:bedrock:us-west-2:123456789012:inference-profile/sample-embedding-profile-id"
fi

# Store profile ARNs in SSM for reference by other resources
if [[ "$DRY_RUN" != "--dry-run" ]]; then
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
else
    echo "[Dry run] Would store the following SSM parameters:"
    echo "  - /coding-agent/$ENV/inference-profile-arn: $MAIN_PROFILE_ARN"
    echo "  - /coding-agent/$ENV/embedding-profile-arn: $EMBEDDING_PROFILE_ARN"
fi