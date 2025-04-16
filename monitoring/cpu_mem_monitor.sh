#!/bin/bash
#
# cpu_mem_monitor.sh - Monitor CPU and memory usage
#
# This script monitors CPU and memory usage on a system, with options for continuous
# monitoring, threshold alerts, and various output formats. It can be run as a
# one-time check or in continuous monitoring mode with configurable intervals.
#
# Usage:
#   ./cpu_mem_monitor.sh [options]
#
# Options:
#   -i, --interval <seconds>     Check interval in seconds (default: 5)
#   -c, --count <number>         Number of times to check (default: continuous)
#   -t, --cpu-threshold <percent> CPU usage alert threshold (default: 80)
#   -m, --mem-threshold <percent> Memory usage alert threshold (default: 80)
#   -f, --format <format>        Output format (table, csv, json; default: table)
#   -o, --output <file>          Write output to file
#   -a, --append                 Append to output file instead of overwriting
#   -n, --no-header              Don't print header in output
#   -q, --quiet                  Only output when thresholds are exceeded
#   -v, --verbose                Display detailed output
#   -h, --help                   Display this help message
#
# Requirements:
#   - Basic system utilities: top, free, grep, awk
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
INTERVAL=5
COUNT=0  # 0 means continuous
CPU_THRESHOLD=80
MEM_THRESHOLD=80
FORMAT="table"
OUTPUT_FILE=""
APPEND=false
NO_HEADER=false
QUIET=false
VERBOSE=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Monitor CPU and memory usage."
    echo ""
    echo "Options:"
    echo "  -i, --interval <seconds>      Check interval in seconds (default: 5)"
    echo "  -c, --count <number>          Number of times to check (default: continuous)"
    echo "  -t, --cpu-threshold <percent> CPU usage alert threshold (default: 80)"
    echo "  -m, --mem-threshold <percent> Memory usage alert threshold (default: 80)"
    echo "  -f, --format <format>         Output format (table, csv, json; default: table)"
    echo "  -o, --output <file>           Write output to file"
    echo "  -a, --append                  Append to output file instead of overwriting"
    echo "  -n, --no-header               Don't print header in output"
    echo "  -q, --quiet                   Only output when thresholds are exceeded"
    echo "  -v, --verbose                 Display detailed output"
    echo "  -h, --help                    Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")"
    echo "  $(basename "$0") -i 10 -c 6 -t 90 -m 85"
    echo "  $(basename "$0") -f csv -o cpu_mem_log.csv -a"
    echo "  $(basename "$0") -q -t 95 -m 90"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -i|--interval)
                INTERVAL="$2"
                if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 1 ]; then
                    log_error "Interval must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -c|--count)
                COUNT="$2"
                if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
                    log_error "Count must be a non-negative integer"
                    exit 1
                fi
                shift 2
                ;;
            -t|--cpu-threshold)
                CPU_THRESHOLD="$2"
                if ! [[ "$CPU_THRESHOLD" =~ ^[0-9]+$ ]] || [ "$CPU_THRESHOLD" -lt 0 ] || [ "$CPU_THRESHOLD" -gt 100 ]; then
                    log_error "CPU threshold must be an integer between 0 and 100"
                    exit 1
                fi
                shift 2
                ;;
            -m|--mem-threshold)
                MEM_THRESHOLD="$2"
                if ! [[ "$MEM_THRESHOLD" =~ ^[0-9]+$ ]] || [ "$MEM_THRESHOLD" -lt 0 ] || [ "$MEM_THRESHOLD" -gt 100 ]; then
                    log_error "Memory threshold must be an integer between 0 and 100"
                    exit 1
                fi
                shift 2
                ;;
            -f|--format)
                FORMAT="$2"
                case "$FORMAT" in
                    table|csv|json)
                        # Valid format
                        ;;
                    *)
                        log_error "Invalid format: $FORMAT"
                        log_error "Valid formats: table, csv, json"
                        exit 1
                        ;;
                esac
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
}

# Function to check for required commands
check_requirements() {
    local missing_cmds=()
    
    # Check for required commands
    for cmd in top free grep awk; do
        if ! command -v $cmd &>/dev/null; then
            missing_cmds+=("$cmd")
        fi
    done
    
    if [ ${#missing_cmds[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_cmds[*]}"
        log_info "Please install the required packages for your distribution:"
        log_info "  - Debian/Ubuntu: sudo apt-get install procps grep gawk"
        log_info "  - RHEL/CentOS: sudo yum install procps-ng grep gawk"
        log_info "  - Fedora: sudo dnf install procps-ng grep gawk"
        exit 1
    fi
}

# Function to get CPU usage
get_cpu_usage() {
    # Use top to get CPU usage
    local cpu_usage
    if command -v mpstat &>/dev/null; then
        # Use mpstat if available for more accurate readings
        cpu_usage=$(mpstat 1 1 | awk '/^Average:/ {print 100 - $NF}')
    else
        # Fallback to top
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    fi
    
    # Format to 2 decimal places
    printf "%.2f" "$cpu_usage"
}

# Function to get memory usage
get_memory_usage() {
    # Use free to get memory usage
    local mem_info
    mem_info=$(free -m | grep Mem)
    
    local total
    local used
    total=$(echo "$mem_info" | awk '{print $2}')
    used=$(echo "$mem_info" | awk '{print $3}')
    
    # Calculate percentage
    local percentage
    percentage=$(echo "scale=2; $used * 100 / $total" | bc)
    
    # Format to 2 decimal places
    printf "%.2f" "$percentage"
}

# Function to get memory details
get_memory_details() {
    # Use free to get detailed memory information
    local mem_info
    mem_info=$(free -m | grep Mem)
    
    local total
    local used
    local free
    local shared
    local buffers
    local cached
    
    total=$(echo "$mem_info" | awk '{print $2}')
    used=$(echo "$mem_info" | awk '{print $3}')
    free=$(echo "$mem_info" | awk '{print $4}')
    shared=$(echo "$mem_info" | awk '{print $5}')
    buffers_cached=$(echo "$mem_info" | awk '{print $6}')
    
    echo "$total $used $free $shared $buffers_cached"
}

# Function to check if thresholds are exceeded
check_thresholds() {
    local cpu="$1"
    local mem="$2"
    
    if (( $(echo "$cpu >= $CPU_THRESHOLD" | bc -l) )); then
        return 0
    fi
    
    if (( $(echo "$mem >= $MEM_THRESHOLD" | bc -l) )); then
        return 0
    fi
    
    return 1
}

# Function to format output
format_output() {
    local timestamp="$1"
    local cpu="$2"
    local mem="$3"
    local mem_details="$4"
    
    # Parse memory details
    local mem_total
    local mem_used
    local mem_free
    local mem_shared
    local mem_buffers_cached
    
    read -r mem_total mem_used mem_free mem_shared mem_buffers_cached <<< "$mem_details"
    
    case "$FORMAT" in
        table)
            printf "%-20s %-10s %-10s %-10s %-10s %-10s %-10s %-10s\n" \
                "$timestamp" "$cpu%" "$mem%" "${mem_total}MB" "${mem_used}MB" "${mem_free}MB" "${mem_shared}MB" "${mem_buffers_cached}MB"
            ;;
        csv)
            printf "%s,%s,%s,%s,%s,%s,%s,%s\n" \
                "$timestamp" "$cpu" "$mem" "$mem_total" "$mem_used" "$mem_free" "$mem_shared" "$mem_buffers_cached"
            ;;
        json)
            printf '{"timestamp":"%s","cpu":%.2f,"memory":%.2f,"mem_total":%d,"mem_used":%d,"mem_free":%d,"mem_shared":%d,"mem_buffers_cached":%d}\n' \
                "$timestamp" "$cpu" "$mem" "$mem_total" "$mem_used" "$mem_free" "$mem_shared" "$mem_buffers_cached"
            ;;
    esac
}

# Function to print header
print_header() {
    if [ "$NO_HEADER" = true ]; then
        return
    fi
    
    case "$FORMAT" in
        table)
            printf "%-20s %-10s %-10s %-10s %-10s %-10s %-10s %-10s\n" \
                "TIMESTAMP" "CPU%" "MEM%" "TOTAL" "USED" "FREE" "SHARED" "BUFF/CACHE"
            printf "%-20s %-10s %-10s %-10s %-10s %-10s %-10s %-10s\n" \
                "--------------------" "----------" "----------" "----------" "----------" "----------" "----------" "----------"
            ;;
        csv)
            printf "%s,%s,%s,%s,%s,%s,%s,%s\n" \
                "timestamp" "cpu_percent" "mem_percent" "mem_total_mb" "mem_used_mb" "mem_free_mb" "mem_shared_mb" "mem_buffers_cached_mb"
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

# Main monitoring function
monitor() {
    local interval="$1"
    local count="$2"
    local iterations=0
    local json_first_item=true
    
    # Print header
    if [ -z "$OUTPUT_FILE" ]; then
        print_header
    elif [ "$APPEND" = false ] || [ ! -f "$OUTPUT_FILE" ]; then
        header=$(print_header)
        if [ -n "$header" ]; then
            echo "$header" > "$OUTPUT_FILE"
        fi
    fi
    
    while true; do
        # Get current timestamp
        local timestamp
        timestamp=$(date "+%Y-%m-%d %H:%M:%S")
        
        # Get CPU and memory usage
        local cpu_usage
        local mem_usage
        local mem_details
        
        cpu_usage=$(get_cpu_usage)
        mem_usage=$(get_memory_usage)
        mem_details=$(get_memory_details)
        
        # Check if thresholds are exceeded
        if [ "$QUIET" = false ] || check_thresholds "$cpu_usage" "$mem_usage"; then
            # Format output
            local output
            output=$(format_output "$timestamp" "$cpu_usage" "$mem_usage" "$mem_details")
            
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
                # Write to file or stdout
                if [ -n "$OUTPUT_FILE" ]; then
                    write_to_file "$output" "$OUTPUT_FILE" "$APPEND"
                else
                    echo "$output"
                fi
            fi
            
            # Log alerts if thresholds are exceeded
            if check_thresholds "$cpu_usage" "$mem_usage"; then
                if (( $(echo "$cpu_usage >= $CPU_THRESHOLD" | bc -l) )); then
                    log_warning "CPU usage alert: ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)"
                fi
                
                if (( $(echo "$mem_usage >= $MEM_THRESHOLD" | bc -l) )); then
                    log_warning "Memory usage alert: ${mem_usage}% (threshold: ${MEM_THRESHOLD}%)"
                fi
            fi
        fi
        
        # Increment iteration counter
        iterations=$((iterations + 1))
        
        # Check if we've reached the desired count
        if [ "$count" -gt 0 ] && [ "$iterations" -ge "$count" ]; then
            break
        fi
        
        # Sleep for the specified interval
        sleep "$interval"
    done
    
    # Print footer
    if [ "$FORMAT" = "json" ] && [ -z "$OUTPUT_FILE" ]; then
        echo
        echo ']'
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    check_requirements
    
    log_info "Starting CPU and memory monitoring"
    log_info "CPU threshold: ${CPU_THRESHOLD}%, Memory threshold: ${MEM_THRESHOLD}%"
    
    # Handle termination signal
    trap 'log_info "Monitoring stopped"; [ "$FORMAT" = "json" ] && [ -z "$OUTPUT_FILE" ] && echo -e "\n]"; exit 0' SIGINT SIGTERM
    
    # Start monitoring
    monitor "$INTERVAL" "$COUNT"
    
    log_success "Monitoring completed"
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi