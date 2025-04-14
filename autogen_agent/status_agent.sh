#!/bin/bash

AGENT_DIR=$(dirname "$0")
cd "$AGENT_DIR" || exit 1

PID_FILE="agent.pid"
SCRIPT_NAME="autogen_discord_bot.py"

# Check using PID file first
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null; then
        echo "Agent is RUNNING (PID: $PID, according to PID file)."
        exit 0
    else
        echo "Agent is STOPPED (stale PID file found for PID $PID, process not running)."
        # Consider removing the stale PID file here if desired: rm "$PID_FILE"
        exit 1 # Exit with error code 1 to indicate stopped status
    fi
else
    # If no PID file, check if the process is running anyway
    pgrep -f "python $AGENT_DIR/$SCRIPT_NAME" > /dev/null
    if [ $? -eq 0 ]; then
        RUNNING_PIDS=$(pgrep -f "python $AGENT_DIR/$SCRIPT_NAME")
        echo "Agent is RUNNING (PID(s): $RUNNING_PIDS, found running process but no PID file)."
        echo "Consider running stop and start scripts to manage it properly."
        exit 0
    else
        echo "Agent is STOPPED (no PID file and no running process found)."
        exit 1 # Exit with error code 1 to indicate stopped status
    fi
fi
