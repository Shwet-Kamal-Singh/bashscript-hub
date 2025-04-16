#!/bin/bash
#
# process_uptime_report.sh - Report on process uptime and restarts
#
# This script monitors process uptime and detects restarts, generating reports on
# process stability. It can track specific processes or system services across
# different types of init systems (systemd, sysvinit, upstart).
#
# Usage:
#   ./process_uptime_report.sh [options]
#
# Options:
#   -p, --process <name>       Process name to monitor (can be used multiple times)
#   -s, --service <name>       Service name to monitor (can be used multiple times)
#   -i, --interval <seconds>   Check interval in seconds (default: 60)
#   -d, --duration <time>      Monitoring duration (e.g., 1h, 2d; default: continuous)
#   -m, --min-uptime <seconds> Alert if uptime is below threshold (default: 300)
#   -r, --restart-threshold <count> Alert if restarts exceed threshold (default: 3)
#   -o, --output <file>        Write report to file
#   -f, --format <format>      Output format (text, csv, json; default: text)
#   -a, --alert-command <cmd>  Command to run on alert (e.g., email notification)
#   -n, --no-header            Don't print header in output
#   -q, --quiet                Only output alerts
#   -v, --verbose              Display detailed output
#   -h, --help                 Display this help message
#
# Requirements:
#   - Basic system utilities: ps, grep, awk
#   - systemctl for systemd services
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
PROCESSES=()
SERVICES=()
INTERVAL=60
DURATION=""
MIN_UPTIME=300
RESTART_THRESHOLD=3
OUTPUT_FILE=""
FORMAT="text"
ALERT_COMMAND=""
NO_HEADER=false
QUIET=false
VERBOSE=false

# Process tracking variables
declare -A PROCESS_START_TIMES
declare -A PROCESS_RESTART_COUNTS

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Report on process uptime and restarts."
    echo ""
    echo "Options:"
    echo "  -p, --process <name>       Process name to monitor (can be used multiple times)"
    echo "  -s, --service <name>       Service name to monitor (can be used multiple times)"
    echo "  -i, --interval <seconds>   Check interval in seconds (default: 60)"
    echo "  -d, --duration <time>      Monitoring duration (e.g., 1h, 2d; default: continuous)"
    echo "  -m, --min-uptime <seconds> Alert if uptime is below threshold (default: 300)"
    echo "  -r, --restart-threshold <count> Alert if restarts exceed threshold (default: 3)"
    echo "  -o, --output <file>        Write report to file"
    echo "  -f, --format <format>      Output format (text, csv, json; default: text)"
    echo "  -a, --alert-command <cmd>  Command to run on alert (e.g., email notification)"
    echo "  -n, --no-header            Don't print header in output"
    echo "  -q, --quiet                Only output alerts"
    echo "  -v, --verbose              Display detailed output"
    echo "  -h, --help                 Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") -p nginx -p apache2 -i 300"
    echo "  $(basename "$0") -s ssh -s mysql -d 24h -o service_report.csv -f csv"
    echo "  $(basename "$0") -p httpd -m 600 -r 5 -a 'mail -s \"Process restart alert\" admin@example.com'"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -p|--process)
                PROCESSES+=("$2")
                shift 2
                ;;
            -s|--service)
                SERVICES+=("$2")
                shift 2
                ;;
            -i|--interval)
                INTERVAL="$2"
                if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 1 ]; then
                    log_error "Interval must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -d|--duration)
                DURATION="$2"
                # Validate duration format (e.g., 1h, 2d)
                if ! [[ "$DURATION" =~ ^[0-9]+[hd]$ ]]; then
                    log_error "Invalid duration format: $DURATION"
                    log_error "Valid formats: 1h, 12h, 1d, 7d"
                    exit 1
                fi
                shift 2
                ;;
            -m|--min-uptime)
                MIN_UPTIME="$2"
                if ! [[ "$MIN_UPTIME" =~ ^[0-9]+$ ]] || [ "$MIN_UPTIME" -lt 0 ]; then
                    log_error "Minimum uptime must be a non-negative integer"
                    exit 1
                fi
                shift 2
                ;;
            -r|--restart-threshold)
                RESTART_THRESHOLD="$2"
                if ! [[ "$RESTART_THRESHOLD" =~ ^[0-9]+$ ]] || [ "$RESTART_THRESHOLD" -lt 1 ]; then
                    log_error "Restart threshold must be a positive integer"
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
            -a|--alert-command)
                ALERT_COMMAND="$2"
                shift 2
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
    
    # Validate required arguments
    if [ ${#PROCESSES[@]} -eq 0 ] && [ ${#SERVICES[@]} -eq 0 ]; then
        log_error "At least one process or service must be specified"
        show_usage
        exit 1
    fi
    
    # Convert duration to seconds
    if [ -n "$DURATION" ]; then
        local value="${DURATION%[hd]}"
        local unit="${DURATION: -1}"
        
        if [ "$unit" = "h" ]; then
            DURATION_SECONDS=$((value * 3600))
        elif [ "$unit" = "d" ]; then
            DURATION_SECONDS=$((value * 86400))
        fi
    else
        DURATION_SECONDS=0  # 0 means continuous
    fi
}

# Function to check if required commands are available
check_requirements() {
    local missing_cmds=()
    
    # Check for required commands
    for cmd in ps grep awk; do
        if ! command -v $cmd &>/dev/null; then
            missing_cmds+=("$cmd")
        fi
    done
    
    # Check for systemctl if monitoring services
    if [ ${#SERVICES[@]} -gt 0 ] && ! command -v systemctl &>/dev/null && ! command -v service &>/dev/null; then
        missing_cmds+=("systemctl or service")
    fi
    
    if [ ${#missing_cmds[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_cmds[*]}"
        log_info "Please install the required packages for your distribution:"
        log_info "  - Debian/Ubuntu: sudo apt-get install procps grep gawk"
        log_info "  - RHEL/CentOS: sudo yum install procps-ng grep gawk"
        log_info "  - Fedora: sudo dnf install procps-ng grep gawk"
        exit 1
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

# Function to get process info
get_process_info() {
    local process_name="$1"
    
    # Check if process is running
    local pid=$(pgrep -f "$process_name" | head -n1)
    
    if [ -z "$pid" ]; then
        echo "not_running 0"
        return 1
    fi
    
    # Get process start time
    local start_time
    if [ -f "/proc/$pid/stat" ]; then
        # Use /proc filesystem if available
        local stat=$(cat "/proc/$pid/stat")
        local process_start_time=$(echo "$stat" | awk '{print $22}')
        local system_uptime=$(cat /proc/uptime | awk '{print $1}')
        local system_boot_time=$(date +%s)
        start_time=$(echo "$system_boot_time - $system_uptime + $process_start_time / 100" | bc)
    else
        # Fallback to ps command
        start_time=$(ps -o lstart= -p "$pid" | xargs -0 date +%s -d)
    fi
    
    # Calculate uptime
    local current_time=$(date +%s)
    local uptime=$((current_time - start_time))
    
    echo "running $uptime $pid"
}

# Function to get service info
get_service_info() {
    local service_name="$1"
    local init_system="$2"
    
    case "$init_system" in
        systemd)
            # Check if service is running
            if ! systemctl is-active "$service_name" &>/dev/null; then
                echo "not_running 0"
                return 1
            fi
            
            # Get service start time
            local start_time=$(systemctl show "$service_name" --property=ActiveEnterTimestamp | awk -F= '{print $2}')
            if [ -z "$start_time" ]; then
                echo "running unknown"
                return 0
            fi
            
            # Convert to seconds since epoch
            start_time=$(date -d "$start_time" +%s 2>/dev/null)
            if [ $? -ne 0 ]; then
                echo "running unknown"
                return 0
            fi
            
            # Calculate uptime
            local current_time=$(date +%s)
            local uptime=$((current_time - start_time))
            
            echo "running $uptime"
            ;;
            
        sysvinit|upstart)
            # Check if service is running
            local status
            if [ "$init_system" = "sysvinit" ]; then
                status=$(/etc/init.d/"$service_name" status 2>/dev/null || service "$service_name" status 2>/dev/null)
            else
                status=$(initctl status "$service_name" 2>/dev/null)
            fi
            
            if ! echo "$status" | grep -q "running"; then
                echo "not_running 0"
                return 1
            fi
            
            # Extract PID if possible
            local pid=$(echo "$status" | grep -o 'process [0-9]*' | awk '{print $2}')
            if [ -z "$pid" ]; then
                pid=$(pgrep -f "$service_name" | head -n1)
            fi
            
            if [ -n "$pid" ]; then
                # Get process start time
                local start_time
                if [ -f "/proc/$pid/stat" ]; then
                    local stat=$(cat "/proc/$pid/stat")
                    local process_start_time=$(echo "$stat" | awk '{print $22}')
                    local system_uptime=$(cat /proc/uptime | awk '{print $1}')
                    local system_boot_time=$(date +%s)
                    start_time=$(echo "$system_boot_time - $system_uptime + $process_start_time / 100" | bc)
                else
                    start_time=$(ps -o lstart= -p "$pid" | xargs -0 date +%s -d)
                fi
                
                # Calculate uptime
                local current_time=$(date +%s)
                local uptime=$((current_time - start_time))
                
                echo "running $uptime $pid"
            else
                echo "running unknown"
            fi
            ;;
            
        *)
            echo "unknown 0"
            ;;
    esac
}

# Function to check for process restarts
check_process_restarts() {
    local name="$1"
    local type="$2"
    local info="$3"
    local init_system="$4"
    
    # Parse process info
    local status
    local uptime
    local pid
    read -r status uptime pid <<< "$info"
    
    if [ "$status" = "not_running" ]; then
        if [ -n "${PROCESS_START_TIMES[$name]}" ]; then
            # Process was running before but now stopped
            log_warning "$type $name has stopped"
            
            # Increment restart count
            PROCESS_RESTART_COUNTS[$name]=$((${PROCESS_RESTART_COUNTS[$name]:-0} + 1))
            
            # Clear start time
            unset PROCESS_START_TIMES[$name]
            
            return 1
        else
            # Process was not running before and still not running
            log_warning "$type $name is not running"
            return 1
        fi
    elif [ "$status" = "running" ]; then
        if [ -z "${PROCESS_START_TIMES[$name]}" ]; then
            # Process was not running before but now started
            log_info "$type $name has started"
            PROCESS_START_TIMES[$name]=$uptime
            return 0
        elif [ "$uptime" -lt "${PROCESS_START_TIMES[$name]}" ]; then
            # Process has restarted (new uptime is less than previous uptime)
            log_warning "$type $name has restarted"
            
            # Increment restart count
            PROCESS_RESTART_COUNTS[$name]=$((${PROCESS_RESTART_COUNTS[$name]:-0} + 1))
            
            # Update start time
            PROCESS_START_TIMES[$name]=$uptime
            
            return 1
        else
            # Process is still running, update uptime
            PROCESS_START_TIMES[$name]=$uptime
            return 0
        fi
    else
        # Unknown status
        log_warning "Unknown status for $type $name: $status"
        return 1
    fi
}

# Function to format time
format_time() {
    local seconds="$1"
    
    if [ "$seconds" = "unknown" ]; then
        echo "unknown"
        return
    fi
    
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    if [ $days -gt 0 ]; then
        printf "%dd %02d:%02d:%02d" $days $hours $minutes $secs
    else
        printf "%02d:%02d:%02d" $hours $minutes $secs
    fi
}

# Function to format output
format_output() {
    local timestamp="$1"
    local name="$2"
    local type="$3"
    local status="$4"
    local uptime="$5"
    local restarts="$6"
    local alert="$7"
    
    case "$FORMAT" in
        text)
            printf "%-20s %-20s %-10s %-10s %-15s %-10s %-10s\n" \
                "$timestamp" "$name" "$type" "$status" "$(format_time "$uptime")" "$restarts" "$alert"
            ;;
        csv)
            printf "%s,%s,%s,%s,%s,%s,%s\n" \
                "$timestamp" "$name" "$type" "$status" "$uptime" "$restarts" "$alert"
            ;;
        json)
            printf '{"timestamp":"%s","name":"%s","type":"%s","status":"%s","uptime":%s,"restarts":%s,"alert":"%s"}\n' \
                "$timestamp" "$name" "$type" "$status" \
                $([ "$uptime" = "unknown" ] && echo "\"unknown\"" || echo "$uptime") \
                "$restarts" "$alert"
            ;;
    esac
}

# Function to print header
print_header() {
    if [ "$NO_HEADER" = true ]; then
        return
    fi
    
    case "$FORMAT" in
        text)
            printf "%-20s %-20s %-10s %-10s %-15s %-10s %-10s\n" \
                "TIMESTAMP" "NAME" "TYPE" "STATUS" "UPTIME" "RESTARTS" "ALERT"
            printf "%-20s %-20s %-10s %-10s %-15s %-10s %-10s\n" \
                "--------------------" "--------------------" "----------" "----------" "---------------" "----------" "----------"
            ;;
        csv)
            printf "%s,%s,%s,%s,%s,%s,%s\n" \
                "timestamp" "name" "type" "status" "uptime" "restarts" "alert"
            ;;
        json)
            # For JSON, we'll start an array that will be closed at the end
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

# Function to run alert command
run_alert_command() {
    local message="$1"
    
    if [ -z "$ALERT_COMMAND" ]; then
        return
    fi
    
    # Replace placeholder with actual message
    local cmd="${ALERT_COMMAND/\%m/$message}"
    
    log_info "Running alert command: $cmd"
    eval "$cmd"
}

# Function to write output to file
write_to_file() {
    local output="$1"
    local file="$2"
    
    echo "$output" >> "$file"
}

# Function to monitor processes and services
monitor() {
    local init_system
    init_system=$(detect_init_system)
    
    log_info "Detected init system: $init_system"
    
    # Initialize process tracking
    for process in "${PROCESSES[@]}"; do
        PROCESS_RESTART_COUNTS[$process]=0
    done
    
    for service in "${SERVICES[@]}"; do
        PROCESS_RESTART_COUNTS[$service]=0
    done
    
    # Print header
    local header
    header=$(print_header)
    
    if [ -n "$OUTPUT_FILE" ]; then
        echo "$header" > "$OUTPUT_FILE"
    elif [ -n "$header" ]; then
        echo "$header"
    fi
    
    local json_first_item=true
    local start_time=$(date +%s)
    local end_time
    
    if [ "$DURATION_SECONDS" -gt 0 ]; then
        end_time=$((start_time + DURATION_SECONDS))
    else
        end_time=0  # 0 means continuous
    fi
    
    while true; do
        # Check if duration has been reached
        local current_time=$(date +%s)
        if [ "$end_time" -gt 0 ] && [ "$current_time" -ge "$end_time" ]; then
            break
        fi
        
        # Get current timestamp
        local timestamp
        timestamp=$(date "+%Y-%m-%d %H:%M:%S")
        
        # Check processes
        for process in "${PROCESSES[@]}"; do
            local process_info
            process_info=$(get_process_info "$process")
            
            # Parse process info
            local status
            local uptime
            local pid
            read -r status uptime pid <<< "$process_info"
            
            # Check for restarts
            check_process_restarts "$process" "Process" "$process_info" "$init_system"
            
            # Get restart count
            local restart_count=${PROCESS_RESTART_COUNTS[$process]:-0}
            
            # Determine alert status
            local alert="OK"
            local alert_message=""
            
            if [ "$status" = "not_running" ]; then
                alert="ERROR"
                alert_message="Process $process is not running"
            elif [ "$status" = "running" ] && [ "$uptime" != "unknown" ] && [ "$uptime" -lt "$MIN_UPTIME" ]; then
                alert="WARNING"
                alert_message="Process $process uptime ($(format_time "$uptime")) is below minimum threshold ($(format_time "$MIN_UPTIME"))"
            fi
            
            if [ "$restart_count" -ge "$RESTART_THRESHOLD" ]; then
                alert="ERROR"
                alert_message="Process $process has restarted $restart_count times (threshold: $RESTART_THRESHOLD)"
            fi
            
            # Output results
            if [ "$alert" != "OK" ] || [ "$QUIET" = false ]; then
                local output
                output=$(format_output "$timestamp" "$process" "Process" "$status" "$uptime" "$restart_count" "$alert")
                
                # Handle JSON format specially for continuous output
                if [ "$FORMAT" = "json" ] && [ -z "$OUTPUT_FILE" ]; then
                    if [ "$json_first_item" = true ]; then
                        json_first_item=false
                        echo '['
                    else
                        echo ','
                    fi
                    echo "$output" | tr -d '\n'
                else
                    if [ -n "$OUTPUT_FILE" ]; then
                        write_to_file "$output" "$OUTPUT_FILE"
                    else
                        echo "$output"
                    fi
                fi
            fi
            
            # Run alert command if needed
            if [ "$alert" != "OK" ] && [ -n "$alert_message" ]; then
                run_alert_command "$alert_message"
            fi
        done
        
        # Check services
        for service in "${SERVICES[@]}"; do
            local service_info
            service_info=$(get_service_info "$service" "$init_system")
            
            # Parse service info
            local status
            local uptime
            read -r status uptime <<< "$service_info"
            
            # Check for restarts
            check_process_restarts "$service" "Service" "$service_info" "$init_system"
            
            # Get restart count
            local restart_count=${PROCESS_RESTART_COUNTS[$service]:-0}
            
            # Determine alert status
            local alert="OK"
            local alert_message=""
            
            if [ "$status" = "not_running" ]; then
                alert="ERROR"
                alert_message="Service $service is not running"
            elif [ "$status" = "running" ] && [ "$uptime" != "unknown" ] && [ "$uptime" -lt "$MIN_UPTIME" ]; then
                alert="WARNING"
                alert_message="Service $service uptime ($(format_time "$uptime")) is below minimum threshold ($(format_time "$MIN_UPTIME"))"
            fi
            
            if [ "$restart_count" -ge "$RESTART_THRESHOLD" ]; then
                alert="ERROR"
                alert_message="Service $service has restarted $restart_count times (threshold: $RESTART_THRESHOLD)"
            fi
            
            # Output results
            if [ "$alert" != "OK" ] || [ "$QUIET" = false ]; then
                local output
                output=$(format_output "$timestamp" "$service" "Service" "$status" "$uptime" "$restart_count" "$alert")
                
                # Handle JSON format specially for continuous output
                if [ "$FORMAT" = "json" ] && [ -z "$OUTPUT_FILE" ]; then
                    if [ "$json_first_item" = true ]; then
                        json_first_item=false
                        echo '['
                    else
                        echo ','
                    fi
                    echo "$output" | tr -d '\n'
                else
                    if [ -n "$OUTPUT_FILE" ]; then
                        write_to_file "$output" "$OUTPUT_FILE"
                    else
                        echo "$output"
                    fi
                fi
            fi
            
            # Run alert command if needed
            if [ "$alert" != "OK" ] && [ -n "$alert_message" ]; then
                run_alert_command "$alert_message"
            fi
        done
        
        # Sleep for the interval
        sleep "$INTERVAL"
    done
    
    # Print footer for JSON format
    if [ "$FORMAT" = "json" ] && [ -z "$OUTPUT_FILE" ]; then
        echo
        print_footer
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    check_requirements
    
    log_info "Starting process uptime monitoring"
    
    # Handle termination signal
    trap 'log_info "Monitoring stopped"; [ "$FORMAT" = "json" ] && [ -z "$OUTPUT_FILE" ] && echo -e "\n]"; exit 0' SIGINT SIGTERM
    
    # Start monitoring
    monitor
    
    log_success "Monitoring completed"
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi