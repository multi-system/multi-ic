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

# Generate a new test identity
generate_test_identity() {
    print_info "Setting up test identity..."
    
    if dfx identity list | grep -q "multi-test-identity"; then
        print_info "Test identity already exists"
        return
    fi
    
    # Generate a new key using OpenSSL
    local KEY_FILE="test_identity_$(date +%Y%m%d_%H%M%S).pem"
    openssl ecparam -name secp256k1 -genkey -noout -out "$KEY_FILE"
    
    # Import the identity
    dfx identity import multi-test-identity "$KEY_FILE" --storage-mode plaintext
    
    # Clean up the key file
    rm "$KEY_FILE"
    
    print_success "Test identity created"
}

# Setup environment variables
setup_env_vars() {
    print_info "Setting up environment variables..."
    
    # Export the test identity principal
    export MULTI_TEST_PRINCIPAL=$(dfx identity get-principal --identity multi-test-identity)
    
    # Add other environment variables as needed
    export DFX_NETWORK=${DFX_NETWORK:-"local"}
    export TEST_MODE="true"
    
    print_success "Environment variables set"
}

main() {
    print_info "Starting environment setup..."
    
    check_dependencies
    generate_test_identity
    setup_env_vars
    
    print_success "Environment setup complete!"
    
    # Print useful information
    echo -e "\nTest Identity Principal: ${YELLOW}$MULTI_TEST_PRINCIPAL${NC}"
    echo -e "DFX Network: ${YELLOW}$DFX_NETWORK${NC}"
}

main