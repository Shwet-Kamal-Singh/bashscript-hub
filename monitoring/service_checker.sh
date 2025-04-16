#!/bin/bash
#
# service_checker.sh - Check service status and perform actions
#
# This script checks the status of system services across different init systems
# (systemd, sysvinit, upstart) and can perform actions such as starting, stopping
# or restarting services based on their status.
#
# Usage:
#   ./service_checker.sh [options] <service>...
#
# Options:
#   -a, --action <action>      Action to perform if service is not running:
#                               start, restart, none (default: none)
#   -r, --restart-action <action> Action to perform if service needs restart:
#                               restart, reload, none (default: none)
#                               (based on timestamps of service config files)
#   -c, --check-config-dir <dir>  Check timestamp of config files in directory
#   -t, --check-time <seconds> How far back to check config changes (default: 86400 - 1 day)
#   -w, --wait <seconds>       Wait time after action (default: 5)
#   -m, --max-attempts <num>   Maximum number of restart attempts (default: 3)
#   -o, --output <file>        Write results to file
#   -f, --format <format>      Output format (text, csv, json; default: text)
#   -e, --email <address>      Send email notification for failures
#   -q, --quiet                Only output failures
#   -v, --verbose              Display detailed output
#   -h, --help                 Display this help message
#
# Requirements:
#   - System utilities: systemctl (systemd), service (sysvinit), or initctl (upstart)
#   - Basic system utilities: grep, awk
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
ACTION="none"
RESTART_ACTION="none"
CONFIG_DIR=""
CHECK_TIME=86400
WAIT_TIME=5
MAX_ATTEMPTS=3
OUTPUT_FILE=""
FORMAT="text"
EMAIL=""
QUIET=false
VERBOSE=false
SERVICES=()

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options] <service>..."
    echo ""
    echo "Check service status and perform actions."
    echo ""
    echo "Options:"
    echo "  -a, --action <action>      Action to perform if service is not running:"
    echo "                               start, restart, none (default: none)"
    echo "  -r, --restart-action <action> Action to perform if service needs restart:"
    echo "                               restart, reload, none (default: none)"
    echo "                               (based on timestamps of service config files)"
    echo "  -c, --check-config-dir <dir>  Check timestamp of config files in directory"
    echo "  -t, --check-time <seconds> How far back to check config changes (default: 86400 - 1 day)"
    echo "  -w, --wait <seconds>       Wait time after action (default: 5)"
    echo "  -m, --max-attempts <num>   Maximum number of restart attempts (default: 3)"
    echo "  -o, --output <file>        Write results to file"
    echo "  -f, --format <format>      Output format (text, csv, json; default: text)"
    echo "  -e, --email <address>      Send email notification for failures"
    echo "  -q, --quiet                Only output failures"
    echo "  -v, --verbose              Display detailed output"
    echo "  -h, --help                 Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") nginx mysql"
    echo "  $(basename "$0") -a restart -w 10 apache2"
    echo "  $(basename "$0") -r restart -c /etc/nginx -t 3600 nginx"
    echo "  $(basename "$0") -f json -o service_status.json -e admin@example.com ssh mysql"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -a|--action)
                ACTION="$2"
                # Validate action
                case "${ACTION,,}" in
                    start|restart|none)
                        ACTION="${ACTION,,}"
                        ;;
                    *)
                        log_error "Invalid action: $ACTION"
                        log_error "Valid actions: start, restart, none"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -r|--restart-action)
                RESTART_ACTION="$2"
                # Validate restart action
                case "${RESTART_ACTION,,}" in
                    restart|reload|none)
                        RESTART_ACTION="${RESTART_ACTION,,}"
                        ;;
                    *)
                        log_error "Invalid restart action: $RESTART_ACTION"
                        log_error "Valid restart actions: restart, reload, none"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -c|--check-config-dir)
                CONFIG_DIR="$2"
                if [ ! -d "$CONFIG_DIR" ]; then
                    log_error "Config directory does not exist: $CONFIG_DIR"
                    exit 1
                fi
                shift 2
                ;;
            -t|--check-time)
                CHECK_TIME="$2"
                if ! [[ "$CHECK_TIME" =~ ^[0-9]+$ ]] || [ "$CHECK_TIME" -lt 1 ]; then
                    log_error "Check time must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -w|--wait)
                WAIT_TIME="$2"
                if ! [[ "$WAIT_TIME" =~ ^[0-9]+$ ]] || [ "$WAIT_TIME" -lt 0 ]; then
                    log_error "Wait time must be a non-negative integer"
                    exit 1
                fi
                shift 2
                ;;
            -m|--max-attempts)
                MAX_ATTEMPTS="$2"
                if ! [[ "$MAX_ATTEMPTS" =~ ^[0-9]+$ ]] || [ "$MAX_ATTEMPTS" -lt 1 ]; then
                    log_error "Maximum attempts must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -f|--format)
                FORMAT="$2"
                # Validate format
                case "${FORMAT,,}" in
                    text|csv|json)
                        FORMAT="${FORMAT,,}"
                        ;;
                    *)
                        log_error "Invalid format: $FORMAT"
                        log_error "Valid formats: text, csv, json"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
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
                # Assume argument is a service name
                SERVICES+=("$1")
                shift
                ;;
        esac
    done
    
    # Validate required arguments
    if [ ${#SERVICES[@]} -eq 0 ]; then
        log_error "At least one service must be specified"
        show_usage
        exit 1
    fi
    
    # Check for email dependencies if email is specified
    if [ -n "$EMAIL" ]; then
        if ! command -v mail &>/dev/null; then
            log_error "Email notification requested but 'mail' command is not available"
            log_error "Please install a mail client for your distribution:"
            log_error "  - Debian/Ubuntu: sudo apt-get install mailutils"
            log_error "  - RHEL/CentOS: sudo yum install mailx"
            log_error "  - Fedora: sudo dnf install mailx"
            exit 1
        fi
    fi
}

# Function to detect init system
detect_init_system() {
    if command -v systemctl &>/dev/null; then
        echo "systemd"
    elif [ -f /etc/init.d/cron ] && [ ! -h /etc/init.d/cron ]; then
        echo "sysvinit"
    elif command -v initctl &>/dev/null; then
        echo "upstart"
    else
        echo "unknown"
    fi
}

# Function to check service status
check_service_status() {
    local service="$1"
    local init_system="$2"
    
    case "$init_system" in
        systemd)
            if systemctl is-active --quiet "$service"; then
                echo "running"
            else
                echo "stopped"
            fi
            ;;
        sysvinit)
            if service "$service" status &>/dev/null || /etc/init.d/"$service" status &>/dev/null; then
                echo "running"
            else
                echo "stopped"
            fi
            ;;
        upstart)
            if initctl status "$service" 2>/dev/null | grep -q "running"; then
                echo "running"
            else
                echo "stopped"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Function to check if service needs restart based on config file timestamps
needs_restart() {
    local service="$1"
    local config_dir="$2"
    local check_time="$3"
    
    if [ -z "$config_dir" ]; then
        return 1
    fi
    
    # Get current time
    local current_time=$(date +%s)
    local check_since=$((current_time - check_time))
    
    # Check for recently modified files
    if find "$config_dir" -type f -mtime -$((check_time / 86400)) | grep -q .; then
        return 0
    fi
    
    return 1
}

# Function to perform action on service
perform_service_action() {
    local service="$1"
    local action="$2"
    local init_system="$3"
    
    log_info "Performing '$action' on service: $service"
    
    case "$init_system" in
        systemd)
            systemctl "$action" "$service"
            return $?
            ;;
        sysvinit)
            if [ -x "/etc/init.d/$service" ]; then
                /etc/init.d/"$service" "$action"
            else
                service "$service" "$action"
            fi
            return $?
            ;;
        upstart)
            case "$action" in
                start|stop)
                    initctl "$action" "$service"
                    ;;
                restart)
                    initctl restart "$service"
                    ;;
                reload)
                    # Try reload if supported, otherwise restart
                    initctl reload "$service" 2>/dev/null || initctl restart "$service"
                    ;;
                *)
                    return 1
                    ;;
            esac
            return $?
            ;;
        *)
            log_error "Unknown init system, cannot perform action"
            return 1
            ;;
    esac
}

# Function to format output
format_output() {
    local timestamp="$1"
    local service="$2"
    local status="$3"
    local action_performed="$4"
    local action_result="$5"
    local restart_needed="$6"
    
    case "$FORMAT" in
        text)
            printf "%-20s %-20s %-10s %-20s %-10s %-15s\n" \
                "$timestamp" "$service" "$status" "$action_performed" "$action_result" "$restart_needed"
            ;;
        csv)
            printf "%s,%s,%s,%s,%s,%s\n" \
                "$timestamp" "$service" "$status" "$action_performed" "$action_result" "$restart_needed"
            ;;
        json)
            printf '{"timestamp":"%s","service":"%s","status":"%s","action_performed":"%s","action_result":"%s","restart_needed":"%s"}\n' \
                "$timestamp" "$service" "$status" "$action_performed" "$action_result" "$restart_needed"
            ;;
    esac
}

# Function to print header
print_header() {
    case "$FORMAT" in
        text)
            printf "%-20s %-20s %-10s %-20s %-10s %-15s\n" \
                "TIMESTAMP" "SERVICE" "STATUS" "ACTION" "RESULT" "RESTART NEEDED"
            printf "%-20s %-20s %-10s %-20s %-10s %-15s\n" \
                "--------------------" "--------------------" "----------" "--------------------" "----------" "---------------"
            ;;
        csv)
            printf "%s,%s,%s,%s,%s,%s\n" \
                "timestamp" "service" "status" "action_performed" "action_result" "restart_needed"
            ;;
        json)
            # For JSON, we'll start an array
            printf '[\n'
            ;;
    esac
}

# Function to print footer
print_footer() {
    if [ "$FORMAT" = "json" ]; then
        # Close the JSON array
        printf ']\n'
    fi
}

# Function to send email notification
send_email() {
    local email_address="$1"
    local subject="$2"
    local body="$3"
    
    if [ -z "$email_address" ]; then
        return
    fi
    
    log_info "Sending email notification to: $email_address"
    
    # Send email
    echo -e "$body" | mail -s "$subject" "$email_address"
    
    if [ $? -eq 0 ]; then
        log_success "Email notification sent successfully"
    else
        log_error "Failed to send email notification"
    fi
}

# Function to write output to file
write_to_file() {
    local output="$1"
    local file="$2"
    local append="$3"
    
    if [ "$append" = true ]; then
        echo "$output" >> "$file"
    else
        echo "$output" > "$file"
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    
    # Detect init system
    local init_system
    init_system=$(detect_init_system)
    
    if [ "$init_system" = "unknown" ]; then
        log_error "Could not detect init system"
        exit 1
    fi
    
    log_info "Detected init system: $init_system"
    
    # Initialize json_first_item flag for JSON output
    local json_first_item=true
    
    # Print header
    local header
    header=$(print_header)
    
    if [ -n "$OUTPUT_FILE" ]; then
        echo "$header" > "$OUTPUT_FILE"
    elif [ -n "$header" ] && [ "$QUIET" = false ]; then
        echo "$header"
    fi
    
    # Initialize error count
    local error_count=0
    local error_messages=""
    
    # Check each service
    for service in "${SERVICES[@]}"; do
        # Get current timestamp
        local timestamp
        timestamp=$(date "+%Y-%m-%d %H:%M:%S")
        
        # Check service status
        local status
        status=$(check_service_status "$service" "$init_system")
        
        # Check if service needs restart based on config files
        local restart_needed="no"
        if [ "$status" = "running" ] && [ -n "$CONFIG_DIR" ] && needs_restart "$service" "$CONFIG_DIR" "$CHECK_TIME"; then
            restart_needed="yes"
        fi
        
        # Determine action to take
        local action_performed="none"
        local action_result="n/a"
        
        if [ "$status" = "stopped" ] && [ "$ACTION" != "none" ]; then
            action_performed="$ACTION"
            
            # Perform action with retry logic
            local attempts=0
            local success=false
            
            while [ "$attempts" -lt "$MAX_ATTEMPTS" ] && [ "$success" = false ]; do
                attempts=$((attempts + 1))
                
                if perform_service_action "$service" "$action_performed" "$init_system"; then
                    success=true
                    action_result="success"
                    
                    # Wait for service to start
                    if [ "$WAIT_TIME" -gt 0 ]; then
                        log_info "Waiting $WAIT_TIME seconds for service to stabilize..."
                        sleep "$WAIT_TIME"
                    fi
                    
                    # Verify service is now running
                    if [ "$(check_service_status "$service" "$init_system")" = "running" ]; then
                        status="running"
                    else
                        action_result="failed"
                        success=false
                    fi
                else
                    action_result="failed"
                fi
                
                if [ "$success" = false ] && [ "$attempts" -lt "$MAX_ATTEMPTS" ]; then
                    log_warning "Attempt $attempts failed, retrying in $WAIT_TIME seconds..."
                    sleep "$WAIT_TIME"
                fi
            done
            
            if [ "$success" = false ]; then
                log_error "Failed to $action_performed $service after $MAX_ATTEMPTS attempts"
                error_count=$((error_count + 1))
                error_messages+="Service $service: Failed to $action_performed after $MAX_ATTEMPTS attempts\n"
            fi
        elif [ "$restart_needed" = "yes" ] && [ "$RESTART_ACTION" != "none" ]; then
            action_performed="$RESTART_ACTION"
            
            # Perform restart/reload action
            if perform_service_action "$service" "$action_performed" "$init_system"; then
                action_result="success"
                
                # Wait for service to stabilize
                if [ "$WAIT_TIME" -gt 0 ]; then
                    log_info "Waiting $WAIT_TIME seconds for service to stabilize..."
                    sleep "$WAIT_TIME"
                fi
                
                # Verify service is still running
                if [ "$(check_service_status "$service" "$init_system")" != "running" ]; then
                    action_result="failed"
                    status="stopped"
                    error_count=$((error_count + 1))
                    error_messages+="Service $service: $action_performed succeeded but service is now stopped\n"
                fi
            else
                action_result="failed"
                error_count=$((error_count + 1))
                error_messages+="Service $service: Failed to $action_performed\n"
            fi
        fi
        
        # Format output
        local output
        output=$(format_output "$timestamp" "$service" "$status" "$action_performed" "$action_result" "$restart_needed")
        
        # Output results
        if [ "$status" != "running" ] || [ "$action_result" = "failed" ] || [ "$QUIET" = false ]; then
            # Handle JSON format specially
            if [ "$FORMAT" = "json" ]; then
                if [ -n "$OUTPUT_FILE" ]; then
                    # For file output, append the JSON object
                    if [ "$json_first_item" = true ]; then
                        json_first_item=false
                        echo '[' > "$OUTPUT_FILE"
                        echo "$output" >> "$OUTPUT_FILE"
                    else
                        echo "," >> "$OUTPUT_FILE"
                        echo "$output" >> "$OUTPUT_FILE"
                    fi
                else
                    # For stdout, print properly formatted JSON
                    if [ "$json_first_item" = true ]; then
                        json_first_item=false
                        echo '['
                    else
                        echo ','
                    fi
                    echo "$output" | tr -d '\n'
                fi
            else
                # For non-JSON formats, simply output or append
                if [ -n "$OUTPUT_FILE" ]; then
                    write_to_file "$output" "$OUTPUT_FILE" true
                else
                    echo "$output"
                fi
            fi
        fi
        
        # Log appropriate message
        if [ "$status" = "running" ]; then
            if [ "$action_performed" != "none" ]; then
                log_success "Service $service is running (after $action_performed)"
            else
                log_success "Service $service is running"
            fi
        else
            log_error "Service $service is not running"
            
            if [ "$action_performed" != "none" ]; then
                log_error "Failed to $action_performed service $service"
            fi
            
            # Count as error if not already counted
            if [ "$action_result" != "failed" ]; then
                error_count=$((error_count + 1))
                error_messages+="Service $service: Not running\n"
            fi
        fi
    done
    
    # Print footer for JSON format
    if [ "$FORMAT" = "json" ]; then
        if [ -n "$OUTPUT_FILE" ]; then
            echo ']' >> "$OUTPUT_FILE"
        else
            echo
            echo ']'
        fi
    fi
    
    # Send email notification if there are errors
    if [ "$error_count" -gt 0 ] && [ -n "$EMAIL" ]; then
        local subject="Service check alert: $error_count service(s) have issues on $(hostname)"
        local body="The following service issues were detected:\n\n$error_messages"
        
        send_email "$EMAIL" "$subject" "$body"
    fi
    
    # Print summary
    log_info "Service check summary: ${#SERVICES[@]} services checked, $error_count errors"
    
    # Set exit code based on results
    if [ "$error_count" -gt 0 ]; then
        exit 1
    fi
    
    exit 0
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi