#!/bin/bash

# Script to restart a specific developer VM by saving its state (suspend)
# and then resuming it using Vagrant.

# Check if username is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <username>"
  exit 1
fi

DEV_USERNAME=$1
VM_NAME="dev-${DEV_USERNAME}-vm" # Used for messaging

echo ">>> Attempting to restart (via suspend/resume) VM for user '$DEV_USERNAME' using Vagrant..."

# Get the current state using vagrant status
# We need to pass DEV_USERNAME here too, in case Vagrant needs it to identify the machine
echo "Checking current state..."
# Pass $DEV_USERNAME as the machine name argument
VAGRANT_STATUS_OUTPUT=$(DEV_USERNAME="$DEV_USERNAME" vagrant status "$DEV_USERNAME" --machine-readable 2>&1)
VAGRANT_STATUS_EXIT_CODE=$?

if [ $VAGRANT_STATUS_EXIT_CODE -ne 0 ]; then
    echo "Error getting Vagrant status for '$DEV_USERNAME'."
    echo "$VAGRANT_STATUS_OUTPUT"
    exit 1
fi

# Parse the state (robust parsing is tricky, this is a basic attempt)
# Format is like: 1680819788,default,state,running
VM_STATE=$(echo "$VAGRANT_STATUS_OUTPUT" | grep ",state," | cut -d, -f4)

if [ -z "$VM_STATE" ]; then
    echo "Error: Could not determine VM state from Vagrant status output:"
    echo "$VAGRANT_STATUS_OUTPUT"
    exit 1
fi

echo "Current state: $VM_STATE"

# --- Suspend Phase (if running) ---
if [ "$VM_STATE" == "running" ]; then
  echo "VM is running. Attempting to suspend..."
  # Pass $DEV_USERNAME as the machine name argument
  if ! DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant suspend "$DEV_USERNAME"; then
      echo "Error: Failed to suspend VM for '$DEV_USERNAME'."
      exit 1
  fi
  echo "VM suspended successfully."
  # After suspend, the state should be 'saved' for the resume step
  VM_STATE="saved"
elif [ "$VM_STATE" == "saved" ]; then
  echo "VM is already suspended (saved state)."
else
  echo "Error: VM is not running or saved (state: '$VM_STATE'). Cannot restart via suspend/resume."
  echo "Use './start_vm.sh $DEV_USERNAME' or './restart_vm.sh $DEV_USERNAME' instead."
  exit 1
fi

# --- Resume Phase ---
# At this point, VM_STATE should be 'saved'
if [ "$VM_STATE" == "saved" ]; then
    echo ">>> Attempting to resume VM for '$DEV_USERNAME'..."
    # Pass $DEV_USERNAME as the machine name argument
    if ! DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant resume "$DEV_USERNAME"; then
        echo "Error: Failed to resume VM for '$DEV_USERNAME'."
        exit 1
    fi
    echo "VM for '$DEV_USERNAME' resumed successfully."
else
    # Should not happen if logic above is correct, but good to check
    echo "Error: VM is in unexpected state '$VM_STATE' before resume phase. Aborting."
    exit 1
fi

exit 0
