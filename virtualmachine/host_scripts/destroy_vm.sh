#!/bin/bash

# Script to forcefully destroy a specific developer VM using Vagrant

# Check if username is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

USERNAME=$1
DEV_USERNAME=$1
VM_NAME="dev-${DEV_USERNAME}-vm" # Used for messaging

echo ">>> Attempting to forcefully destroy VM for user '$DEV_USERNAME' (machine name: '$DEV_USERNAME') using 'vagrant destroy -f'..."

# Run vagrant destroy -f. This will:
# 1. Stop the VM if running.
# 2. Remove the VM from VirtualBox.
# 3. Clean up Vagrant's tracking information for this machine.
# Pass $DEV_USERNAME as the machine name argument
# Use sudo -E to preserve environment for Vagrantfile
if DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant destroy "$DEV_USERNAME" -f; then
  echo "VM for '$DEV_USERNAME' destroyed successfully via name."
  exit 0 # Success
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
      exit 0 # Success
    else
      echo "Warning: Failed to destroy VM using global ID '$GLOBAL_ID'."
      # Still exit 0 as the goal is cleanup and the VM might truly be gone
      exit 0
    fi
  else
    echo "Warning: No matching global ID found for machine '$DEV_USERNAME' in directory '$CURRENT_DIR'."
    # Exit 0 as the VM likely doesn't exist in Vagrant's tracking at all
    exit 0
  fi
fi
