#!/bin/bash

# Test script for Docker image build

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
DOCKER_DIR="$PROJECT_ROOT/docker"

echo "=== Testing Docker Image Build ==="
echo ""

# Function to print test results
print_result() {
    local test_name=$1
    local result=$2
    if [ $result -eq 0 ]; then
        echo "✓ $test_name: PASSED"
    else
        echo "✗ $test_name: FAILED"
        exit 1
    fi
}

# Test 1: Check Dockerfile exists
echo "Test 1: Checking Dockerfile exists..."
if [ -f "$DOCKER_DIR/Dockerfile" ]; then
    print_result "Dockerfile exists" 0
else
    print_result "Dockerfile exists" 1
fi

# Test 2: Check required source directories exist
echo ""
echo "Test 2: Checking required source directories..."
missing_dirs=0
for dir in "autogen_agent" "mcp_servers/discord-mcp" "vm_cli"; do
    if [ ! -d "$PROJECT_ROOT/$dir" ]; then
        echo "  Missing: $dir"
        missing_dirs=1
    else
        echo "  Found: $dir"
    fi
done
print_result "Required directories exist" $missing_dirs

# Test 3: Build the Docker image (autogen stage)
echo ""
echo "Test 3: Building Docker image (autogen stage)..."
cd "$PROJECT_ROOT"
if docker build \
    -f "$DOCKER_DIR/Dockerfile" \
    --target autogen-agent \
    -t webfg-quick:autogen-test \
    . >/dev/null 2>&1; then
    print_result "Docker build autogen stage" 0
else
    echo "Build failed. Running with verbose output:"
    docker build \
        -f "$DOCKER_DIR/Dockerfile" \
        --target autogen-agent \
        -t webfg-quick:autogen-test \
        .
    print_result "Docker build autogen stage" 1
fi

# Test 4: Build the Docker image (claude-code stage)
echo ""
echo "Test 4: Building Docker image (claude-code stage)..."
if docker build \
    -f "$DOCKER_DIR/Dockerfile" \
    --target claude-code-agent \
    -t webfg-quick:claude-code-test \
    . >/dev/null 2>&1; then
    print_result "Docker build claude-code stage" 0
else
    echo "Build failed. Running with verbose output:"
    docker build \
        -f "$DOCKER_DIR/Dockerfile" \
        --target claude-code-agent \
        -t webfg-quick:claude-code-test \
        .
    print_result "Docker build claude-code stage" 1
fi

# Test 5: Verify agent user was created properly in the image
echo ""
echo "Test 5: Verifying agent user in Docker image..."
if docker run --rm webfg-quick:autogen-test id agent >/dev/null 2>&1; then
    print_result "Agent user exists in image" 0
else
    print_result "Agent user exists in image" 1
fi

# Test 6: Verify directories were created
echo ""
echo "Test 6: Verifying directories in Docker image..."
if docker run --rm webfg-quick:autogen-test ls -la /home/agent/.claude >/dev/null 2>&1; then
    print_result "Required directories exist in image" 0
else
    print_result "Required directories exist in image" 1
fi

# Clean up test images
echo ""
echo "Cleaning up test images..."
docker rmi webfg-quick:autogen-test webfg-quick:claude-code-test >/dev/null 2>&1 || true

echo ""
echo "=== All Docker build tests passed! ==="