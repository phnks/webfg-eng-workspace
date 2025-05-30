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
    # Copy contents of .ssh directory, not the directory itself
    cp -r "$HOME/.ssh"/* "$DOCKER_DIR/volumes/$USERNAME/ssh/" 2>/dev/null || true
    # Only chmod if files were actually copied
    if [ "$(ls -A "$DOCKER_DIR/volumes/$USERNAME/ssh/" 2>/dev/null)" ]; then
        chmod 700 "$DOCKER_DIR/volumes/$USERNAME/ssh"
        chmod 600 "$DOCKER_DIR/volumes/$USERNAME/ssh"/* 2>/dev/null || true
    fi
fi

# Copy git config if it exists
if [ -f "$HOME/.gitconfig" ]; then
    echo "Copying git config..."
    cp "$HOME/.gitconfig" "$DOCKER_DIR/volumes/$USERNAME/gitconfig"
fi

# No need to create user-specific docker-compose file anymore
# The main docker-compose.yml is dynamic and uses environment variables

# Create network if it doesn't exist
if ! docker network inspect agent-network >/dev/null 2>&1; then
    echo "Creating Docker network..."
    docker network create --subnet=172.20.0.0/16 agent-network
fi

# Don't export environment variables - docker-compose will use --env-file
echo "Using environment variables from docker/.env"

# Store agent type for future use
echo "$AGENT_TYPE" > "$DOCKER_DIR/volumes/$USERNAME/.agent_type"

# Check if Docker image exists
if ! docker image inspect webfg-quick:latest >/dev/null 2>&1; then
    echo "Warning: Docker image webfg-quick:latest not found!"
    echo "Please build the image first by running:"
    echo "  $SCRIPT_DIR/build_image.sh"
    echo ""
    echo "Or you can build it now with: sudo $SCRIPT_DIR/build_image.sh"
    exit 1
else
    echo "Using existing Docker image..."
fi

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