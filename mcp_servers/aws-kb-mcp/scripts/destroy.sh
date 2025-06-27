#!/bin/bash

# AWS Knowledge Base MCP Server - Destroy Script
# This script removes all AWS resources created by the deployment

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STACK_NAME="mcp-knowledge-base-stack"
REGION="${AWS_REGION:-us-east-1}"

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

# Confirmation prompt
confirm_destroy() {
    echo ""
    log_warn "This will PERMANENTLY DELETE all AWS resources created by the MCP Knowledge Base deployment."
    log_warn "This includes:"
    echo "  - Knowledge Base and all its data"
    echo "  - OpenSearch Serverless collection"
    echo "  - S3 bucket and all stored documents"
    echo "  - IAM roles and policies"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Operation cancelled."
        exit 0
    fi
}

# Empty S3 bucket before deletion
empty_s3_bucket() {
    # Get bucket name from stack outputs
    local bucket_name
    bucket_name=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
        --output text 2>/dev/null || echo "")

    if [ -n "$bucket_name" ] && [ "$bucket_name" != "None" ]; then
        log_info "Emptying S3 bucket: $bucket_name"
        
        # Delete all objects and versions
        aws s3 rm "s3://$bucket_name" --recursive --region "$REGION" 2>/dev/null || true
        
        # Delete all object versions (if versioning is enabled)
        aws s3api delete-objects \
            --bucket "$bucket_name" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$bucket_name" \
                --output json \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                2>/dev/null || echo '{"Objects":[]}')" \
            --region "$REGION" 2>/dev/null || true
        
        # Delete all delete markers
        aws s3api delete-objects \
            --bucket "$bucket_name" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$bucket_name" \
                --output json \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                2>/dev/null || echo '{"Objects":[]}')" \
            --region "$REGION" 2>/dev/null || true
        
        log_info "S3 bucket emptied successfully"
    else
        log_warn "Could not determine S3 bucket name, skipping bucket cleanup"
    fi
}

# Delete CloudFormation stack
delete_stack() {
    log_info "Checking if stack exists: $STACK_NAME"
    
    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &> /dev/null; then
        log_warn "Stack $STACK_NAME does not exist or has already been deleted"
        return 0
    fi

    log_info "Deleting CloudFormation stack: $STACK_NAME"
    
    aws cloudformation delete-stack \
        --stack-name "$STACK_NAME" \
        --region "$REGION"

    log_info "Waiting for stack deletion to complete..."
    aws cloudformation wait stack-delete-complete \
        --stack-name "$STACK_NAME" \
        --region "$REGION"

    log_info "Stack deleted successfully!"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove environment file
    local env_file="$PROJECT_ROOT/.env"
    if [ -f "$env_file" ]; then
        rm "$env_file"
        log_info "Removed environment file: $env_file"
    fi
    
    # Remove deployment outputs
    local output_file="$PROJECT_ROOT/deployment-outputs.json"
    if [ -f "$output_file" ]; then
        rm "$output_file"
        log_info "Removed deployment outputs: $output_file"
    fi
}

# Main destroy function
main() {
    echo "====================================="
    echo "  AWS Knowledge Base MCP Destroyer"
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
            --force)
                FORCE=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --region REGION      AWS region (default: us-east-1)"
                echo "  --stack-name NAME    CloudFormation stack name (default: mcp-knowledge-base-stack)"
                echo "  --force             Skip confirmation prompt"
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

    # Confirmation (unless forced)
    if [ "$FORCE" != true ]; then
        confirm_destroy
    fi

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi

    # Destruction steps
    empty_s3_bucket
    delete_stack
    cleanup_local_files

    echo ""
    log_info "=== Destruction Complete ==="
    log_info "All AWS resources have been successfully removed."
    echo ""
}

# Run main function
main "$@"