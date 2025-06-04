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
    # Note: AWS CLI doesn't accept --dry-run directly, so we'll use a flag to skip creation
    DRY_RUN_MODE=true
else
    DRY_RUN_MODE=false
fi

# Validate environment parameter
if [[ ! "$ENV" =~ ^(dev|qa|prod|test)$ ]]; then
    echo "Error: Invalid environment. Use dev, qa, prod, or test."
    exit 1
fi

echo "Setting up inference profiles for $ENV environment..."

# Set model ARN based on environment
# Using the AWS-provided system inference profile for Claude Opus 4
# System-provided inference profiles are required for models that only support INFERENCE_PROFILE type
# These profiles route to multiple regions for better availability
SYSTEM_PROFILE_ARN="arn:aws:bedrock:us-east-1:507323066541:inference-profile/us.anthropic.claude-opus-4-20250514-v1:0"  # Using Claude Opus 4 system inference profile
# For embedding model, we need one that supports ON_DEMAND type
EMBEDDING_MODEL_ARN="arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-embed-text-v2:0"  # Using Titan Embed Text for embeddings (supports ON_DEMAND)

# Note: Claude Opus 4 only supports INFERENCE_PROFILE and not ON_DEMAND

# Use the system-provided inference profile directly instead of creating a new one
MAIN_PROFILE_NAME="us.anthropic.claude-opus-4-20250514-v1:0"
echo "Using system-provided inference profile: $MAIN_PROFILE_NAME"

# Store the system inference profile ARN directly
MAIN_PROFILE_ARN="$SYSTEM_PROFILE_ARN"
echo "Using system inference profile ARN: $MAIN_PROFILE_ARN"

# Create embedding profile
EMBEDDING_PROFILE_NAME="coding-agent-embedding-profile-${ENV}"
echo "Creating embedding profile: $EMBEDDING_PROFILE_NAME"

if [[ "$DRY_RUN_MODE" == false ]]; then
    # Only create the profile if not in dry-run mode
    aws bedrock create-inference-profile \
        --inference-profile-name "$EMBEDDING_PROFILE_NAME" \
        --model-source copyFrom="$EMBEDDING_MODEL_ARN" \
        --tags "[{\"key\":\"Environment\",\"value\":\"$ENV\"},{\"key\":\"Project\",\"value\":\"WebFG-Coding-Agent\"}]"
else
    echo "[Dry run] Would create embedding profile with command: aws bedrock create-inference-profile --inference-profile-name $EMBEDDING_PROFILE_NAME --model-source copyFrom=$EMBEDDING_MODEL_ARN"
fi

# Get the embedding profile ARN if not in dry-run mode
if [[ "$DRY_RUN_MODE" == false ]]; then
    # Wait a moment for the profile to be available in the list
    echo "Waiting for embedding profile to be available..."
    sleep 5
    
    # Fetch the profile ARN
    EMBEDDING_PROFILE_ARN=$(aws bedrock list-inference-profiles --query "inferenceProfileSummaries[?inferenceProfileName=='$EMBEDDING_PROFILE_NAME'].inferenceProfileArn" --output text)
    
    # Check if the ARN is empty and retry if needed
    if [[ -z "$EMBEDDING_PROFILE_ARN" ]]; then
        echo "Profile ARN not found on first attempt, retrying..."
        sleep 10
        EMBEDDING_PROFILE_ARN=$(aws bedrock list-inference-profiles --query "inferenceProfileSummaries[?inferenceProfileName=='$EMBEDDING_PROFILE_NAME'].inferenceProfileArn" --output text)
    fi
    
    # Verify that we have a valid ARN
    if [[ -z "$EMBEDDING_PROFILE_ARN" ]]; then
        echo "Error: Failed to retrieve embedding profile ARN. Using profile name as fallback."
        # Use the profile name as the ARN as a fallback
        EMBEDDING_PROFILE_ARN="arn:aws:bedrock:us-west-2:$(aws sts get-caller-identity --query 'Account' --output text):inference-profile/$EMBEDDING_PROFILE_NAME"
    fi
    
    echo "Created embedding profile with ARN: $EMBEDDING_PROFILE_ARN"
else
    echo "[Dry run] Would create embedding profile: $EMBEDDING_PROFILE_NAME"
    # Use a placeholder ARN for dry run
    EMBEDDING_PROFILE_ARN="arn:aws:bedrock:us-west-2:123456789012:inference-profile/sample-embedding-profile-id"
fi

# Store profile ARNs in SSM for reference by other resources
if [[ "$DRY_RUN_MODE" == false ]]; then
    echo "Storing inference profile ARNs in SSM parameters..."
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

    echo "Creating CloudFormation stack for profile exports..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PARENT_DIR="$(dirname "$SCRIPT_DIR")"
    EXPORTS_TEMPLATE="$PARENT_DIR/inference-profiles/exports.yaml"
    
    aws cloudformation deploy \
        --template-file "$EXPORTS_TEMPLATE" \
        --stack-name "coding-inference-profiles-$ENV" \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
            Environment=$ENV \
            MainProfileArn=$MAIN_PROFILE_ARN \
            EmbeddingProfileArn=$EMBEDDING_PROFILE_ARN

    echo "Inference profiles created and ARNs stored in SSM parameters and CloudFormation exports."
else
    echo "[Dry run] Would store the following SSM parameters:"
    echo "  - /coding-agent/$ENV/inference-profile-arn: $MAIN_PROFILE_ARN"
    echo "  - /coding-agent/$ENV/embedding-profile-arn: $EMBEDDING_PROFILE_ARN"
    echo "[Dry run] Would create CloudFormation stack: coding-inference-profiles-$ENV"
fi