#!/usr/bin/env bash
if [[ -f "$AGENT_HOME" ]]; then
    echo "❌  Could not locate AGENT_HOME" >&2
    echo "    Checked: $AGENT_HOME" >&2
    exit 1
fi

cd "$AGENT_HOME" || {
    echo "❌  cd \"$AGENT_HOME\" failed" >&2
    exit 1
}

echo $AGENT_HOME

PID_FILE="$AGENT_HOME/agent.pid"
LOG_FILE="$AGENT_HOME/agent.log"
VENV_PATH="$AGENT_HOME/venv/bin/activate"
SCRIPT_NAME="$AGENT_HOME/autogen_discord_bot.py"

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
