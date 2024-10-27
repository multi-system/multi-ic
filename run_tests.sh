#!/bin/bash

# Set strict mode
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to handle errors
handle_error() {
    echo -e "${RED}Error: $1${NC}"
    dfx stop
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

# Function to check if time sync is needed
# Returns 0 if sync is needed, 1 if not
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

    # Optionally check other files (JS, TS, etc.)
    info_msg "Checking other source files..."
    if ! yarn format:check; then
        echo -e "${RED}❌ Some files are not properly formatted${NC}"
        echo "Run 'yarn format' to fix formatting issues"
        exit 1
    fi
    success_msg "All files are properly formatted"
}

main() {
    info_msg "Starting IC test workflow..."

    # Check formatting first
    check_formatting

    # Stop any running dfx instances
    info_msg "Stopping any existing dfx processes..."
    dfx stop || true
    sleep 2

    # Start dfx with clean state
    info_msg "Starting dfx with clean state..."
    dfx start --clean --background
    check_success "Failed to start dfx"
    sleep 5  # Give dfx time to initialize

    # Try to deploy, sync time only if needed
    info_msg "Attempting deployment..."
    if dfx deploy; then
        success_msg "Deployment successful!"
    else
        if need_time_sync; then
            info_msg "Time sync needed. Synchronizing WSL time..."
            sudo hwclock -s
            check_success "Failed to sync WSL time"
            
            info_msg "Retrying deployment..."
            dfx stop
            dfx start --clean --background
            sleep 5
            dfx deploy
            check_success "Failed to deploy canisters even after time sync"
        else
            handle_error "Failed to deploy canisters for unknown reason"
        fi
    fi

    # Run npm tests in non-watch mode
    info_msg "Running npm tests..."
    npm test -- --run
    check_success "npm tests failed"

    # Run canister tests
    info_msg "Running canister tests..."
    dfx canister call multi_test run
    check_success "Canister tests failed"

    # Stop dfx
    info_msg "Stopping dfx..."
    dfx stop
    check_success "Failed to stop dfx"

    success_msg "Test workflow completed successfully! 🎉"
}

# Trap ctrl-c and call cleanup
trap 'echo -e "\n${RED}Test script interrupted${NC}"; dfx stop; exit 1' INT

# Run main function
main