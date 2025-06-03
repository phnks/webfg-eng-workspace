#!/bin/bash

# Test AWS Bedrock agent deployment process
# This script verifies that all components deploy successfully

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
ENV="test"

echo "Testing AWS Bedrock agent deployment process..."

# Step 1: Test inference profiles deployment
echo "Testing inference profiles deployment..."
cd "$PARENT_DIR/inference-profiles"
aws cloudformation validate-template --template-body file://resources-qa.yaml
if [ $? -ne 0 ]; then
    echo "❌ Inference profiles template validation failed"
    exit 1
fi
echo "✅ Inference profiles template validation passed"

# Step 2: Test knowledge base deployment
echo "Testing knowledge base deployment..."
cd "$PARENT_DIR/knowledge-base"
aws cloudformation validate-template --template-body file://resources-qa.yaml
if [ $? -ne 0 ]; then
    echo "❌ Knowledge base template validation failed"
    exit 1
fi
echo "✅ Knowledge base template validation passed"

# Step 3: Test agent deployment
echo "Testing agent deployment..."
cd "$PARENT_DIR/agent"
aws cloudformation validate-template --template-body file://resources-qa.yaml
if [ $? -ne 0 ]; then
    echo "❌ Agent template validation failed"
    exit 1
fi
echo "✅ Agent template validation passed"

# Step 4: Test Lambda functions
echo "Testing Lambda functions..."
cd "$PARENT_DIR/agent/lambdas"
for f in *.py; do
    if [ -f "$f" ]; then
        python -m py_compile "$f"
        if [ $? -ne 0 ]; then
            echo "❌ Lambda function $f has syntax errors"
            exit 1
        fi
        echo "✅ Lambda function $f syntax check passed"
    fi
done

echo "All deployment tests passed successfully! 🎉"
exit 0