# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a VM management system that creates isolated Ubuntu development environments for each developer, with integrated Discord communication channels. The system consists of:

1. **Vagrant VMs**: Ubuntu 24.04 VMs with Xubuntu desktop, development tools, and bridge networking
2. **Host Service**: Node.js service managing Discord bots and VM-to-Discord communication
3. **Autogen Bot**: Python AI agent that can execute code and interact via Discord
4. **VM CLI**: `devchat` command for developers to communicate with admins

## Essential Commands

### VM Management
```bash
# Provision/update a developer VM
./host_scripts/provision_vm.sh <username>

# Start/stop/restart VMs
./host_scripts/start_vm.sh <username>
./host_scripts/stop_vm.sh <username>
./host_scripts/restart_vm.sh <username>

# Manage all VMs at once
./host_scripts/start_all_vms.sh
./host_scripts/stop_all_vms.sh
./host_scripts/savestate_all_vms.sh
```

### Host Service
```bash
# Start the host service (required for Discord communication)
cd host_service
npm install  # First time only
npm start    # Or use ./host_scripts/start_host_service.sh
```

### Autogen Agent
```bash
# Start the AI Discord bot
cd autogen_agent
./start_agent.sh

# View logs
./get_logs.sh

# Check status
./status_agent.sh
```

### MCP Discord Server
```bash
# Build and run the MCP server
cd mcp_servers/discord-mcp
npm install
npm run build
```

### VM Internal Commands
```bash
# Send message from VM to admin (inside VM)
devchat @admin "Your message here"
```

## Architecture

### Communication Flow
1. Developer in VM uses `devchat` → sends HTTP request to host service
2. Host service authenticates request and forwards to Discord using bot token
3. Admin/AI replies in Discord → host service receives via bot
4. Host service notifies VM via WebSocket → `devchat` displays response

### Security Model
- Each developer has a dedicated Discord bot (token stored on host only)
- VMs authenticate to host service using their hostname
- Bot tokens never exposed to VMs
- All VM-to-Discord communication proxied through host service

### Key Files
- `config/dev_users.txt`: List of developer usernames (one per line)
- `host_service/.env`: Discord bot tokens (BOT_TOKEN_USERNAME=token)
- `autogen_agent/.env`: AI service credentials and Discord app token
- `Vagrantfile`: VM configuration and provisioning logic

## Testing

### Host Service
```bash
cd host_service
# No automated tests - manual testing via Discord interactions
```

### Autogen Agent
```bash
cd autogen_agent
# Test by interacting with bot in Discord
# Check logs with ./get_logs.sh for errors
```

### VM Provisioning
```bash
# Test VM creation and setup
./host_scripts/provision_vm.sh testuser
# Verify VM boots and has all tools installed
```

## Common Development Tasks

### Adding a New Developer
1. Add username to `config/dev_users.txt`
2. Create Discord bot application and add token to `host_service/.env`
3. Run `./host_scripts/provision_vm.sh <username>`

### Updating VM Software
1. Edit provisioning script in `Vagrantfile`
2. Run `./host_scripts/provision_all_vms.sh` to update all VMs

### Debugging Discord Communication
1. Check host service logs: `cd host_service && npm start`
2. Check autogen bot logs: `cd autogen_agent && ./get_logs.sh`
3. Verify bot tokens in `.env` files are correct
4. Test with `devchat @admin "test"` from inside VM