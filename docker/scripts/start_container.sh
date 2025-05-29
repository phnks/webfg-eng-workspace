#!/bin/bash

# Docker equivalent of start_vm.sh
# Starts a Docker container for a specific user

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

USERNAME=$1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
DOCKER_DIR="$PROJECT_ROOT/docker"

echo "Starting Docker container for user: $USERNAME"

# Check if user has been provisioned (volumes exist)
if [ ! -d "$DOCKER_DIR/volumes/$USERNAME" ]; then
    echo "Error: Container not provisioned for $USERNAME"
    echo "Run: $SCRIPT_DIR/provision_container.sh $USERNAME <agent_type>"
    exit 1
fi

# Get user's bot token and agent type from .env
BOT_TOKEN_VAR="BOT_TOKEN_${USERNAME}"
BOT_TOKEN=$(grep "^${BOT_TOKEN_VAR}=" "$DOCKER_DIR/.env" | cut -d'=' -f2-)

# Get agent type from a marker file
if [ -f "$DOCKER_DIR/volumes/$USERNAME/.agent_type" ]; then
    AGENT_TYPE=$(cat "$DOCKER_DIR/volumes/$USERNAME/.agent_type")
else
    AGENT_TYPE="autogen"  # Default
fi

# Start the container with dynamic environment variables
cd "$DOCKER_DIR"
USERNAME=$USERNAME AGENT_TYPE=$AGENT_TYPE BOT_TOKEN=$BOT_TOKEN \
docker-compose --env-file "$DOCKER_DIR/.env" up -d

# Wait for container to be ready
echo "Waiting for container to be ready..."
sleep 3

# Check if container is running
if docker ps | grep -q "agent-$USERNAME"; then
    echo "Container agent-$USERNAME is running"
    echo ""
    echo "Container started successfully!"
    echo "To view logs: docker logs -f agent-$USERNAME"
    echo "To enter container: $SCRIPT_DIR/enter_container.sh $USERNAME"
else
    echo "Error: Container failed to start"
    docker-compose -f "$DOCKER_DIR/docker-compose.$USERNAME.yml" logs
    exit 1
fi