#!/bin/bash
#
# file_watcher.sh - Watch files or directories for changes
#
# This script monitors files or directories for changes and executes
# a specified command when changes are detected.
#
# Usage:
#   ./file_watcher.sh [options] <path> <command>
#
# Options:
#   -i, --interval <seconds>   Set polling interval (default: 2)
#   -r, --recursive            Watch directory recursively
#   -e, --extension <ext>      Only watch files with this extension
#   -h, --help                 Display this help message
#
# Author: BashScriptHub
# Date: 2023
# License: MIT

# Source the color_echo utility if it exists in the same directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/color_echo.sh" ]; then
    source "$SCRIPT_DIR/color_echo.sh"
else
    # Define minimal versions if color_echo.sh is not available
    log_info() { echo "INFO: $*"; }
    log_error() { echo "ERROR: $*" >&2; }
    log_success() { echo "SUCCESS: $*"; }
    log_warning() { echo "WARNING: $*"; }
    log_debug() { echo "DEBUG: $*"; }
fi

# Default values
INTERVAL=2
RECURSIVE=false
EXTENSION=""

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options] <path> <command>"
    echo ""
    echo "Watch files or directories for changes and execute a command when changes are detected."
    echo ""
    echo "Options:"
    echo "  -i, --interval <seconds>   Set polling interval (default: $INTERVAL)"
    echo "  -r, --recursive            Watch directory recursively"
    echo "  -e, --extension <ext>      Only watch files with this extension"
    echo "  -h, --help                 Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") /var/log/syslog 'echo \"Log changed!\"'"
    echo "  $(basename "$0") -r -e js -i 5 ./src 'npm run build'"
}

# Parse command line arguments
parse_arguments() {
    local positional=()
    
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -i|--interval)
                INTERVAL="$2"
                if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]]; then
                    log_error "Interval must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -r|--recursive)
                RECURSIVE=true
                shift
                ;;
            -e|--extension)
                EXTENSION="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*) # Unknown option
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *) # Anything else is positional
                positional+=("$1")
                shift
                ;;
        esac
    done
    
    # Check for required positional arguments
    if [ ${#positional[@]} -lt 2 ]; then
        log_error "Missing required arguments"
        show_usage
        exit 1
    fi
    
    WATCH_PATH="${positional[0]}"
    # Combine remaining arguments as the command
    COMMAND="${positional[@]:1}"
}

# Function to check if a file exists
check_watch_path() {
    if [ ! -e "$WATCH_PATH" ]; then
        log_error "Path does not exist: $WATCH_PATH"
        exit 1
    fi
}

# Function to get file/directory checksum
get_checksum() {
    local path="$1"
    
    if [ -d "$path" ]; then
        if [ "$RECURSIVE" = true ]; then
            if [ -n "$EXTENSION" ]; then
                find "$path" -type f -name "*.$EXTENSION" -print0 | sort -z | xargs -0 sha1sum 2>/dev/null | sha1sum | cut -d' ' -f1
            else
                find "$path" -type f -print0 | sort -z | xargs -0 sha1sum 2>/dev/null | sha1sum | cut -d' ' -f1
            fi
        else
            if [ -n "$EXTENSION" ]; then
                find "$path" -maxdepth 1 -type f -name "*.$EXTENSION" -print0 | sort -z | xargs -0 sha1sum 2>/dev/null | sha1sum | cut -d' ' -f1
            else
                find "$path" -maxdepth 1 -type f -print0 | sort -z | xargs -0 sha1sum 2>/dev/null | sha1sum | cut -d' ' -f1
            fi
        fi
    else
        sha1sum "$path" 2>/dev/null | cut -d' ' -f1
    fi
}

# Function to watch files/directories for changes
watch_for_changes() {
    log_info "Starting file watcher on: $WATCH_PATH"
    if [ "$RECURSIVE" = true ]; then
        log_info "Watching recursively"
    fi
    if [ -n "$EXTENSION" ]; then
        log_info "Watching files with extension: .$EXTENSION"
    fi
    log_info "Polling interval: $INTERVAL seconds"
    log_info "Press Ctrl+C to stop watching"
    
    # Get initial checksum
    local last_checksum
    last_checksum=$(get_checksum "$WATCH_PATH")
    
    # Continue watching until interrupted
    while true; do
        sleep "$INTERVAL"
        
        # Get new checksum
        local current_checksum
        current_checksum=$(get_checksum "$WATCH_PATH")
        
        # If checksum changed, execute command
        if [ "$current_checksum" != "$last_checksum" ]; then
            log_info "Changes detected in $WATCH_PATH"
            log_info "Executing: $COMMAND"
            
            # Execute command in a subshell
            ( eval "$COMMAND" )
            
            # Update last checksum
            last_checksum="$current_checksum"
        fi
    done
}

# Main execution
main() {
    parse_arguments "$@"
    check_watch_path
    watch_for_changes
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'echo -e "\nFile watcher stopped."; exit 0' INT
    main "$@"
fi
