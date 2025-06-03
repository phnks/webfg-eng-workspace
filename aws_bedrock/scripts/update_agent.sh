#!/bin/bash

# Update existing AWS Bedrock agent
# Usage: ./update_agent.sh [environment] [component]
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

echo "Updating WebFG Coding Agent components in $ENV environment..."

# Update inference profiles if requested
if [ "$COMPONENT" = "all" ] || [ "$COMPONENT" = "profiles" ]; then
    echo "Updating inference profiles..."
    cd "$PARENT_DIR/inference-profiles"
    if [ "$ENV" = "dev" ] || [ "$ENV" = "qa" ]; then
        aws cloudformation deploy \
            --template-file resources-qa.yaml \
            --stack-name coding-inference-profiles-$ENV \
            --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
            --parameter-overrides Environment=$ENV
    else
        aws cloudformation deploy \
            --template-file resources.yaml \
            --stack-name coding-inference-profiles-$ENV \
            --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
            --parameter-overrides Environment=$ENV
    fi
fi

# Update knowledge base if requested
if [ "$COMPONENT" = "all" ] || [ "$COMPONENT" = "kb" ]; then
    echo "Updating knowledge base..."
    cd "$PARENT_DIR/knowledge-base"
    if [ "$ENV" = "dev" ] || [ "$ENV" = "qa" ]; then
        aws cloudformation deploy \
            --template-file resources-qa.yaml \
            --stack-name coding-agent-knowledge-base-$ENV \
            --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
            --parameter-overrides Environment=$ENV
    else
        aws cloudformation deploy \
            --template-file resources.yaml \
            --stack-name coding-agent-knowledge-base-$ENV \
            --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
            --parameter-overrides Environment=$ENV
    fi
    
    # Update documentation files
    echo "Updating documentation and instructions..."
    BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name coding-agent-knowledge-base-$ENV --query "Stacks[0].Outputs[?OutputKey=='DocumentsBucketName'].OutputValue" --output text)

    if [ ! -z "$BUCKET_NAME" ]; then
        # Create instructions directory if it doesn't exist
        mkdir -p "$PARENT_DIR/temp_upload/instructions"

        # Copy the agent instructions to the upload directory
        cp "$PARENT_DIR/agent/instructions/coding-agent-instruction.md" "$PARENT_DIR/temp_upload/instructions/"

        # Upload to S3
        aws s3 sync "$PARENT_DIR/temp_upload/" "s3://$BUCKET_NAME/" --delete

        # Clean up temp directory
        rm -rf "$PARENT_DIR/temp_upload"
    fi
fi

# Update agent if requested
if [ "$COMPONENT" = "all" ] || [ "$COMPONENT" = "agent" ]; then
    echo "Updating WebFG Coding Agent..."
    cd "$PARENT_DIR/agent"
    
    # Package Lambda functions
    echo "Packaging Lambda functions..."
    mkdir -p "$PARENT_DIR/temp_lambdas"

    # Create zip packages for each Lambda function
    cd "$PARENT_DIR/agent/lambdas"

    # Package code_repository_search Lambda
    zip -j "$PARENT_DIR/temp_lambdas/code_repository_search.zip" code_repository_search.py

    # Package code_analysis Lambda
    zip -j "$PARENT_DIR/temp_lambdas/code_analysis.zip" code_analysis.py

    # Package document_search Lambda
    zip -j "$PARENT_DIR/temp_lambdas/document_search.zip" document_search.py

    # Package slack_handler Lambda
    cd "$PARENT_DIR/agent/lambdas/slack_handler"
    pip install -t . -r requirements.txt
    zip -r "$PARENT_DIR/temp_lambdas/slack_handler.zip" .

    # Deploy the agent with packaged code
    cd "$PARENT_DIR/agent"
    if [ "$ENV" = "dev" ] || [ "$ENV" = "qa" ]; then
        aws cloudformation deploy \
            --template-file resources-qa.yaml \
            --stack-name coding-agent-$ENV \
            --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
            --parameter-overrides Environment=$ENV
    else
        aws cloudformation deploy \
            --template-file resources.yaml \
            --stack-name coding-agent-$ENV \
            --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
            --parameter-overrides Environment=$ENV
    fi

    # Update Lambda code after stack is deployed
    echo "Updating Lambda functions with actual code..."
    aws lambda update-function-code \
        --function-name coding-agent-code-repository-search-$ENV \
        --zip-file fileb://$PARENT_DIR/temp_lambdas/code_repository_search.zip

    aws lambda update-function-code \
        --function-name coding-agent-code-analysis-$ENV \
        --zip-file fileb://$PARENT_DIR/temp_lambdas/code_analysis.zip

    aws lambda update-function-code \
        --function-name coding-agent-document-search-$ENV \
        --zip-file fileb://$PARENT_DIR/temp_lambdas/document_search.zip

    # Clean up temp directory
    rm -rf "$PARENT_DIR/temp_lambdas"
fi

echo "Update completed successfully!"