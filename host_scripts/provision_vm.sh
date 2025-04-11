#!/bin/bash

# Script to create a VM if it doesn't exist, ensure it's running,
# and run/re-run the provisioning process.

# Exit immediately if a command exits with a non-zero status.
# set -e # Temporarily disable for debugging
set -x # Print commands and their arguments as they are executed.

# Check if a username argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <developer_username>"
  echo "Example: $0 jsmith"
  exit 1
fi

DEV_USERNAME="$1"
VM_NAME="dev-${DEV_USERNAME}-vm" # Used for messaging

# --- Define GitHub App Credentials per User ---
# Store credentials in an associative array (Bash 4.0+)
declare -A GITHUB_CREDS
GITHUB_CREDS["anum_app_id"]="1210600"
GITHUB_CREDS["anum_install_id"]="64247573"
GITHUB_CREDS["anum_key_path"]="config/anum-bot-app.2025-04-09.private-key.pem"
GITHUB_CREDS["homonculus_app_id"]="1210603"
GITHUB_CREDS["homonculus_install_id"]="64247782"
GITHUB_CREDS["homonculus_key_path"]="config/homonculus-bot-app.2025-04-09.private-key.pem"
# Add more users here if needed

# Get the specific credentials for the current dev_username
APP_ID_VAR="${DEV_USERNAME}_app_id"
INSTALL_ID_VAR="${DEV_USERNAME}_install_id"
KEY_PATH_VAR="${DEV_USERNAME}_key_path"

APP_ID="${GITHUB_CREDS[$APP_ID_VAR]}"
INSTALL_ID="${GITHUB_CREDS[$INSTALL_ID_VAR]}"
KEY_PATH="${GITHUB_CREDS[$KEY_PATH_VAR]}"

if [ -z "$APP_ID" ] || [ -z "$INSTALL_ID" ] || [ -z "$KEY_PATH" ]; then
  echo "Error: GitHub credentials not defined in provision_vm.sh for user: $DEV_USERNAME"
  exit 1
fi
if [ ! -f "$KEY_PATH" ]; then
    echo "Error: Private key file not found at path: $KEY_PATH"
    exit 1
fi

# --- Generate GitHub Installation Token using gh api ---
echo ">>> Generating GitHub Installation Token for $DEV_USERNAME using gh api..."
GH_EXECUTABLE="/usr/bin/gh" # Use explicit path
API_ENDPOINT="/app/installations/${INSTALL_ID}/access_tokens"
echo "Target API endpoint: ${API_ENDPOINT}"

# Read key content into a variable and clean it (remove potential DOS line endings)
echo "Reading and cleaning private key content from $KEY_PATH..."
PRIVATE_KEY_CONTENT=$(tr -d '\r' < "$KEY_PATH") # Read using redirection and remove \r
if [ -z "$PRIVATE_KEY_CONTENT" ]; then
    echo "Error: Failed to read or clean content from private key file: $KEY_PATH"
    exit 1
fi
echo "Key content read and cleaned."

# Temporarily export App ID and Cleaned Key Content for gh api
export GH_APP_ID="$APP_ID"
export GH_PRIVATE_KEY="$PRIVATE_KEY_CONTENT" # Use cleaned key content

echo "Running command: GH_APP_ID=... GH_PRIVATE_KEY=... $GH_EXECUTABLE api --method POST $API_ENDPOINT"

# Execute the command, capture JSON output, and parse the token using jq (ensure jq is installed or add check)
# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq (e.g., sudo apt install jq) on the host machine."
    exit 1
fi

API_RESPONSE=$($GH_EXECUTABLE api --method POST "$API_ENDPOINT" 2>&1) # Capture stdout and stderr
EXIT_STATUS=$?

# Print raw response immediately for debugging
echo "--- Raw API Response START ---"
echo "$API_RESPONSE"
echo "--- Raw API Response END ---"
echo "API command exited with status: $EXIT_STATUS"


# Unset temporary env vars
unset GH_APP_ID
unset GH_PRIVATE_KEY # Unset the key content variable

if [ $EXIT_STATUS -ne 0 ]; then
    echo "Error: Failed to generate GitHub installation token via API. Command exited with status $EXIT_STATUS."
    # Response already printed above
    echo "Please check gh cli setup, App credentials, permissions, and key path ($KEY_PATH)."
    exit 1 # Exit manually since set -e is off
fi

# Parse the token from the JSON response
echo "Attempting to parse token with jq..."
GENERATED_TOKEN=$(echo "$API_RESPONSE" | jq -r '.token')
JQ_EXIT_STATUS=$?
echo "jq exited with status: $JQ_EXIT_STATUS"

if [ $JQ_EXIT_STATUS -ne 0 ]; then
    echo "Error: jq failed to parse the API response."
    exit 1 # Exit manually
fi


if [ -z "$GENERATED_TOKEN" ] || [ "$GENERATED_TOKEN" = "null" ]; then
    echo "Error: Generated GitHub installation token is empty or null after jq parsing."
    # Response already printed above
    exit 1 # Exit manually
fi
echo "Successfully generated and parsed GitHub installation token via gh api."

# Export the token so Vagrant commands inherit it
export GH_INSTALLATION_TOKEN="$GENERATED_TOKEN"

# --- End Token Generation ---


echo ""
echo ">>> Ensuring VM for user '$DEV_USERNAME' exists and is running..."

# Run vagrant up. This will:
# 1. Create the VM if it doesn't exist (and run initial provisioning).
# 2. Start the VM if it exists but is stopped.
# 3. Do nothing if the VM is already running.
# We now pass $DEV_USERNAME as the machine name argument to vagrant
# Use sudo -E to ensure consistency with how VMs might have been created/managed
if ! DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant up "$DEV_USERNAME" --provider=virtualbox; then
    echo ""
    echo "Error: 'sudo -E vagrant up $DEV_USERNAME' failed for VM '$VM_NAME'. Cannot proceed."
    exit 1
fi
echo ">>> VM '$VM_NAME' is up and running."

# Explicitly run provisioning to ensure it runs even if the VM already existed.
# Vagrant provision should wait for SSH to be ready.
echo ""
echo ">>> Running provisioning for VM '$VM_NAME'..."
# We now pass $DEV_USERNAME as the machine name argument to vagrant
if ! DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant provision "$DEV_USERNAME"; then
    echo ""
    echo "Error: 'sudo -E vagrant provision $DEV_USERNAME' failed for VM '$VM_NAME'."
    exit 1
fi

echo ""
echo ">>> VM provisioning process for '$DEV_USERNAME' finished successfully."
echo ">>> Note: The guest provisioning script might include a reboot."
echo ">>> The developer can log in via the GUI with username '$DEV_USERNAME' and password 'password'."
echo ">>> IMPORTANT: Remind the developer to change the default password immediately if this was the first setup!"

exit 0
