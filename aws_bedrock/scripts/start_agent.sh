#!/bin/bash

# Start an AWS Bedrock agent alias
# Usage: ./start_agent.sh [environment]
# Environment options: dev, qa, prod (default: dev)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
ENV=${1:-dev}

# Validate environment parameter
if [[ ! "$ENV" =~ ^(dev|qa|prod)$ ]]; then
    echo "Error: Invalid environment. Use dev, qa, or prod."
    exit 1
fi

echo "Starting WebFG Coding Agent alias in $ENV environment..."

# Get agent ID from CloudFormation outputs
AGENT_ID=$(aws cloudformation describe-stacks --stack-name coding-agent-$ENV --query "Stacks[0].Outputs[?OutputKey=='AgentId'].OutputValue" --output text)
ALIAS_ID=$(aws cloudformation describe-stacks --stack-name coding-agent-$ENV --query "Stacks[0].Outputs[?OutputKey=='AgentAliasId'].OutputValue" --output text)

if [ -z "$AGENT_ID" ] || [ -z "$ALIAS_ID" ]; then
    echo "Error: Could not retrieve agent or alias ID. Please check if the stack exists and has the expected outputs."
    exit 1
fi

echo "Found agent ID: $AGENT_ID"
echo "Found alias ID: $ALIAS_ID"

# Start the agent alias
aws bedrock update-agent-alias \
    --agent-id $AGENT_ID \
    --agent-alias-id $ALIAS_ID \
    --agent-alias-status ENABLED

echo "WebFG Coding Agent alias has been started successfully!"