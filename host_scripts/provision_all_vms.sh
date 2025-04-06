#!/bin/bash

# Script to provision (create or re-provision) VMs for all users listed in a config file.
# Uses the unified provision_vm.sh script.
# Allows continuing to next user if one fails.

CONFIG_FILE="config/dev_users.txt"
PROVISION_SCRIPT="./host_scripts/provision_vm.sh"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found at '$CONFIG_FILE'"
  exit 1
fi

# Check if the unified provision script exists and is executable
if [ ! -x "$PROVISION_SCRIPT" ]; then
    echo "Error: Provision script '$PROVISION_SCRIPT' not found or not executable."
    exit 1
fi

echo ">>> Starting provisioning for all users in '$CONFIG_FILE'..."
echo "--------------------------------------------------"

# Read the config file line by line, skipping comments and empty lines
grep -v '^#' "$CONFIG_FILE" | grep -v '^[[:space:]]*$' | while IFS= read -r USERNAME; do
  # Trim whitespace just in case
  USERNAME=$(echo "$USERNAME" | xargs)

  if [ -z "$USERNAME" ]; then
      continue # Skip empty lines after potential trimming
  fi

  echo ">>> Processing user: $USERNAME"

  # Call the unified provisioning script
  if ! "$PROVISION_SCRIPT" "$USERNAME"; then
      echo "Error: Provisioning failed for user '$USERNAME'. Continuing to next user."
  else
      echo "Provisioning finished for '$USERNAME'."
  fi

  echo "--------------------------------------------------"
done

echo ">>> All users processed."
exit 0
