#!/bin/bash

# Delete AWS Bedrock agent and related resources
# Usage: ./delete_agent.sh [environment] [component]
# Environment options: dev, qa, prod (default: dev)
# Component options: all, agent, kb, profiles (default: all)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
ENV=${1:-dev}
COMPONENT=${2:-all}

# Validate environment parameter
if [[ ! "$ENV" =~ ^(dev|qa|prod)$ ]]; then
    echo "Error: Invalid environment. Use dev, qa, or prod."
    exit 1
fi

# Validate component parameter
if [[ ! "$COMPONENT" =~ ^(all|agent|kb|profiles)$ ]]; then
    echo "Error: Invalid component. Use all, agent, kb, or profiles."
    exit 1
fi

# Confirm deletion
echo "WARNING: You are about to delete WebFG Coding Agent resources in the $ENV environment."
echo "This action cannot be undone and may result in data loss."
read -p "Are you sure you want to proceed? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Deletion cancelled."
    exit 0
fi

# Delete agent if requested
if [ "$COMPONENT" = "all" ] || [ "$COMPONENT" = "agent" ]; then
    echo "Deleting WebFG Coding Agent..."
    aws cloudformation delete-stack --stack-name coding-agent-$ENV
    echo "Waiting for agent stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name coding-agent-$ENV || true
fi

# Delete knowledge base if requested
if [ "$COMPONENT" = "all" ] || [ "$COMPONENT" = "kb" ]; then
    echo "Deleting knowledge base..."
    
    # Get knowledge base bucket name
    BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name coding-agent-knowledge-base-$ENV --query "Stacks[0].Outputs[?OutputKey=='DocumentsBucketName'].OutputValue" --output text 2>/dev/null || echo "")
    
    if [ ! -z "$BUCKET_NAME" ]; then
        echo "Emptying S3 bucket $BUCKET_NAME..."
        aws s3 rm s3://$BUCKET_NAME --recursive
    fi
    
    aws cloudformation delete-stack --stack-name coding-agent-knowledge-base-$ENV
    echo "Waiting for knowledge base stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name coding-agent-knowledge-base-$ENV || true
fi

# Delete inference profiles if requested
if [ "$COMPONENT" = "all" ] || [ "$COMPONENT" = "profiles" ]; then
    echo "Deleting inference profiles..."
    bash "$SCRIPT_DIR/delete_inference_profile.sh" "$ENV"
fi

echo "Deletion completed successfully!"