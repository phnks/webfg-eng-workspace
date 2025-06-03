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
./virtualmachine/host_scripts/provision_vm.sh <username>

# Start/stop/restart VMs
./virtualmachine/host_scripts/start_vm.sh <username>
./virtualmachine/host_scripts/stop_vm.sh <username>
./virtualmachine/host_scripts/restart_vm.sh <username>

# Manage all VMs at once
./virtualmachine/host_scripts/start_all_vms.sh
./virtualmachine/host_scripts/stop_all_vms.sh
./virtualmachine/host_scripts/savestate_all_vms.sh
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


## Architecture

### Communication Flow
1. AutoGen agent connects directly to Discord using bot token
2. Admin/AI replies in Discord → agent receives via Discord API
3. MCP (Model Context Protocol) servers provide additional integrations

### Security Model
- Each developer has a dedicated Discord bot token
- Bot tokens configured via environment variables in containers/VMs
- Direct Discord API communication for reliable message delivery

### Key Files
- `config/dev_users.txt`: List of developer usernames (one per line)
- `docker/.env`: Discord bot tokens and environment variables (BOT_TOKEN_USERNAME=token)
- `autogen_agent/.env`: AI service credentials and Discord app token
- `virtualmachine/Vagrantfile`: VM configuration and provisioning logic

## Testing


### Autogen Agent
```bash
cd autogen_agent
# Test by interacting with bot in Discord
# Check logs with ./get_logs.sh for errors
```

### VM Provisioning
```bash
# Test VM creation and setup
./virtualmachine/host_scripts/provision_vm.sh testuser
# Verify VM boots and has all tools installed
```

## Common Development Tasks

### Adding a New Developer
1. Add username to `config/dev_users.txt`
2. Create Discord bot application and add token to `docker/.env`
3. Run `./virtualmachine/host_scripts/provision_vm.sh <username>` for VMs or `./docker/scripts/provision_container.sh <username>` for containers

### Updating VM Software
1. Edit provisioning script in `virtualmachine/Vagrantfile`
2. Run `./virtualmachine/host_scripts/provision_all_vms.sh` to update all VMs

### Debugging Discord Communication
1. Check autogen bot logs: `cd autogen_agent && ./get_logs.sh`
2. Check container logs: `docker logs agent-<username>`
3. Verify bot tokens in `.env` files are correct
4. Test by sending messages directly in Discord to the bot

## Development Workflow

1. When you are given a task for this project, the first thing you must ensure is that you have a feature branch for your task. Never work directly on master.
2. Once you have your feature branch, you must ensure that you have a pull request (PR) for that branch. There can only ever be 1 PR for each branch. You can use the `gh` cli tool to check for PRs to see if one already exists for your feature branch. 
3. If a PR does not exist for your feature branch create one using the same `gh` cli command.

## Completing a Task

1. In this project, whenever you finish a task, please run the necessary commands in terminal to test your code changes. Depending on the task there may already be test scrpts under `tests` directories that you should reuse if they exist. Or add to if they do not exist
2. When you have confirmed that your changes are working then do the following
    1. Update the PR for your feature branch to include any additional code changes you made for this task, use the `gh` cli for this
    2. On the PR make sure to include a detailed description of all the changes you made and in which files, why you made those changes, and then also describe any uncertainties or issues you encountered. If the PR description already exists make sure to update it and not overwrite what is already there
    3. Add all files you have made changes to using the `git add` command
    4. Then commit the files you added by using the `git commit` command, providing a descriptive commit message of what the changes include
    5. Push your commit using `git push`, confirm that it was pushed successfully
    6. Then tell the user that the task is complete, and that you added, committed, and pushed the changes successfully. Please provide a link to your PR so that the user can review your code changes
    7. NOTE: the user isn't always available directly at the computer. This is why you have been given a discord MCP. Make sure to always notify the user via discord otherwise you may have to wait a long time for them to come back to the computer which will affect your ability to complete your task in a timely manner
