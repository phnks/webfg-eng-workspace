#!/bin/bash

# Script to start a specific developer VM using VBoxManage

# Check if username is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME=$1
VM_NAME="dev-${USERNAME}-vm"

echo ">>> Attempting to start VM: $VM_NAME..."

# Check if VM exists
if ! VBoxManage showvminfo "$VM_NAME" --machinereadable > /dev/null 2>&1; then
  echo "Error: VM '$VM_NAME' not found."
  echo "Make sure the VM was created first (e.g., using 'DEV_USERNAME=$USERNAME vagrant up')."
  exit 1
fi

# Check if VM is already running
VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep VMState= | cut -d'=' -f2 | tr -d '"')

if [ "$VM_STATE" == "running" ]; then
  echo "VM '$VM_NAME' is already running."
  exit 0
elif [ "$VM_STATE" != "poweroff" ] && [ "$VM_STATE" != "saved" ] && [ "$VM_STATE" != "aborted" ]; then
  echo "Error: VM '$VM_NAME' is in an unexpected state ('$VM_STATE'). Cannot start."
  exit 1
fi

# Start the VM (headless mode is often preferred for servers, but GUI was enabled in Vagrantfile)
# Use --type gui to match the Vagrantfile setting
VBoxManage startvm "$VM_NAME" --type gui

if [ $? -eq 0 ]; then
  echo "VM '$VM_NAME' started successfully."
else
  echo "Error: Failed to start VM '$VM_NAME'."
  exit 1
fi

exit 0
