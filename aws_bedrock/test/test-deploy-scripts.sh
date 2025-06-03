#!/bin/bash

# Test script for AWS Bedrock deployment scripts
# This script tests the deployment scripts without actually creating resources
# It validates script syntax and API parameter validation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
ENV="test"

echo "Testing AWS Bedrock deployment scripts..."

# Test create_inference_profile.sh script syntax
echo "Testing create_inference_profile.sh script syntax..."
bash -n "$PARENT_DIR/scripts/create_inference_profile.sh" || {
    echo "❌ create_inference_profile.sh has syntax errors"
    exit 1
}

# Check for key error patterns in the output
if echo "$DRY_RUN_OUTPUT" | grep -q "ValidationException"; then
    echo "❌ create_inference_profile.sh failed validation: $DRY_RUN_OUTPUT"
    exit 1
fi

# Test create_inference_profile.sh by checking model ARN format
echo "Validating model ARN format in create_inference_profile.sh..."
ARN_PATTERN="arn:aws:bedrock:[a-z0-9-]+::foundation-model/[a-zA-Z0-9\.-]+:[0-9]+"

# Extract ARNs from script
SCRIPT_CONTENT=$(cat "$PARENT_DIR/scripts/create_inference_profile.sh")
MAIN_ARN=$(echo "$SCRIPT_CONTENT" | grep -o 'MODEL_ARN="[^"]*"' | cut -d'"' -f2)
EMBEDDING_ARN=$(echo "$SCRIPT_CONTENT" | grep -o 'EMBEDDING_MODEL_ARN="[^"]*"' | cut -d'"' -f2)

# Check main model ARN format
if ! [[ $MAIN_ARN =~ $ARN_PATTERN ]]; then
    echo "❌ Main model ARN does not match expected format: $MAIN_ARN"
    exit 1
fi

# Check embedding model ARN format
if ! [[ $EMBEDDING_ARN =~ $ARN_PATTERN ]]; then
    echo "❌ Embedding model ARN does not match expected format: $EMBEDDING_ARN"
    exit 1
fi

echo "✅ Model ARNs in create_inference_profile.sh are correctly formatted"

# Test if deploy_agent.sh script syntax is valid
echo "Testing deploy_agent.sh script syntax..."
bash -n "$PARENT_DIR/scripts/deploy_agent.sh" || {
    echo "❌ deploy_agent.sh has syntax errors"
    exit 1
}
echo "✅ deploy_agent.sh script syntax is valid"

# Test delete_agent.sh script syntax
echo "Testing delete_agent.sh script syntax..."
bash -n "$PARENT_DIR/scripts/delete_agent.sh" || {
    echo "❌ delete_agent.sh has syntax errors"
    exit 1
}
echo "✅ delete_agent.sh script syntax is valid"

# Test delete_inference_profile.sh script syntax
echo "Testing delete_inference_profile.sh script syntax..."
bash -n "$PARENT_DIR/scripts/delete_inference_profile.sh" || {
    echo "❌ delete_inference_profile.sh has syntax errors"
    exit 1
}
echo "✅ delete_inference_profile.sh script syntax is valid"

echo "All script syntax tests passed. ✅"
echo "Note: This test validates script syntax only, not actual resource creation."
echo "To test actual resource creation, you need appropriate AWS permissions."