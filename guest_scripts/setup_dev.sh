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

# --- Install GitHub CLI (gh) ---
echo ">>> Installing GitHub CLI..."
# Add GH CLI key and repository (following official instructions)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
apt-get update -y
apt-get install -y gh
echo "GitHub CLI installed."

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

fi

# --- Set Environment Variables for User (Run Every Time) ---
# Ensure this runs even if the user already existed
if [ -f "/home/$USERNAME/.bashrc" ]; then
    # Untested code by chatgpt, may not yet work just needs some tweaks like paths
    # put your helper scripts anywhere, e.g. /usr/local/bin
    sudo cp status_agent.sh restart_agent.sh stop_agent.sh start_agent.sh /usr/local/bin
    sudo chmod +x /usr/local/bin/agent_*.sh
    echo 'anum ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/agent
    echo 'homonculus ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/agent
    sudo chmod 0440 /etc/sudoers.d/agent

    grep -q '^AGENT_HOME='/etc/environment \
        || echo "AGENT_HOME=/home/anum/webfg-eng-workspace/autogen_agent" | sudo tee -a /etc/environment  #change to wherever we want the agent scripts to be ideally the agent doesn't have access to its own code
    if ! grep -q 'export AGENT_HOME=/home/anum/webfg-eng-workspace/autogen_agent' "/home/$USERNAME/.bashrc"; then
        echo "Setting AGENT_HOME environment variable in /home/$USERNAME/.bashrc ..."
        echo '' >> "/home/$USERNAME/.bashrc" # Add a newline for separation
        echo '# Set autogen agent home directory' >> "/home/$USERNAME/.bashrc"
        echo 'export AGENT_HOME=/home/anum/webfg-eng-workspace/autogen_agent' >> "/home/$USERNAME/.bashrc"
        # Ownership should be correct if user exists or was just created
    else
         echo "AGENT_HOME already set in /home/$USERNAME/.bashrc."
    fi

    # Untested code by chatgpt
    # 1. Export your GitHub username and PAT into env vars
    GIT_USERNAME=phnks
    GIT_TOKEN=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
    grep -q '^GIT_USERNAME='/etc/environment \
        || echo "GIT_USERNAME=$GIT_USERNAME" | sudo tee -a /etc/environment
    if ! grep -q "export GIT_USERNAME=$GIT_USERNAME" "/home/$USERNAME/.bashrc"; then
        echo "Setting GIT_USERNAME environment variable in /home/$USERNAME/.bashrc ..."
        echo '' >> "/home/$USERNAME/.bashrc" # Add a newline for separation
        echo '# Set git username' >> "/home/$USERNAME/.bashrc"
        echo "export GIT_USERNAME=$GIT_USERNAME" >> "/home/$USERNAME/.bashrc"
        # Ownership should be correct if user exists or was just created
    else
         echo "GIT_USERNAME already set in /home/$USERNAME/.bashrc."
    fi

    grep -q '^GIT_TOKEN='/etc/environment \
        || echo "GIT_TOKEN=$GIT_TOKEN" | sudo tee -a /etc/environment
    if ! grep -q "export GIT_TOKEN=$GIT_TOKEN" "/home/$USERNAME/.bashrc"; then
        echo "Setting GIT_TOKEN environment variable in /home/$USERNAME/.bashrc ..."
        echo '' >> "/home/$USERNAME/.bashrc" # Add a newline for separation
        echo '# Set git token' >> "/home/$USERNAME/.bashrc"
        echo "export GIT_TOKEN=$GIT_TOKEN" >> "/home/$USERNAME/.bashrc"
        # Ownership should be correct if user exists or was just created
    else
         echo "GIT_TOKEN already set in /home/$USERNAME/.bashrc."
    fi

    # 2. Tell git to store (and re‑use) your HTTPS creds
    git config --global credential.helper "store --file ~/.git-credentials"
    git config --global user.email "$USERNAME@email.com"
    git config --global user.name "$USERNAME"

    # 3. Populate the credentials file
    cat > ~/.git-credentials <<< "https://${GIT_USERNAME}:${GIT_TOKEN}@github.com"

    # 4. Lock it down
    chmod 600 ~/.git-credentials

    # 5. Export the same token for the GitHub CLI
    grep -q '^GH_TOKEN='/etc/environment \
        || echo "GH_TOKEN=$GIT_TOKEN" | sudo tee -a /etc/environment
    if ! grep -q "export GH_TOKEN=$GIT_TOKEN" "/home/$USERNAME/.bashrc"; then
        echo "Setting GH_TOKEN environment variable in /home/$USERNAME/.bashrc ..."
        echo '' >> "/home/$USERNAME/.bashrc" # Add a newline for separation
        echo '# Set gh cli token' >> "/home/$USERNAME/.bashrc"
        echo "export GH_TOKEN=GIT_TOKEN" >> "/home/$USERNAME/.bashrc"
        # Ownership should be correct if user exists or was just created
    else
         echo "GH_TOKEN already set in /home/$USERNAME/.bashrc."
    fi

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
    echo "Warning: /home/$USERNAME/.bashrc not found. Cannot set user env variables."
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

# --- Install Correct VirtualBox Guest Additions (7.0.x) ---
echo ">>> Installing VirtualBox Guest Additions (target: 7.0.x)..."

# ensure build tools & headers are present
apt-get install -y build-essential dkms linux-headers-$(uname -r)

# pick your exact 7.0 version here (match the host: e.g. 7.0.26)
GA_VERSION="7.0.26"
GA_ISO="VBoxGuestAdditions_${GA_VERSION}.iso"
GA_URL="https://download.virtualbox.org/virtualbox/${GA_VERSION}/${GA_ISO}"
ISO_MOUNT_POINT="/mnt/vbox_ga"

echo "Downloading Guest Additions ISO from ${GA_URL}..."
wget -q -O "/tmp/${GA_ISO}" "${GA_URL}" || {
  echo "Error: failed to download ${GA_ISO}"; exit 1
}

echo "Mounting Guest Additions ISO..."
mkdir -p "${ISO_MOUNT_POINT}"
mount -o loop "/tmp/${GA_ISO}" "${ISO_MOUNT_POINT}" || {
  echo "Error: failed to mount ${GA_ISO}"; exit 1
}

echo "Running Guest Additions installer..."
sh "${ISO_MOUNT_POINT}/VBoxLinuxAdditions.run" --nox11 || {
  echo "Warning: VBoxLinuxAdditions.run exited non‑zero; check /var/log/vboxadd-setup.log"
}

echo "Cleaning up..."
umount "${ISO_MOUNT_POINT}"
rm -rf "${ISO_MOUNT_POINT}" "/tmp/${GA_ISO}"

echo ">>> Guest Additions 7.0.x installation complete."

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
