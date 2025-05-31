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
    chmod +x virtualmachine/host_scripts/provision_vm.sh
    ./virtualmachine/host_scripts/provision_vm.sh <developer_username>
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

A set of scripts are provided in `virtualmachine/host_scripts/` to manage individual VMs by username, primarily using `vagrant` commands. Make sure they are executable (`chmod +x virtualmachine/host_scripts/*.sh`). Replace `<username>` with the target developer's username (e.g., `jsmith`).

- **Provision (Create or Update):** `./virtualmachine/host_scripts/provision_vm.sh <username>`
  - Creates the VM if it doesn't exist, starts it if stopped, and runs/re-runs the `virtualmachine/guest_scripts/setup_dev.sh` provisioning.
- **Start/Resume VM:** `./virtualmachine/host_scripts/start_vm.sh <username>` (Uses `vagrant up`)
  - Starts the VM if powered off or saved. Does nothing if already running.
- **Stop VM (Graceful Shutdown):** `./virtualmachine/host_scripts/stop_vm.sh <username>` (Uses `vagrant halt`)
  - Gracefully shuts down the VM.
- **Restart VM (Graceful):** `./virtualmachine/host_scripts/restart_vm.sh <username>` (Uses `vagrant reload`)
  - Gracefully stops, then starts the VM. Starts it if already stopped.
- **Save VM State (Suspend):** `./virtualmachine/host_scripts/savestate_vm.sh <username>` (Uses `vagrant suspend`)
  - Suspends the VM and saves its current state to disk.
- **Restart VM (via Suspend/Resume):** `./virtualmachine/host_scripts/restart_savestate_vm.sh <username>` (Uses `vagrant suspend` and `vagrant resume`)
  - Suspends the VM state, then immediately resumes it. Only works if VM is running or already suspended.
- **SSH into the VM (command line):** `DEV_USERNAME=<username> vagrant ssh` (Run from `virtualmachine/` directory)
  - Connects as the default `vagrant` user. Requires the `DEV_USERNAME` environment variable.
- **Destroy the VM (delete it completely):** `./virtualmachine/host_scripts/destroy_vm.sh <username>` (Uses `vagrant destroy <name>` with fallback to `vagrant destroy <global_id>`)
  - Use with caution! Attempts to destroy the VM via its name, and if that fails due to inconsistent state, tries to find and destroy it via its global ID.

## Managing All VMs (Bulk Operations)

1.  **Configure User List:**

    - Edit the `config/dev_users.txt` file.
    - Add one developer username per line. Lines starting with `#` and empty lines are ignored.

2.  **Provision All VMs (Create or Update):**

    - Ensure the script is executable: `chmod +x virtualmachine/host_scripts/provision_all_vms.sh`
    - Execute the script: `./virtualmachine/host_scripts/provision_all_vms.sh`
    - The script iterates through each username in `config/dev_users.txt` and calls `./virtualmachine/host_scripts/provision_vm.sh <username>` for each.
    - **Note:** This script attempts to continue processing other users if an error occurs for one user.

3.  **Other Bulk Operations:**
    - Ensure the scripts are executable: `chmod +x virtualmachine/host_scripts/*_all_vms.sh`
    - **Start/Resume All VMs:** `./virtualmachine/host_scripts/start_all_vms.sh`
      - Iterates through `config/dev_users.txt` and runs `start_vm.sh` for each user.
    - **Stop All VMs (Graceful):** `./virtualmachine/host_scripts/stop_all_vms.sh`
      - Iterates through `config/dev_users.txt` and runs `stop_vm.sh` for each user.
    - **Save State for All VMs (Suspend):** `./virtualmachine/host_scripts/savestate_all_vms.sh`
      - Iterates through `config/dev_users.txt` and runs `savestate_vm.sh` for each user.
    - **Destroy All VMs:** `./virtualmachine/host_scripts/destroy_all_vms.sh`
      - Iterates through `config/dev_users.txt` and runs `destroy_vm.sh` for each user.
    - **Note:** These bulk scripts attempt to continue processing other users if an error occurs for one user. They report a summary of successes and failures at the end.

## AutoGen Discord Integration

The VMs and Docker containers are configured to run AutoGen agents that connect directly to Discord for communication.

### Architecture

- **Discord Bots:** One bot application per developer (e.g., `testuser-bot`, `anum-bot`) created in the Discord Developer Portal.
- **AutoGen Agent:** Python agent (`autogen_agent/autogen_discord_bot.py`) runs inside each VM/container and connects directly to Discord.
- **MCP Integration:** Model Context Protocol servers provide additional integrations for enhanced functionality.

### Setup

1.  **Create Discord Bots:**
    - Go to the [Discord Developer Portal](https://discord.com/developers/applications).
    - Create a new application/bot for **each** developer username listed in `config/dev_users.txt`. Name them clearly (e.g., `jsmith-bot`).
    - In the "Bot" tab for each bot, enable the **Message Content Intent** under Privileged Gateway Intents.
    - Reset and copy the **Token** for each bot.
    - Invite each bot to your Discord server.

2.  **Configure Environment:**
    - For VMs: Configure environment variables in the VM's `.env` file
    - For Docker: Add bot tokens to `docker/.env` file with format `BOT_TOKEN_<username>=your_token_here`

3.  **Run AutoGen Agent:**
    - **In VMs:** `cd autogen_agent && ./start_agent.sh`
    - **In Docker:** Agents start automatically when containers are launched
