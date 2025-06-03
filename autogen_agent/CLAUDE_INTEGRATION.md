# Claude Bedrock Integration Guide

This guide explains how to integrate Claude models via AWS Bedrock with the AutoGen Discord bot.

## Overview

The bot now supports three model providers:
- **OpenAI** (default): GPT-4, GPT-3.5-turbo, etc.
- **Gemini**: Google's Gemini models
- **Claude**: Anthropic's Claude models via AWS Bedrock

## Environment Configuration

### Model Provider Selection

Use the `MODEL_PROVIDER` environment variable to choose your model:

```bash
# Use OpenAI (default)
MODEL_PROVIDER=openai
MODEL_NAME=gpt-4o

# Use Gemini  
MODEL_PROVIDER=gemini
MODEL_NAME=gemini-2.5-pro-exp-03-25

# Use Claude via AWS Bedrock
MODEL_PROVIDER=claude
MODEL_NAME=claude-opus-4
```

### Claude-Specific Configuration

For Claude integration, you need separate AWS credentials for Bedrock access:

```bash
# Bedrock AWS credentials (separate from project AWS account)
BEDROCK_AWS_ACCESS_KEY_ID=your_bedrock_access_key
BEDROCK_AWS_SECRET_ACCESS_KEY=your_bedrock_secret_key
BEDROCK_AWS_REGION=us-west-2
```

**Important**: These credentials are separate from your project AWS credentials (`AWS_ACCESS_KEY_ID`, etc.) which the agent uses for project tasks.

## Available Claude Models

The integration supports all Claude models available in AWS Bedrock:

| Model Name | Model ID | Description |
|------------|----------|-------------|
| `claude-3-haiku` | `anthropic.claude-3-haiku-20240307-v1:0` | Fast, cost-effective |
| `claude-3-sonnet` | `anthropic.claude-3-sonnet-20240229-v1:0` | Balanced performance |
| `claude-3-opus` | `anthropic.claude-3-opus-20240229-v1:0` | Most capable |
| `claude-3-5-sonnet` | `anthropic.claude-3-5-sonnet-20240620-v1:0` | Enhanced Sonnet |
| `claude-3-5-sonnet-v2` | `anthropic.claude-3-5-sonnet-20241022-v2:0` | Latest Sonnet |
| `claude-opus-4` | `anthropic.claude-opus-4-20250514-v1:0` | Latest flagship model |

## AWS Bedrock Setup

### 1. Create IAM User for Bedrock Access

```bash
# Create service account
aws iam create-user --user-name bedrock-service-account

# Attach Bedrock permissions
aws iam attach-user-policy --user-name bedrock-service-account \
  --policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess

# Create access keys
aws iam create-access-key --user-name bedrock-service-account
```

### 2. Alternative: Custom Policy (Minimal Permissions)

Create a custom policy with minimal required permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:ListFoundationModels"
      ],
      "Resource": "*"
    }
  ]
}
```

### 3. Enable Model Access in Bedrock

1. Go to AWS Bedrock console
2. Navigate to "Model access" 
3. Enable access for Claude models
4. Wait for approval (usually immediate for Claude)

## Testing the Integration

Use the provided test script to verify everything works:

```bash
cd autogen_agent

# Set your Bedrock credentials
export BEDROCK_AWS_ACCESS_KEY_ID=your_key
export BEDROCK_AWS_SECRET_ACCESS_KEY=your_secret
export BEDROCK_AWS_REGION=us-west-2

# Run the test
python test_claude_integration.py
```

## Usage Examples

### Basic Configuration

```bash
# .env file
MODEL_PROVIDER=claude
MODEL_NAME=claude-opus-4
BEDROCK_AWS_ACCESS_KEY_ID=AKIA...
BEDROCK_AWS_SECRET_ACCESS_KEY=...
BEDROCK_AWS_REGION=us-west-2
```

### Advanced Configuration

```bash
# Use different Claude model
MODEL_PROVIDER=claude
MODEL_NAME=claude-3-sonnet

# Or use specific model ID directly
MODEL_NAME=anthropic.claude-3-sonnet-20240229-v1:0
```

## Migration from USE_GEMINI

The old `USE_GEMINI` boolean is still supported for backward compatibility:

```bash
# Old way (still works)
USE_GEMINI=true

# New way (recommended)
MODEL_PROVIDER=gemini
```

## Troubleshooting

### Common Issues

1. **"AWS Bedrock error (UnauthorizedOperation)"**
   - Check your BEDROCK_AWS_ACCESS_KEY_ID and BEDROCK_AWS_SECRET_ACCESS_KEY
   - Verify IAM user has Bedrock permissions
   - Ensure you're using the correct AWS region

2. **"Model access denied"**
   - Enable model access in AWS Bedrock console
   - Wait for approval (usually immediate for Claude)

3. **"Region not supported"**
   - Claude models are available in specific regions
   - Try us-west-2 or us-east-1

4. **"Import error: claude_bedrock_client"**
   - Ensure boto3 is installed: `pip install boto3`
   - Check that claude_bedrock_client.py is in the same directory

### Debug Mode

Enable debug logging to see detailed request/response information:

```python
import logging
logging.getLogger("ClaudeBedrockClient").setLevel(logging.DEBUG)
```

## Security Best Practices

1. **Use separate AWS accounts** for Bedrock and project resources
2. **Rotate access keys** regularly (every 90 days)
3. **Use least privilege** IAM policies
4. **Store credentials securely** (consider AWS Secrets Manager for production)
5. **Monitor usage** via AWS CloudTrail and billing alerts

## Cost Considerations

Claude models have different pricing tiers:
- **Haiku**: Lowest cost, fastest
- **Sonnet**: Balanced cost/performance  
- **Opus**: Highest cost, most capable

Monitor your usage via AWS Billing dashboard.

## Architecture

```
AutoGen Bot → ClaudeBedrockClient → AWS Bedrock → Claude Model
     ↑              ↑                    ↑
   Discord     Separate AWS         Your Claude
    User       Credentials          Model Access
```

The integration maintains separation between:
- **Bedrock AWS Account**: Where Claude models are accessed
- **Project AWS Account**: Where the agent performs tasks
- **Discord Bot**: The interface layer

This ensures security isolation and proper credential management.