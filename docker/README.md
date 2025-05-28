# Docker Setup for WebFG Agents

This directory contains the Docker configuration for running WebFG agents (AutoGen and Claude Code) in containers instead of VMs.

## Overview

The Docker setup provides:
- Isolated containers for each developer/agent
- Support for both AutoGen and Claude Code agents
- Discord integration via MCP server
- Persistent storage for workspaces and configurations
- Easy scaling and management

## Directory Structure

```
docker/
├── Dockerfile              # Multi-stage Dockerfile for agent containers
├── docker-entrypoint.sh    # Container entrypoint script
├── docker-compose.yml      # Base compose file
├── docker-compose.template.yml  # Template for per-user containers
├── scripts/                # Docker management scripts
│   ├── provision_container.sh
│   ├── start_container.sh
│   ├── stop_container.sh
│   ├── restart_container.sh
│   ├── enter_container.sh
│   ├── destroy_container.sh
│   └── *_all_containers.sh
└── volumes/               # Per-user persistent data
    └── <username>/
        ├── workspace/
        ├── claude/
        ├── config/
        ├── ssh/
        └── autogen_logs/
```

## Prerequisites

1. Docker Engine installed and running
2. docker-compose installed (standalone or plugin)
3. Host service running for Discord communication
4. Environment variables configured (.env file)

## Quick Start

### 1. Set up environment variables

Create a `.env` file in the docker directory with:
```bash
# Discord configuration
ADMIN_DISCORD_ID=your_discord_id
DISCORD_CHANNEL_ID=your_channel_id

# Bot tokens (one per user)
BOT_TOKEN_username=discord_bot_token

# AI Service credentials
OPENAI_API_KEY=your_key
GEMINI_API_KEY=your_key
ANTHROPIC_API_KEY=your_key

# Git/GitHub credentials
GITHUB_TOKEN=your_token
GIT_USERNAME=your_username

# AWS credentials (optional)
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
AWS_DEFAULT_REGION=us-east-1
```

### 2. Provision a container

```bash
# For AutoGen agent
./scripts/provision_container.sh username autogen

# For Claude Code agent
./scripts/provision_container.sh username claude-code
```

### 3. Start the container

```bash
./scripts/start_container.sh username
```

### 4. Enter the container

```bash
./scripts/enter_container.sh username
```

## Management Commands

### Individual Container Management

```bash
# Provision/create a new container
./scripts/provision_container.sh <username> <agent_type>

# Start a container
./scripts/start_container.sh <username>

# Stop a container
./scripts/stop_container.sh <username>

# Restart a container
./scripts/restart_container.sh <username>

# Enter a running container
./scripts/enter_container.sh <username>

# Destroy a container and its data
./scripts/destroy_container.sh <username>
```

### Bulk Container Management

```bash
# Provision containers for all users in config/dev_users.txt
./scripts/provision_all_containers.sh <agent_type>

# Start all containers
./scripts/start_all_containers.sh

# Stop all containers
./scripts/stop_all_containers.sh
```

## Container Features

### AutoGen Containers
- Python 3.x with virtual environment
- AutoGen framework pre-installed
- Discord bot integration
- Automatic agent startup on container start
- Logs available at `/home/username/autogen_logs/`

### Claude Code Containers
- Claude Code CLI pre-installed
- Discord MCP server integration
- Workspace at `/home/username/workspace/`
- MCP configuration at `/home/username/.claude/`

### Common Features
- Ubuntu 24.04 base image
- Development tools (git, aws-cli, gh, docker-cli)
- Node.js v22 and npm
- Python 3.x with pip
- Persistent storage for workspace and configurations
- Host network access for Discord communication

## Networking

- Containers use a custom bridge network `agent-network`
- Host service accessible via `host.docker.internal`
- Containers can communicate with each other on the same network

## Volumes and Persistence

Each container has persistent volumes for:
- `workspace/` - Working directory for code and projects
- `claude/` - Claude Code configuration
- `config/` - Application configurations
- `ssh/` - SSH keys (read-only)
- `autogen_logs/` - AutoGen agent logs

## Troubleshooting

### Container won't start
```bash
# Check logs
docker logs agent-<username>

# Check if network exists
docker network ls | grep agent-network

# Recreate network if needed
docker network create --subnet=172.20.0.0/16 agent-network
```

### Agent not working
```bash
# Enter container and check status
./scripts/enter_container.sh <username>
ps aux | grep -E "(autogen|claude|mcp)"

# Check agent logs (inside container)
tail -f /home/$USER/autogen_logs/agent.log
```

### Discord communication issues
1. Verify host service is running
2. Check bot token in environment variables
3. Ensure DEVCHAT_HOST_IP is set correctly
4. Test with: `devchat @admin "test message"`

### Build issues
```bash
# Build with no cache
docker-compose -f docker-compose.<username>.yml build --no-cache

# Check build logs
docker-compose -f docker-compose.<username>.yml build --progress=plain
```

## Differences from VM Setup

| Feature | VM Setup | Docker Setup |
|---------|----------|--------------|
| Resource Usage | High (full OS) | Low (shared kernel) |
| Startup Time | Minutes | Seconds |
| GUI Support | Yes (Xubuntu) | No (headless) |
| Isolation | Complete | Process-level |
| Management | Vagrant commands | Docker commands |
| Networking | Bridge adapter | Docker network |

## Security Notes

- Bot tokens are passed as environment variables
- SSH keys are mounted read-only
- Each container runs as non-root user
- Containers have sudo access for development
- Network isolation between containers

## Future Improvements

- [ ] Add health checks for agents
- [ ] Implement log rotation
- [ ] Add container resource limits
- [ ] Create web UI for management
- [ ] Add backup/restore functionality
- [ ] Implement container orchestration with Kubernetes