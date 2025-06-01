#!/bin/bash

# Build the Docker image for agent containers

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
DOCKER_DIR="$PROJECT_ROOT/docker"

echo "Building Docker image webfg-eng-autogen:latest..."

# Build the image from the project root to include all necessary files
cd "$PROJECT_ROOT"

# Build the AutoGen agent image
docker build \
    -f "$DOCKER_DIR/Dockerfile" \
    --target autogen-agent \
    -t webfg-eng-autogen:latest \
    .

echo "Docker image built successfully!"
echo "Available images:"
echo "  - webfg-eng-autogen:latest"