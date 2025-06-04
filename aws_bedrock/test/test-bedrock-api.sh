#!/bin/bash

# Test Bedrock API access and functionality
# This script tests basic Bedrock API operations to verify AWS CLI setup

set -e

echo "Testing AWS Bedrock API access..."

# Test listing foundation models
echo "Listing available foundation models..."
aws bedrock list-foundation-models --query "modelSummaries[0:5]" --output json

if [ $? -ne 0 ]; then
    echo "❌ Failed to list foundation models"
    exit 1
fi
echo "✅ Successfully listed foundation models"

# Check if specific models we need are available
echo "Checking required models..."
aws bedrock list-foundation-models --query "modelSummaries[?modelId=='amazon.titan-embed-text-v2:0'].modelId" --output text

if [ $? -ne 0 ]; then
    echo "❌ Failed to check for required embedding model"
    exit 1
fi
echo "✅ Successfully checked embedding model availability"

# Check if system-provided Claude Opus 4 inference profile is available
echo "Checking system-provided Claude Opus 4 inference profile..."
aws bedrock list-inference-profiles --region us-east-1 --query "inferenceProfileSummaries[?contains(inferenceProfileName,'claude-opus-4')].inferenceProfileName" --output text

if [ $? -ne 0 ]; then
    echo "❌ Failed to check for Claude Opus 4 system inference profile"
    exit 1
fi
echo "✅ Successfully verified Claude Opus 4 system inference profile is available"

# Test SSM parameter store access
echo "Testing SSM parameter store access..."
TEST_PARAM_NAME="/coding-agent/test/validation"
TEST_PARAM_VALUE="test-value-$(date +%s)"

aws ssm put-parameter \
    --name "$TEST_PARAM_NAME" \
    --type "String" \
    --value "$TEST_PARAM_VALUE" \
    --overwrite

if [ $? -ne 0 ]; then
    echo "❌ Failed to write to SSM parameter store"
    exit 1
fi

# Verify parameter was written
PARAM_VALUE=$(aws ssm get-parameter --name "$TEST_PARAM_NAME" --query "Parameter.Value" --output text)
if [ "$PARAM_VALUE" = "$TEST_PARAM_VALUE" ]; then
    echo "✅ Successfully verified SSM parameter store access"
else
    echo "❌ Failed to verify SSM parameter value"
    exit 1
fi

# Clean up test parameter
aws ssm delete-parameter --name "$TEST_PARAM_NAME"

echo "All Bedrock API tests completed successfully! ✅"
echo "The AWS environment is properly set up for deploying the Coding Agent."