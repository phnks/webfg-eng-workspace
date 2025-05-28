#!/bin/bash

# Docker equivalent of provision_all_vms.sh
# Provisions Docker containers for all users in config/dev_users.txt

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <agent_type>"
    echo "agent_type: autogen or claude-code"
    exit 1
fi

AGENT_TYPE=$1

# Validate agent type
if [[ "$AGENT_TYPE" != "autogen" && "$AGENT_TYPE" != "claude-code" ]]; then
    echo "Error: agent_type must be 'autogen' or 'claude-code'"
    exit 1
fi

echo "Provisioning Docker containers for all users with agent type: $AGENT_TYPE"

# Read users from config file
if [ ! -f "$PROJECT_ROOT/config/dev_users.txt" ]; then
    echo "Error: config/dev_users.txt not found"
    exit 1
fi

# Process each user
while IFS= read -r username; do
    # Skip empty lines and comments
    if [[ -z "$username" || "$username" =~ ^# ]]; then
        continue
    fi
    
    echo "========================================="
    echo "Provisioning container for: $username"
    echo "========================================="
    
    "$SCRIPT_DIR/provision_container.sh" "$username" "$AGENT_TYPE"
    
    echo ""
done < "$PROJECT_ROOT/config/dev_users.txt"

echo "All containers provisioned"