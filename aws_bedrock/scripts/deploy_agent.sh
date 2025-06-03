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

# Step 1: Create inference profiles using direct API calls
echo "Creating inference profiles..."
bash "$SCRIPT_DIR/create_inference_profile.sh" "$ENV"

# Step 2: Deploy knowledge base CloudFormation stack
echo "Deploying knowledge base..."
cd "$PARENT_DIR/knowledge-base"
KNOWLEDGE_BASE_TEMPLATE="resources.yaml"
if [ "$ENV" = "dev" ] || [ "$ENV" = "qa" ]; then
    KNOWLEDGE_BASE_TEMPLATE="resources-qa.yaml"
fi

aws cloudformation deploy \
    --template-file "$KNOWLEDGE_BASE_TEMPLATE" \
    --stack-name coding-agent-knowledge-base-$ENV \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameter-overrides Environment=$ENV

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

# Deploy agent CloudFormation stack with profile ARNs
aws cloudformation deploy \
    --template-file "$AGENT_TEMPLATE" \
    --stack-name coding-agent-$ENV \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
    --parameter-overrides \
        Environment=$ENV \
        InferenceProfileArn=$INFERENCE_PROFILE_ARN \
        KnowledgeBaseId=$KNOWLEDGE_BASE_ID

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