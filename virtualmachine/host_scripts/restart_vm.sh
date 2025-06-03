#!/bin/bash

# Script to gracefully restart a specific developer VM using Vagrant

# Check if username is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME=$1
DEV_USERNAME=$1
VM_NAME="dev-${DEV_USERNAME}-vm" # Used for messaging

echo ">>> Attempting to restart VM for user '$DEV_USERNAME' using 'vagrant reload'..."

# Run vagrant reload. This will:
# 1. Gracefully shut down the VM if running ('vagrant halt').
# 2. Start the VM ('vagrant up').
# 3. If the VM was already stopped, it will just start it.
# 4. Fail if the VM doesn't exist or Vagrant doesn't know about it.
# Pass $DEV_USERNAME as the machine name argument

# Change to the vagrant directory (parent of host_scripts)
cd "$(dirname "$0")/.." || exit 1

# First try without sudo
if DEV_USERNAME="$DEV_USERNAME" vagrant reload "$DEV_USERNAME"; then
  echo "VM for '$DEV_USERNAME' restarted successfully."
else
  # If it failed, check if it's a permission error
  echo ">>> First attempt failed. Checking if sudo is needed..."
  
  # Try with sudo as fallback
  if DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant reload "$DEV_USERNAME"; then
    echo "VM for '$DEV_USERNAME' restarted successfully with sudo."
    
    # Fix ownership after sudo operation
    echo ">>> Fixing ownership after sudo operation..."
    sudo chown -R "$(id -u):$(id -g)" "$HOME/.vagrant.d" 2>/dev/null || true
    [ -d ".vagrant" ] && sudo chown -R "$(id -u):$(id -g)" ".vagrant" 2>/dev/null || true
  else
    echo "Error: Failed to restart VM for '$DEV_USERNAME' using 'vagrant reload'."
    echo "Ensure the VM exists and Vagrant is aware of it."
    exit 1
  fi
fi

exit 0
