#!/bin/bash

# Docker equivalent of destroy_vm.sh
# Destroys a Docker container and its volumes for a specific user

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

USERNAME=$1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
DOCKER_DIR="$PROJECT_ROOT/docker"

echo "WARNING: This will destroy the Docker container and all data for user: $USERNAME"
read -p "Are you sure? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Stop container if running
if docker ps | grep -q "agent-$USERNAME"; then
    echo "Stopping container..."
    "$SCRIPT_DIR/stop_container.sh" "$USERNAME"
fi

# Remove container
if docker ps -a | grep -q "agent-$USERNAME"; then
    echo "Removing container..."
    docker rm -f "agent-$USERNAME" 2>/dev/null || true
fi

# Remove volumes
if [ -d "$DOCKER_DIR/volumes/$USERNAME" ]; then
    echo "Removing volume directories..."
    rm -rf "$DOCKER_DIR/volumes/$USERNAME"
fi

# Remove docker-compose file
if [ -f "$DOCKER_DIR/docker-compose.$USERNAME.yml" ]; then
    echo "Removing docker-compose file..."
    rm -f "$DOCKER_DIR/docker-compose.$USERNAME.yml"
fi

echo "Container and data for $USERNAME destroyed"