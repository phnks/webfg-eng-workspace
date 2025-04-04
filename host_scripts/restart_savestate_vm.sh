#!/bin/bash

# Script to restart a specific developer VM by saving its state and then resuming it.

# Check if username is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME=$1
VM_NAME="dev-${USERNAME}-vm"

echo ">>> Attempting to restart (via savestate) VM: $VM_NAME..."

# Check if VM exists
if ! VBoxManage showvminfo "$VM_NAME" --machinereadable > /dev/null 2>&1; then
  echo "Error: VM '$VM_NAME' not found."
  exit 1
fi

# Check current VM state
VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep VMState= | cut -d'=' -f2 | tr -d '"')

# --- Save State Phase ---
if [ "$VM_STATE" == "running" ]; then
  echo "VM is running. Attempting to save state..."
  VBoxManage controlvm "$VM_NAME" savestate

  # Wait for the VM state to change
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

  # Check state after waiting
  VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep VMState= | cut -d'=' -f2 | tr -d '"')
  if [ "$VM_STATE" == "running" ]; then
    echo "Error: VM '$VM_NAME' did not transition to saved state within $TIMEOUT seconds. Restart aborted."
    exit 1
  elif [ "$VM_STATE" != "saved" ]; then
     echo "Error: VM entered unexpected state '$VM_STATE' after savestate command. Restart aborted."
     exit 1
  else
     echo "VM state saved successfully."
  fi
elif [ "$VM_STATE" == "saved" ]; then
  echo "VM is already in a saved state. Proceeding directly to start phase."
elif [ "$VM_STATE" == "poweroff" ] || [ "$VM_STATE" == "aborted" ]; then
   echo "VM is powered off or aborted (state: '$VM_STATE'). Cannot restart via savestate. Use start_vm.sh instead."
   exit 1
else
  echo "Error: VM '$VM_NAME' is in an unexpected state ('$VM_STATE'). Cannot restart via savestate."
  exit 1
fi

# --- Start Phase (Resume) ---
echo ">>> Attempting to resume/start VM: $VM_NAME..."
# Re-check state just in case
VM_STATE=$(VBoxManage showvminfo "$VM_NAME" --machinereadable | grep VMState= | cut -d'=' -f2 | tr -d '"')

if [ "$VM_STATE" == "running" ]; then
    echo "Error: VM '$VM_NAME' is already running (unexpected). Restart aborted."
    exit 1
elif [ "$VM_STATE" != "saved" ]; then
    # If it's not saved at this point (e.g., poweroff), we shouldn't proceed with a normal start here.
    echo "Error: VM is not in a saved state ('$VM_STATE'). Cannot resume. Restart aborted."
    exit 1
fi

# Start the VM (resumes from saved state if state is 'saved')
VBoxManage startvm "$VM_NAME" --type gui

if [ $? -eq 0 ]; then
  echo "VM '$VM_NAME' resumed/restarted successfully."
else
  echo "Error: Failed to resume/start VM '$VM_NAME' during restart."
  exit 1
fi

exit 0
