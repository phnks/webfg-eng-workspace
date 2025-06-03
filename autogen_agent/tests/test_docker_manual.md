# Manual Docker Claude Integration Test

This document provides step-by-step instructions to manually test the Claude integration in Docker.

## Prerequisites

1. **Docker permissions**: Ensure you can run Docker commands
   ```bash
   # If needed, add user to docker group:
   sudo usermod -aG docker $USER
   newgrp docker
   ```

2. **Claude credentials**: Ensure `docker/.env` has valid Bedrock credentials

## Test Steps

### 1. Verify Configuration Files

Run this quick check to ensure all files are configured correctly:

```bash
cd /sdd/dev/webfg-eng-workspace
python3 -c "
import os
from pathlib import Path

# Check Docker .env file
docker_env = Path('docker/.env')
content = docker_env.read_text()
required_vars = ['MODEL_PROVIDER=claude', 'BEDROCK_AWS_ACCESS_KEY_ID=', 'BEDROCK_AWS_SECRET_ACCESS_KEY=']

print('📋 Docker .env configuration:')
for var in required_vars:
    if var in content:
        print(f'✅ {var}')
    else:
        print(f'❌ MISSING: {var}')

# Check docker-compose.yml
compose_file = Path('docker/docker-compose.yml')
compose_content = compose_file.read_text()
compose_vars = ['MODEL_PROVIDER', 'BEDROCK_AWS_ACCESS_KEY_ID']
print('\n📋 docker-compose.yml environment variables:')
for var in compose_vars:
    if f'- {var}=' in compose_content:
        print(f'✅ {var}')
    else:
        print(f'❌ MISSING: {var}')

print('\n🎉 Configuration check complete!')
"
```

**Expected output**: All variables should show ✅

### 2. Build Docker Image

```bash
cd docker
./scripts/build_image.sh
```

**Expected output**: 
- Image builds successfully
- No error messages about missing dependencies

### 3. Start Container with Claude

```bash
# Start container for test user
./scripts/start_container.sh testclaude
```

**Expected output**:
- Container starts successfully
- No immediate errors

### 4. Check Container Logs

```bash
# Check logs to verify Claude integration
./scripts/logs_container.sh testclaude
```

**Expected SUCCESS indicators** (should see ALL of these):
- `✅ Claude Bedrock client imported.`
- `✅ LLM config created for claude with model: anthropic.claude-3-5-sonnet-20241022-v2:0`
- `✅ AWS Bedrock client initialized successfully`
- No `❌` error indicators
- No `Traceback` or `ImportError` messages
- Should NOT see `✅ Using OpenAI client (default).`

**Example of SUCCESSFUL logs:**
```
20:49:52  INFO  discord-bot: ✅ Git/GitHub environment variables loaded.
20:49:52  INFO  discord-bot: ✅ AWS environment variables loaded.
20:49:52  INFO  discord-bot: ✅ Claude Bedrock client imported.
20:49:54  INFO  discord-bot: ✅ LLM config created for claude with model: anthropic.claude-3-5-sonnet-20241022-v2:0
20:49:54  INFO  ClaudeBedrockClient: ✅ AWS Bedrock client initialized successfully
```

### 5. Test Container Interaction (Optional)

If the container is running successfully, you can test it further:

```bash
# Enter container
docker exec -it agent-testclaude bash

# Inside container, check environment
echo "MODEL_PROVIDER: $MODEL_PROVIDER"
echo "MODEL_NAME: $MODEL_NAME"
echo "BEDROCK_AWS_REGION: $BEDROCK_AWS_REGION"

# Test Python import
python3 -c "
from autogen_discord_bot import create_llm_config
config = create_llm_config()
print(f'Model: {config[\"config_list\"][0][\"model\"]}')
print(f'API Type: {config[\"config_list\"][0][\"api_type\"]}')
"
```

### 6. Cleanup

```bash
# Stop and remove test container
docker stop agent-testclaude
docker rm agent-testclaude
```

## Troubleshooting

### Issue: Container shows OpenAI instead of Claude

**Symptoms**: Logs show `✅ Using OpenAI client (default).` and `MODEL_PROVIDER=openai`

**Fix**: Environment variables not passed through correctly
1. Check `docker/.env` has `MODEL_PROVIDER=claude`
2. Check `docker-compose.yml` has `- MODEL_PROVIDER=${MODEL_PROVIDER}`
3. Rebuild image: `./scripts/build_image.sh`
4. Restart container: `./scripts/restart_container.sh testclaude`

### Issue: ImportError about OpenAI

**Symptoms**: `ImportError: 'openai' is not installed`

**Fix**: Missing bedrock dependencies
1. Check `autogen_agent/requirements.txt` has `pyautogen[openai,gemini,bedrock]==0.9.0`
2. Rebuild image: `./scripts/build_image.sh`

### Issue: AWS Bedrock connection errors

**Symptoms**: `❌ Failed to initialize AWS Bedrock client`

**Fix**: Check AWS credentials
1. Verify `BEDROCK_AWS_ACCESS_KEY_ID` and `BEDROCK_AWS_SECRET_ACCESS_KEY` in `docker/.env`
2. Ensure IAM user has Bedrock permissions
3. Verify region is correct (`us-west-2` recommended)

## Success Criteria

✅ Container starts without errors  
✅ Logs show Claude Bedrock client imported  
✅ LLM config created for claude (not openai)  
✅ AWS Bedrock client initialized  
✅ No ImportError or Traceback messages  
✅ MODEL_PROVIDER=claude in environment  

If all criteria are met, the Claude integration is working correctly in Docker! 🎉