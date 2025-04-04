#!/bin/bash

# Script to re-run the provisioning process on an existing developer VM.

# Exit immediately if a command exits with a non-zero status.
set -e

# Check if a username argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <developer_username>"
  echo "Example: $0 jsmith"
  exit 1
fi

DEV_USERNAME="$1"
VM_NAME="dev-${DEV_USERNAME}-vm" # Used for checking existence/state

echo ">>> Attempting to re-provision VM for user: $DEV_USERNAME (VM: $VM_NAME)..."

# Optional: Check if the VM exists using VBoxManage first
if ! VBoxManage showvminfo "$VM_NAME" --machinereadable > /dev/null 2>&1; then
  echo "Error: VM '$VM_NAME' not found."
  echo "Make sure the VM was created first (e.g., using 'host_scripts/create_dev_vm.sh $DEV_USERNAME')."
  exit 1
fi

# Optional: Check if the VM is running, as 'vagrant provision' typically requires it
VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep VMState= | cut -d'=' -f2 | tr -d '"')
if [ "$VM_STATE" != "running" ]; then
    echo "Warning: VM '$VM_NAME' is not running (state: '$VM_STATE')."
    echo "Attempting to start it first using './host_scripts/start_vm.sh $DEV_USERNAME'..."
    if ! ./host_scripts/start_vm.sh "$DEV_USERNAME"; then
        echo "Error: Failed to start VM '$VM_NAME'. Cannot proceed with provisioning."
        exit 1
    fi
    echo "VM started. Proceeding with provisioning..."
    sleep 5 # Give VM a moment to boot fully before provisioning
fi


# Run vagrant provision, passing the username via environment variable
# Vagrant will connect to the running VM and execute the provisioner(s) defined in Vagrantfile
echo ">>> Running vagrant provision for $DEV_USERNAME..."
DEV_USERNAME="$DEV_USERNAME" vagrant provision

if [ $? -eq 0 ]; then
  echo ""
  echo ">>> VM re-provisioning process for $DEV_USERNAME finished successfully."
  echo ">>> Note: The guest script includes a reboot at the end, so the VM will restart."
else
  echo ""
  echo "Error: VM re-provisioning process for $DEV_USERNAME failed."
  exit 1
fi

exit 0
