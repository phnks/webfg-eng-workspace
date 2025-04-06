#!/bin/bash

# Script to start/resume VMs for all users listed in the config file.
# Allows continuing to next user if one fails.

CONFIG_FILE="config/dev_users.txt"
START_SCRIPT="./host_scripts/start_vm.sh"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found at '$CONFIG_FILE'"
  exit 1
fi

# Check if helper script exists and is executable
if [ ! -x "$START_SCRIPT" ]; then
    echo "Error: Start script '$START_SCRIPT' not found or not executable."
    exit 1
fi

echo ">>> Starting/Resuming VMs for users in '$CONFIG_FILE'..."
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

  # Attempt to start/resume the VM using the start_vm.sh script (which now uses vagrant up)
  if "$START_SCRIPT" "$USERNAME"; then
    echo "Start/Resume command finished for '$USERNAME'."
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "Error: Failed to start/resume VM for user '$USERNAME'."
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
