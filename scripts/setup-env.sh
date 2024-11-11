#!/usr/bin/env bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${YELLOW}➜ $1${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; exit 1; }

# Check required tools
check_dependencies() {
    print_info "Checking dependencies..."
    
    local REQUIRED_TOOLS=("dfx" "mops" "node" "yarn")
    
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_error "$tool is required but not installed"
        fi
    done
    
    print_success "All dependencies found"
}

# Setup environment variables
setup_env_vars() {
    print_info "Setting up environment variables..."
    
    # Export network settings
    export DFX_NETWORK=${DFX_NETWORK:-"local"}
    export TEST_MODE="true"
    
    # Set test environment configuration
    export NODE_ENV="test"
    
    print_success "Environment variables set"
}

main() {
    print_info "Starting environment setup..."
    
    check_dependencies
    setup_env_vars
    
    print_success "Environment setup complete!"
    
    # Print useful information
    echo -e "\nDFX Network: ${YELLOW}$DFX_NETWORK${NC}"
    echo -e "Test Mode: ${YELLOW}$TEST_MODE${NC}"
}

main