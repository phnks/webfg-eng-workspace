# WEBFG Engineering Team Workspace (Developer VM Workspace Setup)

This repository contains configuration files to automatically set up individual Xubuntu 24.04 desktop virtual machines for developers using Vagrant and VirtualBox.

## Prerequisites (Host Machine)

Before you can create developer VMs using this setup, you need the following software installed on your host machine (the machine running the commands):

1.  **VirtualBox:** The virtualization software that runs the VMs.
    *   Download and install from the official website: [https://www.virtualbox.org/wiki/Downloads](https://www.virtualbox.org/wiki/Downloads)
    *   Ensure you install both VirtualBox and the corresponding "VirtualBox Extension Pack" for full functionality (like USB support).

2.  **Vagrant:** The tool that automates the creation and provisioning of the VMs.
    *   Download and install from the official website: [https://developer.hashicorp.com/vagrant/downloads](https://developer.hashicorp.com/vagrant/downloads)
    *   Verify installation by opening a terminal and running: `vagrant --version`

### Automated Prerequisite Installation (for Admin on Debian/Ubuntu)

An `admin_setup.sh` script is included in the `host_scripts/` directory to attempt automated installation of VirtualBox and Vagrant using `apt` on Debian/Ubuntu-based systems.

**NOTE:** This script installs VirtualBox from the distribution repositories, which might be older than the version on virtualbox.org. It also **does not** install the VirtualBox Extension Pack, which must be done manually.

To run the script:
```bash
cd host_scripts
sudo chmod +x admin_setup.sh
sudo ./admin_setup.sh
cd .. # Return to project root
```

## Creating a Developer VM

1.  **Clone this Repository:**
    ```bash
    git clone <your-repository-url>
    cd webfg-eng-workspace
    ```

2.  **Run the Creation Script:**
    Open a terminal in the `webfg-eng-workspace` directory. Use the `create_dev_vm.sh` script located in `host_scripts/`, passing the desired username as an argument.

    Replace `<developer_username>` with the actual username (e.g., `jsmith`, `adoe`).

    ```bash
    chmod +x host_scripts/create_dev_vm.sh
    ./host_scripts/create_dev_vm.sh <developer_username>
    ```

    *   This command will:
        *   Download the necessary Vagrant base box (`ubuntu/noble64`) if not already present.
        *   Create a new VirtualBox VM named `dev-<developer_username>-vm`.
        *   Boot the VM.
    *   Run the `setup_dev.sh` script inside the VM to install the Xubuntu desktop environment, common tools (git, vim, curl, etc.), Google Chrome, Visual Studio Code (with the Cline extension), and create the specified user (`<developer_username>`).
    *   The script attempts to set Google Chrome as the default browser.
    *   The VM will automatically reboot after provisioning.
    *   A VirtualBox window displaying the VM's desktop login screen should appear after the reboot.

3.  **Login:**
    The developer can log into the Xubuntu VM using:
    *   **Username:** `<developer_username>` (the one provided in the command)
    *   **Password:** `password` (the default insecure password set by the script)

    **IMPORTANT:** The developer MUST change this default password immediately after their first login for security reasons!

## Managing Individual VMs

A set of scripts are provided in `host_scripts/` to manage individual VMs by username, using `VBoxManage` directly. Make sure they are executable (`chmod +x host_scripts/*.sh`). Replace `<username>` with the target developer's username (e.g., `jsmith`).

*   **Start/Resume VM:** `./host_scripts/start_vm.sh <username>`
    *   Starts the VM if powered off.
    *   Resumes the VM if its state was previously saved.
*   **Stop VM (Graceful Shutdown):** `./host_scripts/stop_vm.sh <username>`
    *   Sends an ACPI shutdown signal.
*   **Restart VM (Graceful):** `./host_scripts/restart_vm.sh <username>`
    *   Gracefully stops, then starts the VM.
*   **Save VM State:** `./host_scripts/savestate_vm.sh <username>`
    *   Suspends the VM and saves its current state to disk. Faster than shutdown, allows quick resume.
*   **Restart VM (via Save State):** `./host_scripts/restart_savestate_vm.sh <username>`
    *   Saves the VM state, then immediately resumes it. Useful for quick "restarts" without a full OS boot cycle if needed.
*   **Re-run Provisioning:** `./host_scripts/reprovision_vm.sh <username>`
    *   Re-runs the `guest_scripts/setup_dev.sh` script inside the specified user's *running* VM. Useful for applying updates made to the setup script. The VM must be running (the script will attempt to start it if it's not). The VM will reboot at the end of provisioning.
*   **SSH into the VM (command line):** `DEV_USERNAME=<username> vagrant ssh`
    *   Connects as the default `vagrant` user. Requires the `DEV_USERNAME` environment variable to target the correct VM if multiple exist.
*   **Destroy the VM (delete it completely):** `DEV_USERNAME=<username> vagrant destroy`
    *   Use with caution! Requires the `DEV_USERNAME` environment variable.

## Managing All VMs (Bulk Operations)

1.  **Configure User List:**
    *   Edit the `config/dev_users.txt` file.
    *   Add one developer username per line. Lines starting with `#` and empty lines are ignored.

2.  **Run the Management Script:**
    *   Ensure the script is executable: `chmod +x host_scripts/manage_all_vms.sh`
    *   Execute the script: `./host_scripts/manage_all_vms.sh`
    *   The script will iterate through each username in `config/dev_users.txt`.
    *   For each user:
        *   It checks if a VM named `dev-<username>-vm` exists in VirtualBox.
        *   If the VM **exists**, it ensures the VM is running (starting it if necessary) and then runs `vagrant provision` to apply the latest `guest_scripts/setup_dev.sh`.
        *   If the VM **does not exist**, it clears any potentially stale Vagrant state for the directory and runs `vagrant up` to create and provision the VM.
    *   **Note:** This script attempts to continue processing other users if an error occurs for one user.

3.  **Other Bulk Operations:**
    *   Ensure the scripts are executable: `chmod +x host_scripts/*_all_vms.sh`
    *   **Start/Resume All VMs:** `./host_scripts/start_all_vms.sh`
        *   Iterates through `config/dev_users.txt` and runs `start_vm.sh` for each user.
    *   **Stop All VMs (Graceful):** `./host_scripts/stop_all_vms.sh`
        *   Iterates through `config/dev_users.txt` and runs `stop_vm.sh` for each user.
    *   **Save State for All VMs:** `./host_scripts/savestate_all_vms.sh`
        *   Iterates through `config/dev_users.txt` and runs `savestate_vm.sh` for each user.
    *   **Note:** These bulk start/stop/savestate scripts also attempt to continue processing other users if an error occurs for one user. They report a summary of successes and failures at the end.

## Developer Chat Feature (`devchat`)

This setup includes a CLI tool (`devchat`) within each VM that allows developers to send messages to and receive replies from a designated admin via Discord DMs.

### Architecture

*   **Multiple Discord Bots:** One bot application per developer (e.g., `testuser-bot`, `anum-bot`) must be created in the Discord Developer Portal.
*   **Host Service:** A Node.js service (`host_service/index.js`) runs on the **host machine**. It securely stores all bot tokens and relays messages between the VMs and Discord.
*   **CLI Tool:** A Node.js script (`vm_cli/devchat.js`) is installed as `devchat` inside each VM.

### Host Service Setup

1.  **Create Discord Bots:**
    *   Go to the [Discord Developer Portal](https://discord.com/developers/applications).
    *   Create a new application/bot for **each** developer username listed in `config/dev_users.txt`. Name them clearly (e.g., `jsmith-bot`).
    *   In the "Bot" tab for each bot, enable the **Message Content Intent** under Privileged Gateway Intents.
    *   Reset and copy the **Token** for each bot.
    *   Invite each bot to your Discord server or ensure they can DM you.
2.  **Get Admin User ID:**
    *   Enable Developer Mode in Discord settings (Advanced).
    *   Right-click your username and "Copy User ID" (or use the `\@YourUsername` mention trick).
3.  **Configure Environment:**
    *   Navigate to the `host_service` directory.
    *   Copy the template file: `cp .env.template .env`
    *   Edit the `.env` file with a text editor.
    *   Fill in your `ADMIN_DISCORD_ID`.
    *   Fill in the `BOT_TOKEN_<username>` for each developer listed in `config/dev_users.txt`. Make sure the usernames match exactly.
    *   Save the `.env` file. **Do not commit this file to Git.**
4.  **Install Dependencies:**
    ```bash
    cd host_service
    npm install
    cd ..
    ```
5.  **Run the Service:**
    ```bash
    node host_service/index.js
    ```
    Keep this service running on the host machine. You might want to use a process manager like `pm2` or `nodemon` for development/production.

### Using `devchat` in the VM

Once a VM is provisioned and the host service is running:

1.  **Log into the VM.**
2.  **Send a message:**
    *   To the admin (configured via `ADMIN_DISCORD_ID`):
        ```bash
        devchat send @admin "Hello, I need help with..."
        ```
        (You can also use the admin's actual Discord User ID instead of `@admin`)
    *   The message will appear in Discord as a DM from the bot associated with the VM's user (e.g., `anum-bot`).
3.  **Receive messages:**
    ```bash
    devchat receive
    ```
    *   This checks for any new DMs sent *by the admin* directly *to the specific bot* associated with the VM user.

### Replying (Admin Workflow)

*   When you receive a DM from `testuser-bot`, simply reply directly to `testuser-bot` in Discord.
*   When `testuser` runs `devchat receive` in their VM, they will see your reply.
