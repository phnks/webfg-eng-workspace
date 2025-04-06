#!/bin/bash

# Script to stop the host_service Node.js application running in the background.

SERVICE_DIR="host_service"
PID_FILE="$SERVICE_DIR/.pid"

echo ">>> Attempting to stop host_service..."

# Check if PID file exists
if [ ! -f "$PID_FILE" ]; then
    echo "PID file '$PID_FILE' not found. Service might not be running or PID file was removed."
    # Check if the process might be running anyway (e.g., if PID file was lost)
    # This is harder without the PID, could use pgrep but might kill wrong process.
    # For simplicity, we'll rely on the PID file for now.
    exit 0 # Consider it stopped if no PID file
fi

PID=$(cat "$PID_FILE")

# Check if the process is actually running
if ! ps -p "$PID" > /dev/null; then
    echo "Process with PID $PID (from $PID_FILE) is not running. Removing stale PID file."
    rm -f "$PID_FILE"
    exit 0 # Already stopped
fi

echo "Attempting graceful shutdown (SIGTERM) for process $PID..."
kill -TERM "$PID"

# Wait for process to terminate
TIMEOUT=10 # seconds
COUNT=0
while ps -p "$PID" > /dev/null && [ $COUNT -lt $TIMEOUT ]; do
    sleep 1
    echo -n "."
    COUNT=$((COUNT + 1))
done
echo "" # Newline

# Check if it terminated gracefully
if ! ps -p "$PID" > /dev/null; then
    echo "Host service stopped successfully."
    rm -f "$PID_FILE"
    exit 0
else
    echo "Graceful shutdown failed after $TIMEOUT seconds. Attempting forceful shutdown (SIGKILL)..."
    kill -KILL "$PID"
    sleep 1 # Give SIGKILL a moment

    if ! ps -p "$PID" > /dev/null; then
        echo "Host service forcefully stopped."
        rm -f "$PID_FILE"
        exit 0
    else
        echo "Error: Failed to stop process $PID even with SIGKILL."
        exit 1
    fi
fi
