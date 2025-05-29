#!/bin/bash

# Docker entrypoint script for agent containers
set -e

# Set environment variables
export USER=${USER:-agent}
export AGENT_TYPE=${AGENT_TYPE:-autogen}
export AGENT_HOME=/home/agent/autogen_agent
export BOT_USER=agent

echo "========================================="
echo "Starting agent container for user: $USER"
echo "Agent type: $AGENT_TYPE"
echo "========================================="

# Ensure we're the right user
if [ "$(whoami)" != "$USER" ]; then
    echo "Warning: Running as $(whoami), expected $USER"
fi

cd /home/agent

# 1. Setup Python virtual environment
echo "Setting up Python environment..."
# Create venv in writable location and symlink to autogen_agent for compatibility
if [ ! -d "/home/agent/.venvs/autogen" ]; then
    echo "Creating Python virtual environment..."
    mkdir -p /home/agent/.venvs
    python3 -m venv /home/agent/.venvs/autogen
fi

# Create symlink in autogen_agent directory if it doesn't exist
if [ ! -e "/home/agent/autogen_agent/venv" ] && [ -w "/home/agent/autogen_agent" ]; then
    ln -sf /home/agent/.venvs/autogen /home/agent/autogen_agent/venv
elif [ ! -e "/home/agent/autogen_agent/venv" ]; then
    echo "Note: Cannot create symlink in read-only autogen_agent directory"
    echo "Original scripts will need to use: source /home/agent/.venvs/autogen/bin/activate"
fi

# Always activate and ensure dependencies are installed
source /home/agent/.venvs/autogen/bin/activate
pip install --quiet --upgrade pip
pip install --quiet pyautogen discord.py python-dotenv

# Override local .env with container environment variables for AutoGen
echo "Setting up environment variables for AutoGen..."
cat > /home/agent/workspace/.env << EOF
# Container environment variables (overrides local .env)
DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
DISCORD_CHANNEL_ID=${DISCORD_CHANNEL_ID}
OPENAI_API_KEY=${OPENAI_API_KEY}
GEMINI_API_KEY=${GEMINI_API_KEY}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
USE_GEMINI=${USE_GEMINI:-true}
BOT_USER=${BOT_USER}
AGENT_HOME=${AGENT_HOME}
EOF

# 2. Setup Discord MCP in writable location
echo "Setting up Discord MCP..."
if [ ! -d "/home/agent/discord-mcp-local" ]; then
    echo "Copying Discord MCP to writable location..."
    cp -r /home/agent/discord-mcp /home/agent/discord-mcp-local
    cd /home/agent/discord-mcp-local
    npm ci --silent
    npm run build --silent
    cd /home/agent
fi

# 3. Setup devchat CLI
echo "Setting up devchat CLI..."
if ! grep -q "alias devchat" /home/agent/.bashrc 2>/dev/null; then
    echo 'alias devchat="node /home/agent/vm_cli/devchat.js"' >> /home/agent/.bashrc
    echo 'export PATH=/home/agent/.local/bin:$PATH' >> /home/agent/.bashrc
fi

# 4. Create agent startup scripts
echo "Creating agent startup scripts..."

# AutoGen startup script
cat > /home/agent/start_autogen.sh << 'EOF'
#!/bin/bash
echo "Starting AutoGen agent..."
source /home/agent/.venvs/autogen/bin/activate
cd /home/agent/autogen_agent

# Check for required environment variables
if [ -z "$DISCORD_BOT_TOKEN" ] || [ "$DISCORD_BOT_TOKEN" = "test_token" ]; then
    echo "ERROR: DISCORD_BOT_TOKEN not set or using test token"
    echo "Please set a valid Discord bot token to start the agent"
    echo "Current token: $DISCORD_BOT_TOKEN"
    exit 1
fi

# Set BOT_USER to the actual container user to fix home directory detection
export BOT_USER=agent

echo "Starting autogen_discord_bot.py..."
python autogen_discord_bot.py
EOF
chmod +x /home/agent/start_autogen.sh

# Claude Code startup script  
cat > /home/agent/start_claude.sh << 'EOF'
#!/bin/bash
echo "Starting Claude Code agent..."
cd /home/agent/workspace

# Start Discord MCP server in background
echo "Starting Discord MCP server..."
cd /home/agent/discord-mcp-local
npm start &
MCP_PID=$!
echo "Discord MCP server started with PID: $MCP_PID"

# Wait for MCP server to be ready
sleep 3

# Start Claude Code with MCP config
cd /home/agent/workspace
if [ -f "/home/agent/.claude/mcp-config.json" ]; then
    claude --mcp-config "/home/agent/.claude/mcp-config.json"
else
    claude
fi

# Cleanup MCP server on exit
kill $MCP_PID 2>/dev/null || true
EOF
chmod +x /home/agent/start_claude.sh

# 5. Make original AutoGen scripts compatible
echo "Making original AutoGen scripts compatible..."
cd /home/agent/autogen_agent

# Ensure original scripts are executable
chmod +x *.sh 2>/dev/null || true

# Create fixed version of start_agent.sh that works in container (in writable location)
cat > /home/agent/start_agent_fixed.sh << 'EOF'
#!/usr/bin/env bash
if [[ -z "$AGENT_HOME" ]]; then
    echo "❌  Could not locate AGENT_HOME" >&2
    echo "    AGENT_HOME is not set" >&2
    exit 1
fi

cd "$AGENT_HOME" || {
    echo "❌  cd \"$AGENT_HOME\" failed" >&2
    exit 1
}

echo "AGENT_HOME: $AGENT_HOME"

# Use writable locations for PID and log files
PID_FILE="/home/agent/workspace/.agent.pid"
LOG_FILE="/home/agent/workspace/.agent.log"
VENV_PATH="/home/agent/.venvs/autogen/bin/activate"
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

# Load container environment variables
echo "Loading container environment variables..."
export BOT_USER=${BOT_USER}
export DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
export DISCORD_CHANNEL_ID=${DISCORD_CHANNEL_ID}
export OPENAI_API_KEY=${OPENAI_API_KEY}
export GEMINI_API_KEY=${GEMINI_API_KEY}
export ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
export USE_GEMINI=${USE_GEMINI:-true}

# Activate virtual environment and run the script in the background
echo "Starting AutoGen Discord Bot..."
echo "Using Discord Bot Token: ${DISCORD_BOT_TOKEN:0:20}..."
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
EOF
chmod +x /home/agent/start_agent_fixed.sh

# Create wrapper script for original start_agent.sh that fixes the venv path
cat > /home/agent/start_agent_wrapper.sh << 'EOF'
#!/bin/bash
# Wrapper for original start_agent.sh that fixes venv path for read-only filesystem

export AGENT_HOME=/home/agent/autogen_agent
export BOT_USER=agent

cd "$AGENT_HOME" || {
    echo "❌  cd \"$AGENT_HOME\" failed" >&2
    exit 1
}

PID_FILE="$AGENT_HOME/.agent.pid"
LOG_FILE="$AGENT_HOME/.agent.log"
VENV_PATH="/home/agent/.venvs/autogen/bin/activate"  # Fixed path for container
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

# Create writable PID and log files in workspace if autogen_agent is read-only
if [ ! -w "$AGENT_HOME" ]; then
    PID_FILE="/home/agent/workspace/.agent.pid"
    LOG_FILE="/home/agent/workspace/.agent.log"
    echo "Note: Using writable workspace for PID and log files"
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
EOF
chmod +x /home/agent/start_agent_wrapper.sh

echo "========================================="
echo "Container setup complete!"
echo "Available commands:"
echo "  /home/agent/start_autogen.sh                    - Start AutoGen agent (simple wrapper)"
echo "  /home/agent/start_claude.sh                     - Start Claude Code agent"
echo "  /home/agent/start_agent_fixed.sh                - Start AutoGen agent (fixed original script)"
echo "  /home/agent/start_agent_wrapper.sh              - Start AutoGen agent (compatible wrapper)"
echo "  devchat                                         - Send Discord messages"
echo "Environment variables set:"
echo "  AGENT_HOME=$AGENT_HOME"
echo "  BOT_USER=$BOT_USER"
echo "  DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN:0:20}..."
echo "========================================="

# Drop to shell instead of auto-starting to prevent restart loops
echo "Dropping to shell. You can manually run the agent scripts."
echo "Use start_agent_fixed.sh for the corrected original script"
exec /bin/bash