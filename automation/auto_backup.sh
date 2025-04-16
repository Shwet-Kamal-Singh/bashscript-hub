#!/bin/bash
#
# auto_backup.sh - Automated backup script for files and directories
#
# This script creates backups of specified files or directories, optionally compressing
# them and storing them with timestamps. It can be used as a scheduled task for regular backups.
#
# Usage:
#   ./auto_backup.sh [options] <source> <destination>
#
# Options:
#   -c, --compress           Compress the backup using tar and gzip
#   -t, --timestamp          Add timestamp to backup filename (default: YYYY-MM-DD)
#   -i, --incremental        Perform incremental backup (requires rsync)
#   -r, --retention <days>   Keep backups for specified number of days (default: 30)
#   -e, --exclude <pattern>  Exclude files/dirs matching pattern (can be used multiple times)
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
COMPRESS=false
TIMESTAMP=true
INCREMENTAL=false
RETENTION_DAYS=30
EXCLUDE_PATTERNS=()
SOURCE=""
DESTINATION=""

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options] <source> <destination>"
    echo ""
    echo "Create backups of files or directories."
    echo ""
    echo "Options:"
    echo "  -c, --compress           Compress the backup using tar and gzip"
    echo "  -t, --timestamp          Add timestamp to backup filename (default: YYYY-MM-DD)"
    echo "  -i, --incremental        Perform incremental backup (requires rsync)"
    echo "  -r, --retention <days>   Keep backups for specified number of days (default: 30)"
    echo "  -e, --exclude <pattern>  Exclude files/dirs matching pattern (can be used multiple times)"
    echo "  -h, --help               Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") /home/user/data /backup"
    echo "  $(basename "$0") -c -r 7 /var/www /backup/websites"
    echo "  $(basename "$0") -i -e '*.log' -e '*.tmp' /home/user /backup/home"
}

# Function to parse command line arguments
parse_arguments() {
    local positional=()
    
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -c|--compress)
                COMPRESS=true
                shift
                ;;
            -t|--timestamp)
                TIMESTAMP=true
                shift
                ;;
            -i|--incremental)
                INCREMENTAL=true
                shift
                ;;
            -r|--retention)
                RETENTION_DAYS="$2"
                if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
                    log_error "Retention days must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -e|--exclude)
                EXCLUDE_PATTERNS+=("$2")
                shift 2
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
    if [ ${#positional[@]} -lt 2 ]; then
        log_error "Missing required arguments"
        show_usage
        exit 1
    fi
    
    SOURCE="${positional[0]}"
    DESTINATION="${positional[1]}"
    
    # Check if source exists
    if [ ! -e "$SOURCE" ]; then
        log_error "Source does not exist: $SOURCE"
        exit 1
    fi
    
    # Check if destination directory exists
    if [ ! -d "$DESTINATION" ]; then
        log_info "Destination directory does not exist, creating: $DESTINATION"
        mkdir -p "$DESTINATION"
        if [ $? -ne 0 ]; then
            log_error "Failed to create destination directory: $DESTINATION"
            exit 1
        fi
    fi
}

# Function to check required tools
check_dependencies() {
    # Check for tar if compression is enabled
    if [ "$COMPRESS" = true ] && ! command -v tar &>/dev/null; then
        log_error "tar is required for compression but not found"
        log_error "Install tar using your distribution's package manager:"
        log_error "  - Debian/Ubuntu: sudo apt install tar"
        log_error "  - RHEL/CentOS: sudo yum install tar"
        log_error "  - Fedora: sudo dnf install tar"
        exit 1
    fi
    
    # Check for rsync if incremental backup is enabled
    if [ "$INCREMENTAL" = true ] && ! command -v rsync &>/dev/null; then
        log_error "rsync is required for incremental backups but not found"
        log_error "Install rsync using your distribution's package manager:"
        log_error "  - Debian/Ubuntu: sudo apt install rsync"
        log_error "  - RHEL/CentOS: sudo yum install rsync"
        log_error "  - Fedora: sudo dnf install rsync"
        exit 1
    fi
}

# Function to generate backup filename
generate_backup_filename() {
    local source_basename
    source_basename=$(basename "$SOURCE")
    
    local timestamp=""
    if [ "$TIMESTAMP" = true ]; then
        timestamp="_$(date +%Y-%m-%d_%H-%M-%S)"
    fi
    
    if [ "$COMPRESS" = true ]; then
        echo "${source_basename}${timestamp}.tar.gz"
    else
        echo "${source_basename}${timestamp}"
    fi
}

# Function to create compressed backup
create_compressed_backup() {
    local backup_file="$DESTINATION/$(generate_backup_filename)"
    log_info "Creating compressed backup: $backup_file"
    
    # Build tar command with exclude patterns
    local tar_cmd="tar -czf \"$backup_file\""
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        tar_cmd+=" --exclude=\"$pattern\""
    done
    tar_cmd+=" -C \"$(dirname "$SOURCE")\" \"$(basename "$SOURCE")\""
    
    # Execute tar command
    eval "$tar_cmd"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create compressed backup"
        return 1
    fi
    
    log_success "Compressed backup created successfully: $backup_file"
    return 0
}

# Function to create regular backup
create_regular_backup() {
    local backup_dir="$DESTINATION/$(generate_backup_filename)"
    log_info "Creating backup: $backup_dir"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Build rsync or cp command
    if [ "$INCREMENTAL" = true ]; then
        # Build rsync command with exclude patterns
        local rsync_cmd="rsync -ah --progress"
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            rsync_cmd+=" --exclude=\"$pattern\""
        done
        rsync_cmd+=" \"$SOURCE/\" \"$backup_dir/\""
        
        # Execute rsync command
        eval "$rsync_cmd"
    else
        # Build cp command
        local cp_cmd="cp -a \"$SOURCE\""
        cp_cmd+=" \"$backup_dir\""
        
        # Execute cp command
        eval "$cp_cmd"
    fi
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create backup"
        return 1
    fi
    
    log_success "Backup created successfully: $backup_dir"
    return 0
}

# Function to remove old backups
cleanup_old_backups() {
    log_info "Cleaning up backups older than $RETENTION_DAYS days"
    
    local source_basename
    source_basename=$(basename "$SOURCE")
    
    # Find and remove old backups
    find "$DESTINATION" -maxdepth 1 -type f -name "${source_basename}_*" -mtime +$RETENTION_DAYS -delete 2>/dev/null
    find "$DESTINATION" -maxdepth 1 -type d -name "${source_basename}_*" -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null
    
    log_info "Cleanup completed"
}

# Main execution
main() {
    parse_arguments "$@"
    check_dependencies
    
    # Create backup
    if [ "$COMPRESS" = true ]; then
        create_compressed_backup
    else
        create_regular_backup
    fi
    
    # Clean up old backups if retention is specified
    if [ "$RETENTION_DAYS" -gt 0 ]; then
        cleanup_old_backups
    fi
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
