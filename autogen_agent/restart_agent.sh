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

# Launch the real restart sequence in a completely detached process
nohup bash -c '
  echo "=== [restart_agent.sh] Background restart sequence starting ==="
  sleep 5
  echo "--- Stopping agent ---"
  bash "'"$AGENT_HOME"'/stop_agent.sh"
  echo "--- Waiting 5s before restart ---"
  sleep 5
  echo "--- Starting agent ---"
  bash "'"$AGENT_HOME"'/start_agent.sh"
  echo "=== [restart_agent.sh] Restart sequence complete ==="
' >/dev/null 2>&1 &

# Immediately return to the caller (your Discord bot)
echo "Agent restart initiated! You should see me back online in a few seconds."
exit 0