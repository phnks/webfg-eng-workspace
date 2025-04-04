#!/bin/bash

# Script to create or re-provision VMs for all users listed in a config file.

# Exit immediately if a command exits with a non-zero status.
# We might want to remove this if we want the script to continue with other users
# even if one fails. Let's keep it for now for stricter error checking.
set -e

CONFIG_FILE="config/dev_users.txt"
CREATE_SCRIPT="./host_scripts/create_dev_vm.sh"
REPROVISION_SCRIPT="./host_scripts/reprovision_vm.sh"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found at '$CONFIG_FILE'"
  exit 1
fi

# Check if helper scripts exist and are executable
if [ ! -x "$CREATE_SCRIPT" ]; then
    echo "Error: Create script '$CREATE_SCRIPT' not found or not executable."
    exit 1
fi
if [ ! -x "$REPROVISION_SCRIPT" ]; then
    echo "Error: Reprovision script '$REPROVISION_SCRIPT' not found or not executable."
    exit 1
fi


echo ">>> Starting VM management for users in '$CONFIG_FILE'..."
echo "--------------------------------------------------"

# Read the config file line by line, skipping comments and empty lines
grep -v '^#' "$CONFIG_FILE" | grep -v '^[[:space:]]*$' | while IFS= read -r USERNAME; do
  # Trim whitespace just in case
  USERNAME=$(echo "$USERNAME" | xargs)

  if [ -z "$USERNAME" ]; then
      continue # Skip empty lines after potential trimming
  fi

  echo ">>> Processing user: $USERNAME"
  VM_NAME="dev-${USERNAME}-vm"

  # Check if VM exists using VBoxManage
  if VBoxManage showvminfo "$VM_NAME" --machinereadable > /dev/null 2>&1; then
    echo "VM '$VM_NAME' exists. Running re-provisioning..."
    if ! "$REPROVISION_SCRIPT" "$USERNAME"; then
        echo "Error: Failed to re-provision VM for user '$USERNAME'. Stopping script due to 'set -e'."
        # If 'set -e' was removed, we could just 'continue' here.
        exit 1 # Stop script on failure
    fi
    echo "Re-provisioning finished for '$USERNAME'."
  else
    echo "VM '$VM_NAME' does not exist. Running creation..."
    if ! "$CREATE_SCRIPT" "$USERNAME"; then
         echo "Error: Failed to create VM for user '$USERNAME'. Stopping script due to 'set -e'."
         # If 'set -e' was removed, we could just 'continue' here.
         exit 1 # Stop script on failure
    fi
    echo "Creation finished for '$USERNAME'."
  fi
  echo "--------------------------------------------------"

done # < "$CONFIG_FILE" # Feed the file to the loop

echo ">>> All users processed."
exit 0
