#!/bin/bash

# Docker equivalent of provision_vm.sh
# Creates or updates a Docker container for a specific user

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <username> <agent_type>"
    echo "agent_type: autogen or claude-code"
    exit 1
fi

USERNAME=$1
AGENT_TYPE=$2
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
DOCKER_DIR="$PROJECT_ROOT/docker"

echo "Provisioning Docker container for user: $USERNAME with agent type: $AGENT_TYPE"

# Validate agent type
if [[ "$AGENT_TYPE" != "autogen" && "$AGENT_TYPE" != "claude-code" ]]; then
    echo "Error: agent_type must be 'autogen' or 'claude-code'"
    exit 1
fi

# Check if user is in dev_users.txt
if ! grep -q "^${USERNAME}$" "$PROJECT_ROOT/config/dev_users.txt"; then
    echo "Error: User $USERNAME not found in config/dev_users.txt"
    exit 1
fi

# Create volumes directories
echo "Creating volume directories..."
mkdir -p "$DOCKER_DIR/volumes/$USERNAME"/{workspace,claude,config,ssh,autogen_logs}

# Copy SSH keys if they exist
if [ -d "$HOME/.ssh" ]; then
    echo "Copying SSH keys..."
    cp -r "$HOME/.ssh" "$DOCKER_DIR/volumes/$USERNAME/ssh/"
    chmod 700 "$DOCKER_DIR/volumes/$USERNAME/ssh"
    chmod 600 "$DOCKER_DIR/volumes/$USERNAME/ssh"/*
fi

# Copy git config if it exists
if [ -f "$HOME/.gitconfig" ]; then
    echo "Copying git config..."
    cp "$HOME/.gitconfig" "$DOCKER_DIR/volumes/$USERNAME/gitconfig"
fi

# Create user-specific docker-compose file
echo "Creating docker-compose file for $USERNAME..."
TEMPLATE_FILE="$DOCKER_DIR/docker-compose.template.yml"

# Use more specific replacements to avoid replacing the args key
cat "$TEMPLATE_FILE" | \
    sed "s/agent-USERNAME/agent-$USERNAME/g" | \
    sed "s/hostname: USERNAME/hostname: $USERNAME/g" | \
    sed "s/volumes\/USERNAME/volumes\/$USERNAME/g" | \
    sed "s/USER=USERNAME/USER=$USERNAME/g" | \
    sed "s/BOT_TOKEN_USERNAME/BOT_TOKEN_$USERNAME/g" | \
    sed "s/USERNAME: USERNAME/USERNAME: $USERNAME/g" | \
    sed "s/AGENT_TYPE-agent/$AGENT_TYPE-agent/g" | \
    sed "s/AGENT_TYPE=AGENT_TYPE/AGENT_TYPE=$AGENT_TYPE/g" > "$DOCKER_DIR/docker-compose.$USERNAME.yml"

# Create network if it doesn't exist
if ! docker network inspect agent-network >/dev/null 2>&1; then
    echo "Creating Docker network..."
    docker network create --subnet=172.20.0.0/16 agent-network
fi

# Load environment variables from docker .env (priority)
if [ -f "$DOCKER_DIR/.env" ]; then
    export $(grep -v '^#' "$DOCKER_DIR/.env" | xargs)
    echo "Loaded environment variables from docker/.env"
fi

# Load environment variables from host service .env (fallback)
if [ -f "$PROJECT_ROOT/host_service/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/host_service/.env" | xargs)
fi

# Load environment variables from autogen .env (fallback)
if [ -f "$PROJECT_ROOT/autogen_agent/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/autogen_agent/.env" | xargs)
fi

# Build the Docker image
echo "Building Docker image..."
cd "$DOCKER_DIR"
docker build -t webfg:latest .

# Container will use entrypoint script instead of custom start script

# Create MCP config for Claude Code
if [ "$AGENT_TYPE" = "claude-code" ]; then
    mkdir -p "$DOCKER_DIR/volumes/$USERNAME/claude"
    cat > "$DOCKER_DIR/volumes/$USERNAME/claude/mcp-config.json" << EOF
{
  "servers": {
    "discord": {
      "command": "node",
      "args": ["/home/$USERNAME/discord-mcp/dist/index.js"],
      "env": {
        "DISCORD_BOT_TOKEN": "\${BOT_TOKEN_$USERNAME}",
        "DISCORD_CHANNEL_ID": "\${DISCORD_CHANNEL_ID}"
      }
    }
  }
}
EOF
fi

echo "Container provisioning complete for $USERNAME"
echo ""
echo "To start the container, run:"
echo "  $SCRIPT_DIR/start_container.sh $USERNAME"
echo ""
echo "To enter the container, run:"
echo "  $SCRIPT_DIR/enter_container.sh $USERNAME"