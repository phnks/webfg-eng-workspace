#!/bin/bash

# Alternative container startup script using docker run instead of docker-compose
# This avoids Docker Compose v1.x compatibility issues with the 'ContainerConfig' error

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

USERNAME=$1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
DOCKER_DIR="$PROJECT_ROOT/docker"

echo "🚀 Starting Docker container for user: $USERNAME (using docker run)"

# Check if user has been provisioned (volumes exist)
if [ ! -d "$DOCKER_DIR/volumes/$USERNAME" ]; then
    echo "❌ Error: Container not provisioned for $USERNAME"
    echo "Run: $SCRIPT_DIR/provision_container.sh $USERNAME autogen"
    exit 1
fi

# Load environment variables from .env file
if [ ! -f "$DOCKER_DIR/.env" ]; then
    echo "❌ Error: .env file not found at $DOCKER_DIR/.env"
    exit 1
fi

# Source the .env file to get variables
set -a  # automatically export all variables
source "$DOCKER_DIR/.env"
set +a

# Get user's bot token
BOT_TOKEN_VAR="BOT_TOKEN_${USERNAME}"
BOT_TOKEN=$(grep "^${BOT_TOKEN_VAR}=" "$DOCKER_DIR/.env" | cut -d'=' -f2-)

if [ -z "$BOT_TOKEN" ]; then
    echo "❌ Error: Bot token not found for user $USERNAME"
    echo "Expected variable: $BOT_TOKEN_VAR in $DOCKER_DIR/.env"
    exit 1
fi

# Stop and remove existing container if it exists
echo "🧹 Cleaning up existing container..."
sudo docker stop agent-$USERNAME 2>/dev/null || echo "No existing container to stop"
sudo docker rm agent-$USERNAME 2>/dev/null || echo "No existing container to remove"

# Create network if it doesn't exist
echo "🌐 Ensuring Docker network exists..."
sudo docker network create agent-network 2>/dev/null || echo "Network already exists"

# Start container using docker run
echo "🚀 Starting container agent-$USERNAME..."

sudo docker run -d \
    --name agent-$USERNAME \
    --hostname $USERNAME \
    --network agent-network \
    --restart unless-stopped \
    --add-host host.docker.internal:host-gateway \
    -v "$DOCKER_DIR/volumes/$USERNAME/workspace:/home/agent/workspace" \
    -v "$DOCKER_DIR/volumes/$USERNAME/config:/home/agent/.config" \
    -v "$DOCKER_DIR/volumes/$USERNAME/ssh:/home/agent/.ssh:ro" \
    -v "$DOCKER_DIR/volumes/$USERNAME/gitconfig:/home/agent/.gitconfig:ro" \
    -v "$PROJECT_ROOT/autogen_agent:/home/agent/autogen_agent:ro" \
    -v "$PROJECT_ROOT/mcp_servers/discord-mcp:/home/agent/discord-mcp:ro" \
    -v "$DOCKER_DIR/docker-entrypoint.sh:/home/agent/entrypoint.sh:ro" \
    -e USER=$USERNAME \
    -e DISCORD_BOT_TOKEN=$BOT_TOKEN \
    -e DISCORD_CHANNEL_ID=$DISCORD_CHANNEL_ID \
    -e MODEL_PROVIDER=$MODEL_PROVIDER \
    -e MODEL_NAME=$MODEL_NAME \
    -e OPENAI_API_KEY=$OPENAI_API_KEY \
    -e GEMINI_API_KEY="$GEMINI_API_KEYS" \
    -e USE_GEMINI=$USE_GEMINI \
    -e BEDROCK_AWS_ACCESS_KEY_ID=$BEDROCK_AWS_ACCESS_KEY_ID \
    -e BEDROCK_AWS_SECRET_ACCESS_KEY=$BEDROCK_AWS_SECRET_ACCESS_KEY \
    -e BEDROCK_AWS_REGION=$BEDROCK_AWS_REGION \
    -e GITHUB_TOKEN=$GITHUB_TOKEN \
    -e GIT_USERNAME=$GIT_USERNAME \
    -e GIT_TOKEN=$GITHUB_TOKEN \
    -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    -e AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION \
    -e AWS_REGION=$AWS_DEFAULT_REGION \
    -e AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID \
    --entrypoint /home/agent/entrypoint.sh \
    webfg-eng-autogen:latest

# Wait for container to be ready
echo "⏳ Waiting for container to be ready..."
sleep 5

# Check if container is running
if sudo docker ps | grep -q "agent-$USERNAME"; then
    echo "✅ Container agent-$USERNAME is running"
    echo ""
    echo "🎉 Container started successfully!"
    echo ""
    echo "📝 Useful commands:"
    echo "  View logs: sudo docker logs -f agent-$USERNAME"
    echo "  Enter container: sudo docker exec -it agent-$USERNAME bash"
    echo "  Stop container: sudo docker stop agent-$USERNAME"
    echo ""
    echo "📊 To check if Claude integration is working:"
    echo "  ./scripts/logs_container.sh $USERNAME"
    echo "  Look for: '✅ Claude Bedrock client imported' and '✅ LLM config created for claude'"
else
    echo "❌ Error: Container failed to start"
    echo "Getting container logs..."
    sudo docker logs agent-$USERNAME
    exit 1
fi