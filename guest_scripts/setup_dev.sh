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
# Add unzip for AWS CLI, python3 and pip for SAM CLI
apt-get install -y git vim curl build-essential net-tools openssh-server wget gpg apt-transport-https unzip python3 python3-pip

# --- Install Latest GitHub CLI (gh) ---
echo ">>> Installing latest GitHub CLI..."
# Remove existing gh if installed via apt to avoid conflicts
apt-get remove -y gh || echo "gh not installed via apt, proceeding."
# Clean up old apt source if it exists
rm -f /etc/apt/sources.list.d/github-cli.list
apt-get update -y

# Download the latest .deb package from GitHub releases
# Determine architecture
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" = "amd64" ]; then
    GH_ARCH="amd64"
elif [ "$ARCH" = "arm64" ]; then
    GH_ARCH="arm64"
# Add other architectures if needed, e.g., armhf
else
    echo "Unsupported architecture: $ARCH for gh cli download."
    exit 1
fi

GH_VERSION=$(curl -s "https://api.github.com/repos/cli/cli/releases/latest" | grep -Po '"tag_name": "v\K[0-9.]+')
if [ -z "$GH_VERSION" ]; then
    echo "Failed to fetch latest gh version. Exiting."
    exit 1
fi
echo "Latest gh version: $GH_VERSION"
GH_DEB_URL="https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GH_ARCH}.deb"
GH_DEB_PATH="/tmp/gh_${GH_VERSION}_linux_${GH_ARCH}.deb"

echo "Downloading gh from ${GH_DEB_URL}..."
wget -q -O "${GH_DEB_PATH}" "${GH_DEB_URL}"
if [ $? -ne 0 ]; then
    echo "Error: Failed to download gh deb package. Exiting."
    exit 1
fi

echo "Installing gh deb package..."
# Use apt install to handle dependencies
apt-get install -y "${GH_DEB_PATH}"
if [ $? -ne 0 ]; then
    echo "Error: Failed to install gh deb package. Exiting."
    exit 1
fi

# Clean up downloaded deb
rm -f "${GH_DEB_PATH}"
echo "Latest GitHub CLI installed successfully."
# Verify version (optional)
gh --version

# --- Install AWS CLI v2 ---
echo ">>> Installing AWS CLI v2..."
cd /tmp
# Check if AWS CLI is already installed before downloading/installing
if command -v aws &> /dev/null; then
    echo "AWS CLI already installed. Attempting update..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -oq awscliv2.zip # Use -o to overwrite without prompt, -q for quiet
    ./aws/install --update # Use --update flag
    rm -rf aws awscliv2.zip
    echo "AWS CLI updated."
else
    echo "AWS CLI not found. Performing fresh install..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip # Use -q for quiet
    ./aws/install # Installs to /usr/local/aws-cli and creates symlink at /usr/local/bin/aws
    rm -rf aws awscliv2.zip
    echo "AWS CLI installed."
fi
# Verify (optional)
# aws --version

# --- Install AWS SAM CLI ---
echo ">>> Installing pipx..."
apt-get install -y pipx
# Ensure pipx paths are available for the target user
# Run this as the user to set up the pipx environment correctly
echo "Ensuring pipx path for user $USERNAME..."
sudo -i -u "$USERNAME" bash -c 'pipx ensurepath' || echo "Warning: pipx ensurepath command failed."

echo ">>> Installing AWS SAM CLI using pipx..."
# Install SAM CLI using pipx - run as root, pipx handles user context? Or run as user?
# Let's try running as the target user to ensure it's installed in their context.
sudo -i -u "$USERNAME" bash -c 'pipx install aws-sam-cli' || echo "Warning: pipx install aws-sam-cli failed."
echo "AWS SAM CLI installation attempted via pipx."

# Note: pipx ensurepath should have added ~/.local/bin to the PATH in .bashrc or similar
# Let's double-check and add it if missing, as before.
if [ -f "/home/$USERNAME/.bashrc" ]; then
    if ! grep -q '.local/bin' "/home/$USERNAME/.bashrc"; then
        echo "Adding ~/.local/bin to PATH in /home/$USERNAME/.bashrc (fallback for pipx/sam)..."
        echo '' >> "/home/$USERNAME/.bashrc"
        echo '# Add local bin to PATH for pipx/pip user installs' >> "/home/$USERNAME/.bashrc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "/home/$USERNAME/.bashrc"
    fi
fi
# Verify (optional, run as user after sourcing .bashrc or new login)
# sudo -i -u "$USERNAME" bash -c 'source ~/.bashrc && sam --version'


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
fi # End of the user creation block

# --- GitHub CLI Auth & Git Config (Run Every Time) ---
# This block should run regardless of whether the user was just created or already existed.
echo ">>> Configuring GitHub CLI and Git for $USERNAME..."
# Check for the installation token instead of App ID/Key
if [ -n "$GH_INSTALLATION_TOKEN" ] && [ -n "$GIT_AUTHOR_NAME" ] && [ -n "$GIT_AUTHOR_EMAIL" ]; then
    echo "GitHub Installation Token and Git author info found, attempting configuration..."
    # TEMP_KEY_PATH is no longer needed

    # Ensure the user's home directory exists and has correct permissions before proceeding
    if [ ! -d "/home/$USERNAME" ]; then
        echo "Error: Home directory /home/$USERNAME not found. Cannot configure GitHub/Git."
    else
        # Ensure ownership is correct before running sudo
        chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
        echo "Attempting to execute sudo block for $USERNAME (using sudo -u, direct command)..."

        # Run as the user using sudo -u and bash -c
        sudo -u "$USERNAME" HOME="/home/$USERNAME" bash -c "
            # set -e # Temporarily disable exit on error for debugging
            echo '[User Shell] Starting GitHub/Git config...'
            # No private key decoding needed

            echo '[User Shell] Attempting gh auth login (with --with-token)...'
            # Pipe the token to gh auth login
            echo \"$GH_INSTALLATION_TOKEN\" | gh auth login --hostname github.com --with-token
            GH_AUTH_STATUS=\$?
            echo \"[User Shell] gh auth login exited with status: \$GH_AUTH_STATUS\"

            if [ \$GH_AUTH_STATUS -eq 0 ]; then
                echo '[User Shell] gh auth login successful.'
                echo '[User Shell] Configuring Git user...'
                git config --global user.name \"$GIT_AUTHOR_NAME\"
                git config --global user.email \"$GIT_AUTHOR_EMAIL\"
                echo '[User Shell] Git configured.'
            else
                echo '[User Shell] gh auth login failed. Skipping git config.'
            fi

            echo '[User Shell] Displaying gh config:'
            cat ~/.config/gh/hosts.yml || echo '[User Shell] Could not cat gh config file.'

            # No temporary key to clean up
            echo '[User Shell] GitHub CLI and Git configuration attempt finished.'
            exit \$GH_AUTH_STATUS # Exit subshell with gh auth status
        "
        SUDO_EXIT_STATUS=$?
        echo "Sudo command finished with exit status: $SUDO_EXIT_STATUS"
        if [ $SUDO_EXIT_STATUS -ne 0 ]; then
             echo "Warning: Subshell for GitHub/Git configuration failed for $USERNAME."
        fi

        # No key file to clean up here either
    fi
else
    # Update warning message
    echo "Warning: GitHub Installation Token or Git author info not provided via environment variables (GH_INSTALLATION_TOKEN, GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL). Skipping gh auth and git config."
fi
# --- End GitHub CLI Auth & Git Config ---

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
    echo "Node.js not found, installing Node.js v22..."
    # Use nodesource setup script for Node 22 LTS
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
else
    # Check if the installed version is v22, upgrade if not? For simplicity, just log for now.
    # A more robust check could compare `node -v` output.
    echo "Node.js already installed: $(node -v). Ensure it is v22 if required."
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
