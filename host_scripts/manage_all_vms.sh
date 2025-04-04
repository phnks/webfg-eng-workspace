#!/bin/bash

# Script to create or re-provision VMs for all users listed in a config file.
# Allows continuing to next user if one fails.

CONFIG_FILE="config/dev_users.txt"
START_SCRIPT="./host_scripts/start_vm.sh" # Needed to start before provision

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found at '$CONFIG_FILE'"
  exit 1
fi

# Check if helper script exists and is executable
if [ ! -x "$START_SCRIPT" ]; then
    echo "Error: Start script '$START_SCRIPT' not found or not executable."
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
  VAGRANT_ID_FILE=".vagrant/machines/default/virtualbox/id" # Default path

  # Check if VM exists using VBoxManage
  if VBoxManage showvminfo "$VM_NAME" --machinereadable > /dev/null 2>&1; then
    # VM Exists in VirtualBox
    echo "VM '$VM_NAME' exists. Running re-provisioning..."

    # Check state, start if needed
    VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep VMState= | cut -d'=' -f2 | tr -d '"')
    if [ "$VM_STATE" != "running" ]; then
        echo "VM not running (state: '$VM_STATE'). Attempting to start..."
        if ! "$START_SCRIPT" "$USERNAME"; then
             echo "Error: Failed to start VM '$VM_NAME' for provisioning. Skipping user '$USERNAME'."
             echo "--------------------------------------------------"
             continue # Skip to next user
        fi
        echo "VM started. Waiting 5 seconds before provisioning..."
        sleep 5 # Give VM time to boot
    fi

    # Run vagrant provision directly
    echo "Running vagrant provision for $USERNAME..."
    if ! DEV_USERNAME="$USERNAME" vagrant provision; then
        echo "Error: Failed to re-provision VM for user '$USERNAME'."
        # Loop will continue to next user
    else
        echo "Re-provisioning finished for '$USERNAME'."
    fi

  else
    # VM Does NOT Exist in VirtualBox
    echo "VM '$VM_NAME' does not exist. Running creation..."

    # Check if Vagrant *thinks* a machine exists for this directory and remove state if it does
    if [ -f "$VAGRANT_ID_FILE" ]; then
        STORED_ID=$(cat "$VAGRANT_ID_FILE")
        echo "Warning: Vagrant state file found ($VAGRANT_ID_FILE) pointing to ID '$STORED_ID', but target VM '$VM_NAME' does not exist in VirtualBox."
        echo "Removing Vagrant state file to ensure correct VM creation..."
        rm -f "$VAGRANT_ID_FILE"
        # Optionally remove the whole directory: rm -rf "$(dirname "$VAGRANT_ID_FILE")"
    fi

    # Now run vagrant up
    echo "Running vagrant up for $USERNAME..."
    if ! DEV_USERNAME="$USERNAME" vagrant up --provider=virtualbox; then
         echo "Error: Failed to create VM for user '$USERNAME'."
         # Loop will continue to next user
    else
        echo "Creation finished for '$USERNAME'."
    fi
  fi
  echo "--------------------------------------------------"

done # < "$CONFIG_FILE" # Feed the file to the loop

echo ">>> All users processed."
exit 0
