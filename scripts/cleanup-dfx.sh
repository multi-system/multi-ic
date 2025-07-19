#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper functions
print_info() { echo -e "${YELLOW}$1${NC}"; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_error() { echo -e "${RED}$1${NC}"; }

# Main cleanup function
cleanup_dfx() {
    print_info "🧹 Cleaning up DFX environment..."
    
    # Stop dfx gracefully first
    if dfx ping >/dev/null 2>&1; then
        print_info "Stopping dfx..."
        dfx stop >/dev/null 2>&1 || true
    fi
    
    # Kill any dfx-related processes
    print_info "Killing any remaining processes..."
    for process in "dfx" "replica" "ic-starter" "icx-proxy"; do
        pkill -f "$process" 2>/dev/null || true
    done
    
    # Wait a moment for processes to die
    sleep 2
    
    # Free up commonly used ports
    for port in 4943 8000 8080; do
        if lsof -i :$port >/dev/null 2>&1; then
            print_info "Freeing port $port..."
            lsof -ti :$port | xargs -r kill -9 2>/dev/null || true
            sudo lsof -ti :$port | xargs -r sudo kill -9 2>/dev/null || true
        fi
    done
    
    # Remove .dfx directory if it exists
    if [ -d ".dfx" ]; then
        print_info "Removing .dfx directory..."
        # Try normal removal first
        if rm -rf .dfx 2>/dev/null; then
            print_success "✓ .dfx directory removed"
        else
            # If that fails, try with sudo
            print_info "Normal removal failed, trying with sudo..."
            if sudo rm -rf .dfx 2>/dev/null; then
                print_success "✓ .dfx directory removed with sudo"
            else
                # If that still fails, check for stuck mounts
                print_info "Checking for stuck mounts..."
                mount | grep ".dfx" | awk '{print $3}' | xargs -r sudo umount -f 2>/dev/null || true
                # Final attempt
                if sudo rm -rf .dfx 2>/dev/null; then
                    print_success "✓ .dfx directory removed after unmount"
                else
                    print_error "⚠️  Warning: Could not remove .dfx directory"
                fi
            fi
        fi
    fi
    
    # Clean up any dfx temp files
    print_info "Cleaning temporary files..."
    rm -rf /tmp/dfx* 2>/dev/null || true
    rm -rf /tmp/.dfx* 2>/dev/null || true
    
    # Clean up any log files in current directory
    rm -f dfx.log 2>/dev/null || true
    
    # Final wait to ensure everything is cleaned up
    sleep 1
    
    print_success "✓ DFX cleanup complete"
}

# Function to verify cleanup
verify_cleanup() {
    local issues=0
    
    # Check if .dfx directory exists
    if [ -d ".dfx" ]; then
        print_error "⚠️  .dfx directory still exists"
        issues=$((issues + 1))
    fi
    
    # Check if any dfx processes are running
    if pgrep -f "dfx|replica|ic-starter" >/dev/null 2>&1; then
        print_error "⚠️  DFX processes still running"
        issues=$((issues + 1))
    fi
    
    # Check if ports are free
    for port in 4943 8000; do
        if lsof -i :$port >/dev/null 2>&1; then
            print_error "⚠️  Port $port is still in use"
            issues=$((issues + 1))
        fi
    done
    
    if [ $issues -eq 0 ]; then
        print_success "✓ Environment is clean"
        return 0
    else
        print_error "⚠️  Found $issues cleanup issues"
        return 1
    fi
}

# If script is run directly, execute cleanup
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    cleanup_dfx
    verify_cleanup
fi