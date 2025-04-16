#!/bin/bash
#
# log_rotation.sh - Rotate log files with configurable parameters
#
# This script rotates log files by creating date-stamped backups and
# optionally compressing them. It can be used to manage log files for
# applications that don't have built-in log rotation.
#
# Usage:
#   ./log_rotation.sh [options] <log_file>
#
# Options:
#   -n, --num-backups <num>   Number of backups to keep (default: 5)
#   -c, --compress            Compress rotated logs using gzip
#   -s, --size <size>         Rotate if log file is larger than size (e.g., 10M, 1G)
#   -f, --force               Force rotation regardless of size
#   -p, --path <path>         Path to store rotated logs (default: same directory as log file)
#   -h, --help                Display this help message
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
NUM_BACKUPS=5
COMPRESS=false
SIZE=""
FORCE=false
BACKUP_PATH=""
LOG_FILE=""

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options] <log_file>"
    echo ""
    echo "Rotate log files with configurable parameters."
    echo ""
    echo "Options:"
    echo "  -n, --num-backups <num>   Number of backups to keep (default: $NUM_BACKUPS)"
    echo "  -c, --compress            Compress rotated logs using gzip"
    echo "  -s, --size <size>         Rotate if log file is larger than size (e.g., 10M, 1G)"
    echo "  -f, --force               Force rotation regardless of size"
    echo "  -p, --path <path>         Path to store rotated logs (default: same directory as log file)"
    echo "  -h, --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") /var/log/myapp.log"
    echo "  $(basename "$0") -n 10 -c -s 100M /var/log/myapp.log"
    echo "  $(basename "$0") -f -p /backup/logs /var/log/myapp.log"
}

# Function to parse command line arguments
parse_arguments() {
    local positional=()
    
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -n|--num-backups)
                NUM_BACKUPS="$2"
                if ! [[ "$NUM_BACKUPS" =~ ^[0-9]+$ ]]; then
                    log_error "Number of backups must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -c|--compress)
                COMPRESS=true
                shift
                ;;
            -s|--size)
                SIZE="$2"
                if ! [[ "$SIZE" =~ ^[0-9]+[KMG]?$ ]]; then
                    log_error "Size must be in format: <number>[K|M|G]"
                    exit 1
                fi
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -p|--path)
                BACKUP_PATH="$2"
                if [ ! -d "$BACKUP_PATH" ]; then
                    log_error "Backup path does not exist: $BACKUP_PATH"
                    exit 1
                fi
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
    if [ ${#positional[@]} -lt 1 ]; then
        log_error "Missing log file argument"
        show_usage
        exit 1
    fi
    
    LOG_FILE="${positional[0]}"
    
    # Check if log file exists
    if [ ! -f "$LOG_FILE" ]; then
        log_error "Log file does not exist: $LOG_FILE"
        exit 1
    fi
    
    # If backup path not specified, use same directory as log file
    if [ -z "$BACKUP_PATH" ]; then
        BACKUP_PATH="$(dirname "$LOG_FILE")"
    fi
}

# Function to convert size to bytes
size_to_bytes() {
    local size="$1"
    
    # Extract number and unit
    if [[ "$size" =~ ^([0-9]+)([KMG])?$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        
        case $unit in
            K)
                echo "$((num * 1024))"
                ;;
            M)
                echo "$((num * 1024 * 1024))"
                ;;
            G)
                echo "$((num * 1024 * 1024 * 1024))"
                ;;
            *)
                echo "$num"
                ;;
        esac
    else
        echo "0"
    fi
}

# Function to check if log file needs rotation
needs_rotation() {
    # Always rotate if FORCE is true
    if [ "$FORCE" = true ]; then
        return 0 # true
    fi
    
    # If SIZE is specified, check file size
    if [ -n "$SIZE" ]; then
        local size_bytes
        size_bytes=$(size_to_bytes "$SIZE")
        
        local file_size
        file_size=$(stat -c%s "$LOG_FILE")
        
        if [ "$file_size" -ge "$size_bytes" ]; then
            return 0 # true
        fi
    fi
    
    return 1 # false
}

# Function to rotate log file
rotate_log() {
    log_info "Rotating log file: $LOG_FILE"
    
    # Get base filename without path
    local base_name
    base_name=$(basename "$LOG_FILE")
    
    # Create timestamp
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    
    # Create new backup filename
    local backup_file
    backup_file="$BACKUP_PATH/${base_name}.${timestamp}"
    
    # Copy log file to backup
    cp "$LOG_FILE" "$backup_file"
    
    # Check if copy was successful
    if [ $? -ne 0 ]; then
        log_error "Failed to create backup: $backup_file"
        return 1
    fi
    
    # Compress backup if requested
    if [ "$COMPRESS" = true ]; then
        log_info "Compressing backup: $backup_file"
        gzip "$backup_file"
        
        # Check if compression was successful
        if [ $? -ne 0 ]; then
            log_error "Failed to compress backup: $backup_file"
            return 1
        fi
        
        backup_file="${backup_file}.gz"
    fi
    
    # Truncate original log file
    truncate -s 0 "$LOG_FILE"
    
    # Check if truncate was successful
    if [ $? -ne 0 ]; then
        log_error "Failed to truncate log file: $LOG_FILE"
        return 1
    fi
    
    log_success "Log rotated successfully: $backup_file"
    
    return 0
}

# Function to remove old backups
remove_old_backups() {
    local base_name
    base_name=$(basename "$LOG_FILE")
    
    # Find all backups
    local backups
    if [ "$COMPRESS" = true ]; then
        backups=$(find "$BACKUP_PATH" -name "${base_name}.*" -o -name "${base_name}.*.gz" | sort)
    else
        backups=$(find "$BACKUP_PATH" -name "${base_name}.*" | grep -v "\.gz$" | sort)
    fi
    
    # Count backups
    local count
    count=$(echo "$backups" | wc -l)
    
    # Remove oldest backups if count exceeds NUM_BACKUPS
    if [ "$count" -gt "$NUM_BACKUPS" ]; then
        local to_remove=$((count - NUM_BACKUPS))
        log_info "Removing $to_remove old backup(s)"
        
        echo "$backups" | head -n "$to_remove" | while read -r old_backup; do
            log_info "Removing old backup: $old_backup"
            rm -f "$old_backup"
        done
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    
    # Check if log file needs rotation
    if needs_rotation; then
        # Rotate log file
        rotate_log
        
        # Remove old backups
        remove_old_backups
    else
        log_info "No rotation needed for log file: $LOG_FILE"
    fi
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
