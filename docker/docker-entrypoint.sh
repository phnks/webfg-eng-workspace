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
# Create venv in autogen_agent directory for compatibility with original scripts
if [ ! -d "/home/agent/autogen_agent/venv" ]; then
    echo "Creating Python virtual environment..."
    cd /home/agent/autogen_agent
    python3 -m venv venv
fi

# Always activate and ensure dependencies are installed
source /home/agent/autogen_agent/venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet pyautogen discord.py python-dotenv

# Also create backup venv location for our scripts
if [ ! -d "/home/agent/.venvs/autogen" ]; then
    mkdir -p /home/agent/.venvs
    ln -sf /home/agent/autogen_agent/venv /home/agent/.venvs/autogen
fi

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
source /home/agent/autogen_agent/venv/bin/activate
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

echo "========================================="
echo "Container setup complete!"
echo "Available commands:"
echo "  /home/agent/start_autogen.sh        - Start AutoGen agent (new wrapper)"
echo "  /home/agent/start_claude.sh         - Start Claude Code agent"
echo "  /home/agent/autogen_agent/start_agent.sh - Start AutoGen agent (original script)"
echo "  devchat                             - Send Discord messages"
echo "Environment variables set:"
echo "  AGENT_HOME=$AGENT_HOME"
echo "  BOT_USER=$BOT_USER"
echo "========================================="

# Drop to shell instead of auto-starting to prevent restart loops
echo "Dropping to shell. You can manually run the agent scripts."
echo "To test the original script: cd \$AGENT_HOME && ./start_agent.sh"
exec /bin/bash