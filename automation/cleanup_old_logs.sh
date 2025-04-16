#!/bin/bash
#
# cleanup_old_logs.sh - Clean up old log files to conserve disk space
#
# This script finds and removes log files older than a specified age and/or
# larger than a specified size. It can also compress old logs instead of deleting them.
#
# Usage:
#   ./cleanup_old_logs.sh [options] <path>
#
# Options:
#   -a, --age <days>         Remove files older than specified days (default: 30)
#   -s, --size <size>        Remove files larger than specified size (e.g., 10M, 1G)
#   -c, --compress           Compress files instead of deleting
#   -e, --extension <ext>    Only process files with this extension (default: log)
#   -r, --recursive          Process directories recursively
#   -d, --dry-run            Show what would be done without actually doing it
#   -t, --truncate           Truncate files instead of removing them
#   -h, --help               Display this help message
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
MAX_AGE=30
MAX_SIZE=""
COMPRESS=false
FILE_EXT="log"
RECURSIVE=false
DRY_RUN=false
TRUNCATE=false
LOG_PATH=""

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options] <path>"
    echo ""
    echo "Clean up old log files to conserve disk space."
    echo ""
    echo "Options:"
    echo "  -a, --age <days>         Remove files older than specified days (default: $MAX_AGE)"
    echo "  -s, --size <size>        Remove files larger than specified size (e.g., 10M, 1G)"
    echo "  -c, --compress           Compress files instead of deleting"
    echo "  -e, --extension <ext>    Only process files with this extension (default: $FILE_EXT)"
    echo "  -r, --recursive          Process directories recursively"
    echo "  -d, --dry-run            Show what would be done without actually doing it"
    echo "  -t, --truncate           Truncate files instead of removing them"
    echo "  -h, --help               Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") /var/log"
    echo "  $(basename "$0") -a 7 -s 100M -r /var/log"
    echo "  $(basename "$0") -c -e gz -r -d /home/user/logs"
}

# Function to parse command line arguments
parse_arguments() {
    local positional=()
    
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -a|--age)
                MAX_AGE="$2"
                if ! [[ "$MAX_AGE" =~ ^[0-9]+$ ]]; then
                    log_error "Age must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -s|--size)
                MAX_SIZE="$2"
                if ! [[ "$MAX_SIZE" =~ ^[0-9]+[KMG]?$ ]]; then
                    log_error "Size must be in format: <number>[K|M|G]"
                    exit 1
                fi
                shift 2
                ;;
            -c|--compress)
                COMPRESS=true
                shift
                ;;
            -e|--extension)
                FILE_EXT="$2"
                shift 2
                ;;
            -r|--recursive)
                RECURSIVE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -t|--truncate)
                TRUNCATE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done
    
    # Check for required positional arguments
    if [ ${#positional[@]} -lt 1 ]; then
        log_error "Missing path argument"
        show_usage
        exit 1
    fi
    
    LOG_PATH="${positional[0]}"
    
    # Check if path exists
    if [ ! -e "$LOG_PATH" ]; then
        log_error "Path does not exist: $LOG_PATH"
        exit 1
    fi
}

# Function to convert size to find parameter
size_to_find_param() {
    local size="$1"
    
    # Extract number and unit
    if [[ "$size" =~ ^([0-9]+)([KMG])?$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        
        case $unit in
            K)
                echo "${num}k"
                ;;
            M)
                echo "${num}M"
                ;;
            G)
                echo "${num}G"
                ;;
            *)
                echo "${num}c"
                ;;
        esac
    else
        echo "0c"
    fi
}

# Function to build find command
build_find_command() {
    local find_cmd="find \"$LOG_PATH\""
    
    # Add recursion option
    if [ "$RECURSIVE" = false ]; then
        find_cmd+=" -maxdepth 1"
    fi
    
    # Add file type option
    find_cmd+=" -type f"
    
    # Add extension filter
    find_cmd+=" -name \"*.$FILE_EXT\""
    
    # Add age filter
    if [ "$MAX_AGE" -gt 0 ]; then
        find_cmd+=" -mtime +$MAX_AGE"
    fi
    
    # Add size filter
    if [ -n "$MAX_SIZE" ]; then
        local size_param
        size_param=$(size_to_find_param "$MAX_SIZE")
        find_cmd+=" -size +$size_param"
    fi
    
    echo "$find_cmd"
}

# Function to process log files
process_log_files() {
    # Build find command
    local find_cmd
    find_cmd=$(build_find_command)
    
    log_info "Finding log files to process"
    log_debug "Find command: $find_cmd"
    
    # Execute find command and store results
    local files
    files=$(eval "$find_cmd")
    
    # Check if any files were found
    if [ -z "$files" ]; then
        log_info "No matching files found"
        return 0
    fi
    
    # Process each file
    local count=0
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            count=$((count + 1))
            
            if [ "$COMPRESS" = true ]; then
                # Compress file
                if [ "$DRY_RUN" = true ]; then
                    log_info "[DRY RUN] Would compress: $file"
                else
                    log_info "Compressing: $file"
                    gzip -f "$file"
                    if [ $? -eq 0 ]; then
                        log_success "Compressed: $file"
                    else
                        log_error "Failed to compress: $file"
                    fi
                fi
            elif [ "$TRUNCATE" = true ]; then
                # Truncate file
                if [ "$DRY_RUN" = true ]; then
                    log_info "[DRY RUN] Would truncate: $file"
                else
                    log_info "Truncating: $file"
                    truncate -s 0 "$file"
                    if [ $? -eq 0 ]; then
                        log_success "Truncated: $file"
                    else
                        log_error "Failed to truncate: $file"
                    fi
                fi
            else
                # Remove file
                if [ "$DRY_RUN" = true ]; then
                    log_info "[DRY RUN] Would remove: $file"
                else
                    log_info "Removing: $file"
                    rm -f "$file"
                    if [ $? -eq 0 ]; then
                        log_success "Removed: $file"
                    else
                        log_error "Failed to remove: $file"
                    fi
                fi
            fi
        fi
    done <<< "$files"
    
    log_info "Processed $count files"
}

# Function to display summary before cleaning
display_summary() {
    log_info "Log Cleanup Summary:"
    log_info "  Path: $LOG_PATH"
    log_info "  Recursive: $([ "$RECURSIVE" = true ] && echo "Yes" || echo "No")"
    log_info "  File Extension: $FILE_EXT"
    log_info "  Maximum Age: $MAX_AGE days"
    
    if [ -n "$MAX_SIZE" ]; then
        log_info "  Maximum Size: $MAX_SIZE"
    else
        log_info "  Maximum Size: Not specified"
    fi
    
    if [ "$COMPRESS" = true ]; then
        log_info "  Action: Compress files"
    elif [ "$TRUNCATE" = true ]; then
        log_info "  Action: Truncate files"
    else
        log_info "  Action: Remove files"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "  DRY RUN: No actual changes will be made"
    fi
    
    echo ""
}

# Main execution
main() {
    parse_arguments "$@"
    display_summary
    process_log_files
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
