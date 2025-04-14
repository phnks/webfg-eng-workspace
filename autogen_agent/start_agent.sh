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
echo "Starting AutoGen Discord Bot..."
source "$VENV_PATH"
nohup python "$SCRIPT_NAME" >> "$LOG_FILE" 2>&1 &

# Get the PID of the background process
BG_PID=$!
echo $BG_PID > "$PID_FILE"

# Check if the process started successfully
sleep 2 # Give it a moment to potentially fail
if ps -p $BG_PID > /dev/null; then
    echo "Agent started successfully with PID $BG_PID. Output logged to $LOG_FILE"
else
    echo "Error: Agent failed to start. Check $LOG_FILE for details."
    rm "$PID_FILE" # Clean up PID file if start failed
    exit 1
fi

exit 0
