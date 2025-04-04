#!/bin/bash

# Script to gracefully stop a specific developer VM using VBoxManage

# Check if username is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME=$1
VM_NAME="dev-${USERNAME}-vm"

echo ">>> Attempting to stop VM: $VM_NAME..."

# Check if VM exists
if ! VBoxManage showvminfo "$VM_NAME" --machinereadable > /dev/null 2>&1; then
  echo "Error: VM '$VM_NAME' not found."
  exit 1
fi

# Check if VM is running
VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep VMState= | cut -d'=' -f2 | tr -d '"')

if [ "$VM_STATE" != "running" ]; then
  echo "VM '$VM_NAME' is not currently running (state: '$VM_STATE')."
  # Consider it a success if it's already stopped
  exit 0
fi

# Send ACPI shutdown signal (graceful shutdown)
echo "Sending ACPI shutdown signal to VM '$VM_NAME'..."
VBoxManage controlvm "$VM_NAME" acpipowerbutton

# Wait for the VM to power off (optional, but good for feedback)
TIMEOUT=60 # seconds
echo "Waiting up to $TIMEOUT seconds for VM to power off..."
COUNT=0
while [ "$VM_STATE" == "running" ] && [ $COUNT -lt $TIMEOUT ]; do
  sleep 1
  VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep VMState= | cut -d'=' -f2 | tr -d '"')
  COUNT=$((COUNT + 1))
  echo -n "."
done
echo "" # Newline after dots

# Final check
VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep VMState= | cut -d'=' -f2 | tr -d '"')
if [ "$VM_STATE" == "poweroff" ]; then
  echo "VM '$VM_NAME' stopped successfully."
  exit 0
elif [ "$VM_STATE" == "running" ]; then
  echo "Error: VM '$VM_NAME' did not stop within $TIMEOUT seconds."
  echo "You may need to force power off using: VBoxManage controlvm '$VM_NAME' poweroff"
  exit 1
else
  echo "VM '$VM_NAME' is now in state '$VM_STATE'."
  # Consider other states like 'saved' or 'aborted' as potentially stopped for this script's purpose
  exit 0
fi
