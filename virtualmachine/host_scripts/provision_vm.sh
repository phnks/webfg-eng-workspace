#!/bin/bash

# Script to create a VM if it doesn't exist, ensure it's running,
# and run/re-run the provisioning process.

# Exit immediately if a command exits with a non-zero status.
set -e

# Check if a username argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <developer_username>"
  echo "Example: $0 jsmith"
  exit 1
fi

DEV_USERNAME="$1"
VM_NAME="dev-${DEV_USERNAME}-vm" # Used for messaging

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
