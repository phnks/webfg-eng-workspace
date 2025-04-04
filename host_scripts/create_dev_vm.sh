#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Check if a username argument is provided
if [ -z "$1" ]; then
  echo "Usage: ./create_dev_vm.sh <developer_username>"
  echo "Example: ./create_dev_vm.sh jsmith"
  exit 1
fi

DEV_USERNAME="$1"

echo ">>> Creating/Starting VM for user: $DEV_USERNAME using VirtualBox provider..."

# Run vagrant up, passing the username and specifying the provider
# Vagrant will handle creating the VM if it doesn't exist, or just starting it if it does.
# The provisioning script (setup_dev.sh) runs automatically the first time the VM is created.
DEV_USERNAME="$DEV_USERNAME" vagrant up --provider=virtualbox

echo ""
echo ">>> VM creation/startup process for $DEV_USERNAME finished."
echo ">>> If this was the first time, the VM should be provisioned with Xubuntu and the user account."
echo ">>> The developer can log in via the GUI with username '$DEV_USERNAME' and password 'password'."
echo ">>> IMPORTANT: Remind the developer to change the default password immediately!"
