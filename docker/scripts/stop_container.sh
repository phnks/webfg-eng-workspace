#!/bin/bash

# Docker equivalent of stop_vm.sh
# Stops a Docker container for a specific user

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

USERNAME=$1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
DOCKER_DIR="$PROJECT_ROOT/docker"

echo "Stopping Docker container for user: $USERNAME"

# Check if user has been provisioned (volumes exist)
if [ ! -d "$DOCKER_DIR/volumes/$USERNAME" ]; then
    echo "Error: Container not provisioned for $USERNAME"
    exit 1
fi

# Stop the container
cd "$DOCKER_DIR"
USERNAME=$USERNAME docker-compose --env-file "$DOCKER_DIR/.env" down

echo "Container agent-$USERNAME stopped"