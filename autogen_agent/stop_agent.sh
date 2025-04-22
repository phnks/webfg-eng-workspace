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

# Tell the caller we're on it — then detach the real work
echo "Agent stop initiated; shutting down in background…"

nohup bash -c '
  sleep 5
  cd "$AGENT_HOME" || exit 1

  PID_FILE="$AGENT_HOME/agent.pid"
  LOG_FILE="$AGENT_HOME/agent.log"
  SCRIPT="$AGENT_HOME/autogen_discord_bot.py"

  # If no PID file, try killing by matching python process
  if [ ! -f "$PID_FILE" ]; then
    echo "[stop_agent] No PID file; checking for stray process…" >&2
    if pgrep -f "python $SCRIPT" >/dev/null; then
      echo "[stop_agent] Found running agent without PID file; killing…" >&2
      pkill -f "python $SCRIPT"
      sleep 2
      if ! pgrep -f "python $SCRIPT" >/dev/null; then
        echo "[stop_agent] Agent process stopped."
        rm -f "$LOG_FILE"
        echo "Deleted old log file"
      else
        echo "[stop_agent] ERROR: Still running after kill."
      fi
    else
      echo "[stop_agent] Agent not running."
    fi
    exit 0
  fi

  # Read PID from file
  PID="$(<"$PID_FILE")"
  if ! ps -p "$PID" >/dev/null; then
    echo "[stop_agent] Stale PID file ($PID); removing." >&2
    rm -f "$PID_FILE"
    rm -f "$LOG_FILE"
    echo "Deleted old log file"
    exit 0
  fi

  # Attempt graceful stop
  echo "[stop_agent] Stopping agent (PID $PID) …" >&2
  kill "$PID"
  sleep 2

  if ps -p "$PID" >/dev/null; then
    echo "[stop_agent] Did not stop; sending SIGKILL…" >&2
    kill -9 "$PID"
    sleep 1
    if ps -p "$PID" >/dev/null; then
      echo "[stop_agent] ERROR: Still running after SIGKILL." >&2
      exit 1
    else
      echo "[stop_agent] Agent force‑killed."
      rm -f "$LOG_FILE"
      echo "Deleted old log file"
    fi
  else
    echo "[stop_agent] Agent stopped gracefully."
    rm -f "$LOG_FILE"
    echo "Deleted old log file"
  fi

  # Clean up
  rm -f "$PID_FILE"
  echo "[stop_agent] PID file removed."
  rm -f "$LOG_FILE"
  echo "Deleted old log file"
' >/dev/null 2>&1 &

exit 0