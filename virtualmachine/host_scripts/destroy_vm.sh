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

# Function to clean up orphaned VirtualBox VMs and Vagrant cache
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
    else
      echo "Warning: Failed to remove VirtualBox VM '$VM_NAME' by name."
      echo "You may need to manually remove it using VirtualBox Manager GUI."
      exit 1
    fi
  else
    echo "No VirtualBox VM named '$VM_NAME' found in VirtualBox."
  fi
  
  # Clean up Vagrant global status cache for this VM name
  echo ">>> Cleaning up Vagrant global status cache..."
  cleanup_vagrant_cache
  
  # Clean up local .vagrant directory if it exists
  echo ">>> Cleaning up local Vagrant state..."
  cleanup_local_vagrant_state
  
  # Fix Vagrant global data permissions
  echo ">>> Fixing Vagrant global data permissions..."
  fix_vagrant_global_permissions
  
  echo "✓ Cleanup complete."
  exit 0
}

# Function to clean up Vagrant global status cache
cleanup_vagrant_cache() {
  echo "Checking Vagrant global status for stale '$DEV_USERNAME' entries..."
  
  # Get all global status entries for this username (may be multiple from different directories)
  GLOBAL_ENTRIES=$(DEV_USERNAME="$DEV_USERNAME" vagrant global-status 2>/dev/null | grep "$DEV_USERNAME" | awk '{print $1}' || true)
  
  if [ -n "$GLOBAL_ENTRIES" ]; then
    echo "Found Vagrant global status entries for '$DEV_USERNAME':"
    echo "$GLOBAL_ENTRIES"
    
    # Try to destroy each entry
    for ENTRY_ID in $GLOBAL_ENTRIES; do
      echo "Attempting to clean up Vagrant entry: $ENTRY_ID"
      
      # Try normal destroy first (without DEV_USERNAME since we're using global ID)
      if vagrant destroy "$ENTRY_ID" -f 2>/dev/null; then
        echo "✓ Cleaned up Vagrant entry: $ENTRY_ID"
      else
        echo "Warning: Could not destroy Vagrant entry $ENTRY_ID, trying with sudo..."
        # Try with sudo for entries created as root
        if sudo -n vagrant destroy "$ENTRY_ID" -f 2>/dev/null; then
          echo "✓ Cleaned up Vagrant entry with sudo: $ENTRY_ID"
        else
          echo "Warning: Failed to destroy entry $ENTRY_ID even with sudo, removing from cache..."
          # Force remove the stale entry by pruning and then manually removing if needed
          vagrant global-status --prune 2>/dev/null || true
        fi
      fi
    done
    
    # Always prune stale entries at the end
    echo "Pruning stale Vagrant global status entries..."
    if vagrant global-status --prune 2>/dev/null; then
      echo "✓ Successfully pruned Vagrant global status"
    else
      echo "Warning: Could not prune with vagrant command, manually cleaning machine index..."
      manual_clean_vagrant_index
    fi
  else
    echo "No Vagrant global status entries found for '$DEV_USERNAME'"
  fi
}

# Function to clean up local Vagrant state directory
cleanup_local_vagrant_state() {
  local VAGRANT_DIR=".vagrant"
  local MACHINE_DIR="$VAGRANT_DIR/machines/$DEV_USERNAME"
  
  if [ -d "$MACHINE_DIR" ]; then
    echo "Found local Vagrant state for '$DEV_USERNAME' at $MACHINE_DIR"
    
    # Check if the directory is owned by root and we're not root
    if [ "$(stat -c %u "$MACHINE_DIR")" = "0" ] && [ "$(id -u)" != "0" ]; then
      echo "Local Vagrant state owned by root, removing with sudo..."
      if sudo rm -rf "$MACHINE_DIR" 2>/dev/null; then
        echo "✓ Removed local Vagrant state for '$DEV_USERNAME'"
      else
        echo "Warning: Failed to remove local Vagrant state (no sudo access)"
        echo "Local Vagrant state created by root prevents VM recreation."
        echo ""
        echo "To fix this issue, run one of these commands:"
        echo "  sudo rm -rf $VAGRANT_DIR"
        echo "  sudo rm -rf $MACHINE_DIR"
        echo ""
        echo "This cleanup is required before creating new VMs."
      fi
    else
      echo "Removing local Vagrant state for '$DEV_USERNAME'..."
      rm -rf "$MACHINE_DIR"
      echo "✓ Removed local Vagrant state for '$DEV_USERNAME'"
    fi
    
    # If no machines left, remove the entire .vagrant directory
    if [ -d "$VAGRANT_DIR/machines" ] && [ -z "$(ls -A "$VAGRANT_DIR/machines" 2>/dev/null)" ]; then
      echo "No machines left, removing entire .vagrant directory..."
      if [ "$(stat -c %u "$VAGRANT_DIR")" = "0" ] && [ "$(id -u)" != "0" ]; then
        sudo rm -rf "$VAGRANT_DIR" 2>/dev/null || echo "Warning: Failed to remove .vagrant directory"
      else
        rm -rf "$VAGRANT_DIR"
      fi
      echo "✓ Removed empty .vagrant directory"
    fi
  else
    echo "No local Vagrant state found for '$DEV_USERNAME'"
  fi
}

# Function to fix Vagrant global data permissions
fix_vagrant_global_permissions() {
  local VAGRANT_DATA_DIR="$HOME/.vagrant.d/data"
  
  if [ ! -d "$VAGRANT_DATA_DIR" ]; then
    echo "No Vagrant data directory found at $VAGRANT_DATA_DIR"
    return
  fi
  
  # Check if any files are owned by root
  ROOT_OWNED_FILES=$(find "$VAGRANT_DATA_DIR" -user 0 2>/dev/null | wc -l)
  
  if [ "$ROOT_OWNED_FILES" -gt 0 ]; then
    echo "Found $ROOT_OWNED_FILES files owned by root in Vagrant data directory"
    echo "Attempting to fix ownership..."
    
    # Try to change ownership to current user
    if sudo chown -R "$(id -u):$(id -g)" "$VAGRANT_DATA_DIR" 2>/dev/null; then
      echo "✓ Fixed Vagrant data directory ownership"
    else
      echo "Warning: Failed to fix Vagrant data directory ownership (no sudo access)"
      echo "Manual fix required: sudo chown -R $(id -u):$(id -g) $VAGRANT_DATA_DIR"
    fi
  else
    echo "Vagrant data directory permissions are correct"
  fi
}

# Function to manually clean Vagrant machine index when prune fails
manual_clean_vagrant_index() {
  local MACHINE_INDEX_FILE="$HOME/.vagrant.d/data/machine-index/index"
  
  if [ ! -f "$MACHINE_INDEX_FILE" ]; then
    echo "No Vagrant machine index file found at $MACHINE_INDEX_FILE"
    return
  fi
  
  echo "Manually cleaning Vagrant machine index for '$DEV_USERNAME'..."
  
  # Create a backup
  cp "$MACHINE_INDEX_FILE" "${MACHINE_INDEX_FILE}.backup.$(date +%s)"
  
  # Use jq to remove all entries for the specific username (since VMs don't exist)
  if command -v jq >/dev/null 2>&1; then
    jq --arg username "$DEV_USERNAME" '
      .machines = (.machines | with_entries(select(.value.name != $username)))
    ' "$MACHINE_INDEX_FILE" > "${MACHINE_INDEX_FILE}.tmp"
    
    # Only update if jq succeeded
    if [ $? -eq 0 ]; then
      mv "${MACHINE_INDEX_FILE}.tmp" "$MACHINE_INDEX_FILE"
      echo "✓ Manually removed all '$DEV_USERNAME' entries from Vagrant machine index"
    else
      echo "Warning: Failed to clean machine index with jq"
      rm -f "${MACHINE_INDEX_FILE}.tmp"
    fi
  else
    echo "Warning: jq not available for machine index cleanup"
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
    
    # Also clean up local .vagrant state
    echo ">>> Cleaning up local Vagrant state..."
    cleanup_local_vagrant_state
    
    # Fix Vagrant global data permissions
    echo ">>> Fixing Vagrant global data permissions..."
    fix_vagrant_global_permissions
    
    echo "✓ Complete cleanup successful."
    exit 0 # Success
  fi
else
  echo "Warning: Initial 'vagrant destroy $DEV_USERNAME -f' failed. Checking global status..."
  # Attempt to find the global ID for this machine in this directory
  # Need the current directory path for matching
  CURRENT_DIR=$(pwd)
  # Use awk for more robust parsing of the global-status output
  GLOBAL_ID=$(DEV_USERNAME="$DEV_USERNAME" vagrant global-status | awk -v name="$DEV_USERNAME" -v dir="$CURRENT_DIR" '$2 == name && $5 == dir { print $1 }')

  if [ -n "$GLOBAL_ID" ]; then
    echo "Found global ID '$GLOBAL_ID' for machine '$DEV_USERNAME' in directory '$CURRENT_DIR'."
    echo "Attempting to destroy using global ID: vagrant destroy $GLOBAL_ID -f"
    if DEV_USERNAME="$DEV_USERNAME" vagrant destroy "$GLOBAL_ID" -f; then
      echo "VM for '$DEV_USERNAME' (ID: $GLOBAL_ID) destroyed successfully via global ID."
      
      # Verify that VirtualBox VM is actually gone
      echo "Verifying VirtualBox VM cleanup..."
      if VBoxManage list vms | grep -q "\"$VM_NAME\""; then
        echo "Warning: VirtualBox VM '$VM_NAME' still exists after Vagrant destroy."
        echo "Running VirtualBox cleanup to complete the destruction..."
        cleanup_virtualbox_vm
      else
        echo "✓ Verified: VirtualBox VM '$VM_NAME' has been completely removed."
        
        # Also clean up local .vagrant state
        echo ">>> Cleaning up local Vagrant state..."
        cleanup_local_vagrant_state
        
        # Fix Vagrant global data permissions
        echo ">>> Fixing Vagrant global data permissions..."
        fix_vagrant_global_permissions
        
        echo "✓ Complete cleanup successful."
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
