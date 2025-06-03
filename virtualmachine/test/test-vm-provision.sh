#!/bin/bash

# Test script for VM provisioning
# This script tests the VM provisioning process to ensure it completes successfully

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
TEST_USER="testprovision"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VAGRANT_DIR="$TEST_DIR/virtualmachine"

echo -e "${YELLOW}Starting VM Provisioning Test${NC}"
echo "Test directory: $TEST_DIR"
echo "Vagrant directory: $VAGRANT_DIR"
echo "Test user: $TEST_USER"
echo ""

# Function to cleanup test VM
cleanup_test_vm() {
    echo -e "${YELLOW}Cleaning up test VM...${NC}"
    cd "$VAGRANT_DIR"
    
    # Destroy the test VM if it exists
    if DEV_USERNAME="$TEST_USER" vagrant status "$TEST_USER" 2>/dev/null | grep -q "running\|poweroff\|saved"; then
        echo "Destroying existing test VM..."
        DEV_USERNAME="$TEST_USER" vagrant destroy "$TEST_USER" -f || true
    fi
    
    # Clean up VirtualBox VM if it still exists
    if VBoxManage list vms | grep -q "dev-${TEST_USER}-vm"; then
        echo "Removing VirtualBox VM..."
        VBoxManage unregistervm "dev-${TEST_USER}-vm" --delete || true
    fi
}

# Function to check if a service is running in the VM
check_vm_service() {
    local service=$1
    local vm_user=$2
    
    echo -n "Checking $service service... "
    if DEV_USERNAME="$vm_user" vagrant ssh "$vm_user" -c "systemctl is-active --quiet $service" 2>/dev/null; then
        echo -e "${GREEN}ACTIVE${NC}"
        return 0
    else
        echo -e "${RED}INACTIVE${NC}"
        return 1
    fi
}

# Function to run command in VM
run_in_vm() {
    local vm_user=$1
    local command=$2
    DEV_USERNAME="$vm_user" vagrant ssh "$vm_user" -c "$command" 2>/dev/null
}

# Main test execution
main() {
    # Change to vagrant directory
    cd "$VAGRANT_DIR"
    
    # Clean up any existing test VM
    cleanup_test_vm
    
    echo -e "\n${YELLOW}Step 1: Testing VM Provisioning${NC}"
    echo "Running provision_vm.sh for test user..."
    
    if ./host_scripts/provision_vm.sh "$TEST_USER"; then
        echo -e "${GREEN}✓ VM provisioning script completed successfully${NC}"
    else
        echo -e "${RED}✗ VM provisioning script failed${NC}"
        exit 1
    fi
    
    echo -e "\n${YELLOW}Step 2: Waiting for VM to stabilize${NC}"
    echo "Waiting 30 seconds for services to start..."
    sleep 30
    
    echo -e "\n${YELLOW}Step 3: Verifying VM State${NC}"
    
    # Check if VM is running
    echo -n "Checking VM status... "
    if DEV_USERNAME="$TEST_USER" vagrant status "$TEST_USER" | grep -q "running"; then
        echo -e "${GREEN}RUNNING${NC}"
    else
        echo -e "${RED}NOT RUNNING${NC}"
        exit 1
    fi
    
    echo -e "\n${YELLOW}Step 4: Testing VM Connectivity${NC}"
    
    # Test SSH connectivity
    echo -n "Testing SSH connectivity... "
    if run_in_vm "$TEST_USER" "echo 'SSH OK'" | grep -q "SSH OK"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        exit 1
    fi
    
    echo -e "\n${YELLOW}Step 5: Checking Installed Software${NC}"
    
    # Check for key software installations
    declare -a software=("git" "vim" "curl" "python3" "node" "npm" "aws" "sam" "gh" "google-chrome-stable" "code")
    
    for cmd in "${software[@]}"; do
        echo -n "Checking $cmd... "
        if run_in_vm "$TEST_USER" "command -v $cmd" >/dev/null 2>&1; then
            echo -e "${GREEN}INSTALLED${NC}"
        else
            echo -e "${RED}NOT FOUND${NC}"
        fi
    done
    
    echo -e "\n${YELLOW}Step 6: Checking Services${NC}"
    
    # Check critical services
    check_vm_service "ssh" "$TEST_USER"
    check_vm_service "lightdm" "$TEST_USER"
    
    # Check VirtualBox Guest Additions
    echo -n "Checking VirtualBox Guest Additions... "
    if run_in_vm "$TEST_USER" "systemctl is-active --quiet vboxadd.service || systemctl is-active --quiet vboxadd" 2>/dev/null; then
        echo -e "${GREEN}ACTIVE${NC}"
        # Get version info
        GA_VERSION=$(run_in_vm "$TEST_USER" "VBoxService --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1" || echo "unknown")
        echo "  Guest Additions version: $GA_VERSION"
    else
        echo -e "${YELLOW}INACTIVE (may still be functional)${NC}"
    fi
    
    echo -e "\n${YELLOW}Step 7: Checking User Configuration${NC}"
    
    # Check if test user exists
    echo -n "Checking if user '$TEST_USER' exists... "
    if run_in_vm "$TEST_USER" "id $TEST_USER" >/dev/null 2>&1; then
        echo -e "${GREEN}EXISTS${NC}"
    else
        echo -e "${RED}NOT FOUND${NC}"
        exit 1
    fi
    
    # Check autogen_agent directory
    echo -n "Checking autogen_agent directory... "
    if run_in_vm "$TEST_USER" "[ -d /home/$TEST_USER/autogen_agent ]"; then
        echo -e "${GREEN}EXISTS${NC}"
    else
        echo -e "${RED}NOT FOUND${NC}"
    fi
    
    # Check .env file
    echo -n "Checking .env file... "
    if run_in_vm "$TEST_USER" "[ -f /home/$TEST_USER/autogen_agent/.env ]"; then
        echo -e "${GREEN}EXISTS${NC}"
    else
        echo -e "${YELLOW}NOT FOUND (may need Discord token configuration)${NC}"
    fi
    
    echo -e "\n${YELLOW}Step 8: Checking dpkg status${NC}"
    
    # Check for dpkg issues
    echo -n "Checking for interrupted dpkg processes... "
    if run_in_vm "$TEST_USER" "sudo dpkg --audit" 2>&1 | grep -q "no packages"; then
        echo -e "${GREEN}NONE${NC}"
    else
        echo -e "${RED}FOUND ISSUES${NC}"
        run_in_vm "$TEST_USER" "sudo dpkg --audit"
    fi
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}VM Provisioning Test Completed Successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    echo -e "\n${YELLOW}Cleanup Options:${NC}"
    echo "1. Keep the test VM running for manual inspection"
    echo "2. Destroy the test VM"
    echo -n "Enter choice (1/2): "
    read -r choice
    
    if [ "$choice" = "2" ]; then
        cleanup_test_vm
        echo -e "${GREEN}Test VM cleaned up${NC}"
    else
        echo -e "${YELLOW}Test VM left running at: dev-${TEST_USER}-vm${NC}"
        echo "To connect: cd $VAGRANT_DIR && DEV_USERNAME=$TEST_USER vagrant ssh $TEST_USER"
        echo "To destroy later: cd $VAGRANT_DIR && DEV_USERNAME=$TEST_USER vagrant destroy $TEST_USER -f"
    fi
}

# Run main function
main