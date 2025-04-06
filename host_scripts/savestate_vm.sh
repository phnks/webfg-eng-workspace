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
if DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant suspend "$DEV_USERNAME"; then
  echo "VM for '$DEV_USERNAME' suspended successfully or was already suspended/off."
else
  echo "Error: Failed to suspend VM for '$DEV_USERNAME' using 'vagrant suspend'."
  echo "Ensure the VM exists and Vagrant is aware of it."
  exit 1
fi

exit 0
