#!/bin/bash

# Script to stop a specific developer VM by saving its state using VBoxManage

# Check if username is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME=$1
VM_NAME="dev-${USERNAME}-vm"

echo ">>> Attempting to save state for VM: $VM_NAME..."

# Check if VM exists
if ! VBoxManage showvminfo "$VM_NAME" --machinereadable > /dev/null 2>&1; then
  echo "Error: VM '$VM_NAME' not found."
  exit 1
fi

# Check if VM is running
VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep VMState= | cut -d'=' -f2 | tr -d '"')

if [ "$VM_STATE" != "running" ]; then
  echo "VM '$VM_NAME' is not currently running (state: '$VM_STATE'). Cannot save state."
  # If it's already saved or powered off, consider it a success for idempotency? Or error? Let's error for clarity.
  if [ "$VM_STATE" == "saved" ]; then
    echo "VM is already in a saved state."
    exit 0 # Treat as success
  else
     exit 1 # Error for other non-running states
  fi
fi

# Save the VM state
echo "Saving state for VM '$VM_NAME'..."
VBoxManage controlvm "$VM_NAME" savestate

# Wait for the VM state to change (optional, but good for feedback)
TIMEOUT=60 # seconds
echo "Waiting up to $TIMEOUT seconds for VM state to change to 'saved'..."
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
if [ "$VM_STATE" == "saved" ]; then
  echo "VM '$VM_NAME' state saved successfully."
  exit 0
elif [ "$VM_STATE" == "running" ]; then
  echo "Error: VM '$VM_NAME' did not transition to saved state within $TIMEOUT seconds."
  exit 1
else
  echo "VM '$VM_NAME' is now in unexpected state '$VM_STATE' after savestate command."
  exit 1 # Treat unexpected states post-command as error
fi
