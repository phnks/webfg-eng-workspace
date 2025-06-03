#!/bin/bash

# Script to create a VM if it doesn't exist, ensure it's running,
# and run/re-run the provisioning process.

# Exit immediately if a command exits with a non-zero status.
set -e

# Check if a username argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <developer_username>"
  echo "Example: $0 jsmith"
  exit 1
fi

DEV_USERNAME="$1"
VM_NAME="dev-${DEV_USERNAME}-vm" # Used for messaging

# Function to fix Vagrant box permissions
fix_vagrant_box_permissions() {
  local VAGRANT_BOXES_DIR="$HOME/.vagrant.d/boxes"
  
  if [ -d "$VAGRANT_BOXES_DIR" ]; then
    # Check if any files are owned by root
    local ROOT_OWNED_FILES=$(find "$VAGRANT_BOXES_DIR" -user 0 2>/dev/null | wc -l || echo "0")
    
    if [ "$ROOT_OWNED_FILES" -gt "0" ]; then
      echo ">>> Found $ROOT_OWNED_FILES files owned by root in Vagrant boxes directory"
      echo ">>> Attempting to fix permissions (may require sudo)..."
      
      # Try to fix ownership
      if sudo chown -R "$(id -u):$(id -g)" "$VAGRANT_BOXES_DIR" 2>/dev/null; then
        echo ">>> ✓ Fixed Vagrant boxes directory permissions"
      else
        echo ">>> Warning: Could not fix Vagrant boxes permissions"
        echo ">>> This may cause errors during provisioning"
        echo ">>> To fix manually, run: sudo chown -R $(id -u):$(id -g) $VAGRANT_BOXES_DIR"
      fi
    fi
  fi
}

echo ">>> Ensuring VM for user '$DEV_USERNAME' exists and is running..."

# Fix permissions before attempting vagrant operations
fix_vagrant_box_permissions

# Run vagrant up. This will:
# 1. Create the VM if it doesn't exist (and run initial provisioning).
# 2. Start the VM if it exists but is stopped.
# 3. Do nothing if the VM is already running.
# We now pass $DEV_USERNAME as the machine name argument to vagrant

# First attempt without sudo
echo ">>> Attempting to start VM without sudo..."
if DEV_USERNAME="$DEV_USERNAME" vagrant up "$DEV_USERNAME" --provider=virtualbox 2>&1 | tee /tmp/vagrant_up_$$.log; then
    echo ">>> VM created/started successfully without sudo"
else
    # Check if the error is permission-related
    if grep -q "Permission denied" /tmp/vagrant_up_$$.log || grep -q "Errno::EACCES" /tmp/vagrant_up_$$.log; then
        echo ">>> Permission error detected. Fixing permissions and retrying..."
        
        # Try to fix permissions more aggressively
        echo ">>> Fixing Vagrant directory permissions..."
        sudo chown -R "$(id -u):$(id -g)" "$HOME/.vagrant.d" 2>/dev/null || true
        
        # Also fix local .vagrant directory if it exists
        if [ -d ".vagrant" ]; then
            sudo chown -R "$(id -u):$(id -g)" ".vagrant" 2>/dev/null || true
        fi
        
        # Retry with fixed permissions
        echo ">>> Retrying vagrant up after fixing permissions..."
        if DEV_USERNAME="$DEV_USERNAME" vagrant up "$DEV_USERNAME" --provider=virtualbox; then
            echo ">>> VM created/started successfully after fixing permissions"
        else
            # Last attempt with sudo
            echo ">>> Attempting with sudo as last resort..."
            if DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant up "$DEV_USERNAME" --provider=virtualbox; then
                echo ">>> VM created/started successfully with sudo"
                
                # Fix ownership after sudo operation
                echo ">>> Fixing ownership after sudo operation..."
                sudo chown -R "$(id -u):$(id -g)" "$HOME/.vagrant.d" 2>/dev/null || true
                [ -d ".vagrant" ] && sudo chown -R "$(id -u):$(id -g)" ".vagrant" 2>/dev/null || true
            else
                echo ""
                echo "Error: 'vagrant up $DEV_USERNAME' failed for VM '$VM_NAME' even with sudo."
                echo "Check /tmp/vagrant_up_$$.log for details."
                exit 1
            fi
        fi
    else
        # Try with sudo if not a permission error
        echo ">>> Non-permission error detected. Attempting with sudo..."
        if DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant up "$DEV_USERNAME" --provider=virtualbox; then
            echo ">>> VM created/started successfully with sudo"
            
            # Fix ownership after sudo operation
            echo ">>> Fixing ownership after sudo operation..."
            sudo chown -R "$(id -u):$(id -g)" "$HOME/.vagrant.d" 2>/dev/null || true
            [ -d ".vagrant" ] && sudo chown -R "$(id -u):$(id -g)" ".vagrant" 2>/dev/null || true
        else
            echo ""
            echo "Error: 'vagrant up $DEV_USERNAME' failed for VM '$VM_NAME'."
            echo "Check /tmp/vagrant_up_$$.log for details."
            exit 1
        fi
    fi
fi

# Clean up log file
rm -f /tmp/vagrant_up_$$.log
echo ">>> VM '$VM_NAME' is up and running."

# Explicitly run provisioning to ensure it runs even if the VM already existed.
# Vagrant provision should wait for SSH to be ready.
echo ""
echo ">>> Running provisioning for VM '$VM_NAME'..."

# Try provisioning without sudo first
if DEV_USERNAME="$DEV_USERNAME" vagrant provision "$DEV_USERNAME" 2>&1 | tee /tmp/vagrant_provision_$$.log; then
    echo ">>> VM provisioned successfully without sudo"
else
    # Check if it's a permission error
    if grep -q "Permission denied" /tmp/vagrant_provision_$$.log || grep -q "Errno::EACCES" /tmp/vagrant_provision_$$.log; then
        echo ">>> Permission error during provisioning. Fixing and retrying..."
        
        # Fix permissions
        sudo chown -R "$(id -u):$(id -g)" "$HOME/.vagrant.d" 2>/dev/null || true
        [ -d ".vagrant" ] && sudo chown -R "$(id -u):$(id -g)" ".vagrant" 2>/dev/null || true
        
        # Retry provisioning
        if DEV_USERNAME="$DEV_USERNAME" vagrant provision "$DEV_USERNAME"; then
            echo ">>> VM provisioned successfully after fixing permissions"
        else
            # Try with sudo
            if DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant provision "$DEV_USERNAME"; then
                echo ">>> VM provisioned successfully with sudo"
                # Fix ownership after sudo
                sudo chown -R "$(id -u):$(id -g)" "$HOME/.vagrant.d" 2>/dev/null || true
                [ -d ".vagrant" ] && sudo chown -R "$(id -u):$(id -g)" ".vagrant" 2>/dev/null || true
            else
                echo ""
                echo "Error: 'vagrant provision $DEV_USERNAME' failed for VM '$VM_NAME'."
                echo "Check /tmp/vagrant_provision_$$.log for details."
                exit 1
            fi
        fi
    else
        # Try with sudo for non-permission errors
        if DEV_USERNAME="$DEV_USERNAME" sudo -E vagrant provision "$DEV_USERNAME"; then
            echo ">>> VM provisioned successfully with sudo"
            # Fix ownership after sudo
            sudo chown -R "$(id -u):$(id -g)" "$HOME/.vagrant.d" 2>/dev/null || true
            [ -d ".vagrant" ] && sudo chown -R "$(id -u):$(id -g)" ".vagrant" 2>/dev/null || true
        else
            echo ""
            echo "Error: 'vagrant provision $DEV_USERNAME' failed for VM '$VM_NAME'."
            echo "Check /tmp/vagrant_provision_$$.log for details."
            exit 1
        fi
    fi
fi

# Clean up log file
rm -f /tmp/vagrant_provision_$$.log

echo ""
echo ">>> VM provisioning process for '$DEV_USERNAME' finished successfully."
echo ">>> Note: The guest provisioning script might include a reboot."
echo ">>> The developer can log in via the GUI with username '$DEV_USERNAME' and password 'password'."
echo ">>> IMPORTANT: Remind the developer to change the default password immediately if this was the first setup!"

exit 0
