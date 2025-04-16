#!/bin/bash
#
# Script Name: bandwidth_usage_monitor.sh
# Description: Monitor network bandwidth usage across interfaces with customizable alerts
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./bandwidth_usage_monitor.sh [options]
#
# Options:
#   -i, --interface <name>    Network interface to monitor (default: all interfaces)
#   -t, --time <seconds>      Time interval between measurements (default: 1)
#   -a, --alert <Mbps>        Alert threshold in Mbps (default: no alert)
#   -s, --stat <rx|tx|both>   Statistics to show: rx (download), tx (upload), both (default: both)
#   -d, --duration <seconds>  Duration of monitoring in seconds (default: continuous)
#   -n, --no-color            Disable colored output
#   -l, --log <file>          Log measurements to file
#   -e, --email <address>     Send alerts to email address
#   -u, --unit <unit>         Display unit: bytes, KB, MB, GB (default: auto)
#   -b, --bar                 Show graphical bar display
#   -g, --graph               Create a graph of bandwidth usage (requires gnuplot)
#   -r, --report              Create a summary report at the end
#   -p, --peak                Track and show peak usage
#   -q, --quiet               Quiet mode (only output on alert or end)
#   -h, --help                Display this help message
#
# Examples:
#   ./bandwidth_usage_monitor.sh
#   ./bandwidth_usage_monitor.sh -i eth0 -t 5 -a 50 -l bandwidth.log
#   ./bandwidth_usage_monitor.sh -i wlan0 -d 3600 -r -p
#   ./bandwidth_usage_monitor.sh -s tx -b -g -u MB
#
# Requirements:
#   - Linux system with /proc/net/dev or ip/ifconfig command
#   - Optional: gnuplot (for graph generation)
#   - Optional: mail or sendmail (for email alerts)
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
INTERFACE=""
INTERVAL=1
ALERT_THRESHOLD=0  # 0 means no alert
STAT_TYPE="both"
DURATION=0  # 0 means continuous
USE_COLOR=true
LOG_FILE=""
EMAIL_ADDRESS=""
DISPLAY_UNIT="auto"
SHOW_BAR=false
CREATE_GRAPH=false
CREATE_REPORT=false
TRACK_PEAK=false
QUIET_MODE=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interface)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            INTERFACE="$2"
            shift 2
            ;;
        -t|--time)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
                log_error "Invalid time interval: $2"
                exit 1
            fi
            INTERVAL="$2"
            shift 2
            ;;
        -a|--alert)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [ "$(echo "$2 < 0" | bc)" -eq 1 ]; then
                log_error "Invalid alert threshold: $2"
                exit 1
            fi
            ALERT_THRESHOLD="$2"
            shift 2
            ;;
        -s|--stat)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "rx" && "$2" != "tx" && "$2" != "both" ]]; then
                log_error "Invalid stat type: $2"
                log_error "Valid options: rx, tx, both"
                exit 1
            fi
            STAT_TYPE="$2"
            shift 2
            ;;
        -d|--duration)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
                log_error "Invalid duration: $2"
                exit 1
            fi
            DURATION="$2"
            shift 2
            ;;
        -n|--no-color)
            USE_COLOR=false
            shift
            ;;
        -l|--log)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            LOG_FILE="$2"
            shift 2
            ;;
        -e|--email)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            EMAIL_ADDRESS="$2"
            shift 2
            ;;
        -u|--unit)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "bytes" && "$2" != "KB" && "$2" != "MB" && "$2" != "GB" && "$2" != "auto" ]]; then
                log_error "Invalid display unit: $2"
                log_error "Valid options: bytes, KB, MB, GB, auto"
                exit 1
            fi
            DISPLAY_UNIT="$2"
            shift 2
            ;;
        -b|--bar)
            SHOW_BAR=true
            shift
            ;;
        -g|--graph)
            CREATE_GRAPH=true
            shift
            ;;
        -r|--report)
            CREATE_REPORT=true
            shift
            ;;
        -p|--peak)
            TRACK_PEAK=true
            shift
            ;;
        -q|--quiet)
            QUIET_MODE=true
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

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to check prerequisites
check_prerequisites() {
    # Check if proc filesystem is available
    if [ ! -f "/proc/net/dev" ]; then
        if ! command_exists "ip" && ! command_exists "ifconfig"; then
            log_error "Neither /proc/net/dev nor ip/ifconfig commands are available"
            exit 1
        fi
    fi
    
    # Check for gnuplot if graph creation is requested
    if [ "$CREATE_GRAPH" = true ] && ! command_exists "gnuplot"; then
        log_warning "gnuplot is not installed but required for graph creation"
        log_warning "Graph creation will be disabled"
        CREATE_GRAPH=false
    fi
    
    # Check for email sending capability if email alerts are requested
    if [ -n "$EMAIL_ADDRESS" ]; then
        if ! command_exists "mail" && ! command_exists "sendmail"; then
            log_warning "mail and sendmail commands not found, email alerts will be disabled"
            EMAIL_ADDRESS=""
        fi
    fi
}

# Function to get available network interfaces
get_available_interfaces() {
    if [ -f "/proc/net/dev" ]; then
        grep -E "^ *[a-zA-Z0-9]+:" /proc/net/dev | cut -d: -f1 | sed 's/ //g'
    elif command_exists "ip"; then
        ip -o link show | awk -F': ' '{print $2}'
    elif command_exists "ifconfig"; then
        ifconfig | grep -E "^[a-zA-Z0-9]+" | awk '{print $1}'
    else
        log_error "Cannot determine available network interfaces"
        exit 1
    fi
}

# Function to validate interface
validate_interface() {
    local interface="$1"
    local available_interfaces
    
    available_interfaces=$(get_available_interfaces)
    
    if ! echo "$available_interfaces" | grep -q "^$interface$"; then
        log_error "Interface $interface not found"
        log_info "Available interfaces:"
        echo "$available_interfaces" | sed 's/^/- /'
        exit 1
    fi
}

# Function to get network statistics
get_network_stats() {
    local interface="$1"
    local stats_line
    
    if [ -f "/proc/net/dev" ]; then
        stats_line=$(grep "^ *$interface:" /proc/net/dev)
        rx_bytes=$(echo "$stats_line" | awk '{print $2}')
        tx_bytes=$(echo "$stats_line" | awk '{print $10}')
    elif command_exists "ip"; then
        rx_bytes=$(ip -s link show "$interface" | grep -A1 RX | tail -n1 | awk '{print $1}')
        tx_bytes=$(ip -s link show "$interface" | grep -A1 TX | tail -n1 | awk '{print $1}')
    elif command_exists "ifconfig"; then
        rx_bytes=$(ifconfig "$interface" | grep "RX bytes" | awk -F'[()]' '{print $2}' | awk '{print $1}')
        tx_bytes=$(ifconfig "$interface" | grep "TX bytes" | awk -F'[()]' '{print $2}' | awk '{print $1}')
    else
        rx_bytes=0
        tx_bytes=0
    fi
    
    echo "$rx_bytes $tx_bytes"
}

# Function to format bytes to human-readable format
format_bytes() {
    local bytes="$1"
    local unit="$2"
    local value
    
    if [ "$unit" = "auto" ]; then
        if [ "$bytes" -lt 1024 ]; then
            value="$bytes bytes"
        elif [ "$bytes" -lt 1048576 ]; then
            value=$(echo "scale=2; $bytes/1024" | bc)" KB"
        elif [ "$bytes" -lt 1073741824 ]; then
            value=$(echo "scale=2; $bytes/1048576" | bc)" MB"
        else
            value=$(echo "scale=2; $bytes/1073741824" | bc)" GB"
        fi
    else
        case "$unit" in
            "bytes")
                value="$bytes bytes"
                ;;
            "KB")
                value=$(echo "scale=2; $bytes/1024" | bc)" KB"
                ;;
            "MB")
                value=$(echo "scale=2; $bytes/1048576" | bc)" MB"
                ;;
            "GB")
                value=$(echo "scale=2; $bytes/1073741824" | bc)" GB"
                ;;
            *)
                value="$bytes bytes"
                ;;
        esac
    fi
    
    echo "$value"
}

# Function to calculate bytes per second
calculate_bps() {
    local prev_bytes="$1"
    local curr_bytes="$2"
    local interval="$3"
    
    echo "scale=2; ($curr_bytes - $prev_bytes) / $interval" | bc
}

# Function to convert bytes per second to Mbps
bps_to_mbps() {
    local bps="$1"
    
    echo "scale=2; $bps * 8 / 1000000" | bc
}

# Function to create a graphical bar
create_bar() {
    local value="$1"
    local max="$2"
    local width=50
    local bar_width
    
    if [ "$max" -eq 0 ]; then
        bar_width=0
    else
        bar_width=$(echo "scale=0; $value * $width / $max" | bc)
    fi
    
    if [ "$USE_COLOR" = true ]; then
        # Determine color based on percentage
        local percentage=$(echo "scale=2; $value * 100 / $max" | bc)
        
        if [ "$(echo "$percentage < 50" | bc)" -eq 1 ]; then
            echo -en "\033[32m" # Green
        elif [ "$(echo "$percentage < 85" | bc)" -eq 1 ]; then
            echo -en "\033[33m" # Yellow
        else
            echo -en "\033[31m" # Red
        fi
    fi
    
    # Print the bar
    printf "["
    for i in $(seq 1 "$bar_width"); do
        printf "#"
    done
    for i in $(seq 1 $((width - bar_width))); do
        printf " "
    done
    printf "]"
    
    if [ "$USE_COLOR" = true ]; then
        echo -en "\033[0m" # Reset color
    fi
}

# Function to send email alert
send_email_alert() {
    local interface="$1"
    local stat_type="$2"
    local value="$3"
    local threshold="$4"
    local unit="Mbps"
    
    local subject="Bandwidth Alert: $interface exceeded $threshold $unit"
    local body="Bandwidth usage alert for $interface:\n\n"
    body+="$stat_type bandwidth: $value $unit\n"
    body+="Threshold: $threshold $unit\n\n"
    body+="Time: $(date)\n"
    body+="Host: $(hostname)\n"
    
    if command_exists "mail"; then
        echo -e "$body" | mail -s "$subject" "$EMAIL_ADDRESS"
    elif command_exists "sendmail"; then
        echo -e "Subject: $subject\n\n$body" | sendmail "$EMAIL_ADDRESS"
    fi
}

# Function to initialize log file
initialize_log_file() {
    local log_file="$1"
    
    if [ -n "$log_file" ]; then
        echo "Timestamp,Interface,RX_bytes,TX_bytes,RX_bps,TX_bps,RX_Mbps,TX_Mbps" > "$log_file"
    fi
}

# Function to write to log file
write_to_log() {
    local log_file="$1"
    local timestamp="$2"
    local interface="$3"
    local rx_bytes="$4"
    local tx_bytes="$5"
    local rx_bps="$6"
    local tx_bps="$7"
    local rx_mbps="$8"
    local tx_mbps="$9"
    
    if [ -n "$log_file" ]; then
        echo "$timestamp,$interface,$rx_bytes,$tx_bytes,$rx_bps,$tx_bps,$rx_mbps,$tx_mbps" >> "$log_file"
    fi
}

# Function to generate graph using gnuplot
generate_graph() {
    local log_file="$1"
    local output_file="${log_file%.*}_graph.png"
    
    if [ ! -f "$log_file" ]; then
        log_error "Log file not found for graph generation"
        return
    fi
    
    # Create gnuplot script
    local gnuplot_script="/tmp/bandwidth_graph_$$.gp"
    cat > "$gnuplot_script" << EOF
set terminal png size 800,600
set output "$output_file"
set title "Network Bandwidth Usage"
set xlabel "Time"
set ylabel "Bandwidth (Mbps)"
set grid
set xdata time
set timefmt "%Y-%m-%d %H:%M:%S"
set format x "%H:%M:%S"
set key outside
plot "$log_file" using 1:7 with lines title "Download (Mbps)", \\
     "$log_file" using 1:8 with lines title "Upload (Mbps)"
EOF
    
    # Run gnuplot
    gnuplot "$gnuplot_script"
    
    # Clean up
    rm -f "$gnuplot_script"
    
    log_success "Graph generated: $output_file"
}

# Function to generate report
generate_report() {
    local duration="$1"
    local interface="$2"
    local total_rx_bytes="$3"
    local total_tx_bytes="$4"
    local avg_rx_mbps="$5"
    local avg_tx_mbps="$6"
    local peak_rx_mbps="$7"
    local peak_tx_mbps="$8"
    
    print_header "Bandwidth Usage Report"
    echo "Interface: $interface"
    echo "Duration: $duration seconds"
    echo ""
    echo "Total Download: $(format_bytes "$total_rx_bytes" "auto")"
    echo "Total Upload: $(format_bytes "$total_tx_bytes" "auto")"
    echo ""
    echo "Average Download: $avg_rx_mbps Mbps"
    echo "Average Upload: $avg_tx_mbps Mbps"
    echo ""
    
    if [ "$TRACK_PEAK" = true ]; then
        echo "Peak Download: $peak_rx_mbps Mbps"
        echo "Peak Upload: $peak_tx_mbps Mbps"
    fi
}

# Main function
main() {
    print_header "Bandwidth Usage Monitor"
    
    # Check prerequisites
    check_prerequisites
    
    # Get list of interfaces to monitor
    local interfaces_to_monitor
    if [ -n "$INTERFACE" ]; then
        validate_interface "$INTERFACE"
        interfaces_to_monitor="$INTERFACE"
    else
        interfaces_to_monitor=$(get_available_interfaces | grep -v "lo")
    fi
    
    # Initialize log file if specified
    if [ -n "$LOG_FILE" ]; then
        initialize_log_file "$LOG_FILE"
    fi
    
    # Print monitoring settings
    if [ "$QUIET_MODE" = false ]; then
        echo "Monitoring settings:"
        echo "- Interfaces: ${interfaces_to_monitor:-All}"
        echo "- Interval: $INTERVAL seconds"
        
        if [ "$ALERT_THRESHOLD" -gt 0 ]; then
            echo "- Alert threshold: $ALERT_THRESHOLD Mbps"
        else
            echo "- Alert threshold: Disabled"
        fi
        
        echo "- Statistics type: $STAT_TYPE"
        
        if [ "$DURATION" -gt 0 ]; then
            echo "- Duration: $DURATION seconds"
        else
            echo "- Duration: Continuous"
        fi
        
        echo "- Display unit: $DISPLAY_UNIT"
        echo ""
    fi
    
    # Initialize variables
    local start_time
    local elapsed_time=0
    local total_rx_bytes=0
    local total_tx_bytes=0
    local peak_rx_mbps=0
    local peak_tx_mbps=0
    local iterations=0
    
    # Print table header
    if [ "$QUIET_MODE" = false ]; then
        printf "%-12s | %-15s | %-15s | %-15s | %-15s " "Time" "Interface" "Download" "Upload" "Total"
        
        if [ "$SHOW_BAR" = true ]; then
            printf "| %-52s " "Download Bar"
        fi
        
        printf "\n"
        printf -- "%-12s-|-%-15s-|-%-15s-|-%-15s-|-%-15s" \
            "------------" "---------------" "---------------" "---------------" "---------------"
        
        if [ "$SHOW_BAR" = true ]; then
            printf "-|-%-52s" "--------------------------------------------------"
        fi
        
        printf "\n"
    fi
    
    # Get initial statistics
    local interface_stats=()
    for interface in $interfaces_to_monitor; do
        local stats
        stats=$(get_network_stats "$interface")
        interface_stats["$interface"]="$stats"
    done
    
    # Start time measurement
    start_time=$(date +%s)
    
    # Monitoring loop
    while true; do
        # Sleep for the specified interval
        sleep "$INTERVAL"
        
        # Current timestamp for logging
        local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        local current_time=$(date +"%H:%M:%S")
        
        # Update elapsed time
        elapsed_time=$(($(date +%s) - start_time))
        iterations=$((iterations + 1))
        
        # Process each interface
        for interface in $interfaces_to_monitor; do
            # Get previous stats
            local prev_stats="${interface_stats[$interface]}"
            local prev_rx_bytes=$(echo "$prev_stats" | awk '{print $1}')
            local prev_tx_bytes=$(echo "$prev_stats" | awk '{print $2}')
            
            # Get current stats
            local curr_stats
            curr_stats=$(get_network_stats "$interface")
            local curr_rx_bytes=$(echo "$curr_stats" | awk '{print $1}')
            local curr_tx_bytes=$(echo "$curr_stats" | awk '{print $2}')
            
            # Store current stats for next iteration
            interface_stats["$interface"]="$curr_stats"
            
            # Calculate bandwidth
            local rx_bytes_diff=$((curr_rx_bytes - prev_rx_bytes))
            local tx_bytes_diff=$((curr_tx_bytes - prev_tx_bytes))
            
            # Update totals
            total_rx_bytes=$((total_rx_bytes + rx_bytes_diff))
            total_tx_bytes=$((total_tx_bytes + tx_bytes_diff))
            
            # Calculate bytes per second
            local rx_bps
            local tx_bps
            rx_bps=$(calculate_bps "$prev_rx_bytes" "$curr_rx_bytes" "$INTERVAL")
            tx_bps=$(calculate_bps "$prev_tx_bytes" "$curr_tx_bytes" "$INTERVAL")
            
            # Convert to Mbps
            local rx_mbps
            local tx_mbps
            rx_mbps=$(bps_to_mbps "$rx_bps")
            tx_mbps=$(bps_to_mbps "$tx_bps")
            
            # Update peak values if tracking
            if [ "$TRACK_PEAK" = true ]; then
                if [ "$(echo "$rx_mbps > $peak_rx_mbps" | bc)" -eq 1 ]; then
                    peak_rx_mbps=$rx_mbps
                fi
                
                if [ "$(echo "$tx_mbps > $peak_tx_mbps" | bc)" -eq 1 ]; then
                    peak_tx_mbps=$tx_mbps
                fi
            fi
            
            # Write to log file if specified
            if [ -n "$LOG_FILE" ]; then
                write_to_log "$LOG_FILE" "$timestamp" "$interface" "$curr_rx_bytes" "$curr_tx_bytes" "$rx_bps" "$tx_bps" "$rx_mbps" "$tx_mbps"
            fi
            
            # Check for alerts
            if [ "$ALERT_THRESHOLD" -gt 0 ]; then
                if [ "$STAT_TYPE" = "rx" ] || [ "$STAT_TYPE" = "both" ]; then
                    if [ "$(echo "$rx_mbps > $ALERT_THRESHOLD" | bc)" -eq 1 ]; then
                        if [ "$USE_COLOR" = true ]; then
                            log_error "Alert: Download bandwidth on $interface exceeded threshold: $rx_mbps Mbps > $ALERT_THRESHOLD Mbps"
                        else
                            echo "Alert: Download bandwidth on $interface exceeded threshold: $rx_mbps Mbps > $ALERT_THRESHOLD Mbps"
                        fi
                        
                        # Send email alert if configured
                        if [ -n "$EMAIL_ADDRESS" ]; then
                            send_email_alert "$interface" "Download" "$rx_mbps" "$ALERT_THRESHOLD"
                        fi
                    fi
                fi
                
                if [ "$STAT_TYPE" = "tx" ] || [ "$STAT_TYPE" = "both" ]; then
                    if [ "$(echo "$tx_mbps > $ALERT_THRESHOLD" | bc)" -eq 1 ]; then
                        if [ "$USE_COLOR" = true ]; then
                            log_error "Alert: Upload bandwidth on $interface exceeded threshold: $tx_mbps Mbps > $ALERT_THRESHOLD Mbps"
                        else
                            echo "Alert: Upload bandwidth on $interface exceeded threshold: $tx_mbps Mbps > $ALERT_THRESHOLD Mbps"
                        fi
                        
                        # Send email alert if configured
                        if [ -n "$EMAIL_ADDRESS" ]; then
                            send_email_alert "$interface" "Upload" "$tx_mbps" "$ALERT_THRESHOLD"
                        fi
                    fi
                fi
            fi
            
            # Display bandwidth information
            if [ "$QUIET_MODE" = false ]; then
                # Format bytes based on settings
                local rx_formatted
                local tx_formatted
                local total_formatted
                
                if [ "$DISPLAY_UNIT" = "auto" ]; then
                    rx_formatted=$(echo "$rx_mbps Mbps")
                    tx_formatted=$(echo "$tx_mbps Mbps")
                    total_formatted=$(echo "$(echo "$rx_mbps + $tx_mbps" | bc) Mbps")
                else
                    rx_formatted=$(format_bytes "$rx_bps" "$DISPLAY_UNIT")/s
                    tx_formatted=$(format_bytes "$tx_bps" "$DISPLAY_UNIT")/s
                    total_formatted=$(format_bytes "$(echo "$rx_bps + $tx_bps" | bc)" "$DISPLAY_UNIT")/s
                fi
                
                # Only show requested stat types
                if [ "$STAT_TYPE" = "rx" ]; then
                    tx_formatted="-"
                elif [ "$STAT_TYPE" = "tx" ]; then
                    rx_formatted="-"
                fi
                
                # Display the information
                printf "%-12s | %-15s | %-15s | %-15s | %-15s " "$current_time" "$interface" "$rx_formatted" "$tx_formatted" "$total_formatted"
                
                # Show bar graph if requested
                if [ "$SHOW_BAR" = true ]; then
                    # Calculate maximum bandwidth for bar scale (auto-adjusting)
                    local max_mbps
                    if [ "$(echo "$rx_mbps > $tx_mbps" | bc)" -eq 1 ]; then
                        max_mbps=$rx_mbps
                    else
                        max_mbps=$tx_mbps
                    fi
                    
                    # Ensure minimum scale for bar
                    if [ "$(echo "$max_mbps < 1" | bc)" -eq 1 ]; then
                        max_mbps=1
                    fi
                    
                    # Round up to next multiple of 10
                    max_mbps=$(echo "scale=0; ($max_mbps + 9) / 10 * 10" | bc)
                    
                    # Create the bar
                    printf "| "
                    create_bar "$(echo "$rx_mbps" | bc)" "$max_mbps"
                    printf " "
                fi
                
                printf "\n"
            fi
        done
        
        # Check if monitoring duration has been reached
        if [ "$DURATION" -gt 0 ] && [ "$elapsed_time" -ge "$DURATION" ]; then
            break
        fi
    done
    
    # Generate report if requested
    if [ "$CREATE_REPORT" = true ]; then
        local avg_rx_mbps
        local avg_tx_mbps
        
        if [ "$iterations" -gt 0 ]; then
            avg_rx_mbps=$(echo "scale=2; $total_rx_bytes * 8 / 1000000 / $elapsed_time" | bc)
            avg_tx_mbps=$(echo "scale=2; $total_tx_bytes * 8 / 1000000 / $elapsed_time" | bc)
        else
            avg_rx_mbps=0
            avg_tx_mbps=0
        fi
        
        generate_report "$elapsed_time" "$INTERFACE" "$total_rx_bytes" "$total_tx_bytes" "$avg_rx_mbps" "$avg_tx_mbps" "$peak_rx_mbps" "$peak_tx_mbps"
    fi
    
    # Generate graph if requested
    if [ "$CREATE_GRAPH" = true ] && [ -n "$LOG_FILE" ]; then
        generate_graph "$LOG_FILE"
    fi
}

# Run the main function
main