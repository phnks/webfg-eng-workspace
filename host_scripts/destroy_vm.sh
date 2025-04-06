#!/bin/bash

# Script to forcefully destroy a specific developer VM using Vagrant

# Check if username is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME=$1
DEV_USERNAME=$1
VM_NAME="dev-${DEV_USERNAME}-vm" # Used for messaging

echo ">>> Attempting to forcefully destroy VM for user '$DEV_USERNAME' (machine name: '$DEV_USERNAME') using 'vagrant destroy -f'..."

# Run vagrant destroy -f. This will:
# 1. Stop the VM if running.
# 2. Remove the VM from VirtualBox.
# 3. Clean up Vagrant's tracking information for this machine.
# Pass $DEV_USERNAME as the machine name argument
# Use sudo -E to preserve environment for Vagrantfile
if DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant destroy "$DEV_USERNAME" -f; then
  echo "VM for '$DEV_USERNAME' destroyed successfully."
else
  # Exit code 0 because destroy might fail if the VM doesn't exist, which is fine for a cleanup script.
  echo "Warning: Failed to destroy VM for '$DEV_USERNAME' or it didn't exist."
  exit 0
fi

exit 0
