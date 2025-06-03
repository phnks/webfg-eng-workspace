# AutoGen Discord Bot

An AI-powered Discord bot using Microsoft AutoGen framework with support for multiple language models.

## Features

- **Multi-Model Support**: OpenAI (GPT-4), Google Gemini, and Claude (via AWS Bedrock)
- **Code Execution**: Safe sandboxed execution with multiple language support
- **Discord Integration**: Full Discord bot with slash commands
- **Flexible Configuration**: Easy model switching via environment variables

## Quick Start

### 1. Setup Python Environment

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. Configure Environment

Copy `.env.template` to `.env` and configure your settings:

```bash
cp .env.template .env
```

Key configuration options:

```bash
# Choose your model provider
MODEL_PROVIDER=openai    # or gemini, claude
MODEL_NAME=gpt-4o        # optional, uses defaults

# Configure your chosen provider
OPENAI_API_KEY=sk-...               # For OpenAI
GEMINI_API_KEYS=key1,key2,key3      # For Gemini (comma-separated)
BEDROCK_AWS_ACCESS_KEY_ID=...       # For Claude via AWS Bedrock
```

### 3. Run the Bot

```bash
./start_agent.sh
```

## Model Providers

### OpenAI (Default)

```bash
MODEL_PROVIDER=openai
MODEL_NAME=gpt-4o              # or gpt-4-turbo, gpt-3.5-turbo
OPENAI_API_KEY=sk-...
```

### Google Gemini

```bash
MODEL_PROVIDER=gemini
MODEL_NAME=gemini-2.5-pro-exp-03-25  # or any Gemini model
GEMINI_API_KEYS=key1,key2,key3       # Multiple keys for rotation
```

### Claude (AWS Bedrock)

```bash
MODEL_PROVIDER=claude
MODEL_NAME=claude-opus-4       # or claude-3-sonnet, claude-3-haiku

# Separate AWS credentials for Bedrock
BEDROCK_AWS_ACCESS_KEY_ID=AKIA...
BEDROCK_AWS_SECRET_ACCESS_KEY=...
BEDROCK_AWS_REGION=us-west-2
```

#### Available Claude Models

| Model Name | Description |
|------------|-------------|
| `claude-3-haiku` | Fast, cost-effective |
| `claude-3-sonnet` | Balanced performance |
| `claude-3-opus` | Most capable Claude 3 |
| `claude-3-5-sonnet` | Enhanced Sonnet |
| `claude-3-5-sonnet-v2` | Latest Sonnet |
| `claude-opus-4` | Latest flagship model |

#### AWS Bedrock Setup

1. **Create IAM User**
   ```bash
   aws iam create-user --user-name bedrock-service-account
   aws iam attach-user-policy --user-name bedrock-service-account \
     --policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess
   ```

2. **Create Access Keys**
   ```bash
   aws iam create-access-key --user-name bedrock-service-account
   ```

3. **Enable Model Access**
   - Go to AWS Bedrock console
   - Navigate to "Model access"
   - Enable Claude models
   - Wait for approval (usually immediate)

## Discord Commands

- `/status` - Check bot status
- `/restart` - Restart the agent
- `/stop` - Stop the agent
- `/logs [n]` - Show last n log lines (default: 50)
- `/interrupt` - Cancel current task

## Testing

Run tests to verify your configuration:

```bash
# Test Claude integration
python tests/test_claude_integration.py

# View logs
./get_logs.sh
```

## Environment Variables

### Required
- `DISCORD_BOT_TOKEN` - Your Discord bot token
- `BOT_USER` - Bot username
- `AGENT_HOME` - Path to agent directory

### Model Configuration
- `MODEL_PROVIDER` - Choose: `openai`, `gemini`, or `claude`
- `MODEL_NAME` - Specific model name (optional)

### Provider-Specific
- **OpenAI**: `OPENAI_API_KEY`
- **Gemini**: `GEMINI_API_KEYS` (comma-separated)
- **Claude**: `BEDROCK_AWS_ACCESS_KEY_ID`, `BEDROCK_AWS_SECRET_ACCESS_KEY`, `BEDROCK_AWS_REGION`

### Project AWS (separate from Bedrock)
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` - For agent tasks
- `AWS_REGION`, `AWS_DEFAULT_REGION`, `AWS_ACCOUNT_ID`

### Git/GitHub
- `GIT_USERNAME`, `GIT_TOKEN`, `GH_TOKEN`

## Architecture

```
Discord User → Discord Bot → AutoGen Framework → Model Provider
                                ↓
                        Code Executor (Sandboxed)
```

For Claude:
```
AutoGen Bot → ClaudeBedrockClient → AWS Bedrock → Claude Model
     ↑              ↑                    ↑
   Discord     Separate AWS         Your Claude
    User       Credentials          Model Access
```

## Troubleshooting

### Claude/Bedrock Issues

1. **"AWS Bedrock error (UnauthorizedOperation)"**
   - Verify BEDROCK_AWS_* credentials
   - Check IAM permissions
   - Ensure correct region

2. **"Model access denied"**
   - Enable model in Bedrock console
   - Wait for approval

3. **"Import error: boto3"**
   - Run: `pip install boto3`

### General Issues

- **Bot not responding**: Check `DISCORD_BOT_TOKEN`
- **Model errors**: Verify API keys and MODEL_PROVIDER
- **Code execution failing**: Check sandboxing and permissions

## Security Notes

- Keep separate AWS accounts for Bedrock and project resources
- Rotate API keys regularly
- Use environment variables, never commit credentials
- Monitor usage and costs

## Scripts

- `start_agent.sh` - Start the bot
- `stop_agent.sh` - Stop the bot
- `restart_agent.sh` - Restart the bot
- `status_agent.sh` - Check status
- `get_logs.sh` - View logs