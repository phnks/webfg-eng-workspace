#!/bin/bash

# Enter a running Docker container for a specific user

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

USERNAME=$1
CONTAINER_NAME="agent-$USERNAME"

# Check if container is running
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo "Error: Container $CONTAINER_NAME is not running"
    echo "Start it with: ./start_container.sh $USERNAME"
    exit 1
fi

echo "Entering container $CONTAINER_NAME..."
docker exec -it "$CONTAINER_NAME" /bin/bash