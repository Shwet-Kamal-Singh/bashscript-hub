#!/bin/bash
#
# disk_usage_alert.sh - Monitor disk usage and send alerts
#
# This script monitors disk usage across file systems and generates alerts
# when thresholds are exceeded. It supports multiple alert methods including
# console output, log files, and email notifications.
#
# Usage:
#   ./disk_usage_alert.sh [options]
#
# Options:
#   -t, --threshold <percent>    Alert threshold percentage (default: 90)
#   -w, --warning <percent>      Warning threshold percentage (default: 80)
#   -f, --filesystem <path>      Monitor specific filesystem (can be used multiple times)
#   -e, --exclude <path>         Exclude filesystem (can be used multiple times)
#   -i, --include-type <type>    Include only filesystem types (can be used multiple times)
#   -x, --exclude-type <type>    Exclude filesystem types (can be used multiple times)
#   -m, --mail <email>           Send email alert (requires mail command)
#   -s, --slack <webhook>        Send Slack alert (requires curl)
#   -o, --output <file>          Write results to file
#   -a, --append                 Append to output file instead of overwriting
#   -n, --no-header              Don't print header in output
#   -q, --quiet                  Only output when thresholds are exceeded
#   -v, --verbose                Display detailed output
#   -h, --help                   Display this help message
#
# Requirements:
#   - Basic system utilities: df, grep, awk
#   - For email alerts: mail command
#   - For Slack alerts: curl command
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
THRESHOLD=90
WARNING=80
FILESYSTEMS=()
EXCLUDE_FS=()
INCLUDE_TYPES=()
EXCLUDE_TYPES=()
EMAIL=""
SLACK_WEBHOOK=""
OUTPUT_FILE=""
APPEND=false
NO_HEADER=false
QUIET=false
VERBOSE=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Monitor disk usage and send alerts."
    echo ""
    echo "Options:"
    echo "  -t, --threshold <percent>    Alert threshold percentage (default: 90)"
    echo "  -w, --warning <percent>      Warning threshold percentage (default: 80)"
    echo "  -f, --filesystem <path>      Monitor specific filesystem (can be used multiple times)"
    echo "  -e, --exclude <path>         Exclude filesystem (can be used multiple times)"
    echo "  -i, --include-type <type>    Include only filesystem types (can be used multiple times)"
    echo "  -x, --exclude-type <type>    Exclude filesystem types (can be used multiple times)"
    echo "  -m, --mail <email>           Send email alert (requires mail command)"
    echo "  -s, --slack <webhook>        Send Slack alert (requires curl)"
    echo "  -o, --output <file>          Write results to file"
    echo "  -a, --append                 Append to output file instead of overwriting"
    echo "  -n, --no-header              Don't print header in output"
    echo "  -q, --quiet                  Only output when thresholds are exceeded"
    echo "  -v, --verbose                Display detailed output"
    echo "  -h, --help                   Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")"
    echo "  $(basename "$0") -t 95 -w 85"
    echo "  $(basename "$0") -f / -f /home -x tmpfs -x devtmpfs"
    echo "  $(basename "$0") -m admin@example.com -o /var/log/disk_alerts.log -a"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -t|--threshold)
                THRESHOLD="$2"
                if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]] || [ "$THRESHOLD" -lt 0 ] || [ "$THRESHOLD" -gt 100 ]; then
                    log_error "Threshold must be an integer between 0 and 100"
                    exit 1
                fi
                shift 2
                ;;
            -w|--warning)
                WARNING="$2"
                if ! [[ "$WARNING" =~ ^[0-9]+$ ]] || [ "$WARNING" -lt 0 ] || [ "$WARNING" -gt 100 ]; then
                    log_error "Warning threshold must be an integer between 0 and 100"
                    exit 1
                fi
                shift 2
                ;;
            -f|--filesystem)
                FILESYSTEMS+=("$2")
                shift 2
                ;;
            -e|--exclude)
                EXCLUDE_FS+=("$2")
                shift 2
                ;;
            -i|--include-type)
                INCLUDE_TYPES+=("$2")
                shift 2
                ;;
            -x|--exclude-type)
                EXCLUDE_TYPES+=("$2")
                shift 2
                ;;
            -m|--mail)
                EMAIL="$2"
                shift 2
                ;;
            -s|--slack)
                SLACK_WEBHOOK="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -a|--append)
                APPEND=true
                shift
                ;;
            -n|--no-header)
                NO_HEADER=true
                shift
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
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate threshold and warning levels
    if [ "$WARNING" -ge "$THRESHOLD" ]; then
        log_warning "Warning threshold ($WARNING%) is greater than or equal to alert threshold ($THRESHOLD%)"
        log_warning "Warning events may also trigger alerts"
    fi
    
    # Check for notification requirements
    if [ -n "$EMAIL" ]; then
        if ! command -v mail &>/dev/null; then
            log_error "Email notifications requested but 'mail' command is not available"
            log_error "Please install a mail client for your distribution:"
            log_error "  - Debian/Ubuntu: sudo apt-get install mailutils"
            log_error "  - RHEL/CentOS: sudo yum install mailx"
            log_error "  - Fedora: sudo dnf install mailx"
            exit 1
        fi
    fi
    
    if [ -n "$SLACK_WEBHOOK" ]; then
        if ! command -v curl &>/dev/null; then
            log_error "Slack notifications requested but 'curl' command is not available"
            log_error "Please install curl for your distribution:"
            log_error "  - Debian/Ubuntu: sudo apt-get install curl"
            log_error "  - RHEL/CentOS: sudo yum install curl"
            log_error "  - Fedora: sudo dnf install curl"
            exit 1
        fi
    fi
}

# Function to check for required commands
check_requirements() {
    local missing_cmds=()
    
    # Check for required commands
    for cmd in df grep awk; do
        if ! command -v $cmd &>/dev/null; then
            missing_cmds+=("$cmd")
        fi
    done
    
    if [ ${#missing_cmds[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_cmds[*]}"
        log_info "Please install the required packages for your distribution:"
        log_info "  - Debian/Ubuntu: sudo apt-get install coreutils grep gawk"
        log_info "  - RHEL/CentOS: sudo yum install coreutils grep gawk"
        log_info "  - Fedora: sudo dnf install coreutils grep gawk"
        exit 1
    fi
}

# Function to build df command with filters
build_df_command() {
    local cmd="df -h"
    
    # Add filesystem type inclusions if specified
    if [ ${#INCLUDE_TYPES[@]} -gt 0 ]; then
        cmd+=" -t $(IFS=, ; echo "${INCLUDE_TYPES[*]}")"
    fi
    
    # Add filesystem type exclusions if specified
    if [ ${#EXCLUDE_TYPES[@]} -gt 0 ]; then
        cmd+=" -x $(IFS=, ; echo "${EXCLUDE_TYPES[*]}")"
    fi
    
    echo "$cmd"
}

# Function to check if a filesystem should be included
should_include_filesystem() {
    local fs="$1"
    
    # If specific filesystems are listed, only include those
    if [ ${#FILESYSTEMS[@]} -gt 0 ]; then
        for include in "${FILESYSTEMS[@]}"; do
            if [ "$fs" = "$include" ]; then
                return 0
            fi
        done
        return 1
    fi
    
    # Check if filesystem is in exclude list
    for exclude in "${EXCLUDE_FS[@]}"; do
        if [ "$fs" = "$exclude" ]; then
            return 1
        fi
    done
    
    # Default to including
    return 0
}

# Function to get disk usage data
get_disk_usage() {
    local df_cmd
    df_cmd=$(build_df_command)
    
    if [ "$VERBOSE" = true ]; then
        log_debug "Executing command: $df_cmd"
    fi
    
    # Execute command
    local df_output
    df_output=$(eval "$df_cmd" | grep -v "Filesystem")
    
    # Process each filesystem
    local result=""
    
    while IFS= read -r line; do
        local fs size used avail pct mount
        read -r fs size used avail pct mount <<< "$line"
        
        # Remove % from percentage
        pct=${pct/\%/}
        
        # Skip if mount point should be excluded
        if ! should_include_filesystem "$mount"; then
            continue
        fi
        
        # Append to result
        result+="$fs $size $used $avail $pct $mount\n"
    done <<< "$df_output"
    
    echo -e "$result"
}

# Function to format output header
format_header() {
    printf "%-20s %-10s %-10s %-10s %-10s %-30s %-10s\n" \
        "Filesystem" "Size" "Used" "Avail" "Use%" "Mounted on" "Status"
    printf "%-20s %-10s %-10s %-10s %-10s %-30s %-10s\n" \
        "--------------------" "----------" "----------" "----------" "----------" "------------------------------" "----------"
}

# Function to format output line
format_line() {
    local fs="$1"
    local size="$2"
    local used="$3"
    local avail="$4"
    local pct="$5"
    local mount="$6"
    local status="$7"
    
    printf "%-20s %-10s %-10s %-10s %-10s %-30s %-10s\n" \
        "$fs" "$size" "$used" "$avail" "${pct}%" "$mount" "$status"
}

# Function to send email alert
send_email_alert() {
    local email="$1"
    local subject="$2"
    local body="$3"
    
    if [ -z "$email" ]; then
        return
    fi
    
    log_info "Sending email alert to: $email"
    
    echo -e "$body" | mail -s "$subject" "$email"
    
    if [ $? -eq 0 ]; then
        log_success "Email alert sent successfully"
    else
        log_error "Failed to send email alert"
    fi
}

# Function to send Slack alert
send_slack_alert() {
    local webhook="$1"
    local subject="$2"
    local body="$3"
    
    if [ -z "$webhook" ]; then
        return
    fi
    
    log_info "Sending Slack alert"
    
    # Format for Slack
    local hostname
    hostname=$(hostname)
    local payload
    payload=$(cat <<EOF
{
    "text": "*$subject*",
    "blocks": [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "*$subject*\n\`\`\`$body\`\`\`"
            }
        },
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": "Host: $hostname | Time: $(date)"
                }
            ]
        }
    ]
}
EOF
    )
    
    curl -s -X POST -H "Content-type: application/json" -d "$payload" "$webhook" &>/dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Slack alert sent successfully"
    else
        log_error "Failed to send Slack alert"
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
    check_requirements
    
    log_info "Starting disk usage monitoring"
    log_info "Alert threshold: ${THRESHOLD}%, Warning threshold: ${WARNING}%"
    
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Get disk usage data
    local disk_data
    disk_data=$(get_disk_usage)
    
    if [ -z "$disk_data" ]; then
        log_warning "No matching filesystems found"
        exit 0
    fi
    
    # Initialize output
    local output=""
    local alert_output=""
    local warning_output=""
    local alert_count=0
    local warning_count=0
    
    # Add header if not suppressed
    if [ "$NO_HEADER" = false ]; then
        output+="Disk Usage Report - $timestamp\n\n"
        output+=$(format_header)
        output+="\n"
    fi
    
    # Process each filesystem
    while IFS= read -r line; do
        local fs size used avail pct mount status
        read -r fs size used avail pct mount <<< "$line"
        
        # Determine status
        if [ "$pct" -ge "$THRESHOLD" ]; then
            status="CRITICAL"
            alert_count=$((alert_count + 1))
            alert_output+=$(format_line "$fs" "$size" "$used" "$avail" "$pct" "$mount" "$status")
            alert_output+="\n"
        elif [ "$pct" -ge "$WARNING" ]; then
            status="WARNING"
            warning_count=$((warning_count + 1))
            warning_output+=$(format_line "$fs" "$size" "$used" "$avail" "$pct" "$mount" "$status")
            warning_output+="\n"
        else
            status="OK"
        fi
        
        # Add to output unless quiet mode is enabled and status is OK
        if [ "$QUIET" = false ] || [ "$status" != "OK" ]; then
            output+=$(format_line "$fs" "$size" "$used" "$avail" "$pct" "$mount" "$status")
            output+="\n"
        fi
    done <<< "$disk_data"
    
    # Output results
    if [ -n "$OUTPUT_FILE" ]; then
        write_to_file "$output" "$OUTPUT_FILE" "$APPEND"
    else
        echo -e "$output"
    fi
    
    # Send notifications if thresholds are exceeded
    if [ $alert_count -gt 0 ]; then
        local alert_subject="DISK ALERT: $alert_count filesystems above ${THRESHOLD}% threshold on $(hostname)"
        local alert_body="The following filesystems are above the ${THRESHOLD}% threshold:\n\n"
        alert_body+=$(format_header)
        alert_body+="\n"
        alert_body+="$alert_output"
        
        log_error "$alert_subject"
        
        # Send email if configured
        send_email_alert "$EMAIL" "$alert_subject" "$alert_body"
        
        # Send Slack if configured
        send_slack_alert "$SLACK_WEBHOOK" "$alert_subject" "$alert_body"
    fi
    
    if [ $warning_count -gt 0 ] && [ $alert_count -eq 0 ]; then
        local warning_subject="DISK WARNING: $warning_count filesystems above ${WARNING}% threshold on $(hostname)"
        local warning_body="The following filesystems are above the ${WARNING}% threshold:\n\n"
        warning_body+=$(format_header)
        warning_body+="\n"
        warning_body+="$warning_output"
        
        log_warning "$warning_subject"
        
        # Send email if configured
        send_email_alert "$EMAIL" "$warning_subject" "$warning_body"
        
        # Send Slack if configured
        send_slack_alert "$SLACK_WEBHOOK" "$warning_subject" "$warning_body"
    fi
    
    if [ $alert_count -eq 0 ] && [ $warning_count -eq 0 ]; then
        log_success "All filesystems below threshold levels"
    fi
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi