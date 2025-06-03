#!/bin/bash

# Script to stop a specific developer VM by saving its state using Vagrant (suspend)

# Check if username is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME=$1
DEV_USERNAME=$1
VM_NAME="dev-${DEV_USERNAME}-vm" # Used for messaging

echo ">>> Attempting to save state (suspend) for VM for user '$DEV_USERNAME' using 'vagrant suspend'..."

# Run vagrant suspend. This will:
# 1. Save the state if the VM is running.
# 2. Do nothing if the VM is already suspended or powered off.
# 3. Fail if the VM doesn't exist or Vagrant doesn't know about it.
# Pass $DEV_USERNAME as the machine name argument

# Change to the vagrant directory (parent of host_scripts)
cd "$(dirname "$0")/.." || exit 1

# First try without sudo
if DEV_USERNAME="$DEV_USERNAME" vagrant suspend "$DEV_USERNAME"; then
  echo "VM for '$DEV_USERNAME' suspended successfully or was already suspended/off."
else
  # If it failed, check if it's a permission error
  echo ">>> First attempt failed. Checking if sudo is needed..."
  
  # Try with sudo as fallback
  if DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant suspend "$DEV_USERNAME"; then
    echo "VM for '$DEV_USERNAME' suspended successfully with sudo."
    
    # Fix ownership after sudo operation
    echo ">>> Fixing ownership after sudo operation..."
    sudo chown -R "$(id -u):$(id -g)" "$HOME/.vagrant.d" 2>/dev/null || true
    [ -d ".vagrant" ] && sudo chown -R "$(id -u):$(id -g)" ".vagrant" 2>/dev/null || true
  else
    echo "Error: Failed to suspend VM for '$DEV_USERNAME' using 'vagrant suspend'."
    echo "Ensure the VM exists and Vagrant is aware of it."
    exit 1
  fi
fi

exit 0
