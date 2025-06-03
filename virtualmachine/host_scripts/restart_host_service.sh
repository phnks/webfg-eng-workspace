#!/bin/bash

# Script to restart the host_service Node.js application.

STOP_SCRIPT="./stop_host_service.sh"
START_SCRIPT="./start_host_service.sh"

echo ">>> Attempting to restart host_service..."

# Check if helper scripts exist and are executable
if [ ! -x "$STOP_SCRIPT" ]; then
    echo "Error: Stop script '$STOP_SCRIPT' not found or not executable."
    exit 1
fi
if [ ! -x "$START_SCRIPT" ]; then
    echo "Error: Start script '$START_SCRIPT' not found or not executable."
    exit 1
fi

echo "--- Stopping service (if running)... ---"
if ! "$STOP_SCRIPT"; then
    echo "Warning: Stop script failed. Attempting to start anyway..."
    # Continue even if stop fails, start script checks for running process
fi
echo "----------------------------------------"

echo ""
echo "--- Starting service... ---"
if ! "$START_SCRIPT"; then
    echo "Error: Failed to start host service during restart."
    exit 1
fi
echo "---------------------------"

echo ">>> Host service restart process finished."
exit 0
