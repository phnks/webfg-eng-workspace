#!/bin/bash

# Build the Docker image for agent containers

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
DOCKER_DIR="$PROJECT_ROOT/docker"

echo "Building Docker image webfg-quick:latest..."

# Build the image from the project root to include all necessary files
cd "$PROJECT_ROOT"

# Build both stages and tag the final one
docker build \
    -f "$DOCKER_DIR/Dockerfile" \
    --target autogen-agent \
    -t webfg-quick:autogen \
    .

docker build \
    -f "$DOCKER_DIR/Dockerfile" \
    --target claude-code-agent \
    -t webfg-quick:claude-code \
    .

# Create a generic tag that points to autogen by default
docker tag webfg-quick:autogen webfg-quick:latest

echo "Docker image built successfully!"
echo "Available images:"
echo "  - webfg-quick:latest (default, points to autogen)"
echo "  - webfg-quick:autogen"
echo "  - webfg-quick:claude-code"