#!/bin/bash

# Test script to verify Dockerfile syntax without requiring Docker daemon

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
DOCKER_DIR="$PROJECT_ROOT/docker"

echo "=== Testing Dockerfile Syntax ==="
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

# Test 2: Check Dockerfile syntax with hadolint (if available)
echo ""
echo "Test 2: Checking Dockerfile syntax..."
if command -v hadolint >/dev/null 2>&1; then
    if hadolint "$DOCKER_DIR/Dockerfile"; then
        print_result "Dockerfile syntax (hadolint)" 0
    else
        print_result "Dockerfile syntax (hadolint)" 1
    fi
else
    echo "  hadolint not installed, using basic syntax check..."
    # Basic syntax check
    errors=0
    
    # Check for proper FROM statements
    if ! grep -q "^FROM.*AS base" "$DOCKER_DIR/Dockerfile"; then
        echo "  ✗ Missing base stage"
        errors=1
    fi
    
    if ! grep -q "^FROM.*AS autogen-agent" "$DOCKER_DIR/Dockerfile"; then
        echo "  ✗ Missing autogen-agent stage"
        errors=1
    fi
    
    if ! grep -q "^FROM.*AS claude-code-agent" "$DOCKER_DIR/Dockerfile"; then
        echo "  ✗ Missing claude-code-agent stage"
        errors=1
    fi
    
    # Check for user creation logic
    if ! grep -q "getent group" "$DOCKER_DIR/Dockerfile"; then
        echo "  ✗ Missing group existence check"
        errors=1
    fi
    
    if ! grep -q "getent passwd" "$DOCKER_DIR/Dockerfile"; then
        echo "  ✗ Missing user existence check"
        errors=1
    fi
    
    print_result "Basic Dockerfile syntax" $errors
fi

# Test 3: Check required build context files are referenced correctly
echo ""
echo "Test 3: Checking build context references..."
missing_refs=0

# Extract COPY commands from Dockerfile
while IFS= read -r line; do
    if [[ $line =~ ^COPY[[:space:]]+([^[:space:]]+) ]]; then
        src="${BASH_REMATCH[1]}"
        # Remove --chown flag if present
        src=$(echo "$src" | sed 's/--chown=[^ ]*//')
        src=$(echo "$src" | xargs)  # Trim whitespace
        
        # Skip if it's a special file
        if [[ ! "$src" =~ ^(docker/|\./) ]]; then
            if [ ! -e "$PROJECT_ROOT/$src" ]; then
                echo "  Missing: $src"
                missing_refs=1
            else
                echo "  Found: $src"
            fi
        fi
    fi
done < "$DOCKER_DIR/Dockerfile"

print_result "Build context references" $missing_refs

# Test 4: Verify agent user creation logic
echo ""
echo "Test 4: Checking user creation logic..."
if grep -q "getent group" "$DOCKER_DIR/Dockerfile" && \
   grep -q "getent passwd" "$DOCKER_DIR/Dockerfile" && \
   grep -q "groupadd" "$DOCKER_DIR/Dockerfile" && \
   grep -q "useradd" "$DOCKER_DIR/Dockerfile"; then
    print_result "User creation logic" 0
else
    print_result "User creation logic" 1
fi

# Test 5: Check for proper ownership on COPY commands
echo ""
echo "Test 5: Checking COPY ownership..."
copy_without_chown=$(grep "^COPY" "$DOCKER_DIR/Dockerfile" | grep -v "^COPY --chown=" | grep -v "^# " | wc -l)
if [ "$copy_without_chown" -gt 0 ]; then
    echo "  Warning: $copy_without_chown COPY commands without --chown flag"
    grep "^COPY" "$DOCKER_DIR/Dockerfile" | grep -v "^COPY --chown=" | grep -v "^# "
fi
print_result "COPY ownership check" 0

echo ""
echo "=== Dockerfile syntax tests completed ==="
echo ""
echo "Note: To fully test the Docker build, run with sudo:"
echo "  sudo $DOCKER_DIR/scripts/build_image.sh"