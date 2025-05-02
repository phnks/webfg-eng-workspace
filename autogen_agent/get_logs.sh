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

# Determine the number of lines to show, default to 50
if [[ -n "$1" && "$1" =~ ^[0-9]+$ ]]; then
    n="$1"
else
    n=50
fi

log_file="$AGENT_HOME/.agent.log"

if [[ ! -f "$log_file" ]]; then
    echo "❌  Log file not found: $log_file" >&2
    exit 1
fi

echo "📄 Last $n log lines from $log_file:"
tail -n "$n" "$log_file"

exit 0
