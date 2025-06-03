#!/bin/bash

# Container-specific setup script (runs inside the container)
# This adapts the guest_scripts/setup_dev.sh for Docker containers

set -e

USERNAME=${USER:-agent}
AGENT_TYPE=${AGENT_TYPE:-autogen}

echo "Setting up container environment for $USERNAME with $AGENT_TYPE agent..."

# Configure git
if [ -f "/home/$USERNAME/.gitconfig" ]; then
    echo "Git config already present"
else
    # Set basic git config if not present
    git config --global user.name "$USERNAME"
    git config --global user.email "$USERNAME@localhost"
    git config --global init.defaultBranch main
fi

# Setup SSH permissions
if [ -d "/home/$USERNAME/.ssh" ]; then
    chmod 700 "/home/$USERNAME/.ssh"
    chmod 600 "/home/$USERNAME/.ssh"/* 2>/dev/null || true
fi

# Setup AutoGen agent
if [ "$AGENT_TYPE" = "autogen" ] && [ -d "/home/$USERNAME/autogen_agent" ]; then
    echo "Setting up AutoGen agent..."
    
    # Create logs directory
    mkdir -p "/home/$USERNAME/autogen_logs"
    
    # Create start script
    cat > "/home/$USERNAME/start_autogen.sh" << 'EOF'
#!/bin/bash
cd /home/$USER/autogen_agent
source venv/bin/activate
python autogen_discord_bot.py >> /home/$USER/autogen_logs/agent.log 2>&1
EOF
    chmod +x "/home/$USERNAME/start_autogen.sh"
    
    # Create systemd-like service script (for containers without systemd)
    cat > "/home/$USERNAME/run_autogen_service.sh" << 'EOF'
#!/bin/bash
while true; do
    echo "[$(date)] Starting AutoGen agent..."
    /home/$USER/start_autogen.sh
    echo "[$(date)] AutoGen agent stopped. Restarting in 5 seconds..."
    sleep 5
done
EOF
    chmod +x "/home/$USERNAME/run_autogen_service.sh"
fi

# Setup Claude Code agent
if [ "$AGENT_TYPE" = "claude-code" ]; then
    echo "Setting up Claude Code agent..."
    
    # Create Claude config directory
    mkdir -p "/home/$USERNAME/.claude"
    
    # Create MCP config if not exists
    if [ ! -f "/home/$USERNAME/.claude/mcp-config.json" ]; then
        cat > "/home/$USERNAME/.claude/mcp-config.json" << EOF
{
  "servers": {
    "discord": {
      "command": "node",
      "args": ["/home/$USERNAME/discord-mcp/dist/index.js"],
      "env": {
        "DISCORD_BOT_TOKEN": "\${DISCORD_BOT_TOKEN}",
        "DISCORD_CHANNEL_ID": "\${DISCORD_CHANNEL_ID}"
      }
    }
  }
}
EOF
    fi
    
    # Create Claude Code settings
    cat > "/home/$USERNAME/.claude/settings.json" << EOF
{
  "theme": "dark",
  "telemetry": false,
  "codeActions": {
    "enabled": true
  }
}
EOF
fi

# Setup Discord MCP server
if [ -d "/home/$USERNAME/discord-mcp" ]; then
    echo "Setting up Discord MCP server..."
    
    # Create start script
    cat > "/home/$USERNAME/start_discord_mcp.sh" << 'EOF'
#!/bin/bash
cd /home/$USER/discord-mcp
npm start
EOF
    chmod +x "/home/$USERNAME/start_discord_mcp.sh"
fi

# Configure devchat to use host.docker.internal
if [ -n "$DEVCHAT_HOST_IP" ]; then
    echo "export DEVCHAT_HOST_IP=$DEVCHAT_HOST_IP" >> "/home/$USERNAME/.bashrc"
fi

# Add helpful aliases
cat >> "/home/$USERNAME/.bashrc" << 'EOF'

# Container-specific aliases
alias logs='tail -f /home/$USER/autogen_logs/agent.log'
alias restart-agent='pkill -f autogen_discord_bot.py; /home/$USER/start_autogen.sh &'
alias status='ps aux | grep -E "(autogen|claude|mcp)" | grep -v grep'

# Welcome message
echo "Welcome to the agent container!"
echo "Agent type: $AGENT_TYPE"
echo "Commands:"
echo "  logs         - View agent logs"
echo "  restart-agent - Restart the agent"
echo "  status       - Check agent status"
echo "  devchat      - Send messages to Discord"
EOF

echo "Container setup complete!"