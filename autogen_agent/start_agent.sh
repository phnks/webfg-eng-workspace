#!/bin/bash

AGENT_DIR=$(dirname "$0")
cd "$AGENT_DIR" || exit 1

PID_FILE="agent.pid"
LOG_FILE="agent.log"
VENV_PATH="venv/bin/activate"
SCRIPT_NAME="autogen_discord_bot.py"

# Check if already running
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null; then
        echo "Agent is already running with PID $PID."
        exit 0
    else
        echo "Warning: PID file found, but process $PID is not running. Removing stale PID file."
        rm "$PID_FILE"
    fi
fi

# Activate virtual environment and run the script in the background
echo "Starting AutoGen Discord Bot (with AUTOGEN_USE_DOCKER=0)..."
touch "$LOG_FILE"
chmod 666 "$LOG_FILE" # Ensure log is writable

# Load environment variables from .env file into the current shell
set -a # Automatically export all variables subsequently defined or modified
if [ -f ".env" ]; then
    source ".env"
    echo "Loaded environment variables from .env"
else
    echo "Warning: .env file not found."
fi
set +a # Stop automatically exporting variables

# Set environment variable to disable Docker check and run python
export AUTOGEN_USE_DOCKER=0
source "$VENV_PATH" # Activate venv
echo "Running $SCRIPT_NAME with nohup..."
nohup python "$SCRIPT_NAME" >> "$LOG_FILE" 2>&1 &

# Get the PID of the background process
BG_PID=$!

# Check if the process started successfully after a short delay
sleep 2
if ps -p $BG_PID > /dev/null; then
    echo $BG_PID > "$PID_FILE" # Write PID to file
    echo "Agent started successfully with PID $BG_PID. PID saved to $PID_FILE. Output logged to $LOG_FILE"
else
    echo "Error: Agent failed to start (Process $BG_PID not found). Check $LOG_FILE for details."
    # No need to remove PID_FILE here as it wasn't created yet
    exit 1
fi

exit 0
