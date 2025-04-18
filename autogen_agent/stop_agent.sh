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

PID_FILE="$AGENT_HOME/agent.pid"

# Check if PID file exists
if [ ! -f "$PID_FILE" ]; then
    echo "Agent does not appear to be running (no PID file found)."
    # Double check if the process is running without a PID file (e.g., manual start)
    # This part is optional but can be helpful
    pgrep -f "python $AGENT_HOME/autogen_discord_bot.py" > /dev/null
    if [ $? -eq 0 ]; then
        echo "Warning: Found a running agent process without a PID file. Attempting to stop it..."
        pkill -f "python $AGENT_HOME/autogen_discord_bot.py"
        sleep 2
        pgrep -f "python $AGENT_HOME/autogen_discord_bot.py" > /dev/null
        if [ $? -ne 0 ]; then
            echo "Agent process stopped."
        else
            echo "Error: Failed to stop the agent process found without a PID file."
        fi
    fi
    exit 0
fi

# Read PID and check if process is running
PID=$(cat "$PID_FILE")
if ! ps -p $PID > /dev/null; then
    echo "Agent is not running (process $PID not found). Removing stale PID file."
    rm "$PID_FILE"
    exit 0
fi

# Attempt to stop the process
echo "Stopping agent (PID $PID)..."
kill $PID

# Wait and check if stopped
sleep 2
if ps -p $PID > /dev/null; then
    echo "Agent did not stop gracefully with kill $PID. Attempting force kill (SIGKILL)..."
    kill -9 $PID
    sleep 1
    if ps -p $PID > /dev/null; then
        echo "Error: Failed to stop agent (PID $PID) even with force kill."
        exit 1
    else
        echo "Agent stopped forcefully."
    fi
else
    echo "Agent stopped successfully."
fi

# Remove PID file
rm "$PID_FILE"
echo "Removed PID file."
exit 0
