#!/bin/bash

# Run all AWS Bedrock agent tests
# This script runs both deployment and functionality tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV=${1:-dev}

# Validate environment parameter
if [[ ! "$ENV" =~ ^(dev|qa|prod)$ ]]; then
    echo "Error: Invalid environment. Use dev, qa, or prod."
    exit 1
fi

echo "Running all tests for WebFG Coding Agent in $ENV environment..."

# Step 1: Run deployment tests
echo "Running deployment tests..."
bash "$SCRIPT_DIR/test-agent-deployment.sh"
if [ $? -ne 0 ]; then
    echo "❌ Deployment tests failed"
    exit 1
fi
echo "✅ Deployment tests passed"

# Step 2: Run functionality tests if the agent is deployed
echo "Running functionality tests..."
bash "$SCRIPT_DIR/test-agent-functionality.sh" "$ENV"
if [ $? -ne 0 ]; then
    echo "❌ Functionality tests failed"
    exit 1
fi
echo "✅ Functionality tests passed"

echo "All tests passed successfully! 🎉"
exit 0