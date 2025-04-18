# WEBFG Engineering Team Workspace

**Developer VM Workspace Setup**

This repo contains everything you need to spin up per‑developer Xubuntu 24.04 desktop VMs via Vagrant + VirtualBox.

---

## Host Prerequisites

Before you can bring up any developer VM, your **host** needs:

1. **Ubuntu/Debian** (tested on 22.04 / Jammy)

2. **Oracle VirtualBox 7.0.x**  
   We pin downstream to the official 7.0 series so guest additions and kernel modules match exactly.

   ```bash
   # 1) Import Oracle’s apt key into the new keyring
   sudo mkdir -p /usr/share/keyrings
   curl -fsSL https://www.virtualbox.org/download/oracle_vbox_2016.asc \
     | sudo gpg --dearmor -o /usr/share/keyrings/oracle_vbox-archive-keyring.gpg

   # 2) Add the VirtualBox 7.0 repo
   echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle_vbox-archive-keyring.gpg] \
     https://download.virtualbox.org/virtualbox/debian \
     $(lsb_release -cs) contrib" \
     | sudo tee /etc/apt/sources.list.d/virtualbox.list

   # 3) Update & install
   sudo apt update
   sudo apt install -y \
     virtualbox-7.0 \
     virtualbox-dkms \
     linux-headers-$(uname -r) \
     linux-headers-generic

   # 4) (Re)build the vboxdrv module
   sudo /sbin/vboxconfig
   ```

Note: If you have Secure Boot enabled, either disable it or sign the vboxdrv module before running vboxconfig.

3. Vagrant

```bash
# 1) Add HashiCorp GPG key
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# 2) Add the Vagrant repo
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com \
  $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list

# 3) Update & install
sudo apt update
sudo apt install -y vagrant

# 4) Install the vbguest plugin so your host/guest Additions stay in sync
sudo vagrant plugin install vagrant-vbguest
```

4. (Optional) Disable conflicting KVM modules

If you ever need to run nested VMs, VirtualBox and KVM can clash. If you run into “Guru Meditation” errors, you can blacklist:

```bash
echo -e "blacklist kvm\nblacklist kvm_intel\nblacklist kvm_amd" \
  | sudo tee /etc/modprobe.d/99-disable-kvm.conf
sudo update-initramfs -u
```

## Provisioning a Developer VM (Create or Update)

1.  **Clone this Repository:**

    ```bash
    git clone <your-repository-url>
    cd webfg-eng-workspace
    ```

2.  **Run the Provisioning Script:**
    Open a terminal in the `webfg-eng-workspace` directory. Use the unified `provision_vm.sh` script located in `host_scripts/`, passing the desired username as an argument.

    Replace `<developer_username>` with the actual username (e.g., `jsmith`, `adoe`).

    ```bash
    chmod +x host_scripts/provision_vm.sh
    ./host_scripts/provision_vm.sh <developer_username>
    ```

    - This command will:
      - Check if the VM `dev-<developer_username>-vm` exists.
      - If it doesn't exist:
        - Download the necessary Vagrant base box (`bento/ubuntu-24.04`) if not already present.
        - Create a new VirtualBox VM named `dev-<developer_username>-vm`.
        - Boot the VM.
        - Run the initial provisioning using `guest_scripts/setup_dev.sh`.
      - If it _does_ exist:
        - Ensure the VM is running (start it if stopped/saved).
        - Re-run the provisioning using `guest_scripts/setup_dev.sh`.
    - The `setup_dev.sh` script installs the Xubuntu desktop environment, common tools (git, vim, curl, etc.), Google Chrome, Visual Studio Code (with the Cline extension), and creates the specified user (`<developer_username>`).
    - The script attempts to set Google Chrome as the default browser.
    - The VM will automatically reboot after provisioning.
    - A VirtualBox window displaying the VM's desktop login screen should appear after the reboot.

3.  **Login:**
    The developer can log into the Xubuntu VM using:

    - **Username:** `<developer_username>` (the one provided in the command)
    - **Password:** `password` (the default insecure password set by the script)

    **IMPORTANT:** The developer MUST change this default password immediately after their first login for security reasons!

## Managing Individual VMs

A set of scripts are provided in `host_scripts/` to manage individual VMs by username, primarily using `vagrant` commands. Make sure they are executable (`chmod +x host_scripts/*.sh`). Replace `<username>` with the target developer's username (e.g., `jsmith`).

- **Provision (Create or Update):** `./host_scripts/provision_vm.sh <username>` (Replaces `create_dev_vm.sh` and `reprovision_vm.sh`)
  - Creates the VM if it doesn't exist, starts it if stopped, and runs/re-runs the `guest_scripts/setup_dev.sh` provisioning.
- **Start/Resume VM:** `./host_scripts/start_vm.sh <username>` (Uses `vagrant up`)
  - Starts the VM if powered off or saved. Does nothing if already running.
- **Stop VM (Graceful Shutdown):** `./host_scripts/stop_vm.sh <username>` (Uses `vagrant halt`)
  - Gracefully shuts down the VM.
- **Restart VM (Graceful):** `./host_scripts/restart_vm.sh <username>` (Uses `vagrant reload`)
  - Gracefully stops, then starts the VM. Starts it if already stopped.
- **Save VM State (Suspend):** `./host_scripts/savestate_vm.sh <username>` (Uses `vagrant suspend`)
  - Suspends the VM and saves its current state to disk.
- **Restart VM (via Suspend/Resume):** `./host_scripts/restart_savestate_vm.sh <username>` (Uses `vagrant suspend` and `vagrant resume`)
  - Suspends the VM state, then immediately resumes it. Only works if VM is running or already suspended.
- **SSH into the VM (command line):** `DEV_USERNAME=<username> vagrant ssh`
  - Connects as the default `vagrant` user. Requires the `DEV_USERNAME` environment variable.
- **Destroy the VM (delete it completely):** `./host_scripts/destroy_vm.sh <username>` (Uses `vagrant destroy <name>` with fallback to `vagrant destroy <global_id>`)
  - Use with caution! Attempts to destroy the VM via its name, and if that fails due to inconsistent state, tries to find and destroy it via its global ID.

## Managing All VMs (Bulk Operations)

1.  **Configure User List:**

    - Edit the `config/dev_users.txt` file.
    - Add one developer username per line. Lines starting with `#` and empty lines are ignored.

2.  **Provision All VMs (Create or Update):**

    - Ensure the script is executable: `chmod +x host_scripts/provision_all_vms.sh`
    - Execute the script: `./host_scripts/provision_all_vms.sh`
    - The script iterates through each username in `config/dev_users.txt` and calls `./host_scripts/provision_vm.sh <username>` for each.
    - **Note:** This script attempts to continue processing other users if an error occurs for one user.

3.  **Other Bulk Operations:**
    - Ensure the scripts are executable: `chmod +x host_scripts/*_all_vms.sh`
    - **Start/Resume All VMs:** `./host_scripts/start_all_vms.sh`
      - Iterates through `config/dev_users.txt` and runs `start_vm.sh` for each user.
    - **Stop All VMs (Graceful):** `./host_scripts/stop_all_vms.sh`
      - Iterates through `config/dev_users.txt` and runs `stop_vm.sh` for each user.
    - **Save State for All VMs (Suspend):** `./host_scripts/savestate_all_vms.sh`
      - Iterates through `config/dev_users.txt` and runs `savestate_vm.sh` for each user.
    - **Destroy All VMs:** `./host_scripts/destroy_all_vms.sh`
      - Iterates through `config/dev_users.txt` and runs `destroy_vm.sh` for each user.
    - **Note:** These bulk scripts attempt to continue processing other users if an error occurs for one user. They report a summary of successes and failures at the end.

## Developer Chat Feature (`devchat`)

This setup includes a CLI tool (`devchat`) within each VM that allows developers to send messages to a designated admin via Discord DMs and wait for a reply.

### Architecture

- **Multiple Discord Bots:** One bot application per developer (e.g., `testuser-bot`, `anum-bot`) must be created in the Discord Developer Portal.
- **Host Service:** A Node.js service (`host_service/index.js`) runs on the **host machine**. It securely stores all bot tokens, relays messages to Discord, listens for replies from the admin, and notifies the relevant CLI tool via WebSocket.
- **CLI Tool:** A Node.js script (`vm_cli/devchat.js`) is installed as `devchat` inside each VM. It sends a message and then waits for a notification from the host service before fetching and displaying the reply.

### Host Service Setup

1.  **Create Discord Bots:**
    - Go to the [Discord Developer Portal](https://discord.com/developers/applications).
    - Create a new application/bot for **each** developer username listed in `config/dev_users.txt`. Name them clearly (e.g., `jsmith-bot`).
    - In the "Bot" tab for each bot, enable the **Message Content Intent** under Privileged Gateway Intents.
    - Reset and copy the **Token** for each bot.
    - Invite each bot to your Discord server or ensure they can DM you.
2.  **Get Admin User ID:**
    - Enable Developer Mode in Discord settings (Advanced).
    - Right-click your username and "Copy User ID" (or use the `\@YourUsername` mention trick).
3.  **Configure Environment:**
    - Navigate to the `host_service` directory.
    - Copy the template file: `cp .env.template .env`
    - Edit the `.env` file with a text editor.
    - Fill in your `ADMIN_DISCORD_ID`.
    - Fill in the `BOT_TOKEN_<username>` for each developer listed in `config/dev_users.txt`. Make sure the usernames match exactly.
    - Save the `.env` file. **Do not commit this file to Git.**
4.  **Install Dependencies:**

    ```bash
    # Install host service dependencies
    cd host_service
    npm install
    cd ..

    # Install VM CLI dependencies
    cd vm_cli
    npm install
    cd ..
    ```

5.  **Run the Service:**
    Use the provided helper scripts in `host_scripts/`:
    - **Start:** `./host_scripts/start_host_service.sh` (Runs in background, logs to `host_service/host_service.log`, stores PID in `host_service/.pid`)
    - **Stop:** `./host_scripts/stop_host_service.sh`
    - **Restart:** `./host_scripts/restart_host_service.sh`

### Using `devchat` in the VM

Once a VM is provisioned and the host service is running:

1.  **Log into the VM.**
2.  **Send a message and wait for reply:**

    - To the admin (configured via `ADMIN_DISCORD_ID`):

      ```bash
      # Ensure DEVCHAT_HOST_IP is set if needed (e.g., in .bashrc or profile)
      # export DEVCHAT_HOST_IP=10.0.2.2 # Example for default NAT

      devchat @admin "Hello, I need help with..."
      ```

      (You can also use the admin's actual Discord User ID instead of `@admin`)

    - The message will appear in Discord as a DM from the bot associated with the VM's user (e.g., `anum-bot`).
    - The `devchat` command will print "Send confirmation..." and then "Waiting for reply notification...".
    - It will wait (up to 30 minutes by default) for the admin to reply.

3.  **Admin Reply:** The admin replies directly to the bot's DM in Discord (e.g., replies to `anum-bot`).
4.  **CLI Receives Reply:** The host service detects the reply and sends a notification via WebSocket to the waiting `devchat` process. The CLI then fetches the message content via HTTP and displays it before exiting.

**Note:** The `devchat` command requires the `DEVCHAT_HOST_IP` environment variable to be set correctly inside the VM to point to the host machine's IP address (e.g., `10.0.2.2` for default VirtualBox NAT). You may want to add `export DEVCHAT_HOST_IP=10.0.2.2` to the VM user's `.bashrc` or `.profile` during provisioning.
