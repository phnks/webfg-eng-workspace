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

cmd_args=("tail" "-n" "$n")
message="📄 Last $n log lines from $log_file:"

if [[ -n "$2" && "$2" == "-f" ]]; then
    message="📄 Tailing last $n log lines from $log_file (Ctrl+C to stop):"
    cmd_args+=("-f")
fi

cmd_args+=("$log_file")

echo "$message"
"${cmd_args[@]}"

exit 0
