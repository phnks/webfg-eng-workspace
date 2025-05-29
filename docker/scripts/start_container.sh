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

# Check if docker-compose file exists
if [ ! -f "$DOCKER_DIR/docker-compose.$USERNAME.yml" ]; then
    echo "Error: Container not provisioned for $USERNAME"
    echo "Run: $SCRIPT_DIR/provision_container.sh $USERNAME <agent_type>"
    exit 1
fi

# Don't export environment variables - let docker-compose handle it via --env-file

# Start the container
cd "$PROJECT_ROOT"
docker-compose --env-file "$DOCKER_DIR/.env" -f "$DOCKER_DIR/docker-compose.$USERNAME.yml" up -d

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