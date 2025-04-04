#!/bin/bash

# Script to gracefully restart a specific developer VM using VBoxManage

# Check if username is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME=$1
VM_NAME="dev-${USERNAME}-vm"

echo ">>> Attempting to restart VM: $VM_NAME..."

# Check if VM exists
if ! VBoxManage showvminfo "$VM_NAME" --machinereadable > /dev/null 2>&1; then
  echo "Error: VM '$VM_NAME' not found."
  echo "Make sure the VM was created first (e.g., using 'DEV_USERNAME=$USERNAME vagrant up')."
  exit 1
fi

# Check current VM state
VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep VMState= | cut -d'=' -f2 | tr -d '"')

# --- Stop Phase ---
if [ "$VM_STATE" == "running" ]; then
  echo "VM is running. Attempting graceful shutdown..."
  # Send ACPI shutdown signal
  VBoxManage controlvm "$VM_NAME" acpipowerbutton

  # Wait for the VM to power off
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

  # Check state after waiting
  VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep VMState= | cut -d'=' -f2 | tr -d '"')
  if [ "$VM_STATE" == "running" ]; then
    echo "Error: VM '$VM_NAME' did not stop within $TIMEOUT seconds. Restart aborted."
    echo "You may need to manually intervene (e.g., VBoxManage controlvm '$VM_NAME' poweroff)."
    exit 1
  elif [ "$VM_STATE" != "poweroff" ]; then
     echo "VM entered state '$VM_STATE' after shutdown signal. Proceeding to start..."
     # Allow starting from states like 'saved' or 'aborted' if shutdown resulted in them unexpectedly
  else
     echo "VM stopped successfully."
  fi
elif [ "$VM_STATE" == "poweroff" ] || [ "$VM_STATE" == "saved" ] || [ "$VM_STATE" == "aborted" ]; then
  echo "VM is not running (state: '$VM_STATE'). Proceeding directly to start phase."
else
  echo "Error: VM '$VM_NAME' is in an unexpected state ('$VM_STATE'). Cannot restart."
  exit 1
fi

# --- Start Phase ---
echo ">>> Attempting to start VM: $VM_NAME..."
# Re-check state in case it changed or stop phase wasn't needed
VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep VMState= | cut -d'=' -f2 | tr -d '"')

if [ "$VM_STATE" == "running" ]; then
    echo "Error: VM '$VM_NAME' is already running (unexpected). Restart aborted."
    exit 1
fi

# Start the VM
VBoxManage startvm "$VM_NAME" --type gui

if [ $? -eq 0 ]; then
  echo "VM '$VM_NAME' restarted successfully."
else
  echo "Error: Failed to start VM '$VM_NAME' during restart."
  exit 1
fi

exit 0
