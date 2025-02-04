#!/bin/bash
# Set strict mode
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Function to handle errors
handle_error() {
    echo -e "${RED}Error: $1${NC}"
    cleanup
    exit 1
}

# Function to print success messages
success_msg() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print info messages
info_msg() {
    echo -e "${YELLOW}➜ $1${NC}"
}

# Function to check if a command was successful
check_success() {
    if [ $? -ne 0 ]; then
        handle_error "$1"
    fi
}

# Function to clean up DFX processes
cleanup() {
    info_msg "Cleaning up DFX processes..."
    dfx stop || true
    
    # Check if port 4943 is in use
    if lsof -i :4943 >/dev/null 2>&1; then
        info_msg "Port 4943 is still in use. Attempting to free it..."
        sudo lsof -ti :4943 | xargs -r sudo kill
    fi
    
    # Remove .dfx directory if it exists
    if [ -d ".dfx" ]; then
        info_msg "Removing .dfx directory..."
        rm -rf .dfx
    fi
    
    sleep 2
}

# Function to check if time sync is needed
need_time_sync() {
    dfx deploy --check 2>&1 | grep -q "Certificate is stale"
    return $?
}

# Function to check code formatting
check_formatting() {
    info_msg "Checking code formatting..."
    
    # Check if prettier is installed
    if ! command -v yarn &> /dev/null; then
        handle_error "yarn is not installed. Please install yarn first."
    fi

    # Check Motoko files formatting
    info_msg "Checking Motoko files..."
    if ! yarn format:mo:check; then
        echo -e "${RED}❌ Motoko files are not properly formatted${NC}"
        echo "Run 'yarn format:mo' to fix formatting issues"
        exit 1
    fi
    success_msg "Motoko files are properly formatted"

    # Optionally check other files
    info_msg "Checking other source files..."
    if ! yarn format:check; then
        echo -e "${RED}❌ Some files are not properly formatted${NC}"
        echo "Run 'yarn format' to fix formatting issues"
        exit 1
    fi
    success_msg "All files are properly formatted"
}

# Function to run unit tests
run_unit_tests() {
    info_msg "Running Motoko unit tests..."
    if ! mops test -r verbose; then
        handle_error "Motoko unit tests failed"
    fi
    success_msg "Motoko unit tests passed"
}

# Function to start DFX
start_dfx() {
    info_msg "Starting dfx with clean state..."
    cleanup
    # Start dfx in background but redirect output to a file
    dfx start --clean --background > dfx.log 2>&1
    
    # Wait for dfx to be ready
    local counter=0
    while ! dfx ping >/dev/null 2>&1; do
        if [ $counter -gt 30 ]; then
            # If timeout, show the logs to help debug
            cat dfx.log
            handle_error "Timeout waiting for dfx to start"
        fi
        sleep 1
        counter=$((counter + 1))
    done
    
    # Follow the logs in background
    tail -f dfx.log &
    TAIL_PID=$!
    
    # Make sure to kill the tail process in cleanup
    trap 'kill $TAIL_PID' EXIT
    
    success_msg "DFX started successfully"
}

main() {
    info_msg "Starting IC test workflow..."

    # Source environment setup using absolute path
    source "${SCRIPT_DIR}/setup-env.sh"
    
    # Change to project root directory
    cd "${SCRIPT_DIR}/.."
    
    # Check formatting first
    check_formatting
    
    # Run Motoko unit tests
    run_unit_tests
    
    # Start dfx with clean state
    start_dfx
    
    # Try to deploy, sync time only if needed
    info_msg "Attempting deployment..."
    if "${SCRIPT_DIR}/deploy.sh"; then
        success_msg "Deployment successful!"
    else
        if need_time_sync; then
            info_msg "Time sync needed. Synchronizing WSL time..."
            sudo hwclock -s
            check_success "Failed to sync WSL time"
            
            info_msg "Retrying deployment..."
            cleanup
            start_dfx
            "${SCRIPT_DIR}/deploy.sh"
            check_success "Failed to deploy canisters even after time sync"
        else
            handle_error "Failed to deploy canisters for unknown reason"
        fi
    fi
    
    # Run e2e tests
    info_msg "Running e2e tests..."
    yarn test:e2e
    check_success "e2e tests failed"
    
    # Cleanup
    cleanup
    
    success_msg "All tests completed successfully! 🎉"
}

# Trap ctrl-c and call cleanup
trap 'echo -e "\n${RED}Test script interrupted${NC}"; cleanup; exit 1' INT

# Run main function
main