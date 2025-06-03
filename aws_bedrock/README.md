# AWS Bedrock Coding Agent

This directory contains the AWS Bedrock agent setup for the WebFG coding assistant. The agent is designed to help developers with coding tasks through a conversational interface.

## Architecture

The Coding Agent consists of several components:

1. **Bedrock Agent** - The core conversational AI agent powered by Claude 3.5 Sonnet
2. **Knowledge Base** - Programming documentation stored in Amazon OpenSearch Serverless
3. **Lambda Functions** - Custom tools for code search, analysis, and documentation lookup
4. **Slack Integration** - Interface for users to interact with the agent

## Directory Structure

```
aws_bedrock/
├── agent/                 # Agent definition and tools
│   ├── lambdas/           # Lambda functions for agent tools
│   └── instructions/      # Agent system instructions
├── inference-profiles/    # Model configurations
├── knowledge-base/        # Knowledge base configuration
├── scripts/               # Deployment and management scripts
└── test/                  # Test scripts
```

## Deployment

### Prerequisites

- AWS CLI v2.13.0+ configured with appropriate permissions
- SAM CLI installed
- Access to AWS Bedrock and necessary models

### Deployment Steps

1. Deploy the agent to your desired environment (dev, qa, or prod):

   ```bash
   ./scripts/deploy_agent.sh [environment]
   ```

2. Once deployed, start the agent:

   ```bash
   ./scripts/start_agent.sh [environment]
   ```

3. Test the agent functionality:

   ```bash
   ./scripts/test_agent.sh [environment]
   ```

### Managing the Agent

- **Update the agent**: `./scripts/update_agent.sh [environment] [component]`
- **Stop the agent**: `./scripts/stop_agent.sh [environment]`
- **Delete the agent**: `./scripts/delete_agent.sh [environment] [component]`

## Testing

Run the automated tests to verify your deployment:

```bash
cd test
./test-all.sh [environment]
```

Individual test scripts are also available:
- `test-agent-deployment.sh` - Validates CloudFormation templates
- `test-agent-functionality.sh` - Tests agent responses to various prompts

## Lambda Functions

The agent is equipped with several Lambda functions that serve as tools:

1. **code_repository_search.py** - Search code repositories for specific patterns or files
2. **code_analysis.py** - Analyze code to provide insights about structure, quality, and potential issues
3. **document_search.py** - Search documentation and resources for relevant content

## Slack Integration

The agent integrates with Slack using a dedicated Lambda function that:
1. Handles Slack events and messages
2. Sends them to the Bedrock agent
3. Returns the agent's responses to the appropriate Slack channel

To configure Slack integration:
1. Create a Slack app in the [Slack API Console](https://api.slack.com/apps)
2. Update the secrets in AWS Secrets Manager with your Slack tokens
3. Configure the Event Subscriptions URL to point to your deployed API Gateway endpoint

## Knowledge Base

The agent uses a knowledge base that contains programming documentation. You can update this documentation by:

1. Adding new documentation files to the S3 bucket created during deployment
2. Syncing the knowledge base to pick up the new content

## Environments

The agent supports multiple environments:
- **dev**: For development and testing
- **qa**: For quality assurance testing
- **prod**: For production use

Each environment uses a separate set of resources and can be managed independently.

## Security Considerations

- The agent uses AWS Bedrock Guardrails to prevent misuse
- Lambda functions include input validation to prevent command injection
- IAM roles follow least privilege principle
- Slack verification ensures requests come from authorized sources