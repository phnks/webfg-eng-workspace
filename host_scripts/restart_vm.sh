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
if DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant reload "$DEV_USERNAME"; then
  echo "VM for '$DEV_USERNAME' restarted successfully."
else
  echo "Error: Failed to restart VM for '$DEV_USERNAME' using 'vagrant reload'."
  echo "Ensure the VM exists and Vagrant is aware of it."
  exit 1
fi

exit 0
