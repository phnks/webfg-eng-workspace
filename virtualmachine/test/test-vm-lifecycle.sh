#!/bin/bash

# Test script for VM lifecycle operations
# This script tests stopping, starting, restarting, and savestate operations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
TEST_USER="${1:-homonculus}"  # Use provided user or default to homonculus
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VAGRANT_DIR="$TEST_DIR/virtualmachine"

echo -e "${YELLOW}Starting VM Lifecycle Test${NC}"
echo "Test directory: $TEST_DIR"
echo "Vagrant directory: $VAGRANT_DIR"
echo "Test user: $TEST_USER"
echo ""

# Function to check VM status
check_vm_status() {
    local expected_state=$1
    local actual_state
    
    cd "$VAGRANT_DIR"
    actual_state=$(DEV_USERNAME="$TEST_USER" vagrant status "$TEST_USER" 2>/dev/null | grep -E "^$TEST_USER" | awk '{print $2}')
    
    if [[ "$actual_state" == "$expected_state" ]]; then
        echo -e "${GREEN}✓ VM is in expected state: $expected_state${NC}"
        return 0
    else
        echo -e "${RED}✗ VM state mismatch. Expected: $expected_state, Actual: $actual_state${NC}"
        return 1
    fi
}

# Function to run lifecycle command
run_lifecycle_command() {
    local command=$1
    local script=$2
    
    echo -e "\n${YELLOW}Testing: $command${NC}"
    
    cd "$VAGRANT_DIR"
    if "./host_scripts/$script" "$TEST_USER"; then
        echo -e "${GREEN}✓ $command completed successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ $command failed${NC}"
        return 1
    fi
}

# Main test execution
main() {
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo "- VM should already be provisioned for user: $TEST_USER"
    echo "- If not, run: ./virtualmachine/host_scripts/provision_vm.sh $TEST_USER"
    echo ""
    
    # Check initial VM state
    echo -e "${YELLOW}Step 1: Checking initial VM state${NC}"
    cd "$VAGRANT_DIR"
    DEV_USERNAME="$TEST_USER" vagrant status "$TEST_USER" || {
        echo -e "${RED}Error: VM not found for user $TEST_USER${NC}"
        echo "Please provision the VM first."
        exit 1
    }
    
    # Test stop operation
    echo -e "\n${YELLOW}Step 2: Testing VM Stop${NC}"
    run_lifecycle_command "Stop VM" "stop_vm.sh"
    sleep 5
    check_vm_status "poweroff"
    
    # Test start operation
    echo -e "\n${YELLOW}Step 3: Testing VM Start${NC}"
    run_lifecycle_command "Start VM" "start_vm.sh"
    sleep 10
    check_vm_status "running"
    
    # Test restart operation
    echo -e "\n${YELLOW}Step 4: Testing VM Restart${NC}"
    run_lifecycle_command "Restart VM" "restart_vm.sh"
    sleep 10
    check_vm_status "running"
    
    # Test savestate operation
    echo -e "\n${YELLOW}Step 5: Testing VM Savestate (Suspend)${NC}"
    run_lifecycle_command "Savestate VM" "savestate_vm.sh"
    sleep 5
    check_vm_status "saved"
    
    # Resume from savestate
    echo -e "\n${YELLOW}Step 6: Testing VM Resume from Savestate${NC}"
    run_lifecycle_command "Resume VM" "start_vm.sh"
    sleep 10
    check_vm_status "running"
    
    # Test restart from saved state
    echo -e "\n${YELLOW}Step 7: Testing VM Restart from Running State${NC}"
    run_lifecycle_command "Restart VM" "restart_vm.sh"
    sleep 10
    check_vm_status "running"
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}VM Lifecycle Test Completed Successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    echo -e "\n${YELLOW}Final VM State:${NC}"
    cd "$VAGRANT_DIR"
    DEV_USERNAME="$TEST_USER" vagrant status "$TEST_USER"
    
    echo -e "\n${YELLOW}Note:${NC} VM is left in running state"
}

# Run main function
main