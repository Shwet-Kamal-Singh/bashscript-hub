#!/bin/bash
#
# auto_update_packages.sh - Automated package updates for multiple Linux distributions
#
# This script automatically updates system packages on various Linux distributions.
# It supports Debian/Ubuntu (apt), RHEL/CentOS (yum), and Fedora/Rocky/Alma Linux (dnf).
#
# Usage:
#   ./auto_update_packages.sh [options]
#
# Options:
#   -d, --dry-run           Show what would be updated without making changes
#   -s, --security-only     Only install security updates
#   -y, --yes               Answer yes to all prompts (non-interactive)
#   -r, --reboot            Reboot after updates if needed
#   -l, --log <file>        Log output to specified file
#   -e, --exclude <pkg>     Exclude specified package (can be used multiple times)
#   -h, --help              Display this help message
#
# Author: BashScriptHub
# Date: 2023
# License: MIT

# Detect script directory for sourcing utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Source the color_echo utility if available
if [ -f "$ROOT_DIR/utils/color_echo.sh" ]; then
    source "$ROOT_DIR/utils/color_echo.sh"
else
    # Define minimal versions if color_echo.sh is not available
    log_info() { echo "INFO: $*"; }
    log_error() { echo "ERROR: $*" >&2; }
    log_success() { echo "SUCCESS: $*"; }
    log_warning() { echo "WARNING: $*"; }
    log_debug() { echo "DEBUG: $*"; }
fi

# Default values
DRY_RUN=false
SECURITY_ONLY=false
NON_INTERACTIVE=false
REBOOT_AFTER=false
LOG_FILE=""
EXCLUDE_PKGS=()

# Function to detect package manager
detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
        log_info "Detected Debian/Ubuntu (apt)"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        log_info "Detected Fedora/Rocky/Alma Linux (dnf)"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        log_info "Detected RHEL/CentOS (yum)"
    else
        log_error "Unsupported package manager. This script supports apt, dnf, and yum."
        exit 1
    fi
}

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Automatically update system packages on various Linux distributions."
    echo "Supports Debian/Ubuntu (apt), RHEL/CentOS (yum), and Fedora/Rocky/Alma Linux (dnf)."
    echo ""
    echo "Options:"
    echo "  -d, --dry-run           Show what would be updated without making changes"
    echo "  -s, --security-only     Only install security updates"
    echo "  -y, --yes               Answer yes to all prompts (non-interactive)"
    echo "  -r, --reboot            Reboot after updates if needed"
    echo "  -l, --log <file>        Log output to specified file"
    echo "  -e, --exclude <pkg>     Exclude specified package (can be used multiple times)"
    echo "  -h, --help              Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")"
    echo "  $(basename "$0") --security-only --yes"
    echo "  $(basename "$0") --dry-run --exclude firefox --exclude chromium"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--security-only)
                SECURITY_ONLY=true
                shift
                ;;
            -y|--yes)
                NON_INTERACTIVE=true
                shift
                ;;
            -r|--reboot)
                REBOOT_AFTER=true
                shift
                ;;
            -l|--log)
                LOG_FILE="$2"
                shift 2
                ;;
            -e|--exclude)
                EXCLUDE_PKGS+=("$2")
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set up logging if specified
    if [ -n "$LOG_FILE" ]; then
        # Create log directory if it doesn't exist
        log_dir=$(dirname "$LOG_FILE")
        mkdir -p "$log_dir" 2>/dev/null
        
        # Check if log file can be written to
        touch "$LOG_FILE" 2>/dev/null
        if [ $? -ne 0 ]; then
            log_error "Cannot write to log file: $LOG_FILE"
            exit 1
        fi
        
        # Log to both stdout and file
        exec &> >(tee -a "$LOG_FILE")
        
        log_info "Logging to: $LOG_FILE"
    fi
}

# Function to check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        log_error "Try: sudo $(basename "$0") $*"
        exit 1
    fi
}

# Function to update package lists
update_package_lists() {
    log_info "Updating package lists"
    
    case $PKG_MANAGER in
        apt)
            apt-get update
            ;;
        dnf)
            dnf check-update || true  # dnf returns 100 if updates are available
            ;;
        yum)
            yum check-update || true  # yum returns 100 if updates are available
            ;;
    esac
    
    if [ $? -gt 1 ]; then
        log_error "Failed to update package lists"
        exit 1
    fi
    
    log_success "Package lists updated"
}

# Function to build update command
build_update_command() {
    local cmd=""
    
    case $PKG_MANAGER in
        apt)
            cmd="apt-get"
            
            # Non-interactive
            if [ "$NON_INTERACTIVE" = true ]; then
                cmd+=" -y"
            fi
            
            # Exclude packages
            for pkg in "${EXCLUDE_PKGS[@]}"; do
                cmd+=" --exclude=$pkg"
            done
            
            # Security only
            if [ "$SECURITY_ONLY" = true ]; then
                cmd+=" upgrade -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'"
            else
                cmd+=" dist-upgrade -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'"
            fi
            
            # Dry run
            if [ "$DRY_RUN" = true ]; then
                cmd+=" --dry-run"
            fi
            ;;
            
        dnf)
            cmd="dnf"
            
            # Non-interactive
            if [ "$NON_INTERACTIVE" = true ]; then
                cmd+=" -y"
            fi
            
            # Exclude packages
            for pkg in "${EXCLUDE_PKGS[@]}"; do
                cmd+=" --exclude=$pkg"
            done
            
            # Security only
            if [ "$SECURITY_ONLY" = true ]; then
                cmd+=" upgrade --security"
            else
                cmd+=" upgrade"
            fi
            
            # Dry run
            if [ "$DRY_RUN" = true ]; then
                cmd+=" --downloadonly"
            fi
            ;;
            
        yum)
            cmd="yum"
            
            # Non-interactive
            if [ "$NON_INTERACTIVE" = true ]; then
                cmd+=" -y"
            fi
            
            # Exclude packages
            for pkg in "${EXCLUDE_PKGS[@]}"; do
                cmd+=" --exclude=$pkg"
            done
            
            # Security only
            if [ "$SECURITY_ONLY" = true ]; then
                cmd+=" update --security"
            else
                cmd+=" update"
            fi
            
            # Dry run
            if [ "$DRY_RUN" = true ]; then
                cmd+=" --downloadonly"
            fi
            ;;
    esac
    
    echo "$cmd"
}

# Function to apply updates
apply_updates() {
    log_info "Applying updates"
    
    local update_cmd
    update_cmd=$(build_update_command)
    
    log_debug "Update command: $update_cmd"
    
    # Execute update command
    eval "$update_cmd"
    
    local result=$?
    if [ $result -ne 0 ]; then
        log_error "Failed to apply updates"
        return 1
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_success "Dry run completed successfully"
    else
        log_success "Updates applied successfully"
    fi
    
    return 0
}

# Function to clean up package cache
clean_package_cache() {
    # Skip cleanup in dry run mode
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    log_info "Cleaning package cache"
    
    case $PKG_MANAGER in
        apt)
            apt-get clean
            apt-get autoremove -y
            ;;
        dnf)
            dnf clean packages
            dnf autoremove -y
            ;;
        yum)
            yum clean packages
            yum autoremove -y
            ;;
    esac
    
    log_success "Package cache cleaned"
}

# Function to check if reboot is needed
check_reboot_needed() {
    local reboot_needed=false
    
    log_info "Checking if reboot is needed"
    
    case $PKG_MANAGER in
        apt)
            if [ -f /var/run/reboot-required ]; then
                reboot_needed=true
            fi
            ;;
        dnf|yum)
            # Check if kernel was updated
            if rpm -q --last kernel | head -1 | grep -q "$(uname -r)"; then
                reboot_needed=true
            fi
            ;;
    esac
    
    if [ "$reboot_needed" = true ]; then
        log_warning "System reboot is recommended"
        
        if [ "$REBOOT_AFTER" = true ]; then
            log_warning "Automatic reboot in 1 minute. Press Ctrl+C to cancel."
            sleep 60
            reboot
        fi
    else
        log_info "No reboot required"
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    check_root "$@"
    detect_package_manager
    
    log_info "Starting package update process"
    log_info "Date: $(date)"
    log_info "System: $(hostname) ($(uname -s) $(uname -r))"
    
    # Update package lists
    update_package_lists
    
    # Apply updates
    apply_updates
    
    # Clean package cache
    clean_package_cache
    
    # Check if reboot is needed
    check_reboot_needed
    
    log_info "Package update process completed"
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
