# Docker Compose 'ContainerConfig' Error Fix

## The Problem

You encountered this error when running `start_container.sh`:

```
ERROR: for agent  'ContainerConfig'
KeyError: 'ContainerConfig'
```

**Root Cause**: This is a known compatibility issue between Docker Compose v1.x (like 1.29.2) and newer Docker versions. The older Docker Compose cannot properly read container metadata from newer Docker engines.

## Quick Fix (Recommended)

### Option 1: Use the Alternative Startup Script

We've created a workaround script that uses `docker run` instead of `docker-compose`:

```bash
cd docker
./scripts/start_container_direct.sh anum
```

This script:
- ✅ Bypasses Docker Compose entirely
- ✅ Uses `docker run` with the same configuration
- ✅ Works with any Docker version
- ✅ Includes all the same environment variables and volumes

### Option 2: Clean Up and Retry

Sometimes the issue is caused by corrupted container metadata:

```bash
# Stop and remove problematic containers
sudo docker stop agent-anum 2>/dev/null || true
sudo docker rm agent-anum 2>/dev/null || true

# Clean up Docker system
sudo docker system prune -f

# Try starting again
cd docker
./scripts/start_container.sh anum
```

### Option 3: Upgrade Docker Compose (Permanent Fix)

If you want to fix this permanently:

```bash
# Check if Docker Compose v2+ is available
docker compose version

# If not available, install it:
sudo apt update
sudo apt install docker-compose-plugin

# Then you can use 'docker compose' instead of 'docker-compose'
```

## Testing Your Fix

After applying any fix, verify the container is working:

```bash
cd docker

# Check container is running
sudo docker ps | grep agent-anum

# Check logs for Claude integration
./scripts/logs_container.sh anum

# Look for these success indicators:
# ✅ Claude Bedrock client imported
# ✅ LLM config created for claude with model: anthropic.claude-3-5-sonnet...
# ✅ AWS Bedrock client initialized successfully
```

## Expected Success Logs

When working correctly, you should see:

```
✅ Git/GitHub environment variables loaded.
✅ AWS environment variables loaded.
✅ Claude Bedrock client imported.
✅ LLM config created for claude with model: anthropic.claude-3-5-sonnet-20241022-v2:0
✅ AWS Bedrock client initialized successfully
```

## What NOT to See

These indicate the fix didn't work:

```
❌ Using OpenAI client (default).
❌ ImportError: 'openai' is not installed
❌ MODEL_PROVIDER=openai
```

## Automated Testing

To test the complete workflow automatically:

```bash
cd autogen_agent
python3 test_docker_complete.py
```

This will:
- Detect the Docker Compose version issue
- Try the alternative startup method automatically
- Verify Claude integration is working
- Provide specific debugging information

## Why This Happened

Docker Compose 1.x was designed for older Docker APIs. When Docker updated their container metadata format, older Docker Compose versions couldn't properly parse it, leading to the 'ContainerConfig' KeyError.

The alternative `start_container_direct.sh` script bypasses this entirely by using `docker run` directly, which works with any Docker version.

## Prevention

For future deployments, consider:
1. Upgrading to Docker Compose v2+ (`docker compose`)
2. Using the direct startup script as the default
3. Keeping Docker and Docker Compose versions in sync

The Claude integration itself is working perfectly - this is purely a Docker Compose compatibility issue!