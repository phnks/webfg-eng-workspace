#!/bin/bash

# AWS Knowledge Base MCP Server - Deployment Script
# This script automates the deployment of AWS Knowledge Base infrastructure

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STACK_NAME="mcp-knowledge-base-stack"
REGION="${AWS_REGION:-us-east-1}"
BUCKET_PREFIX="mcp-kb-documents"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if AWS CLI is installed and configured
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi

    log_info "AWS CLI is properly configured"
}

# Check if required AWS services are available in the region
check_service_availability() {
    log_info "Checking service availability in region: $REGION"
    
    # Check if Bedrock is available
    if ! aws bedrock list-foundation-models --region "$REGION" &> /dev/null; then
        log_error "Amazon Bedrock is not available in region $REGION"
        log_error "Please use a region where Bedrock is available (e.g., us-east-1, us-west-2)"
        exit 1
    fi

    # Check if OpenSearch Serverless is available
    if ! aws opensearchserverless list-collections --region "$REGION" &> /dev/null; then
        log_error "OpenSearch Serverless is not available in region $REGION"
        exit 1
    fi

    log_info "All required services are available in region $REGION"
}

# Deploy CloudFormation stack
deploy_stack() {
    local template_path="$PROJECT_ROOT/infrastructure/knowledge-base-stack.yaml"
    
    if [ ! -f "$template_path" ]; then
        log_error "CloudFormation template not found at $template_path"
        exit 1
    fi

    log_info "Deploying CloudFormation stack: $STACK_NAME"
    
    # Check if stack already exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &> /dev/null; then
        log_warn "Stack $STACK_NAME already exists. Updating..."
        OPERATION="update-stack"
    else
        log_info "Creating new stack: $STACK_NAME"
        OPERATION="create-stack"
    fi

    # Deploy the stack
    aws cloudformation $OPERATION \
        --stack-name "$STACK_NAME" \
        --template-body "file://$template_path" \
        --parameters \
            ParameterKey=BucketName,ParameterValue="$BUCKET_PREFIX" \
            ParameterKey=KnowledgeBaseName,ParameterValue="mcp-knowledge-base" \
            ParameterKey=CollectionName,ParameterValue="mcp-kb-collection" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION"

    log_info "Waiting for stack deployment to complete..."
    
    if [ "$OPERATION" = "create-stack" ]; then
        aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$REGION"
    else
        aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$REGION"
    fi

    log_info "Stack deployment completed successfully!"
}

# Get stack outputs
get_stack_outputs() {
    log_info "Retrieving stack outputs..."
    
    OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs' \
        --output json)

    if [ "$OUTPUTS" = "null" ] || [ -z "$OUTPUTS" ]; then
        log_error "No outputs found for stack $STACK_NAME"
        return 1
    fi

    # Extract individual outputs
    KNOWLEDGE_BASE_ID=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="KnowledgeBaseId") | .OutputValue')
    DATA_SOURCE_ID=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="DataSourceId") | .OutputValue')
    S3_BUCKET_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="S3BucketName") | .OutputValue')
    OPENSEARCH_ENDPOINT=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="OpenSearchCollectionEndpoint") | .OutputValue')

    # Display outputs
    echo ""
    log_info "=== Deployment Outputs ==="
    echo "Knowledge Base ID: $KNOWLEDGE_BASE_ID"
    echo "Data Source ID: $DATA_SOURCE_ID"
    echo "S3 Bucket Name: $S3_BUCKET_NAME"
    echo "OpenSearch Endpoint: $OPENSEARCH_ENDPOINT"
    echo ""

    # Save outputs to file for later use
    OUTPUT_FILE="$PROJECT_ROOT/deployment-outputs.json"
    echo "$OUTPUTS" > "$OUTPUT_FILE"
    log_info "Outputs saved to: $OUTPUT_FILE"
}

# Upload mock data to S3
upload_mock_data() {
    if [ -z "$S3_BUCKET_NAME" ]; then
        log_error "S3 bucket name not available. Please run deployment first."
        return 1
    fi

    local mock_data_dir="$PROJECT_ROOT/mock-data"
    
    if [ ! -d "$mock_data_dir" ]; then
        log_warn "Mock data directory not found. Skipping mock data upload."
        return 0
    fi

    log_info "Uploading mock data to S3 bucket: $S3_BUCKET_NAME"
    
    aws s3 sync "$mock_data_dir" "s3://$S3_BUCKET_NAME/documents/" \
        --region "$REGION" \
        --exclude ".*"

    log_info "Mock data uploaded successfully"
}

# Sync data source (trigger ingestion)
sync_data_source() {
    if [ -z "$KNOWLEDGE_BASE_ID" ] || [ -z "$DATA_SOURCE_ID" ]; then
        log_error "Knowledge Base ID or Data Source ID not available"
        return 1
    fi

    log_info "Starting data source synchronization..."
    
    SYNC_JOB_ID=$(aws bedrock-agent start-ingestion-job \
        --knowledge-base-id "$KNOWLEDGE_BASE_ID" \
        --data-source-id "$DATA_SOURCE_ID" \
        --region "$REGION" \
        --query 'ingestionJob.ingestionJobId' \
        --output text)

    log_info "Ingestion job started with ID: $SYNC_JOB_ID"
    log_info "You can monitor the job status in the AWS console or using:"
    echo "aws bedrock-agent get-ingestion-job --knowledge-base-id $KNOWLEDGE_BASE_ID --data-source-id $DATA_SOURCE_ID --ingestion-job-id $SYNC_JOB_ID --region $REGION"
}

# Create environment file for MCP server
create_env_file() {
    local env_file="$PROJECT_ROOT/.env"
    
    log_info "Creating environment file: $env_file"
    
    cat > "$env_file" << EOF
# AWS Configuration for MCP Knowledge Base Server
AWS_REGION=$REGION
AWS_PROFILE=default

# Knowledge Base Configuration
KNOWLEDGE_BASE_ID=$KNOWLEDGE_BASE_ID
DATA_SOURCE_ID=$DATA_SOURCE_ID
S3_BUCKET_NAME=$S3_BUCKET_NAME

# MCP Server Configuration
KB_INCLUSION_TAG_KEY=mcp-multirag-kb
BEDROCK_KB_RERANKING_ENABLED=false

# Created by deploy.sh on $(date)
EOF

    log_info "Environment file created successfully"
}

# Main deployment function
main() {
    echo "====================================="
    echo "  AWS Knowledge Base MCP Deployment"
    echo "====================================="
    echo ""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                REGION="$2"
                shift 2
                ;;
            --stack-name)
                STACK_NAME="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --region REGION      AWS region (default: us-east-1)"
                echo "  --stack-name NAME    CloudFormation stack name (default: mcp-knowledge-base-stack)"
                echo "  --help              Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    log_info "Using AWS region: $REGION"
    log_info "Using stack name: $STACK_NAME"
    echo ""

    # Deployment steps
    check_aws_cli
    check_service_availability
    deploy_stack
    get_stack_outputs
    upload_mock_data
    sync_data_source
    create_env_file

    echo ""
    log_info "=== Deployment Complete ==="
    log_info "Your AWS Knowledge Base is now ready!"
    log_info "Knowledge Base ID: $KNOWLEDGE_BASE_ID"
    log_info ""
    log_info "Next steps:"
    echo "1. Test the MCP server: cd $PROJECT_ROOT && python -m awslabs.bedrock_kb_retrieval_mcp_server.server"
    echo "2. Query the knowledge base using the MCP tools"
    echo "3. Add your own documents to s3://$S3_BUCKET_NAME/documents/"
    echo ""
}

# Run main function
main "$@"