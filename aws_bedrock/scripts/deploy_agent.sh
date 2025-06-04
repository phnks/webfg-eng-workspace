#!/bin/bash

# Deploy AWS Bedrock agent and related resources
# Usage: ./deploy_agent.sh [environment]
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

echo "Deploying WebFG Coding Agent to $ENV environment..."

# Step 1: Set up inference profiles (using system profile for Claude Opus 4)
echo "Setting up inference profiles..."
bash "$SCRIPT_DIR/create_inference_profile.sh" "$ENV"

# Step 2: Deploy knowledge base CloudFormation stack
echo "Deploying knowledge base..."
cd "$PARENT_DIR/knowledge-base"
KNOWLEDGE_BASE_TEMPLATE="resources.yaml"
if [ "$ENV" = "dev" ] || [ "$ENV" = "qa" ]; then
    KNOWLEDGE_BASE_TEMPLATE="resources-qa.yaml"
fi

KNOWLEDGE_BASE_STACK_NAME="coding-agent-knowledge-base-$ENV"

# Check if the stack exists and is in a failed state
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$KNOWLEDGE_BASE_STACK_NAME" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [[ "$STACK_STATUS" == "ROLLBACK_COMPLETE" || "$STACK_STATUS" == "CREATE_FAILED" || "$STACK_STATUS" == "UPDATE_ROLLBACK_COMPLETE" ]]; then
    echo "Found knowledge base stack in $STACK_STATUS state. Deleting it before recreating..."
    aws cloudformation delete-stack --stack-name "$KNOWLEDGE_BASE_STACK_NAME"
    
    echo "Waiting for stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name "$KNOWLEDGE_BASE_STACK_NAME"
    
    # If wait command fails, manual polling
    if [ $? -ne 0 ]; then
        echo "Stack deletion is taking longer than expected. Polling status..."
        while true; do
            CURRENT_STATUS=$(aws cloudformation describe-stacks --stack-name "$KNOWLEDGE_BASE_STACK_NAME" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "DELETE_COMPLETE")
            if [[ "$CURRENT_STATUS" == "DELETE_COMPLETE" || "$CURRENT_STATUS" == "DOES_NOT_EXIST" ]]; then
                echo "Stack deletion completed."
                break
            fi
            echo "Stack status: $CURRENT_STATUS. Waiting..."
            sleep 10
        done
    fi
fi

if ! aws cloudformation deploy \
    --template-file "$KNOWLEDGE_BASE_TEMPLATE" \
    --stack-name "$KNOWLEDGE_BASE_STACK_NAME" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameter-overrides Environment=$ENV; then
    
    echo "Failed to deploy knowledge base stack. Checking failure reason..."
    aws cloudformation describe-stack-events \
        --stack-name "$KNOWLEDGE_BASE_STACK_NAME" \
        --query "StackEvents[?ResourceStatus=='CREATE_FAILED' || ResourceStatus=='UPDATE_FAILED'].{Resource:LogicalResourceId, Reason:ResourceStatusReason}" \
        --output json
    
    echo "Knowledge base stack deployment failed. Aborting deployment."
    exit 1
fi

# Step 3: Upload documentation files
echo "Uploading documentation and instructions..."
BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name coding-agent-knowledge-base-$ENV --query "Stacks[0].Outputs[?OutputKey=='DocumentsBucketName'].OutputValue" --output text)

if [ -z "$BUCKET_NAME" ]; then
    echo "Error: Could not determine the S3 bucket name. Check your CloudFormation stack outputs."
    exit 1
fi

# Create instructions directory if it doesn't exist
mkdir -p "$PARENT_DIR/temp_upload/instructions"

# Copy the agent instructions to the upload directory
cp "$PARENT_DIR/agent/instructions/coding-agent-instruction.md" "$PARENT_DIR/temp_upload/instructions/"

# Upload to S3
aws s3 sync "$PARENT_DIR/temp_upload/" "s3://$BUCKET_NAME/" --delete

# Clean up temp directory
rm -rf "$PARENT_DIR/temp_upload"

# Get Knowledge Base ID from CloudFormation output
KNOWLEDGE_BASE_ID=$(aws cloudformation describe-stacks --stack-name coding-agent-knowledge-base-$ENV --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseId'].OutputValue" --output text)

# Step 4: Deploy agent CloudFormation stack
echo "Deploying WebFG Coding Agent..."
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
AGENT_TEMPLATE="resources.yaml"
if [ "$ENV" = "dev" ] || [ "$ENV" = "qa" ]; then
    AGENT_TEMPLATE="resources-qa.yaml"
fi

# Get inference profile ARNs from SSM
INFERENCE_PROFILE_ARN=$(aws ssm get-parameter --name "/coding-agent/$ENV/inference-profile-arn" --query "Parameter.Value" --output text)
EMBEDDING_PROFILE_ARN=$(aws ssm get-parameter --name "/coding-agent/$ENV/embedding-profile-arn" --query "Parameter.Value" --output text)

AGENT_STACK_NAME="coding-agent-$ENV"

# Check if the agent stack exists and is in a failed state
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$AGENT_STACK_NAME" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [[ "$STACK_STATUS" == "ROLLBACK_COMPLETE" || "$STACK_STATUS" == "CREATE_FAILED" || "$STACK_STATUS" == "UPDATE_ROLLBACK_COMPLETE" ]]; then
    echo "Found agent stack in $STACK_STATUS state. Deleting it before recreating..."
    aws cloudformation delete-stack --stack-name "$AGENT_STACK_NAME"
    
    echo "Waiting for stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name "$AGENT_STACK_NAME"
    
    # If wait command fails, manual polling
    if [ $? -ne 0 ]; then
        echo "Stack deletion is taking longer than expected. Polling status..."
        while true; do
            CURRENT_STATUS=$(aws cloudformation describe-stacks --stack-name "$AGENT_STACK_NAME" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "DELETE_COMPLETE")
            if [[ "$CURRENT_STATUS" == "DELETE_COMPLETE" || "$CURRENT_STATUS" == "DOES_NOT_EXIST" ]]; then
                echo "Stack deletion completed."
                break
            fi
            echo "Stack status: $CURRENT_STATUS. Waiting..."
            sleep 10
        done
    fi
fi

# Deploy agent CloudFormation stack with profile ARNs
if ! aws cloudformation deploy \
    --template-file "$AGENT_TEMPLATE" \
    --stack-name "$AGENT_STACK_NAME" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides \
        Environment=$ENV \
        InferenceProfileArn=$INFERENCE_PROFILE_ARN \
        KnowledgeBaseId=$KNOWLEDGE_BASE_ID; then
    
    echo "Failed to deploy agent stack. Checking failure reason..."
    aws cloudformation describe-stack-events \
        --stack-name "$AGENT_STACK_NAME" \
        --query "StackEvents[?ResourceStatus=='CREATE_FAILED' || ResourceStatus=='UPDATE_FAILED'].{Resource:LogicalResourceId, Reason:ResourceStatusReason}" \
        --output json
    
    echo "Agent stack deployment failed. Continuing with Lambda function updates in case of partial success."
fi

# Update Lambda code after stack is created
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

echo "Deployment completed successfully!"
echo "Agent is now available in the AWS Console under Amazon Bedrock > Agents"

# Get webhook URL for Slack integration
WEBHOOK_URL=$(aws cloudformation describe-stacks --stack-name coding-agent-$ENV --query "Stacks[0].Outputs[?OutputKey=='WebhookUrl'].OutputValue" --output text)

if [ ! -z "$WEBHOOK_URL" ]; then
    echo ""
    echo "Slack Webhook URL: $WEBHOOK_URL"
    echo "You need to configure this URL in your Slack app settings."
fi