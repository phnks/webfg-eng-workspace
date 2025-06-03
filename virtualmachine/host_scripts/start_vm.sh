#!/bin/bash

# Script to start a specific developer VM using Vagrant

# Check if username is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME=$1
DEV_USERNAME=$1
VM_NAME="dev-${DEV_USERNAME}-vm" # Used for messaging

echo ">>> Attempting to start VM for user '$DEV_USERNAME' using 'vagrant up'..."

# Run vagrant up. This will:
# 1. Start the VM if it exists but is stopped or saved.
# 2. Do nothing if the VM is already running.
# 3. Fail if the VM doesn't exist (it won't create it here, use provision_vm.sh for that).
# Pass $DEV_USERNAME as the machine name argument

# Change to the vagrant directory (parent of host_scripts)
cd "$(dirname "$0")/.." || exit 1

# First try without sudo
if DEV_USERNAME="$DEV_USERNAME" vagrant up "$DEV_USERNAME" --provider=virtualbox; then
  echo "VM for '$DEV_USERNAME' is running."
else
  # If it failed, check if it's a permission error
  echo ">>> First attempt failed. Checking if sudo is needed..."
  
  # Try with sudo as fallback
  if DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant up "$DEV_USERNAME" --provider=virtualbox; then
    echo "VM for '$DEV_USERNAME' is running (started with sudo)."
    
    # Fix ownership after sudo operation
    echo ">>> Fixing ownership after sudo operation..."
    sudo chown -R "$(id -u):$(id -g)" "$HOME/.vagrant.d" 2>/dev/null || true
    [ -d ".vagrant" ] && sudo chown -R "$(id -u):$(id -g)" ".vagrant" 2>/dev/null || true
  else
    echo "Error: Failed to start VM for '$DEV_USERNAME' using 'vagrant up'."
    echo "Ensure the VM was created first using './provision_vm.sh $DEV_USERNAME'."
    exit 1
  fi
fi

exit 0
