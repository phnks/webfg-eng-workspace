#!/bin/bash

# Script to destroy VMs for all users listed in a config file.
# Uses the destroy_vm.sh script.

CONFIG_FILE="config/dev_users.txt"
DESTROY_SCRIPT="./host_scripts/destroy_vm.sh"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found at '$CONFIG_FILE'"
  exit 1
fi

# Check if the destroy script exists and is executable
if [ ! -x "$DESTROY_SCRIPT" ]; then
    # Attempt to make it executable
    chmod +x "$DESTROY_SCRIPT"
    if [ ! -x "$DESTROY_SCRIPT" ]; then
        echo "Error: Destroy script '$DESTROY_SCRIPT' not found or could not be made executable."
        exit 1
    fi
fi

echo ">>> Starting destruction for all user VMs listed in '$CONFIG_FILE'..."
echo ">>> This will forcefully remove the VMs from VirtualBox."
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

  # Call the destroy script
  if "$DESTROY_SCRIPT" "$USERNAME"; then
      echo "Destroy command finished for '$USERNAME'."
      ((SUCCESS_COUNT++))
  else
      # destroy_vm.sh exits 0 even on failure, but let's catch non-zero just in case
      echo "Error during destroy process for '$USERNAME'. Check output above."
      ((FAIL_COUNT++))
  fi

  echo "--------------------------------------------------"
done

echo ">>> All users processed."
echo ">>> Summary: $SUCCESS_COUNT succeeded, $FAIL_COUNT failed/skipped."

# Also attempt to destroy the 'default' machine if it exists from previous runs
echo ">>> Attempting to destroy potential leftover 'default' machine..."
if DEV_USERNAME="default" sudo -E vagrant destroy default -f; then
    echo "Leftover 'default' machine destroyed successfully (if it existed)."
else
    echo "No leftover 'default' machine found or error destroying it."
fi

# Clean up the .vagrant directory again for good measure
echo ">>> Cleaning up .vagrant directory..."
sudo rm -rf .vagrant
echo ">>> Cleanup complete."

exit 0
