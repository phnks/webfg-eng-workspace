#!/bin/bash

# Script to forcefully destroy a specific developer VM using Vagrant
# Includes VirtualBox cleanup fallback for orphaned VMs that Vagrant can't delete

# Check if username is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME=$1
DEV_USERNAME=$1
VM_NAME="dev-${DEV_USERNAME}-vm" # Used for messaging

# Function to clean up orphaned VirtualBox VMs
cleanup_virtualbox_vm() {
  echo ">>> Checking for orphaned VirtualBox VM '$VM_NAME'..."
  
  # Check if VirtualBox VM exists
  if VBoxManage list vms | grep -q "\"$VM_NAME\""; then
    echo "Found VirtualBox VM '$VM_NAME'. Attempting to remove it..."
    
    # First, try to stop the VM if it's running
    if VBoxManage list runningvms | grep -q "\"$VM_NAME\""; then
      echo "VM '$VM_NAME' is running. Stopping it..."
      VBoxManage controlvm "$VM_NAME" poweroff || echo "Warning: Failed to stop VM, continuing..."
      sleep 2
    fi
    
    # Remove the VM completely (unregister and delete files)
    echo "Removing VirtualBox VM '$VM_NAME'..."
    if VBoxManage unregistervm "$VM_NAME" --delete; then
      echo "✓ Successfully removed VirtualBox VM '$VM_NAME'"
      exit 0
    else
      echo "Warning: Failed to remove VirtualBox VM '$VM_NAME' by name."
      echo "You may need to manually remove it using VirtualBox Manager GUI."
      exit 1
    fi
  else
    echo "No VirtualBox VM named '$VM_NAME' found. Cleanup complete."
    exit 0
  fi
}

echo ">>> Attempting to forcefully destroy VM for user '$DEV_USERNAME' (machine name: '$DEV_USERNAME') using 'vagrant destroy -f'..."

# Run vagrant destroy -f. This will:
# 1. Stop the VM if running.
# 2. Remove the VM from VirtualBox.
# 3. Clean up Vagrant's tracking information for this machine.
# Pass $DEV_USERNAME as the machine name argument
# Use sudo -E to preserve environment for Vagrantfile
if DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant destroy "$DEV_USERNAME" -f; then
  echo "VM for '$DEV_USERNAME' destroyed successfully via name."
  
  # Verify that VirtualBox VM is actually gone
  echo "Verifying VirtualBox VM cleanup..."
  if VBoxManage list vms | grep -q "\"$VM_NAME\""; then
    echo "Warning: VirtualBox VM '$VM_NAME' still exists after Vagrant destroy."
    echo "Running VirtualBox cleanup to complete the destruction..."
    cleanup_virtualbox_vm
  else
    echo "✓ Verified: VirtualBox VM '$VM_NAME' has been completely removed."
    exit 0 # Success
  fi
else
  echo "Warning: Initial 'vagrant destroy $DEV_USERNAME -f' failed. Checking global status..."
  # Attempt to find the global ID for this machine in this directory
  # Need the current directory path for matching
  CURRENT_DIR=$(pwd)
  # Use awk for more robust parsing of the global-status output
  GLOBAL_ID=$(vagrant global-status | awk -v name="$DEV_USERNAME" -v dir="$CURRENT_DIR" '$2 == name && $5 == dir { print $1 }')

  if [ -n "$GLOBAL_ID" ]; then
    echo "Found global ID '$GLOBAL_ID' for machine '$DEV_USERNAME' in directory '$CURRENT_DIR'."
    echo "Attempting to destroy using global ID: vagrant destroy $GLOBAL_ID -f"
    if vagrant destroy "$GLOBAL_ID" -f; then
      echo "VM for '$DEV_USERNAME' (ID: $GLOBAL_ID) destroyed successfully via global ID."
      
      # Verify that VirtualBox VM is actually gone
      echo "Verifying VirtualBox VM cleanup..."
      if VBoxManage list vms | grep -q "\"$VM_NAME\""; then
        echo "Warning: VirtualBox VM '$VM_NAME' still exists after Vagrant destroy."
        echo "Running VirtualBox cleanup to complete the destruction..."
        cleanup_virtualbox_vm
      else
        echo "✓ Verified: VirtualBox VM '$VM_NAME' has been completely removed."
        exit 0 # Success
      fi
    else
      echo "Warning: Failed to destroy VM using global ID '$GLOBAL_ID'."
      echo "Attempting VirtualBox cleanup as fallback..."
      cleanup_virtualbox_vm
    fi
  else
    echo "Warning: No matching global ID found for machine '$DEV_USERNAME' in directory '$CURRENT_DIR'."
    echo "Attempting VirtualBox cleanup as fallback..."
    cleanup_virtualbox_vm
  fi
fi
