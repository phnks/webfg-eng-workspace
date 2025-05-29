#!/bin/bash

# Test script for Docker setup
set -e

echo "=== Docker Setup Test Script ==="
echo "Testing all Docker functionality..."
echo

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
test_pass() {
    echo -e "${GREEN}✓ $1${NC}"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "${RED}✗ $1${NC}"
    echo "  Error: $2"
    ((TESTS_FAILED++))
}

# Change to docker directory
cd /home/anum/webfg-eng-workspace/docker

# Test 1: Check Docker is running
echo "1. Testing Docker daemon..."
if docker info >/dev/null 2>&1; then
    test_pass "Docker daemon is running"
else
    test_fail "Docker daemon check" "Docker is not running"
    exit 1
fi

# Test 2: Check docker-compose
echo -e "\n2. Testing docker-compose..."
if docker-compose version >/dev/null 2>&1; then
    test_pass "docker-compose is available"
else
    test_fail "docker-compose check" "docker-compose not found"
fi

# Test 3: Create test environment
echo -e "\n3. Setting up test environment..."
cat > .env.test << EOF
ADMIN_DISCORD_ID=123456789
DISCORD_CHANNEL_ID=987654321
BOT_TOKEN_testuser=test_token
OPENAI_API_KEY=test_key
GEMINI_API_KEY=test_key
ANTHROPIC_API_KEY=test_key
GITHUB_TOKEN=test_token
AWS_ACCESS_KEY_ID=test_id
AWS_SECRET_ACCESS_KEY=test_secret
AWS_DEFAULT_REGION=us-east-1
EOF
test_pass "Test environment created"

# Test 4: Build minimal test image
echo -e "\n4. Building minimal test image..."
if docker build -f Dockerfile.minimal -t webfg-test:latest .. > build.log 2>&1; then
    test_pass "Docker image built successfully"
else
    test_fail "Docker build" "Check build.log for details"
fi

# Test 5: Create test user compose file
echo -e "\n5. Creating test container configuration..."
cat > docker-compose.testuser.yml << EOF
version: '3.8'

services:
  agent-testuser:
    image: webfg-test:latest
    container_name: agent-testuser
    hostname: testuser
    networks:
      - agent-network
    volumes:
      - ./volumes/testuser/workspace:/home/agent/workspace
    environment:
      - USER=agent
      - AGENT_TYPE=autogen
      - DEVCHAT_HOST_IP=host.docker.internal
    extra_hosts:
      - "host.docker.internal:host-gateway"
    stdin_open: true
    tty: true

networks:
  agent-network:
    external: true
EOF
test_pass "Test container configuration created"

# Test 6: Create network
echo -e "\n6. Creating Docker network..."
if docker network create agent-network 2>/dev/null || docker network inspect agent-network >/dev/null 2>&1; then
    test_pass "Docker network ready"
else
    test_fail "Network creation" "Failed to create agent-network"
fi

# Test 7: Start container
echo -e "\n7. Starting test container..."
mkdir -p volumes/testuser/workspace
if docker-compose -f docker-compose.testuser.yml up -d; then
    test_pass "Container started"
else
    test_fail "Container start" "Failed to start container"
fi

# Test 8: Check container is running
echo -e "\n8. Verifying container status..."
sleep 3
if docker ps | grep agent-testuser >/dev/null; then
    test_pass "Container is running"
else
    test_fail "Container status" "Container is not running"
fi

# Test 9: Execute command in container
echo -e "\n9. Testing command execution..."
if docker exec agent-testuser whoami 2>/dev/null | grep -q agent; then
    test_pass "Command execution works"
else
    test_fail "Command execution" "Failed to execute command in container"
fi

# Test 10: Test volume persistence
echo -e "\n10. Testing volume persistence..."
docker exec agent-testuser bash -c "echo 'test data' > /home/agent/workspace/test.txt"
if [ -f "volumes/testuser/workspace/test.txt" ]; then
    test_pass "Volume persistence works"
else
    test_fail "Volume persistence" "File not found in volume"
fi

# Test 11: Stop container
echo -e "\n11. Testing container stop..."
if docker-compose -f docker-compose.testuser.yml down; then
    test_pass "Container stopped successfully"
else
    test_fail "Container stop" "Failed to stop container"
fi

# Test 12: Test management scripts
echo -e "\n12. Testing management scripts..."
export $(grep -v '^#' .env.test | xargs)

# Test provision script
if ./scripts/provision_container.sh testuser autogen >/dev/null 2>&1; then
    test_pass "Provision script works"
else
    test_fail "Provision script" "Failed to provision container"
fi

# Cleanup
echo -e "\n=== Cleanup ==="
docker-compose -f docker-compose.testuser.yml down 2>/dev/null || true
docker network rm agent-network 2>/dev/null || true
rm -rf volumes/testuser
rm -f docker-compose.testuser.yml
rm -f .env.test
echo "Cleanup completed"

# Summary
echo -e "\n=== Test Summary ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi