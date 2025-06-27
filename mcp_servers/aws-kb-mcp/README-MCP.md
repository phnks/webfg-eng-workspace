# AWS Knowledge Base MCP Server

An AWS Knowledge Base integration for Model Context Protocol (MCP) with fully automated CloudFormation deployment.

## Overview

This MCP server provides access to Amazon Bedrock Knowledge Bases for retrieving relevant information through natural language queries. It includes complete infrastructure automation using CloudFormation templates.

## Features

- **Automated AWS Infrastructure Deployment**: One-command deployment of Knowledge Base, OpenSearch Serverless, and S3 storage
- **Natural Language Querying**: Query knowledge bases using natural language through MCP tools
- **Multi-Data Source Support**: Support for multiple data sources within knowledge bases
- **Result Filtering**: Filter results by specific data sources
- **Optional Reranking**: Improve result relevance with AI-powered reranking
- **Mock Data Included**: Pre-built sample data for testing

## Architecture

The solution creates the following AWS resources:
- **Amazon Bedrock Knowledge Base**: For AI-powered document retrieval
- **OpenSearch Serverless Collection**: Vector storage for embeddings
- **S3 Bucket**: Document storage with automatic ingestion
- **IAM Roles and Policies**: Secure access management

## Quick Start

### Prerequisites

1. **AWS CLI installed and configured**
   ```bash
   aws configure
   ```

2. **Required AWS permissions** for:
   - Amazon Bedrock
   - OpenSearch Serverless
   - S3
   - CloudFormation
   - IAM

3. **Python 3.10+ and dependencies**
   ```bash
   pip install boto3 loguru mcp pydantic
   ```

### Deployment

1. **Deploy the infrastructure**:
   ```bash
   cd scripts
   ./deploy.sh
   ```

   Optional parameters:
   ```bash
   ./deploy.sh --region us-west-2 --stack-name my-kb-stack
   ```

2. **Wait for deployment** (typically 10-15 minutes):
   - CloudFormation stack creation
   - OpenSearch collection setup
   - Knowledge Base configuration
   - Mock data upload and ingestion

3. **Test the MCP server**:
   ```bash
   python -m awslabs.bedrock_kb_retrieval_mcp_server.server
   ```

### Usage

Once deployed, the MCP server provides two main capabilities:

1. **Discover Knowledge Bases**:
   ```json
   {
     "method": "resources/read",
     "params": {
       "uri": "resource://knowledgebases"
     }
   }
   ```

2. **Query Knowledge Bases**:
   ```json
   {
     "method": "tools/call",
     "params": {
       "name": "QueryKnowledgeBases",
       "arguments": {
         "query": "What are the company benefits?",
         "knowledge_base_id": "KB123456789",
         "number_of_results": 5
       }
     }
   }
   ```

## Mock Data

The deployment includes sample documents:
- **Company Handbook**: Employee benefits, policies, contact information
- **Product Catalog**: Software solutions, pricing, features
- **Technical FAQ**: Common technical questions and answers

## Configuration

Environment variables (automatically created by deployment):

```bash
# AWS Configuration
AWS_REGION=us-east-1
AWS_PROFILE=default

# Knowledge Base Settings
KB_INCLUSION_TAG_KEY=mcp-multirag-kb
BEDROCK_KB_RERANKING_ENABLED=false

# Deployment Outputs
KNOWLEDGE_BASE_ID=KB123456789
DATA_SOURCE_ID=DS123456789
S3_BUCKET_NAME=mcp-kb-documents-123456789-us-east-1
```

## Adding Your Own Data

1. **Upload documents to S3**:
   ```bash
   aws s3 cp your-document.pdf s3://YOUR-BUCKET-NAME/documents/
   ```

2. **Trigger data ingestion**:
   ```bash
   aws bedrock-agent start-ingestion-job \
     --knowledge-base-id YOUR-KB-ID \
     --data-source-id YOUR-DS-ID
   ```

3. **Monitor ingestion progress** in the AWS Console or via CLI

## Troubleshooting

### Common Issues

1. **Region Compatibility**: Ensure Bedrock is available in your region
   - Use regions like `us-east-1`, `us-west-2`, `eu-west-1`

2. **IAM Permissions**: Verify your AWS credentials have sufficient permissions
   
3. **Service Quotas**: Check AWS service quotas for OpenSearch Serverless and Bedrock

### Logs and Debugging

- **CloudFormation Events**: Check AWS Console for stack deployment issues
- **Ingestion Job Status**: Monitor via AWS Console or CLI
- **MCP Server Logs**: Check stderr output for runtime issues

### Getting Help

- Check the [AWS Bedrock Documentation](https://docs.aws.amazon.com/bedrock/)
- Review [OpenSearch Serverless Documentation](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/serverless.html)
- Use `./scripts/destroy.sh` to clean up resources if needed

## Cleanup

To remove all AWS resources:

```bash
cd scripts
./destroy.sh
```

This will:
- Empty the S3 bucket
- Delete the CloudFormation stack
- Remove all associated resources
- Clean up local configuration files

## Cost Considerations

Typical monthly costs for the basic setup:
- **OpenSearch Serverless**: ~$50-100/month (OCU-hours)
- **Bedrock Knowledge Base**: Pay-per-query (~$0.0025 per 1K tokens)
- **S3 Storage**: ~$1-5/month (depending on document volume)
- **Data Transfer**: Minimal for typical usage

## Development

### Project Structure

```
mcp_servers/aws-kb-mcp/
├── awslabs/                    # MCP server source code
├── infrastructure/             # CloudFormation templates
├── scripts/                    # Deployment automation
├── mock-data/                  # Sample documents
├── tests/                      # Unit tests
└── README.md                   # This file
```

### Running Tests

```bash
# Install development dependencies
pip install -e .[dev]

# Run tests
pytest tests/

# Run with coverage
pytest --cov=awslabs tests/
```

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

## Support

For issues and questions:
- Create an issue in this repository
- Check the AWS documentation
- Contact AWS support for service-specific issues