#!/bin/bash

# Docker equivalent of restart_vm.sh
# Restarts a Docker container for a specific user

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

USERNAME=$1
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Restarting Docker container for user: $USERNAME"

# Stop the container
"$SCRIPT_DIR/stop_container.sh" "$USERNAME"

# Wait a moment
sleep 2

# Start the container
"$SCRIPT_DIR/start_container.sh" "$USERNAME"