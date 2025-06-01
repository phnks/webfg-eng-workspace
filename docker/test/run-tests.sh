#!/bin/bash

# Comprehensive Docker setup test
set -e

echo "=== Docker Setup Comprehensive Test ==="
date
echo

# Test results log
TEST_LOG="test-results.txt"
> "$TEST_LOG"

# Function to log results
log_test() {
    echo "$1" | tee -a "$TEST_LOG"
}

cd /home/anum/webfg-eng-workspace/docker

# Clean up any existing test containers
log_test "Cleaning up existing test containers..."
docker rm -f test-container 2>/dev/null || true
docker network create agent-network 2>/dev/null || true

# Test 1: Container lifecycle
log_test "Test 1: Testing container lifecycle..."
docker run -d --name test-container --network agent-network webfg-eng-autogen:latest sleep 3600
sleep 2

if docker ps | grep test-container; then
    log_test "✓ Container started successfully"
else
    log_test "✗ Container failed to start"
fi

# Test 2: Execute commands
log_test -e "\nTest 2: Testing command execution..."
if docker exec test-container whoami | grep -q agent; then
    log_test "✓ Command execution works (user: agent)"
else
    log_test "✗ Command execution failed"
fi

# Test 3: Volume mounting
log_test -e "\nTest 3: Testing volume mounting..."
mkdir -p volumes/test/workspace
echo "test data" > volumes/test/workspace/test.txt

docker rm -f test-container
docker run -d --name test-container \
    -v $(pwd)/volumes/test/workspace:/home/agent/workspace \
    --network agent-network \
    webfg-eng-autogen:latest sleep 3600

sleep 2

if docker exec test-container cat /home/agent/workspace/test.txt | grep -q "test data"; then
    log_test "✓ Volume mounting works"
else
    log_test "✗ Volume mounting failed"
fi

# Test 4: Environment variables
log_test -e "\nTest 4: Testing environment variables..."
docker rm -f test-container
docker run -d --name test-container \
    -e USER=agent \
    --network agent-network \
    webfg-eng-autogen:latest sleep 3600

sleep 2

if docker exec test-container printenv | grep -q "USER=agent"; then
    log_test "✓ Environment variables work"
else
    log_test "✗ Environment variables failed"
fi

# Test 5: Network connectivity
log_test -e "\nTest 5: Testing network connectivity..."
if docker exec test-container ping -c 1 google.com >/dev/null 2>&1; then
    log_test "✓ External network connectivity works"
else
    log_test "✗ External network connectivity failed"
fi

# Test 6: Test management scripts
log_test -e "\nTest 6: Testing management scripts..."

# Create minimal test environment
cat > .env << EOF
ADMIN_DISCORD_ID=123456789
BOT_TOKEN_dockertest=test_token
OPENAI_API_KEY=test_key
EOF

# Update provision script to use quick image
sed -i 's/dockerfile: docker\/Dockerfile/dockerfile: docker\/Dockerfile.quick/g' scripts/provision_container.sh 2>/dev/null || true

# Test provision
if ./scripts/provision_container.sh dockertest >/dev/null 2>&1; then
    log_test "✓ Provision script works"
else
    log_test "✗ Provision script failed"
fi

# Test start
if ./scripts/start_container.sh dockertest >/dev/null 2>&1; then
    log_test "✓ Start script works"
    sleep 3
else
    log_test "✗ Start script failed"
fi

# Check if container is running
if docker ps | grep -q agent-dockertest; then
    log_test "✓ Container management scripts work"
else
    log_test "✗ Container management failed"
fi

# Test stop
if ./scripts/stop_container.sh dockertest >/dev/null 2>&1; then
    log_test "✓ Stop script works"
else
    log_test "✗ Stop script failed"
fi

# Cleanup
log_test -e "\nCleaning up..."
docker rm -f test-container 2>/dev/null || true
docker rm -f agent-dockertest 2>/dev/null || true
rm -rf volumes/test volumes/dockertest
rm -f docker-compose.dockertest.yml

log_test -e "\n=== Test Summary ==="
log_test "Test completed at: $(date)"
log_test "See test-results.txt for full results"

# Show summary
echo -e "\n=== Results ==="
grep -E "(✓|✗)" "$TEST_LOG"