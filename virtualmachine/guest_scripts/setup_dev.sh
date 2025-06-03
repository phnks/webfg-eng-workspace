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

# ------------------------------------------------------------------
# Prefer IPv4 over IPv6 for outbound connections
# (avoids 5‑minute IPv6 SYN time‑outs when LAN/router has no IPv6)
# ------------------------------------------------------------------
if ! grep -q 'precedence ::ffff:0:0/96  100' /etc/gai.conf 2>/dev/null; then
  echo ">>> Forcing IPv4 precedence in /etc/gai.conf ..."
  echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf
else
  echo ">>> IPv4 precedence already present in /etc/gai.conf"
fi

echo ">>> Fixing any interrupted dpkg processes..."
# Fix any previously interrupted dpkg processes
dpkg --configure -a || {
    echo "dpkg --configure -a failed, attempting to fix..."
    apt-get install -f -y
    dpkg --configure -a
}

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
    AUTOGEN_DEST_DIR="/home/$USERNAME"
    if [ -d "$AUTOGEN_SOURCE_DIR" ]; then
        echo "Copying autogen_agent directory from $AUTOGEN_SOURCE_DIR to $AUTOGEN_DEST_DIR..."
        # Copy the directory recursively
        cp -r "$AUTOGEN_SOURCE_DIR" "$AUTOGEN_DEST_DIR" || echo "Warning: Failed to copy autogen_agent directory."

        AGENT_HOME_DIR_VM="/home/$USERNAME/autogen_agent" # Consistent with AGENT_HOME_VALUE used later

        echo "Setting ownership of $AGENT_HOME_DIR_VM for user $USERNAME..."
        chown -R "$USERNAME:$USERNAME" "$AGENT_HOME_DIR_VM" || echo "Warning: Failed to chown $AGENT_HOME_DIR_VM."

        # --- Generate VM-specific .env file ---
        echo "Generating VM-specific .env file for $USERNAME..."
        HOST_ENV_FILE="/vagrant/docker/.env"
        VM_ENV_FILE="$AGENT_HOME_DIR_VM/.env"

        # Declare variables to hold extracted values
        GIT_USERNAME=""
        GIT_TOKEN=""
        GH_TOKEN=""
        AWS_ACCESS_KEY_ID=""
        AWS_SECRET_ACCESS_KEY=""
        AWS_REGION=""
        AWS_DEFAULT_REGION=""
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
            AWS_DEFAULT_REGION=$(grep '^AWS_DEFAULT_REGION=' "$HOST_ENV_FILE" | cut -d '=' -f2-)
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
AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
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
        add_to_bashrc "AWS_DEFAULT_REGION" "$AWS_DEFAULT_REGION"
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

        echo "Setting up Python virtual environment and installing dependencies in $AGENT_HOME_DIR_VM..."
        # Combine commands: cd, create venv, activate venv (within subshell), install requirements
        sudo -i -u "$USERNAME" bash -c "cd '$AGENT_HOME_DIR_VM' && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt" || {
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
    add_to_etc_environment "AWS_DEFAULT_REGION" "$AWS_DEFAULT_REGION"
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
Environment=\"AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION\"
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



# --- Setup Discord MCP Server ---
echo ">>> Setting up Discord MCP Server for user $USERNAME..."
MCP_SOURCE_DIR="/vagrant/mcp_servers/discord-mcp"
MCP_DEST_DIR="/home/$USERNAME/discord-mcp"

if [ -d "$MCP_SOURCE_DIR" ]; then
    echo "Copying Discord MCP server files from $MCP_SOURCE_DIR to $MCP_DEST_DIR..."
    mkdir -p "$MCP_DEST_DIR"
    # Copy package.json, tsconfig.json, and the src directory
    cp "$MCP_SOURCE_DIR/package.json" "$MCP_DEST_DIR/"
    cp "$MCP_SOURCE_DIR/tsconfig.json" "$MCP_DEST_DIR/" # tsconfig is needed for 'npm run build'
    if [ -d "$MCP_SOURCE_DIR/src" ]; then
        cp -r "$MCP_SOURCE_DIR/src" "$MCP_DEST_DIR/"
    else
        echo "Warning: $MCP_SOURCE_DIR/src directory not found. Cannot copy MCP source."
    fi

    echo "Setting ownership of $MCP_DEST_DIR for user $USERNAME..."
    chown -R "$USERNAME:$USERNAME" "$MCP_DEST_DIR"

    echo "Cleaning up old artifacts in $MCP_DEST_DIR before reinstalling..."
    sudo -i -u "$USERNAME" bash -c "cd '$MCP_DEST_DIR' && rm -rf node_modules dist"

    echo "Installing Discord MCP server dependencies (including dev for build)..."
    # Install all dependencies first (including typescript for tsc)
    if sudo -i -u "$USERNAME" bash -c "cd '$MCP_DEST_DIR' && npm install"; then
        echo "Discord MCP dependencies installed."
        echo "Compiling Discord MCP server (TypeScript to JavaScript)..."
        # Run the build script which executes tsc
        if sudo -i -u "$USERNAME" bash -c "cd '$MCP_DEST_DIR' && npm run build"; then
            echo "Discord MCP server compiled successfully."

            # Now, prune devDependencies if possible (optional, but good for production)
            echo "Pruning devDependencies for Discord MCP server..."
            sudo -i -u "$USERNAME" bash -c "cd '$MCP_DEST_DIR' && npm prune --omit=dev" || echo "Warning: npm prune failed, continuing..."


            if [ -z "$DISCORD_BOT_TOKEN" ]; then
                echo "Warning: DISCORD_BOT_TOKEN is not set. Cannot configure Discord MCP service environment."
            fi

            DISCORD_MCP_SERVICE_NAME="discord-mcp-$USERNAME.service"
            DISCORD_MCP_SERVICE_FILE="/etc/systemd/system/$DISCORD_MCP_SERVICE_NAME"
            # Correct path to the compiled JavaScript file
            MCP_SCRIPT_PATH="$MCP_DEST_DIR/dist/index.js"

            echo "Creating systemd service file for Discord MCP server at $DISCORD_MCP_SERVICE_FILE..."
            cat > "$DISCORD_MCP_SERVICE_FILE" << EOF_MCP_SERVICE
[Unit]
Description=Discord MCP Server for $USERNAME
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USERNAME
Group=$(id -gn "$USERNAME")
WorkingDirectory=$MCP_DEST_DIR
ExecStart=/usr/bin/node $MCP_SCRIPT_PATH
Restart=on-failure
Environment="DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}"
StandardOutput=append:/var/log/discord-mcp-${USERNAME}.log
StandardError=append:/var/log/discord-mcp-${USERNAME}.error.log

[Install]
WantedBy=multi-user.target
EOF_MCP_SERVICE

            echo "Reloading systemd daemon, enabling and starting Discord MCP service..."
            systemctl daemon-reload
            systemctl enable "$DISCORD_MCP_SERVICE_NAME"
            systemctl restart "$DISCORD_MCP_SERVICE_NAME" # Use restart to ensure it picks up changes
            echo "Discord MCP Server systemd service configured."

        else
            echo "Warning: Failed to compile Discord MCP server (npm run build failed)."
        fi
    else
        echo "Warning: Failed to install Discord MCP dependencies (npm install failed)."
    fi
else
    echo "Warning: Discord MCP source directory $MCP_SOURCE_DIR not found. Skipping Discord MCP server setup."
fi
# --- End Discord MCP Server Setup ---

# --- Handle VirtualBox Guest Additions ---
echo ">>> Checking VirtualBox Guest Additions status..."

# ensure build tools & headers are present
apt-get install -y build-essential dkms linux-headers-$(uname -r)

# Check if Guest Additions are already installed and functional
if systemctl is-active --quiet vboxadd.service 2>/dev/null || systemctl is-active --quiet vboxadd 2>/dev/null; then
    echo ">>> VirtualBox Guest Additions service is already active"
    # Try to get the version
    if command -v VBoxService &>/dev/null; then
        GA_INSTALLED_VERSION=$(VBoxService --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
        echo ">>> Installed Guest Additions version: $GA_INSTALLED_VERSION"
    fi
    echo ">>> Skipping Guest Additions installation"
else
    echo ">>> VirtualBox Guest Additions service not active or not found"
    
    # First try to fix/rebuild existing Guest Additions if present
    if [ -f "/opt/VBoxGuestAdditions*/init/vboxadd" ]; then
        echo ">>> Attempting to rebuild existing Guest Additions kernel modules..."
        /opt/VBoxGuestAdditions*/init/vboxadd setup 2>&1 || echo "Warning: vboxadd setup failed"
    fi
    
    # If still not working, check if we need to install from scratch
    if ! systemctl is-active --quiet vboxadd.service 2>/dev/null && ! systemctl is-active --quiet vboxadd 2>/dev/null; then
        # Use the Guest Additions that come with the box if possible
        echo ">>> Guest Additions still not working. The box should include compatible Guest Additions."
        echo ">>> If issues persist, Guest Additions may need manual intervention."
    fi
fi

# Skip the full Guest Additions installation section
GA_FLAG_FILE="/opt/vbox_ga_checked"

# Create flag to indicate we've checked Guest Additions
touch "$GA_FLAG_FILE" || echo "Warning: Failed to create flag file ${GA_FLAG_FILE}"

# --- Configure LightDM for Autologin ---
echo ">>> Configuring LightDM for autologin for user $USERNAME..."
LIGHTDM_CONF_DIR="/etc/lightdm/lightdm.conf.d"
LIGHTDM_AUTOLOGIN_CONF_FILE="$LIGHTDM_CONF_DIR/50-autologin.conf"

# Check if lightdm is installed (it should be, as xubuntu-desktop is a dependency)
if ! dpkg -s lightdm &> /dev/null; then
    echo "Warning: lightdm is not installed. Skipping autologin configuration."
else
    mkdir -p "$LIGHTDM_CONF_DIR"

    # Create the autologin configuration file
    # The USERNAME variable will be expanded here.
    # The session is set to xubuntu, matching the installed desktop.
    cat > "$LIGHTDM_AUTOLOGIN_CONF_FILE" << EOF_LIGHTDM
[SeatDefaults]
autologin-guest=false
autologin-user=$USERNAME
autologin-user-timeout=0
autologin-session=xubuntu
EOF_LIGHTDM

    chmod 644 "$LIGHTDM_AUTOLOGIN_CONF_FILE"
    echo "LightDM autologin configured for $USERNAME."
fi

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
