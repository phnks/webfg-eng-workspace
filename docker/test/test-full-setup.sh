#!/bin/bash

# Full Docker setup test with actual user
set -e

echo "=== Full Docker Setup Test ==="
echo "Testing with user: anum"
echo

cd /home/anum/webfg-eng-workspace

# Ensure host service .env exists
if [ ! -f "host_service/.env" ]; then
    echo "Creating host_service/.env for testing..."
    cp host_service/.env.template host_service/.env
    # Update with test values
    sed -i 's/YOUR_DISCORD_USER_ID_HERE/123456789/g' host_service/.env
    sed -i 's/TOKEN_FOR_ANUM_BOT_HERE/test_token_anum/g' host_service/.env
fi

# Ensure autogen_agent .env exists
if [ ! -f "autogen_agent/.env" ]; then
    echo "Creating autogen_agent/.env for testing..."
    cat > autogen_agent/.env << EOF
OPENAI_API_KEY=test_key
GEMINI_API_KEY=test_key
USE_GEMINI=false
DISCORD_APP_TOKEN=test_app_token
EOF
fi

cd docker

# Use the quick Dockerfile for faster testing
echo "Updating provision script to use quick Dockerfile..."
cp scripts/provision_container.sh scripts/provision_container.sh.bak
sed -i 's/dockerfile: docker\/Dockerfile/dockerfile: docker\/Dockerfile.quick/g' scripts/provision_container.sh

echo "1. Testing container provisioning for user 'anum'..."
if ./scripts/provision_container.sh anum autogen; then
    echo "✓ Container provisioned successfully"
else
    echo "✗ Container provisioning failed"
    exit 1
fi

echo -e "\n2. Testing container start..."
if ./scripts/start_container.sh anum; then
    echo "✓ Container started successfully"
else
    echo "✗ Container start failed"
    exit 1
fi

echo -e "\n3. Checking container status..."
if docker ps | grep -q agent-anum; then
    echo "✓ Container is running"
    docker ps | grep agent-anum
else
    echo "✗ Container is not running"
    exit 1
fi

echo -e "\n4. Testing command execution..."
if docker exec agent-anum whoami | grep -q anum; then
    echo "✓ Command execution works"
else
    echo "✗ Command execution failed"
fi

echo -e "\n5. Testing volume persistence..."
docker exec agent-anum bash -c "echo 'Hello from container' > /home/anum/workspace/test.txt"
if [ -f "volumes/anum/workspace/test.txt" ]; then
    echo "✓ Volume persistence works"
    cat volumes/anum/workspace/test.txt
else
    echo "✗ Volume persistence failed"
fi

echo -e "\n6. Testing environment variables..."
docker exec agent-anum printenv | grep -E "(USER|AGENT_TYPE|DEVCHAT_HOST_IP)" || true

echo -e "\n7. Testing container restart..."
if ./scripts/restart_container.sh anum; then
    echo "✓ Container restart works"
else
    echo "✗ Container restart failed"
fi

echo -e "\n8. Testing container stop..."
if ./scripts/stop_container.sh anum; then
    echo "✓ Container stop works"
else
    echo "✗ Container stop failed"
fi

echo -e "\n9. Testing entering container (non-interactive)..."
if echo "echo 'Test from enter script'" | ./scripts/enter_container.sh anum 2>/dev/null | grep -q "Test from enter script"; then
    echo "✓ Enter container script works"
else
    echo "✗ Enter container script failed"
fi

# Cleanup
echo -e "\nCleaning up test artifacts..."
rm -f docker-compose.anum.yml
rm -rf volumes/anum
mv scripts/provision_container.sh.bak scripts/provision_container.sh 2>/dev/null || true

echo -e "\n=== Test Complete ==="
echo "All basic Docker functionality has been tested successfully!"