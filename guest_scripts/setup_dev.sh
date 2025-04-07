#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Use the DEV_USER environment variable passed by Vagrant, default to 'devuser'
USERNAME=${DEV_USER:-devuser}

echo ">>> Starting provisioning script for user: $USERNAME"

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Non-interactive frontend for apt commands to avoid prompts
export DEBIAN_FRONTEND=noninteractive

echo ">>> Updating package lists..."
apt-get update -y

echo ">>> Installing Xubuntu Desktop Environment..."
# Install the core Xubuntu desktop and LightDM display manager
# Use --no-install-recommends to keep it slightly leaner if desired, but full install is safer for compatibility
apt-get install -y xubuntu-desktop lightdm

# Ensure LightDM is the default display manager (usually handled by install, but good to be sure)
# dpkg-reconfigure lightdm # This might still be interactive, skip for now

echo ">>> Installing common development tools and dependencies..."
# Add wget, gpg for adding external repos, apt-transport-https for https sources
apt-get install -y git vim curl build-essential net-tools openssh-server wget gpg apt-transport-https

# --- Install Google Chrome ---
echo ">>> Installing Google Chrome..."
# Add Google Chrome key (use --batch --yes for non-interactive gpg)
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor --batch --yes -o /usr/share/keyrings/google-chrome-keyring.gpg
# Add Google Chrome repository
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
# Update package list and install Chrome
apt-get update -y
apt-get install -y google-chrome-stable

# --- Install Visual Studio Code ---
echo ">>> Installing Visual Studio Code..."
# Add Microsoft GPG key (use --batch --yes for non-interactive gpg)
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor --batch --yes > /usr/share/keyrings/packages.microsoft.gpg
# Add VS Code repository
echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
# Update package list and install VS Code
apt-get update -y
apt-get install -y code

echo ">>> Creating user: $USERNAME ..."
if id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME already exists."
else
    # Create the user with a home directory, default bash shell
    useradd -m -s /bin/bash "$USERNAME"
    echo "User $USERNAME created."

    # Add user to the sudo group for admin privileges
    adduser "$USERNAME" sudo
    echo "User $USERNAME added to sudo group."

    # Set a default password (INSECURE - FOR DEMO ONLY)
    # Replace 'password' with a more secure method in a real scenario
    # (e.g., prompt user, use SSH keys, generate random password and display it)
    echo "$USERNAME:password" | chpasswd
    echo "Set default password 'password' for user $USERNAME. CHANGE THIS IMMEDIATELY!"

    # Optional: Copy SSH keys from vagrant user if needed for SSH access later
    # mkdir -p /home/$USERNAME/.ssh
    # cp /home/vagrant/.ssh/authorized_keys /home/$USERNAME/.ssh/authorized_keys
    # chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
    # chmod 700 /home/$USERNAME/.ssh
    # chmod 600 /home/$USERNAME/.ssh/authorized_keys
    # --- User-specific setup ---
    echo ">>> Performing user-specific setup for $USERNAME..."

    # Install VS Code extension (Cline) as the user
    # Need to run this as the user, ensuring HOME is set correctly
    echo "Installing VS Code Cline extension for $USERNAME..."
    sudo -i -u "$USERNAME" bash -c 'code --install-extension SaoudRizwan.cline --force' || echo "VS Code extension install failed (maybe first run before code path is set?)"

    # Set default browser (best effort during provisioning)
    echo "Attempting to set Google Chrome as default browser for $USERNAME..."
    # Ensure the .desktop file exists first
    if [ -f /usr/share/applications/google-chrome.desktop ]; then
        sudo -i -u "$USERNAME" bash -c 'xdg-settings set default-web-browser google-chrome.desktop' || echo "Failed to set default browser via xdg-settings."
    else
        echo "Warning: google-chrome.desktop not found. Cannot set default browser."
    fi

    # --- Set Environment Variables for User ---
    echo "Setting DEVCHAT_HOST_IP environment variable in /home/$USERNAME/.bashrc ..."
    # Append the export command to the user's .bashrc
    echo '' >> "/home/$USERNAME/.bashrc" # Add a newline for separation
    echo '# Set IP for host service communication' >> "/home/$USERNAME/.bashrc"
    echo 'export DEVCHAT_HOST_IP=10.0.2.2' >> "/home/$USERNAME/.bashrc"
    # Ensure the file is owned by the user
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.bashrc"

fi

# --- Set Environment Variables for User (Run Every Time) ---
# Ensure this runs even if the user already existed
if [ -f "/home/$USERNAME/.bashrc" ]; then
    # Check if the line already exists to avoid duplicates
    if ! grep -q 'export DEVCHAT_HOST_IP=10.0.2.2' "/home/$USERNAME/.bashrc"; then
        echo "Setting DEVCHAT_HOST_IP environment variable in /home/$USERNAME/.bashrc ..."
        echo '' >> "/home/$USERNAME/.bashrc" # Add a newline for separation
        echo '# Set IP for host service communication' >> "/home/$USERNAME/.bashrc"
        echo 'export DEVCHAT_HOST_IP=10.0.2.2' >> "/home/$USERNAME/.bashrc"
        # Ownership should be correct if user exists or was just created
    else
         echo "DEVCHAT_HOST_IP already set in /home/$USERNAME/.bashrc."
    fi
else
    echo "Warning: /home/$USERNAME/.bashrc not found. Cannot set DEVCHAT_HOST_IP."
fi


# --- Install Node.js and npm ---
echo ">>> Installing Node.js and npm..."
# Check if Node.js is installed, install if not (using nodesource setup)
if ! command -v node &> /dev/null; then
    echo "Node.js not found, installing..."
    # Use nodesource setup script for a recent version (e.g., Node 20 LTS)
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
else
    echo "Node.js already installed: $(node -v)"
fi
# Ensure npm is available (usually comes with nodejs package)
if ! command -v npm &> /dev/null; then
    echo "npm not found, installing..."
    apt-get install -y npm # Or consider reinstalling nodejs package
else
     echo "npm already installed: $(npm -v)"
fi


# --- Install devchat CLI tool ---
echo ">>> Installing devchat CLI tool wrapper..."
# Create a wrapper script in /usr/local/bin that executes the actual script
# from its source directory (/vagrant/vm_cli) so node_modules are found.
DEVCHAT_SOURCE_DIR="/vagrant/vm_cli" # Assuming default synced folder
DEVCHAT_SCRIPT="devchat.js"
DEVCHAT_WRAPPER="/usr/local/bin/devchat"

if [ -f "${DEVCHAT_SOURCE_DIR}/${DEVCHAT_SCRIPT}" ]; then
    # Create the wrapper script content
    WRAPPER_CONTENT="#!/bin/bash\n# Wrapper for devchat CLI\ncd \"${DEVCHAT_SOURCE_DIR}\" || exit 1\nexec node \"${DEVCHAT_SCRIPT}\" \"\$@\""

    # Write the wrapper script
    echo -e "${WRAPPER_CONTENT}" > "${DEVCHAT_WRAPPER}"
    chmod +x "${DEVCHAT_WRAPPER}"
    echo "devchat wrapper installed to ${DEVCHAT_WRAPPER}"
else
    echo "Warning: ${DEVCHAT_SOURCE_DIR}/${DEVCHAT_SCRIPT} not found. Cannot install devchat tool."
    echo "Ensure the vm_cli directory is present in the project root and synced."
fi


# --- Install Correct VirtualBox Guest Additions ---
echo ">>> Installing VirtualBox Guest Additions (target: 6.1.50)..."
# Install prerequisites for building kernel modules (might be redundant but ensures they are present)
apt-get install -y build-essential dkms linux-headers-$(uname -r)

# Download the correct Guest Additions ISO
# Using 6.1.50 as it matches the DKMS version installed on the host via apt
GA_VERSION="6.1.50"
GA_ISO="VBoxGuestAdditions_${GA_VERSION}.iso"
GA_URL="https://download.virtualbox.org/virtualbox/${GA_VERSION}/${GA_ISO}"
ISO_MOUNT_POINT="/mnt/iso"

echo "Downloading Guest Additions ISO from ${GA_URL}..."
wget -q -O "/tmp/${GA_ISO}" "${GA_URL}"
if [ $? -ne 0 ]; then
    echo "Error: Failed to download Guest Additions ISO. Skipping installation."
else
    echo "Mounting Guest Additions ISO..."
    mkdir -p "${ISO_MOUNT_POINT}"
    mount "/tmp/${GA_ISO}" "${ISO_MOUNT_POINT}" -o loop

    if [ $? -ne 0 ]; then
        echo "Error: Failed to mount Guest Additions ISO. Skipping installation."
    else
        echo "Running Guest Additions installer..."
        # Use --nox11 because this script runs non-interactively.
        # The --force flag is not valid for 6.1.50 installer. It might prompt or handle overwrite automatically.
        if /bin/sh "${ISO_MOUNT_POINT}/VBoxLinuxAdditions.run" --nox11; then
             echo "Guest Additions installation script finished."
             # Check the log file for specific success/failure messages if needed
        else
             echo "Warning: Guest Additions installation script execution failed. Check /var/log/vboxadd-setup.log"
        fi

        echo "Cleaning up Guest Additions ISO..."
        umount "${ISO_MOUNT_POINT}" || echo "Warning: Failed to unmount ISO."
    fi
    rm -f "/tmp/${GA_ISO}"
    rmdir "${ISO_MOUNT_POINT}" || echo "Warning: Failed to remove mount point dir."
fi
# --- End Guest Additions Install ---


# Clean up apt cache
apt-get clean

echo ">>> Provisioning complete for user: $USERNAME"
echo ">>> You should be able to log in via the GUI with username '$USERNAME' and password 'password'."
echo ">>> IMPORTANT: Change the default password immediately after login!"

# Reboot to ensure GUI starts correctly after installation
echo ">>> Rebooting VM in 5 seconds..."
sleep 5
reboot

exit 0
