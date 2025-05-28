#!/bin/bash

# Docker entrypoint script for agent containers

set -e

# Set environment variables
export USER=${USER:-agent}
export AGENT_TYPE=${AGENT_TYPE:-autogen}

echo "Starting agent container..."
echo "User: $USER"
echo "Agent Type: $AGENT_TYPE"

# Run any additional setup if needed
if [ -f /usr/local/bin/setup_container.sh ]; then
    /usr/local/bin/setup_container.sh
fi

# Start Discord MCP server in background if needed
if [ -d "/home/$USER/discord-mcp" ] && [ -f "/home/$USER/discord-mcp/dist/index.js" ]; then
    echo "Starting Discord MCP server..."
    cd "/home/$USER/discord-mcp"
    npm start &
    MCP_PID=$!
    echo "Discord MCP server started with PID: $MCP_PID"
fi

# Start the appropriate agent
if [ "$AGENT_TYPE" = "autogen" ]; then
    echo "Starting AutoGen agent..."
    if [ -f "/home/$USER/run_autogen_service.sh" ]; then
        exec /home/$USER/run_autogen_service.sh
    else
        echo "Error: AutoGen service script not found"
        exec /bin/bash
    fi
elif [ "$AGENT_TYPE" = "claude-code" ]; then
    echo "Starting Claude Code agent..."
    cd "/home/$USER/workspace"
    
    # Wait for MCP server to be ready
    sleep 3
    
    # Start Claude Code with MCP config
    if [ -f "/home/$USER/.claude/mcp-config.json" ]; then
        exec claude --mcp-config "/home/$USER/.claude/mcp-config.json"
    else
        exec claude
    fi
else
    echo "Unknown agent type: $AGENT_TYPE"
    exec /bin/bash
fi