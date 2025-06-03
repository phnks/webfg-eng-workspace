#!/bin/bash

# Script to start the host_service Node.js application in the background.

SERVICE_DIR="host_service"
PID_FILE="$SERVICE_DIR/.pid"
LOG_FILE="$SERVICE_DIR/host_service.log"
MAIN_SCRIPT="index.js"

echo ">>> Attempting to start host_service..."

# Check if service directory exists
if [ ! -d "$SERVICE_DIR" ]; then
    echo "Error: Service directory '$SERVICE_DIR' not found."
    exit 1
fi

# Check if main script exists
if [ ! -f "$SERVICE_DIR/$MAIN_SCRIPT" ]; then
    echo "Error: Main script '$SERVICE_DIR/$MAIN_SCRIPT' not found."
    exit 1
fi

# Check if PID file exists and process is running
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null; then
        echo "Host service appears to be already running with PID $PID (according to $PID_FILE)."
        exit 0 # Already running, consider it success
    else
        echo "Warning: PID file '$PID_FILE' found, but process $PID is not running. Removing stale PID file."
        rm -f "$PID_FILE"
    fi
fi

# Navigate to the service directory to resolve dependencies correctly
cd "$SERVICE_DIR" || exit 1 # Exit if cd fails

LOG_FILE_BASENAME=$(basename "$LOG_FILE") # Get just the filename, e.g., host_service.log
echo "Starting node $MAIN_SCRIPT in background, logging to $LOG_FILE_BASENAME (inside $SERVICE_DIR)..."
# Start with nohup, redirect stdout/stderr using just the filename relative to SERVICE_DIR
nohup node "$MAIN_SCRIPT" > "$LOG_FILE_BASENAME" 2>&1 &
NEW_PID=$!

# Check if the process started successfully (basic check)
sleep 1 # Give it a moment to potentially fail
if ps -p "$NEW_PID" > /dev/null; then
    echo "$NEW_PID" > ".pid" # Save PID relative to SERVICE_DIR
    echo "Host service started successfully with PID $NEW_PID."
    cd .. # Return to original directory
    exit 0
else
    echo "Error: Failed to start host service. Check '$LOG_FILE' for details."
    cd .. # Return to original directory
    exit 1
fi
