#!/bin/bash

# Test script to validate the Docker container permission fix
set -e

echo "=== Testing Docker Container Permission Fix ==="
echo ""

# Check if running as correct user (requires sudo to run docker commands)
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo) to access Docker daemon"
   exit 1
fi

USERNAME="homonculus"
CONTAINER_NAME="agent-$USERNAME"

echo "1. Checking if container exists..."
if docker ps -a | grep -q "$CONTAINER_NAME"; then
    echo "✓ Container $CONTAINER_NAME exists"
    
    # Check container status
    if docker ps | grep -q "$CONTAINER_NAME"; then
        echo "✓ Container is running"
        
        echo ""
        echo "2. Testing workspace permissions..."
        
        # Test if we can create a file in workspace
        echo "Testing file creation in workspace..."
        docker exec "$CONTAINER_NAME" bash -c "echo 'Permission test' > /home/agent/workspace/permission-test.txt"
        
        if [ -f "/sdd/dev/webfg-eng-workspace/docker/volumes/$USERNAME/workspace/permission-test.txt" ]; then
            echo "✓ File creation successful - permissions are working"
            
            # Clean up test file
            docker exec "$CONTAINER_NAME" rm -f /home/agent/workspace/permission-test.txt
        else
            echo "✗ File creation failed - permission issue persists"
        fi
        
        echo ""
        echo "3. Checking .env file creation..."
        if docker exec "$CONTAINER_NAME" test -f /home/agent/workspace/.env; then
            echo "✓ .env file exists"
            echo "Environment variables in .env:"
            docker exec "$CONTAINER_NAME" head -3 /home/agent/workspace/.env
        else
            echo "✗ .env file does not exist"
        fi
        
        echo ""
        echo "4. Checking container logs for errors..."
        echo "Recent container logs:"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -10
        
    else
        echo "✗ Container exists but is not running"
        echo "Container status:"
        docker ps -a | grep "$CONTAINER_NAME"
    fi
else
    echo "✗ Container $CONTAINER_NAME does not exist"
    echo "Available containers:"
    docker ps -a
fi

echo ""
echo "=== Test Complete ==="