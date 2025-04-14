#!/bin/bash

AGENT_DIR=$(dirname "$0")
cd "$AGENT_DIR" || exit 1

STOP_SCRIPT="./stop_agent.sh"
START_SCRIPT="./start_agent.sh"

echo "Attempting to restart the agent..."

# Stop the agent
echo "--- Stopping Agent ---"
bash "$STOP_SCRIPT"
STOP_EXIT_CODE=$?
if [ $STOP_EXIT_CODE -ne 0 ]; then
    echo "Warning: Stop script exited with code $STOP_EXIT_CODE. Attempting to start anyway..."
    # Optionally add more robust error handling here if needed
fi
echo "----------------------"

# Wait a moment before starting
sleep 2

# Start the agent
echo "--- Starting Agent ---"
bash "$START_SCRIPT"
START_EXIT_CODE=$?
if [ $START_EXIT_CODE -ne 0 ]; then
    echo "Error: Failed to start the agent during restart (exit code $START_EXIT_CODE)."
    exit 1
fi
echo "----------------------"

echo "Agent restart process completed."
exit 0
