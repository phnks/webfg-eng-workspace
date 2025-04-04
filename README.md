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
        *   Run the `setup_dev.sh` script inside the VM to install the Xubuntu desktop environment, common tools, and create the specified user (`<developer_username>`).
        *   A VirtualBox window displaying the VM's desktop login screen should appear.

3.  **Login:**
    The developer can log into the Xubuntu VM using:
    *   **Username:** `<developer_username>` (the one provided in the command)
    *   **Password:** `password` (the default insecure password set by the script)

    **IMPORTANT:** The developer MUST change this default password immediately after their first login for security reasons!

## Managing the VM

Use standard Vagrant commands from the `webfg-eng-workspace` directory:

*   **Stop the VM:** `vagrant halt`
*   **Start the VM (without provisioning):** `vagrant up` (if already created)
*   **Restart the VM (and re-run provisioner if needed):** `vagrant reload` or `vagrant reload --provision`
*   **SSH into the VM (command line):** `vagrant ssh` (connects as the default `vagrant` user)
*   **Destroy the VM (delete it completely):** `vagrant destroy` (use with caution!)
