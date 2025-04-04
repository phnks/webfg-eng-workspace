#!/bin/bash

# Script to gracefully stop VMs for all users listed in the config file.
# Allows continuing to next user if one fails.

CONFIG_FILE="config/dev_users.txt"
STOP_SCRIPT="./host_scripts/stop_vm.sh"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found at '$CONFIG_FILE'"
  exit 1
fi

# Check if helper script exists and is executable
if [ ! -x "$STOP_SCRIPT" ]; then
    echo "Error: Stop script '$STOP_SCRIPT' not found or not executable."
    exit 1
fi

echo ">>> Stopping VMs for users in '$CONFIG_FILE'..."
echo "--------------------------------------------------"

SUCCESS_COUNT=0
FAIL_COUNT=0

# Read the config file line by line, skipping comments and empty lines
grep -v '^#' "$CONFIG_FILE" | grep -v '^[[:space:]]*$' | while IFS= read -r USERNAME; do
  # Trim whitespace just in case
  USERNAME=$(echo "$USERNAME" | xargs)

  if [ -z "$USERNAME" ]; then
      continue # Skip empty lines after potential trimming
  fi

  echo ">>> Processing user: $USERNAME"
  VM_NAME="dev-${USERNAME}-vm"

  # Check if VM exists using VBoxManage first
  if ! VBoxManage showvminfo "$VM_NAME" --machinereadable > /dev/null 2>&1; then
    echo "VM '$VM_NAME' not found. Skipping."
    FAIL_COUNT=$((FAIL_COUNT + 1)) # Count not found as a failure/skip
    echo "--------------------------------------------------"
    continue
  fi

  # Attempt to stop the VM
  if "$STOP_SCRIPT" "$USERNAME"; then
    echo "Stop command finished for '$USERNAME'."
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "Error: Failed to stop VM for user '$USERNAME'."
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  echo "--------------------------------------------------"

done

echo ">>> All users processed."
echo ">>> Summary: ${SUCCESS_COUNT} succeeded, ${FAIL_COUNT} failed/skipped."

# Exit with non-zero status if any failures occurred
if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
else
    exit 0
fi
