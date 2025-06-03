#!/bin/bash

# Show logs for a Docker container

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

USERNAME=$1

echo "Showing logs for container: agent-$USERNAME"
docker logs -f "agent-$USERNAME"