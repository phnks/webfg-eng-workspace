#!/bin/bash

# Test AWS Bedrock agent functionality
# Usage: ./test_agent.sh [environment] [test_case]
# Environment options: dev, qa, prod (default: dev)
# Test case options: code_search, code_analysis, doc_search, all (default: all)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
ENV=${1:-dev}
TEST_CASE=${2:-all}

# Validate environment parameter
if [[ ! "$ENV" =~ ^(dev|qa|prod)$ ]]; then
    echo "Error: Invalid environment. Use dev, qa, or prod."
    exit 1
fi

# Validate test case parameter
if [[ ! "$TEST_CASE" =~ ^(code_search|code_analysis|doc_search|all)$ ]]; then
    echo "Error: Invalid test case. Use code_search, code_analysis, doc_search, or all."
    exit 1
fi

echo "Testing WebFG Coding Agent in $ENV environment..."

# Get agent ID and alias ID from CloudFormation outputs
AGENT_ID=$(aws cloudformation describe-stacks --stack-name coding-agent-$ENV --query "Stacks[0].Outputs[?OutputKey=='AgentId'].OutputValue" --output text)
ALIAS_ID=$(aws cloudformation describe-stacks --stack-name coding-agent-$ENV --query "Stacks[0].Outputs[?OutputKey=='AgentAliasId'].OutputValue" --output text)

if [ -z "$AGENT_ID" ] || [ -z "$ALIAS_ID" ]; then
    echo "Error: Could not retrieve agent or alias ID. Please check if the stack exists and has the expected outputs."
    exit 1
fi

echo "Found agent ID: $AGENT_ID"
echo "Found alias ID: $ALIAS_ID"

# Function to run a test and verify the response
run_test() {
    local test_name=$1
    local prompt=$2
    local expected_keyword=$3

    echo "Running test: $test_name"
    echo "Prompt: $prompt"

    # Send the prompt to the agent
    response=$(aws bedrock-agent invoke-agent \
        --agent-id $AGENT_ID \
        --agent-alias-id $ALIAS_ID \
        --session-id "test-session-$(date +%s)" \
        --input-text "$prompt" \
        --query "completion" \
        --output text)

    # Check if the expected keyword is in the response
    if echo "$response" | grep -q "$expected_keyword"; then
        echo "✅ Test passed: Response contains expected keyword '$expected_keyword'"
        return 0
    else
        echo "❌ Test failed: Response does not contain expected keyword '$expected_keyword'"
        echo "Response: $response"
        return 1
    fi
    
    return 0
}

failures=0

# Run code search test if requested
if [ "$TEST_CASE" = "all" ] || [ "$TEST_CASE" = "code_search" ]; then
    if ! run_test "Code Search" "Find functions related to error handling in the codebase" "function"; then
        failures=$((failures + 1))
    fi
fi

# Run code analysis test if requested
if [ "$TEST_CASE" = "all" ] || [ "$TEST_CASE" = "code_analysis" ]; then
    if ! run_test "Code Analysis" "Analyze this code snippet: function add(a, b) { return a + b; }" "function"; then
        failures=$((failures + 1))
    fi
fi

# Run document search test if requested
if [ "$TEST_CASE" = "all" ] || [ "$TEST_CASE" = "doc_search" ]; then
    if ! run_test "Document Search" "What are best practices for error handling in JavaScript?" "error"; then
        failures=$((failures + 1))
    fi
fi

# Report test results
if [ $failures -eq 0 ]; then
    echo "All tests passed successfully! 🎉"
    exit 0
else
    echo "$failures tests failed. Please check the logs for details."
    exit 1
fi