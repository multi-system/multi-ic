#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Helper functions
print_green() { echo -e "${GREEN}$1${NC}"; }
print_error() { echo -e "${RED}$1${NC}"; }
print_info() { echo -e "${YELLOW}$1${NC}"; }
print_blue() { echo -e "${BLUE}$1${NC}"; }
print_magenta() { echo -e "${MAGENTA}$1${NC}"; }

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source the shared cleanup script
source "${SCRIPT_DIR}/cleanup-dfx.sh"

# Function to start dfx
start_dfx() {
    print_info "🚀 Starting dfx..."
    dfx start --clean --background
    
    # Wait for dfx to be ready
    local counter=0
    while ! dfx ping >/dev/null 2>&1; do
        if [ $counter -gt 30 ]; then
            print_error "Timeout waiting for dfx to start"
            exit 1
        fi
        sleep 1
        counter=$((counter + 1))
    done
    
    print_green "✓ DFX started successfully"
}

# Function to deploy Internet Identity
deploy_internet_identity() {
    print_info "🆔 Deploying Internet Identity..."
    
    # Deploy Internet Identity
    dfx deploy internet_identity
    
    # Get the canister ID
    export INTERNET_IDENTITY_ID=$(dfx canister id internet_identity)
    
    print_green "✓ Internet Identity deployed"
    print_info "Internet Identity canister ID: ${INTERNET_IDENTITY_ID}"
}

# Function to deploy backend
deploy_backend() {
    print_info "📦 Deploying backend canisters..."
    
    # Deploy Internet Identity first
    deploy_internet_identity
    
    # Run the deploy script
    "${SCRIPT_DIR}/deploy-backend.sh"
    
    print_green "✓ Backend deployed successfully"
}

# Function to install dependencies
install_dependencies() {
    if [ ! -d "node_modules" ] || [ ! -d ".mops" ]; then
        print_info "📚 Installing dependencies..."
        yarn install
        mops install
        print_green "✓ Dependencies installed"
    else
        print_green "✓ Dependencies already installed"
    fi
}

# Function to start frontend
start_frontend() {
    print_info "🎨 Starting frontend development server..."
    
    # Export environment variables
    export VITE_DFX_NETWORK=${DFX_NETWORK:-local}
    export VITE_CANISTER_ID_MULTI_BACKEND=$(dfx canister id multi_backend)
    export VITE_CANISTER_ID_MULTI_HISTORY=$(dfx canister id multi_history)
    export VITE_CANISTER_ID_MULTI_TOKEN=$(dfx canister id multi_token)
    export VITE_CANISTER_ID_GOVERNANCE_TOKEN=$(dfx canister id governance_token)
    export VITE_CANISTER_ID_TOKEN_A=$(dfx canister id token_a)
    export VITE_CANISTER_ID_TOKEN_B=$(dfx canister id token_b)
    export VITE_CANISTER_ID_TOKEN_C=$(dfx canister id token_c)
    export VITE_CANISTER_ID_INTERNET_IDENTITY=$(dfx canister id internet_identity)
    
    # Generate latest declarations
    print_info "Generating TypeScript declarations..."
    for canister in multi_backend multi_token governance_token token_a token_b token_c; do
        if dfx canister id "$canister" >/dev/null 2>&1; then
            dfx generate "$canister" 2>/dev/null || true
        fi
    done
    
    print_green "✓ Declarations generated"
    
    # Start vite in background
    print_magenta "\n🌐 Frontend starting at http://localhost:5173"
    yarn vite --config vite.frontend.config.ts &
    VITE_PID=$!
    
    # Wait for frontend to be ready
    local counter=0
    while ! curl -s http://localhost:5173 >/dev/null 2>&1; do
        if [ $counter -gt 30 ]; then
            print_error "Timeout waiting for frontend to start"
            exit 1
        fi
        sleep 1
        counter=$((counter + 1))
    done
    
    print_green "✓ Frontend started successfully"
}

# Function to show status
show_status() {
    echo ""
    print_blue "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_green "✨ Multi-IC Development Environment Ready!"
    print_blue "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    print_magenta "🌐 Frontend:          http://localhost:5173"
    print_magenta "🆔 Internet Identity: http://${INTERNET_IDENTITY_ID}.localhost:4943"
    print_magenta "🔧 Backend API:       http://localhost:4943"
    echo ""
    print_info "📦 Canister IDs:"
    echo "   Internet Identity:  ${INTERNET_IDENTITY_ID}"
    echo "   Multi Backend:      $(dfx canister id multi_backend)"
    echo "   Multi History:      $(dfx canister id multi_history)"
    echo "   Multi Token:        $(dfx canister id multi_token)"
    echo "   Governance Token:   $(dfx canister id governance_token)"
    echo "   Token A:            $(dfx canister id token_a)"
    echo "   Token B:            $(dfx canister id token_b)"
    echo "   Token C:            $(dfx canister id token_c)"
    echo ""
    print_blue "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    print_info "📝 The system is deployed but not initialized with data"
    print_info "💡 Run 'yarn demo init' to initialize the system"
    print_info "📊 Run 'yarn history:2years' to populate historical data"
    print_info "🛑 Press Ctrl+C to stop"
    echo ""
}

# Main function
main() {
    print_magenta "\n🚀 Multi-IC Local Development Setup"
    print_info "This will deploy everything fresh and start the frontend\n"
    
    # Change to project root
    cd "${SCRIPT_DIR}/.."
    
    # Clean everything first using shared cleanup
    cleanup_dfx
    
    # Verify cleanup worked
    if ! verify_cleanup; then
        print_error "Cleanup verification failed, but continuing anyway..."
    fi
    
    # Install dependencies
    install_dependencies
    
    # Start dfx
    start_dfx
    
    # Deploy backend
    deploy_backend
    
    # Start frontend
    start_frontend
    
    # Show status
    show_status
    
    # Keep script running and handle Ctrl+C
    trap 'echo -e "\n${YELLOW}Shutting down...${NC}"; kill $VITE_PID 2>/dev/null; dfx stop; exit 0' INT
    
    # Wait forever
    while true; do
        sleep 1
    done
}

# Run main
main