#!/bin/bash

# Docker equivalent of start_all_vms.sh
# Starts all provisioned Docker containers

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
DOCKER_DIR="$PROJECT_ROOT/docker"

echo "Starting all Docker containers..."

# Find all docker-compose files
for compose_file in "$DOCKER_DIR"/docker-compose.*.yml; do
    if [ -f "$compose_file" ]; then
        # Extract username from filename
        filename=$(basename "$compose_file")
        USERNAME="${filename#docker-compose.}"
        USERNAME="${USERNAME%.yml}"
        
        if [ "$USERNAME" != "*" ]; then
            echo "Starting container for $USERNAME..."
            "$SCRIPT_DIR/start_container.sh" "$USERNAME"
            echo ""
        fi
    fi
done

echo "All containers started"