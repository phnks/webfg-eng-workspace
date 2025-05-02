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
echo ">>> Checking/Installing Google Chrome..."
if command -v google-chrome-stable &> /dev/null; then
    echo "Google Chrome is already installed."
else
    echo "Installing Google Chrome..."
    # Add Google Chrome key (use --batch --yes for non-interactive gpg)
    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor --batch --yes -o /usr/share/keyrings/google-chrome-keyring.gpg
    # Add Google Chrome repository
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
    # Update package list and install Chrome
    apt-get update -y
    apt-get install -y google-chrome-stable
    echo "Google Chrome installed."
fi

# --- Install Visual Studio Code ---
echo ">>> Checking/Installing Visual Studio Code..."
if command -v code &> /dev/null; then
    echo "Visual Studio Code is already installed."
else
    echo "Installing Visual Studio Code..."
    # Add Microsoft GPG key (use --batch --yes for non-interactive gpg)
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor --batch --yes > /usr/share/keyrings/packages.microsoft.gpg
    # Add VS Code repository
    echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
    # Update package list and install VS Code
    apt-get update -y
    apt-get install -y code
    echo "Visual Studio Code installed."
fi

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
    # --- Agent Helper Scripts Setup ---
    echo ">>> Setting up agent helper scripts..."
    AGENT_SCRIPTS_SOURCE_DIR="/vagrant/autogen_agent" # Scripts are in autogen_agent dir
    AGENT_SCRIPTS_DEST_DIR="/usr/local/bin"
    # Check if source directory exists before copying
    if [ -d "$AGENT_SCRIPTS_SOURCE_DIR" ]; then
        echo "Copying agent helper scripts from $AGENT_SCRIPTS_SOURCE_DIR to $AGENT_SCRIPTS_DEST_DIR..."
        # Copy only the specific shell scripts
        cp "$AGENT_SCRIPTS_SOURCE_DIR/status_agent.sh" \
           "$AGENT_SCRIPTS_SOURCE_DIR/restart_agent.sh" \
           "$AGENT_SCRIPTS_SOURCE_DIR/stop_agent.sh" \
           "$AGENT_SCRIPTS_SOURCE_DIR/get_logs.sh" \
           "$AGENT_SCRIPTS_SOURCE_DIR/start_agent.sh" \
           "$AGENT_SCRIPTS_DEST_DIR/" || echo "Warning: Failed to copy agent scripts."

        echo "Setting execute permissions for agent scripts..."
        chmod +x "$AGENT_SCRIPTS_DEST_DIR/status_agent.sh" \
                 "$AGENT_SCRIPTS_DEST_DIR/restart_agent.sh" \
                 "$AGENT_SCRIPTS_DEST_DIR/stop_agent.sh" \
                 "$AGENT_SCRIPTS_DEST_DIR/get_logs.sh" \
                 "$AGENT_SCRIPTS_DEST_DIR/start_agent.sh" || echo "Warning: Failed to chmod agent scripts."

        # Grant NOPASSWD sudo rights to the user for these specific scripts (Safer than ALL)
        SUDOERS_FILE="/etc/sudoers.d/${USERNAME}-agent"
        echo "Configuring NOPASSWD sudo for agent scripts for user $USERNAME in $SUDOERS_FILE..."
        # Create the sudoers file content, overwriting if it exists
        {
            echo "$USERNAME ALL=(ALL) NOPASSWD:ALL"
        } > "$SUDOERS_FILE" # Use > to overwrite/create the file

        # Set correct permissions for the sudoers file
        chmod 0440 "$SUDOERS_FILE" || echo "Warning: Failed to chmod sudoers file $SUDOERS_FILE."
        echo "Sudoers configuration complete."
    else
        echo "Warning: Agent scripts source directory $AGENT_SCRIPTS_SOURCE_DIR not found. Skipping helper script setup."
    fi

    # --- Autogen Agent Setup ---
    echo ">>> Setting up Autogen Agent for user $USERNAME..."
    AUTOGEN_SOURCE_DIR="/vagrant/autogen_agent"
    AUTOGEN_DEST_DIR="/home/$USERNAME/autogen_agent"
    if [ -d "$AUTOGEN_SOURCE_DIR" ]; then
        echo "Copying autogen_agent directory from $AUTOGEN_SOURCE_DIR to $AUTOGEN_DEST_DIR..."
        # Copy the directory recursively
        cp -r "$AUTOGEN_SOURCE_DIR" "$AUTOGEN_DEST_DIR" || echo "Warning: Failed to copy autogen_agent directory."

        echo "Setting ownership of $AUTOGEN_DEST_DIR for user $USERNAME..."
        chown -R "$USERNAME:$USERNAME" "$AUTOGEN_DEST_DIR" || echo "Warning: Failed to chown $AUTOGEN_DEST_DIR."

        # --- Generate VM-specific .env file ---
        echo "Generating VM-specific .env file for $USERNAME..."
        HOST_ENV_FILE="/vagrant/host_service/.env"
        VM_ENV_FILE="$AUTOGEN_DEST_DIR/.env"
        AGENT_HOME_DIR_VM="/home/$USERNAME/autogen_agent" # Consistent with AGENT_HOME_VALUE used later

        # Declare variables to hold extracted values
        GIT_USERNAME=""
        GIT_TOKEN=""
        GH_TOKEN=""
        AWS_ACCESS_KEY_ID=""
        AWS_SECRET_ACCESS_KEY=""
        AWS_REGION=""
        AWS_ACCOUNT_ID=""
        OPENAI_API_KEY=""
        GEMINI_API_KEYS=""
        USE_GEMINI=""
        DISCORD_BOT_TOKEN=""

        if [ -f "$HOST_ENV_FILE" ]; then
            # Extract values from host .env (handle potential missing keys gracefully)
            # Use grep '^KEY=' to avoid matching commented lines, then cut
            GIT_USERNAME=$(grep '^GIT_USERNAME=' "$HOST_ENV_FILE" | cut -d '=' -f2-)
            GIT_TOKEN=$(grep '^GIT_TOKEN=' "$HOST_ENV_FILE" | cut -d '=' -f2-)
            GH_TOKEN=$(grep '^GH_TOKEN=' "$HOST_ENV_FILE" | cut -d '=' -f2-)
            AWS_ACCESS_KEY_ID=$(grep '^AWS_ACCESS_KEY_ID=' "$HOST_ENV_FILE" | cut -d '=' -f2-)
            AWS_SECRET_ACCESS_KEY=$(grep '^AWS_SECRET_ACCESS_KEY=' "$HOST_ENV_FILE" | cut -d '=' -f2-)
            AWS_REGION=$(grep '^AWS_REGION=' "$HOST_ENV_FILE" | cut -d '=' -f2-)
            AWS_ACCOUNT_ID=$(grep '^AWS_ACCOUNT_ID=' "$HOST_ENV_FILE" | cut -d '=' -f2-)
            OPENAI_API_KEY=$(grep '^OPENAI_API_KEY=' "$HOST_ENV_FILE" | cut -d '=' -f2-)
            GEMINI_API_KEYS=$(grep '^GEMINI_API_KEYS=' "$HOST_ENV_FILE" | cut -d '=' -f2-)
            USE_GEMINI=$(grep '^USE_GEMINI=' "$HOST_ENV_FILE" | cut -d '=' -f2-)

            # Extract the specific bot token for this user
            USER_BOT_TOKEN_KEY="BOT_TOKEN_$USERNAME"
            DISCORD_BOT_TOKEN=$(grep "^${USER_BOT_TOKEN_KEY}=" "$HOST_ENV_FILE" | cut -d '=' -f2-)

            # Check if token was found
            if [ -z "$DISCORD_BOT_TOKEN" ]; then
                echo "Warning: Bot token for user $USERNAME (${USER_BOT_TOKEN_KEY}) not found in $HOST_ENV_FILE. Setting to placeholder."
                DISCORD_BOT_TOKEN="YOUR_DISCORD_BOT_TOKEN_FOR_${USERNAME}_HERE"
            fi

            # Construct the new .env file content
            # Overwrite the existing file
            cat > "$VM_ENV_FILE" << EOF
# Auto-generated .env file for user $USERNAME

# --- User Specific ---
DISCORD_BOT_TOKEN=$DISCORD_BOT_TOKEN
BOT_USER=$USERNAME
AGENT_HOME=$AGENT_HOME_DIR_VM

# --- Shared Git/GitHub ---
GIT_USERNAME=$GIT_USERNAME
GIT_TOKEN=$GIT_TOKEN
GH_TOKEN=$GH_TOKEN

# --- Shared AWS ---
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID

# --- OpenAI Configuration ---
OPENAI_API_KEY=$OPENAI_API_KEY

# --- Gemini Configuration ---
GEMINI_API_KEYS=$GEMINI_API_KEYS
# Set to "true" to use Gemini, "false" or omit to use OpenAI
USE_GEMINI=$USE_GEMINI
EOF

            echo ".env file generated at $VM_ENV_FILE"
            # Ensure correct ownership of the generated .env file
            chown "$USERNAME:$USERNAME" "$VM_ENV_FILE" || echo "Warning: Failed to chown $VM_ENV_FILE"
        else
            echo "Warning: Host environment file $HOST_ENV_FILE not found. Cannot generate VM .env file."
            # Optionally create a placeholder .env file here if needed
        fi
        # --- End .env generation ---

        # --- Set Generated Env Vars in User .bashrc ---
        echo "Setting generated environment variables in /home/$USERNAME/.bashrc..."
        BASHRC_FILE="/home/$USERNAME/.bashrc"
        # Function to add export line if not present
        add_to_bashrc() {
            # Use direct variable values passed to function for safety/compatibility
            local export_line="export $1=\"$2\"" # Use $1 for name, $2 for value
            local comment="# Added by setup_dev.sh for $1"
            # Use grep -qF to match fixed string exactly
            if ! grep -qF "$export_line" "$BASHRC_FILE"; then
                echo "" >> "$BASHRC_FILE" # Add newline
                echo "$comment" >> "$BASHRC_FILE"
                echo "$export_line" >> "$BASHRC_FILE"
                echo "$1 added to $BASHRC_FILE."
            # else
                # echo "$1 already set in $BASHRC_FILE." # Reduce verbosity
            fi
        }

        # Add variables extracted earlier (ensure they are available in this scope)
        # Note: AGENT_HOME is already handled separately later, so skipping here.
        # Pass name and value explicitly
        add_to_bashrc "AGENT_HOME" "$AGENT_HOME_DIR_VM"
        add_to_bashrc "DISCORD_BOT_TOKEN" "$DISCORD_BOT_TOKEN"
        add_to_bashrc "BOT_USER" "$USERNAME" # Use $USERNAME directly
        add_to_bashrc "GIT_USERNAME" "$GIT_USERNAME"
        add_to_bashrc "GIT_TOKEN" "$GIT_TOKEN"
        add_to_bashrc "GH_TOKEN" "$GH_TOKEN"
        add_to_bashrc "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
        add_to_bashrc "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
        add_to_bashrc "AWS_REGION" "$AWS_REGION"
        add_to_bashrc "AWS_ACCOUNT_ID" "$AWS_ACCOUNT_ID"
        add_to_bashrc "OPENAI_API_KEY" "$OPENAI_API_KEY"
        add_to_bashrc "GEMINI_API_KEYS" "$GEMINI_API_KEYS"
        add_to_bashrc "USE_GEMINI" "$USE_GEMINI"

        # Ensure ownership after modifications
        chown "$USERNAME:$USERNAME" "$BASHRC_FILE" || echo "Warning: Failed to chown $BASHRC_FILE after adding env vars."
        echo "Environment variables checked/added to .bashrc."
        # --- End Env Var Setup ---

        # --- Configure Git Credentials ---
        echo "Configuring Git credential helper for user $USERNAME..."
        # Run git config commands as the user
        # Ensure GIT_USERNAME and GIT_TOKEN are available for the subshell
        # We need to pass the values explicitly to the sudo subshell
        sudo -i -u "$USERNAME" GIT_USERNAME_VAL="$GIT_USERNAME" GIT_TOKEN_VAL="$GIT_TOKEN" bash -c ' \
            git config --global credential.helper "store --file ~/.git-credentials" && \
            git config --global user.email "$USER@email.com" && \
            git config --global user.name "$USER" && \
            echo "https://\${GIT_USERNAME_VAL}:\${GIT_TOKEN_VAL}@github.com" > ~/.git-credentials && \
            chmod 600 ~/.git-credentials \
        ' || echo "Warning: Failed to configure git credentials for $USERNAME."
        echo "Git credentials configured."
        # --- End Git Credential Config ---


        echo "Setting up Python virtual environment and installing dependencies in $AUTOGEN_DEST_DIR..."
        # Combine commands: cd, create venv, activate venv (within subshell), install requirements
        sudo -i -u "$USERNAME" bash -c "cd '$AUTOGEN_DEST_DIR' && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt" || {
            echo "Warning: Autogen Python environment setup failed. Check logs if necessary."
        }
        echo "Autogen Agent Python setup complete."
    else
        echo "Warning: Autogen source directory $AUTOGEN_SOURCE_DIR not found. Skipping Autogen setup."
    fi

    # --- Set Environment Variables (System-wide and User) ---
    echo "Setting environment variables system-wide (/etc/environment) and for user ($USERNAME)..."
    # Function to add var to /etc/environment if not present
    add_to_etc_environment() {
        local var_name="$1"
        local var_value="$2"
        local env_line="$var_name=\"$var_value\"" # Format: VAR="VALUE"
        # Use grep -qF to match fixed string exactly
        if ! grep -qF "$env_line" /etc/environment; then
            echo "$env_line" >> /etc/environment
            echo "$var_name added to /etc/environment."
        # else
            # echo "$var_name already set in /etc/environment."
        fi
    }

    AGENT_HOME_VALUE="/home/$USERNAME/autogen_agent"
    add_to_etc_environment "AGENT_HOME" "$AGENT_HOME_VALUE"
    add_to_etc_environment "DISCORD_BOT_TOKEN" "$DISCORD_BOT_TOKEN"
    add_to_etc_environment "BOT_USER" "$USERNAME" # Use $USERNAME directly
    add_to_etc_environment "GIT_USERNAME" "$GIT_USERNAME"
    add_to_etc_environment "GIT_TOKEN" "$GIT_TOKEN"
    add_to_etc_environment "GH_TOKEN" "$GH_TOKEN"
    add_to_etc_environment "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
    add_to_etc_environment "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
    add_to_etc_environment "AWS_REGION" "$AWS_REGION"
    add_to_etc_environment "AWS_ACCOUNT_ID" "$AWS_ACCOUNT_ID"
    add_to_etc_environment "OPENAI_API_KEY" "$OPENAI_API_KEY"
    add_to_etc_environment "GEMINI_API_KEYS" "$GEMINI_API_KEYS"
    add_to_etc_environment "USE_GEMINI" "$USE_GEMINI"

    echo "System-wide environment variables checked/added to /etc/environment."
    # --- End System/User Env Var Setup ---


    # --- Configure Autogen Agent systemd Service ---
    echo ">>> Configuring Autogen Agent systemd service..."
    SERVICE_NAME="autogen-agent.service"
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
    AGENT_START_SCRIPT="/usr/local/bin/start_agent.sh"
    AGENT_HOME_DIR="/home/$USERNAME/autogen_agent" # Defined earlier as AGENT_HOME_VALUE

    # Create the systemd service file content
    # Ensure User, Group, WorkingDirectory, and Environment are set correctly.
    # Added After/Wants network-online.target assuming agent might need network.
    # Added PATH to include user's local bin, potentially needed if start_agent uses pipx tools.
    # Systemd services DO NOT inherit /etc/environment by default, so we still need Environment= here.
    SERVICE_CONTENT="[Unit]
Description=Autogen Agent Service
After=network-online.target
Wants=network-online.target

[Service]
Type=forking # Specify that the script forks
PIDFile=$AGENT_HOME_DIR/.agent.pid # Tell systemd where the actual agent PID is stored
User=$USERNAME
Group=$(id -gn $USERNAME)
WorkingDirectory=$AGENT_HOME_DIR
Environment=\"PATH=/home/$USERNAME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"
Environment=\"AGENT_HOME=$AGENT_HOME_DIR\"
Environment=\"DISCORD_BOT_TOKEN=$DISCORD_BOT_TOKEN\"
Environment=\"BOT_USER=$USERNAME\"
Environment=\"GIT_USERNAME=$GIT_USERNAME\"
Environment=\"GIT_TOKEN=$GIT_TOKEN\"
Environment=\"GH_TOKEN=$GH_TOKEN\"
Environment=\"AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID\"
Environment=\"AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY\"
Environment=\"AWS_REGION=$AWS_REGION\"
Environment=\"AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID\"
Environment=\"OPENAI_API_KEY=$OPENAI_API_KEY\"
Environment=\"GEMINI_API_KEYS=$GEMINI_API_KEYS\"
Environment=\"USE_GEMINI=$USE_GEMINI\"
# Add a small delay before starting, just in case of network race conditions
ExecStartPre=/bin/sleep 5
# Explicitly activate venv and then run the start script using its full path
# Using 'exec' ensures the agent script replaces the bash shell process
ExecStart=/bin/bash -c 'source $AGENT_HOME_DIR/venv/bin/activate && exec /usr/local/bin/start_agent.sh'
Restart=on-failure
RestartSec=10s # Increased restart delay slightly

[Install]
WantedBy=multi-user.target"

    # Write the service file
    echo "Creating systemd service file at $SERVICE_FILE..."
    echo -e "$SERVICE_CONTENT" > "$SERVICE_FILE" || { echo "Error: Failed to write systemd service file $SERVICE_FILE"; exit 1; }

    # Reload systemd daemon to recognize the new service
    echo "Reloading systemd daemon..."
    systemctl daemon-reload || echo "Warning: systemctl daemon-reload failed."

    # Enable the service to start on boot
    echo "Enabling $SERVICE_NAME to start on boot..."
    systemctl enable "$SERVICE_NAME" || echo "Warning: systemctl enable $SERVICE_NAME failed."

    # Optionally, start the service immediately (useful for first provision)
    echo "Starting $SERVICE_NAME immediately..."
    systemctl start "$SERVICE_NAME" || echo "Warning: systemctl start $SERVICE_NAME failed."

    echo "Autogen Agent systemd service configured and enabled."

    # Removed the direct start command: sudo -i -u "$USERNAME" $AGENT_START_SCRIPT ...

    # Check if the DEVCHAT_HOST_IP line already exists to avoid duplicates
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
