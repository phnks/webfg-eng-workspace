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
if DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant up "$DEV_USERNAME" --provider=virtualbox; then
  echo "VM for '$DEV_USERNAME' is running."
else
  echo "Error: Failed to start VM for '$DEV_USERNAME' using 'vagrant up'."
  echo "Ensure the VM was created first using './provision_vm.sh $DEV_USERNAME'."
  exit 1
fi

exit 0
