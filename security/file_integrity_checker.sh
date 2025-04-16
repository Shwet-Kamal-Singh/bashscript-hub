#!/bin/bash
#
# Script Name: file_integrity_checker.sh
# Description: Basic file integrity checking using hashes
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./file_integrity_checker.sh [options]
#
# Options:
#   -p, --paths <paths>          Paths to monitor (comma-separated)
#   -d, --database <file>        Hash database file (default: file_hashes.db)
#   -a, --algorithm <algo>       Hash algorithm: md5|sha1|sha256|sha512 (default: sha256)
#   -i, --init                   Initialize or update the hash database
#   -c, --check                  Check for changes against the database
#   -r, --recursive              Process directories recursively
#   -e, --exclude <pattern>      Exclude files matching pattern (comma-separated)
#   -m, --monitor                Monitor files continuously
#   -t, --interval <seconds>     Check interval in seconds for monitoring (default: 300)
#   -n, --notify <command>       Command to run on changes
#   -l, --log <file>             Log file for changes (default: file_changes.log)
#   -s, --summary                Show summary of changes
#   -R, --report <file>          Generate report file
#   -f, --format <format>        Report format: text|csv|json (default: text)
#   -b, --backup                 Backup hash database before updating
#   -v, --verbose                Show detailed output
#   -h, --help                   Display this help message
#
# Examples:
#   ./file_integrity_checker.sh -p /etc/passwd,/etc/shadow -i
#   ./file_integrity_checker.sh -p /etc -r -e "*.bak,*.tmp" -c
#   ./file_integrity_checker.sh -p /var/www -m -t 60 -n "mail -s 'Integrity Alert' admin@example.com"
#
# Requirements:
#   - Root privileges (or sudo) for monitoring system files
#   - md5sum/sha256sum or equivalent tools
#
# License: MIT
# Repository: https://github.com/bashscript-hub

# Source the color_echo utility if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$ROOT_DIR/utils/color_echo.sh" ]; then
    source "$ROOT_DIR/utils/color_echo.sh"
else
    # Define minimal versions if color_echo.sh is not available
    log_info() { echo "INFO: $*"; }
    log_error() { echo "ERROR: $*" >&2; }
    log_success() { echo "SUCCESS: $*"; }
    log_warning() { echo "WARNING: $*"; }
    print_header() { echo -e "\n=== $* ===\n"; }
    print_section() { echo -e "\n--- $* ---\n"; }
fi

# Set default values
PATHS=""
DB_FILE="file_hashes.db"
HASH_ALGORITHM="sha256"
INIT_DB=false
CHECK_FILES=false
RECURSIVE=false
EXCLUDE_PATTERNS=""
MONITOR_FILES=false
CHECK_INTERVAL=300
NOTIFY_COMMAND=""
LOG_FILE="file_changes.log"
SHOW_SUMMARY=false
REPORT_FILE=""
REPORT_FORMAT="text"
BACKUP_DB=false
VERBOSE=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--paths)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            PATHS="$2"
            shift 2
            ;;
        -d|--database)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            DB_FILE="$2"
            shift 2
            ;;
        -a|--algorithm)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "md5" && "$2" != "sha1" && "$2" != "sha256" && "$2" != "sha512" ]]; then
                log_error "Invalid hash algorithm: $2"
                log_error "Valid options: md5, sha1, sha256, sha512"
                exit 1
            fi
            HASH_ALGORITHM="$2"
            shift 2
            ;;
        -i|--init)
            INIT_DB=true
            shift
            ;;
        -c|--check)
            CHECK_FILES=true
            shift
            ;;
        -r|--recursive)
            RECURSIVE=true
            shift
            ;;
        -e|--exclude)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            EXCLUDE_PATTERNS="$2"
            shift 2
            ;;
        -m|--monitor)
            MONITOR_FILES=true
            CHECK_FILES=true
            shift
            ;;
        -t|--interval)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid interval: $2"
                exit 1
            fi
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        -n|--notify)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            NOTIFY_COMMAND="$2"
            shift 2
            ;;
        -l|--log)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            LOG_FILE="$2"
            shift 2
            ;;
        -s|--summary)
            SHOW_SUMMARY=true
            shift
            ;;
        -R|--report)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            REPORT_FILE="$2"
            shift 2
            ;;
        -f|--format)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "text" && "$2" != "csv" && "$2" != "json" ]]; then
                log_error "Invalid report format: $2"
                log_error "Valid options: text, csv, json"
                exit 1
            fi
            REPORT_FORMAT="$2"
            shift 2
            ;;
        -b|--backup)
            BACKUP_DB=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            # Extract and display script header
            grep -E '^# (Script Name:|Description:|Usage:|Options:|Examples:|Requirements:)' "$0" | sed 's/^# //'
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            log_error "Use --help to see available options"
            exit 1
            ;;
    esac
done

# Check for required parameters
if [ -z "$PATHS" ]; then
    log_error "No paths specified for monitoring"
    log_error "Use -p/--paths option to specify paths"
    exit 1
fi

if [ "$INIT_DB" = false ] && [ "$CHECK_FILES" = false ]; then
    log_error "No action specified"
    log_error "Use -i/--init to initialize the database or -c/--check to check for changes"
    exit 1
fi

# Verify the hash command
get_hash_command() {
    case "$HASH_ALGORITHM" in
        md5)
            if command -v md5sum &>/dev/null; then
                echo "md5sum"
            else
                log_error "md5sum command not found"
                exit 1
            fi
            ;;
        sha1)
            if command -v sha1sum &>/dev/null; then
                echo "sha1sum"
            else
                log_error "sha1sum command not found"
                exit 1
            fi
            ;;
        sha256)
            if command -v sha256sum &>/dev/null; then
                echo "sha256sum"
            else
                log_error "sha256sum command not found"
                exit 1
            fi
            ;;
        sha512)
            if command -v sha512sum &>/dev/null; then
                echo "sha512sum"
            else
                log_error "sha512sum command not found"
                exit 1
            fi
            ;;
        *)
            log_error "Invalid hash algorithm: $HASH_ALGORITHM"
            exit 1
            ;;
    esac
}

# Get list of files to monitor
get_file_list() {
    local file_list=()
    
    IFS=',' read -ra PATH_LIST <<< "$PATHS"
    for path in "${PATH_LIST[@]}"; do
        # Skip if path doesn't exist
        if [ ! -e "$path" ]; then
            log_warning "Path does not exist: $path"
            continue
        fi
        
        # Process directories
        if [ -d "$path" ]; then
            if [ "$RECURSIVE" = true ]; then
                # Process recursively
                if [ -n "$EXCLUDE_PATTERNS" ]; then
                    # With exclusions
                    IFS=',' read -ra EXCLUDE_LIST <<< "$EXCLUDE_PATTERNS"
                    local exclude_args=()
                    for pattern in "${EXCLUDE_LIST[@]}"; do
                        exclude_args+=("-not" "-path" "*$pattern*")
                    done
                    
                    # Use find with exclusions
                    while IFS= read -r file; do
                        if [ -f "$file" ]; then
                            file_list+=("$file")
                        fi
                    done < <(find "$path" -type f "${exclude_args[@]}" 2>/dev/null)
                else
                    # No exclusions
                    while IFS= read -r file; do
                        if [ -f "$file" ]; then
                            file_list+=("$file")
                        fi
                    done < <(find "$path" -type f 2>/dev/null)
                fi
            else
                # Process only files in the directory (non-recursive)
                for file in "$path"/*; do
                    if [ -f "$file" ]; then
                        # Check exclusions
                        local exclude=false
                        if [ -n "$EXCLUDE_PATTERNS" ]; then
                            IFS=',' read -ra EXCLUDE_LIST <<< "$EXCLUDE_PATTERNS"
                            for pattern in "${EXCLUDE_LIST[@]}"; do
                                if [[ "$file" == *"$pattern"* ]]; then
                                    exclude=true
                                    break
                                fi
                            done
                        fi
                        
                        if [ "$exclude" = false ]; then
                            file_list+=("$file")
                        fi
                    fi
                done
            fi
        elif [ -f "$path" ]; then
            # Process single file
            file_list+=("$path")
        fi
    done
    
    echo "${file_list[@]}"
}

# Initialize or update the hash database
initialize_database() {
    print_section "Initializing/Updating Hash Database"
    
    # Backup the database if requested
    if [ "$BACKUP_DB" = true ] && [ -f "$DB_FILE" ]; then
        local backup_file="${DB_FILE}.$(date +%Y%m%d%H%M%S).bak"
        log_info "Backing up database to $backup_file"
        cp "$DB_FILE" "$backup_file"
    fi
    
    # Get the hash command
    local hash_cmd
    hash_cmd=$(get_hash_command)
    
    # Get the list of files
    local files
    files=$(get_file_list)
    
    # Create or truncate the database file
    > "$DB_FILE"
    
    # Add metadata to the database
    echo "# File Integrity Database" > "$DB_FILE"
    echo "# Created: $(date)" >> "$DB_FILE"
    echo "# Algorithm: $HASH_ALGORITHM" >> "$DB_FILE"
    echo "# Format: HASH  PATH" >> "$DB_FILE"
    
    # Process each file
    local count=0
    for file in $files; do
        # Calculate hash and add to database
        $hash_cmd "$file" | awk '{print $1"  "$2}' >> "$DB_FILE"
        
        if [ "$VERBOSE" = true ]; then
            log_info "Added hash for file: $file"
        fi
        
        ((count++))
    done
    
    log_success "Database initialized/updated with $count files"
}

# Check files against the hash database
check_files() {
    print_section "Checking Files Against Database"
    
    # Check if database exists
    if [ ! -f "$DB_FILE" ]; then
        log_error "Hash database not found: $DB_FILE"
        log_error "Use -i/--init to initialize the database first"
        exit 1
    fi
    
    # Get the hash command
    local hash_cmd
    hash_cmd=$(get_hash_command)
    
    # Get the list of files
    local files
    files=$(get_file_list)
    
    # Clear the log file if it's going to be used
    if [ "$MONITOR_FILES" = true ] || [ -n "$NOTIFY_COMMAND" ]; then
        > "$LOG_FILE"
    fi
    
    # Variables for tracking changes
    local modified_files=()
    local new_files=()
    local missing_files=()
    
    # Check for modified files
    for file in $files; do
        # Skip if file doesn't exist
        if [ ! -f "$file" ]; then
            continue
        fi
        
        # Calculate the current hash
        local current_hash
        current_hash=$($hash_cmd "$file" | awk '{print $1}')
        
        # Extract the stored hash
        local stored_hash
        stored_hash=$(grep -E "[0-9a-f]+  $file$" "$DB_FILE" 2>/dev/null | awk '{print $1}')
        
        if [ -z "$stored_hash" ]; then
            # File is new (not in database)
            if [ "$VERBOSE" = true ]; then
                log_warning "New file detected: $file"
            fi
            new_files+=("$file")
            
            # Log the change
            echo "$(date '+%Y-%m-%d %H:%M:%S') - NEW: $file" >> "$LOG_FILE"
        elif [ "$current_hash" != "$stored_hash" ]; then
            # File has been modified
            log_warning "Modified file detected: $file"
            modified_files+=("$file")
            
            # Log the change
            echo "$(date '+%Y-%m-%d %H:%M:%S') - MODIFIED: $file (Old: $stored_hash, New: $current_hash)" >> "$LOG_FILE"
        elif [ "$VERBOSE" = true ]; then
            # File is unchanged
            log_info "File integrity verified: $file"
        fi
    done
    
    # Check for missing files
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^#.*$ ]] || [ -z "$line" ]; then
            continue
        fi
        
        # Extract the file path
        local file_path
        file_path=$(echo "$line" | awk '{print $2}')
        
        # Skip if file path is empty
        if [ -z "$file_path" ]; then
            continue
        fi
        
        # Check if file exists
        if [ ! -f "$file_path" ]; then
            log_warning "Missing file detected: $file_path"
            missing_files+=("$file_path")
            
            # Log the change
            echo "$(date '+%Y-%m-%d %H:%M:%S') - MISSING: $file_path" >> "$LOG_FILE"
        fi
    done < "$DB_FILE"
    
    # Execute notification command if changes detected and command specified
    if [ -n "$NOTIFY_COMMAND" ] && [ ${#modified_files[@]} -gt 0 -o ${#new_files[@]} -gt 0 -o ${#missing_files[@]} -gt 0 ]; then
        local notification_message="File integrity changes detected:\n"
        notification_message+="Modified files: ${#modified_files[@]}\n"
        notification_message+="New files: ${#new_files[@]}\n"
        notification_message+="Missing files: ${#missing_files[@]}\n"
        notification_message+="Details in: $LOG_FILE"
        
        log_info "Executing notification command"
        echo -e "$notification_message" | eval "$NOTIFY_COMMAND"
    fi
    
    # Show summary if requested
    if [ "$SHOW_SUMMARY" = true ]; then
        print_section "File Integrity Check Summary"
        echo "Modified files: ${#modified_files[@]}"
        echo "New files: ${#new_files[@]}"
        echo "Missing files: ${#missing_files[@]}"
        echo "Total files checked: $(echo "$files" | wc -w)"
        
        if [ ${#modified_files[@]} -gt 0 ]; then
            echo -e "\nModified files:"
            for file in "${modified_files[@]}"; do
                echo "  $file"
            done
        fi
        
        if [ ${#new_files[@]} -gt 0 ]; then
            echo -e "\nNew files:"
            for file in "${new_files[@]}"; do
                echo "  $file"
            done
        fi
        
        if [ ${#missing_files[@]} -gt 0 ]; then
            echo -e "\nMissing files:"
            for file in "${missing_files[@]}"; do
                echo "  $file"
            done
        fi
    fi
    
    # Generate report if requested
    if [ -n "$REPORT_FILE" ]; then
        generate_report "$REPORT_FILE" "$REPORT_FORMAT" "${modified_files[*]}" "${new_files[*]}" "${missing_files[*]}"
    fi
    
    # Return true if no changes, false otherwise
    if [ ${#modified_files[@]} -eq 0 ] && [ ${#new_files[@]} -eq 0 ] && [ ${#missing_files[@]} -eq 0 ]; then
        log_success "No file integrity changes detected"
        return 0
    else
        log_warning "File integrity changes detected"
        return 1
    fi
}

# Generate a report file
generate_report() {
    local report_file="$1"
    local format="$2"
    local modified_files="$3"
    local new_files="$4"
    local missing_files="$5"
    
    print_section "Generating Report"
    
    log_info "Creating report file: $report_file"
    
    case "$format" in
        text)
            # Generate text report
            {
                echo "File Integrity Check Report"
                echo "Generated: $(date)"
                echo "Paths checked: $PATHS"
                echo "Hash algorithm: $HASH_ALGORITHM"
                echo "Database: $DB_FILE"
                echo ""
                echo "Summary:"
                echo "  Modified files: $(echo "$modified_files" | wc -w)"
                echo "  New files: $(echo "$new_files" | wc -w)"
                echo "  Missing files: $(echo "$missing_files" | wc -w)"
                
                if [ -n "$modified_files" ]; then
                    echo -e "\nModified files:"
                    for file in $modified_files; do
                        echo "  $file"
                    done
                fi
                
                if [ -n "$new_files" ]; then
                    echo -e "\nNew files:"
                    for file in $new_files; do
                        echo "  $file"
                    done
                fi
                
                if [ -n "$missing_files" ]; then
                    echo -e "\nMissing files:"
                    for file in $missing_files; do
                        echo "  $file"
                    done
                fi
            } > "$report_file"
            ;;
        csv)
            # Generate CSV report
            {
                echo "Type,File,Timestamp"
                
                for file in $modified_files; do
                    echo "MODIFIED,$file,$(date '+%Y-%m-%d %H:%M:%S')"
                done
                
                for file in $new_files; do
                    echo "NEW,$file,$(date '+%Y-%m-%d %H:%M:%S')"
                done
                
                for file in $missing_files; do
                    echo "MISSING,$file,$(date '+%Y-%m-%d %H:%M:%S')"
                done
            } > "$report_file"
            ;;
        json)
            # Generate JSON report
            {
                echo "{"
                echo "  \"report\": {"
                echo "    \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\"," 
                echo "    \"paths\": \"$PATHS\","
                echo "    \"algorithm\": \"$HASH_ALGORITHM\","
                echo "    \"database\": \"$DB_FILE\","
                echo "    \"summary\": {"
                echo "      \"modified\": $(echo "$modified_files" | wc -w),"
                echo "      \"new\": $(echo "$new_files" | wc -w),"
                echo "      \"missing\": $(echo "$missing_files" | wc -w)"
                echo "    },"
                
                # Modified files
                echo "    \"modified_files\": ["
                local first=true
                for file in $modified_files; do
                    if [ "$first" = true ]; then
                        first=false
                    else
                        echo ","
                    fi
                    echo -n "      \"$file\""
                done
                echo -e "\n    ],"
                
                # New files
                echo "    \"new_files\": ["
                first=true
                for file in $new_files; do
                    if [ "$first" = true ]; then
                        first=false
                    else
                        echo ","
                    fi
                    echo -n "      \"$file\""
                done
                echo -e "\n    ],"
                
                # Missing files
                echo "    \"missing_files\": ["
                first=true
                for file in $missing_files; do
                    if [ "$first" = true ]; then
                        first=false
                    else
                        echo ","
                    fi
                    echo -n "      \"$file\""
                done
                echo -e "\n    ]"
                
                echo "  }"
                echo "}"
            } > "$report_file"
            ;;
        *)
            log_error "Invalid report format: $format"
            return 1
            ;;
    esac
    
    log_success "Report generated: $report_file"
}

# Monitor files continuously
monitor_files() {
    print_header "Starting Continuous Monitoring"
    
    log_info "Monitoring files every $CHECK_INTERVAL seconds"
    log_info "Press Ctrl+C to stop monitoring"
    
    # Create a trap to catch signals
    trap cleanup SIGINT SIGTERM
    
    # Main monitoring loop
    while true; do
        check_files
        sleep "$CHECK_INTERVAL"
    done
}

# Cleanup function for graceful exit
cleanup() {
    print_header "Stopping Monitoring"
    log_info "Monitoring stopped"
    exit 0
}

# Main function
main() {
    print_header "File Integrity Checker"
    
    # Print configuration summary
    print_section "Configuration"
    log_info "Paths to monitor: $PATHS"
    log_info "Database file: $DB_FILE"
    log_info "Hash algorithm: $HASH_ALGORITHM"
    log_info "Recursive: $([ "$RECURSIVE" = true ] && echo "Yes" || echo "No")"
    
    if [ -n "$EXCLUDE_PATTERNS" ]; then
        log_info "Exclude patterns: $EXCLUDE_PATTERNS"
    fi
    
    if [ "$MONITOR_FILES" = true ]; then
        log_info "Continuous monitoring: Yes (interval: $CHECK_INTERVAL seconds)"
    else
        log_info "Continuous monitoring: No"
    fi
    
    if [ -n "$NOTIFY_COMMAND" ]; then
        log_info "Notification command: $NOTIFY_COMMAND"
    fi
    
    if [ -n "$LOG_FILE" ]; then
        log_info "Log file: $LOG_FILE"
    fi
    
    if [ -n "$REPORT_FILE" ]; then
        log_info "Report file: $REPORT_FILE (format: $REPORT_FORMAT)"
    fi
    
    # Initialize database if requested
    if [ "$INIT_DB" = true ]; then
        initialize_database
    fi
    
    # Check files if requested
    if [ "$CHECK_FILES" = true ]; then
        if [ "$MONITOR_FILES" = true ]; then
            monitor_files
        else
            check_files
        fi
    fi
    
    print_header "File Integrity Check Complete"
}

# Run the main function
main