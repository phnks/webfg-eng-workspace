#!/bin/bash

# Test AWS Bedrock agent functionality
# This script tests agent responses to various prompts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
ENV=${1:-dev}

# Validate environment parameter
if [[ ! "$ENV" =~ ^(dev|qa|prod)$ ]]; then
    echo "Error: Invalid environment. Use dev, qa, or prod."
    exit 1
fi

echo "Testing WebFG Coding Agent functionality in $ENV environment..."

# Get agent ID and alias ID from CloudFormation outputs
AGENT_ID=$(aws cloudformation describe-stacks --stack-name coding-agent-$ENV --query "Stacks[0].Outputs[?OutputKey=='AgentId'].OutputValue" --output text)
ALIAS_ID=$(aws cloudformation describe-stacks --stack-name coding-agent-$ENV --query "Stacks[0].Outputs[?OutputKey=='AgentAliasId'].OutputValue" --output text)

if [ -z "$AGENT_ID" ] || [ -z "$ALIAS_ID" ]; then
    echo "Error: Could not retrieve agent or alias ID. Please check if the stack exists and has the expected outputs."
    exit 1
fi

echo "Found agent ID: $AGENT_ID"
echo "Found alias ID: $ALIAS_ID"

# Array of test cases with prompts and expected keywords
declare -A test_cases
test_cases["basic_code_help"]="How do I write a function in JavaScript?" "function|return|var|const"
test_cases["code_review"]="Can you review this code: function sum(a,b) { return a+b; }" "function|return|parameter|argument"
test_cases["debugging"]="How do I debug a memory leak in Node.js?" "heap|profiler|memory|leak"
test_cases["best_practices"]="What are best practices for error handling?" "try|catch|throw|error"
test_cases["language_comparison"]="Compare Python and JavaScript for web development" "Python|JavaScript|framework|syntax"

# Function to run a test and verify the response
run_test() {
    local test_name=$1
    local prompt=$2
    local expected_pattern=$3

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

    # Check if any of the expected keywords are in the response
    if echo "$response" | grep -E "$expected_pattern"; then
        echo "✅ Test passed: Response contains expected pattern"
        return 0
    else
        echo "❌ Test failed: Response does not contain any expected pattern"
        echo "Response: $response"
        return 1
    fi
}

# Run all test cases
failures=0
for test_name in "${!test_cases[@]}"; do
    IFS='|' read -r prompt expected_pattern <<< "${test_cases[$test_name]}"
    if ! run_test "$test_name" "$prompt" "$expected_pattern"; then
        failures=$((failures + 1))
    fi
    echo "-----------------------------------------"
done

# Report test results
if [ $failures -eq 0 ]; then
    echo "All functionality tests passed successfully! 🎉"
    exit 0
else
    echo "$failures tests failed. Please check the logs for details."
    exit 1
fi