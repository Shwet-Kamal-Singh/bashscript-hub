#!/bin/bash
#
# Script Name: trace_route_logger.sh
# Description: Advanced traceroute utility with logging, geolocation and visualization
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./trace_route_logger.sh [options] <target>
#
# Options:
#   -c, --count <number>       Number of traces to perform (default: 1)
#   -i, --interval <seconds>   Time between traces in seconds (default: 0)
#   -4, --ipv4                 Force IPv4 traceroute
#   -6, --ipv6                 Force IPv6 traceroute
#   -m, --max-hops <number>    Maximum number of hops (default: 30)
#   -p, --port <port>          Destination port to use (default: 80)
#   -w, --wait <seconds>       Time to wait for response (default: 1)
#   -f, --first-hop <number>   Start from hop number (default: 1)
#   -g, --geo                  Show geolocation information for each hop
#   -r, --resolve              Resolve IP addresses to hostnames
#   -t, --timestamp            Add timestamp to each trace
#   -x, --export <format>      Export format: txt, csv, json (default: txt)
#   -o, --output <file>        Save results to file (default: stdout)
#   -l, --loop                 Keep running until interrupted
#   -d, --diff                 Show differences between traces
#   -a, --average              Show average RTT for each hop across traces
#   -v, --verbose              Show detailed information
#   -q, --quiet                Suppress progress information
#   -h, --help                 Display this help message
#
# Examples:
#   ./trace_route_logger.sh example.com
#   ./trace_route_logger.sh -c 5 -i 10 -g -o trace_log.csv -x csv google.com
#   ./trace_route_logger.sh -l -i 300 -t -g -x json -o trace_results.json -d 8.8.8.8
#
# Requirements:
#   - traceroute (or tracepath if not available)
#   - whois/dig (optional, for geolocation)
#   - jq (optional, for JSON processing)
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
TRACE_COUNT=1
TRACE_INTERVAL=0
IP_VERSION=""
MAX_HOPS=30
DEST_PORT=80
WAIT_TIME=1
FIRST_HOP=1
SHOW_GEO=false
RESOLVE_HOSTS=false
SHOW_TIMESTAMP=false
EXPORT_FORMAT="txt"
OUTPUT_FILE=""
LOOP_MODE=false
SHOW_DIFF=false
SHOW_AVERAGE=false
VERBOSE=false
QUIET=false
TARGET=""

# Function to display usage
display_usage() {
    grep -E '^# (Script Name:|Description:|Usage:|Options:|Examples:|Requirements:)' "$0" | sed 's/^# //'
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--count)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
                log_error "Invalid count: $2"
                exit 1
            fi
            TRACE_COUNT="$2"
            shift 2
            ;;
        -i|--interval)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 0 ]; then
                log_error "Invalid interval: $2"
                exit 1
            fi
            TRACE_INTERVAL="$2"
            shift 2
            ;;
        -4|--ipv4)
            IP_VERSION="-4"
            shift
            ;;
        -6|--ipv6)
            IP_VERSION="-6"
            shift
            ;;
        -m|--max-hops)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
                log_error "Invalid max hops: $2"
                exit 1
            fi
            MAX_HOPS="$2"
            shift 2
            ;;
        -p|--port)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ] || [ "$2" -gt 65535 ]; then
                log_error "Invalid port: $2"
                exit 1
            fi
            DEST_PORT="$2"
            shift 2
            ;;
        -w|--wait)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]] || [ "$(echo "$2 <= 0" | bc -l)" -eq 1 ]; then
                log_error "Invalid wait time: $2"
                exit 1
            fi
            WAIT_TIME="$2"
            shift 2
            ;;
        -f|--first-hop)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
                log_error "Invalid first hop: $2"
                exit 1
            fi
            FIRST_HOP="$2"
            shift 2
            ;;
        -g|--geo)
            SHOW_GEO=true
            shift
            ;;
        -r|--resolve)
            RESOLVE_HOSTS=true
            shift
            ;;
        -t|--timestamp)
            SHOW_TIMESTAMP=true
            shift
            ;;
        -x|--export)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ ! "$2" =~ ^(txt|csv|json)$ ]]; then
                log_error "Invalid export format: $2"
                log_error "Valid options: txt, csv, json"
                exit 1
            fi
            EXPORT_FORMAT="$2"
            shift 2
            ;;
        -o|--output)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -l|--loop)
            LOOP_MODE=true
            shift
            ;;
        -d|--diff)
            SHOW_DIFF=true
            shift
            ;;
        -a|--average)
            SHOW_AVERAGE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -h|--help)
            display_usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            log_error "Use --help to see available options"
            exit 1
            ;;
        *)
            if [ -z "$TARGET" ]; then
                TARGET="$1"
            else
                log_error "Multiple targets specified. Only one target is allowed."
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if target is specified
if [ -z "$TARGET" ]; then
    log_error "No target specified"
    log_error "Usage: $0 [options] <target>"
    exit 1
fi

# Check if necessary commands are available
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    # Check for traceroute
    local trace_cmd=""
    if command_exists "traceroute"; then
        trace_cmd="traceroute"
    elif command_exists "tracepath"; then
        trace_cmd="tracepath"
        log_warning "traceroute not found, using tracepath instead"
        log_warning "Some options may not be available with tracepath"
    else
        log_error "Neither traceroute nor tracepath command found"
        log_error "Please install traceroute package"
        exit 1
    fi
    
    # Check for geolocation dependencies if enabled
    if [ "$SHOW_GEO" = true ]; then
        if ! command_exists "whois" && ! command_exists "dig"; then
            log_warning "whois and dig commands not found"
            log_warning "Geolocation information may be limited"
        fi
    fi
    
    # Check for jq if using JSON format
    if [ "$EXPORT_FORMAT" = "json" ] && ! command_exists "jq"; then
        log_warning "jq command not found"
        log_warning "JSON output will use a simpler format"
    fi
    
    log_success "All required tools are available"
    
    # Return the trace command to use
    echo "$trace_cmd"
}

# Function to get timestamp
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Function to get geolocation info for an IP
get_geolocation() {
    local ip="$1"
    local geo_info=""
    
    # Skip for private IPs
    if [[ "$ip" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.) ]]; then
        echo "Private IP"
        return
    fi
    
    # Skip for localhost
    if [[ "$ip" =~ ^(127\.|::1) ]]; then
        echo "Localhost"
        return
    fi
    
    # Try whois first, it's usually faster
    if command_exists "whois"; then
        local country=$(whois "$ip" | grep -E "^country:|^Country:" | head -1 | awk '{print $NF}')
        local org=$(whois "$ip" | grep -E "^org-name:|^OrgName:|^Organization:" | head -1 | sed 's/.*: //')
        
        if [ -n "$country" ] || [ -n "$org" ]; then
            if [ -n "$country" ] && [ -n "$org" ]; then
                geo_info="$country / $org"
            elif [ -n "$country" ]; then
                geo_info="$country"
            elif [ -n "$org" ]; then
                geo_info="$org"
            fi
        fi
    fi
    
    # If whois failed or geo_info is still empty, try dig with DNS-based geolocation
    if [ -z "$geo_info" ] && command_exists "dig"; then
        # Reverse the IP and query against country code TXT record
        local reversed_ip=$(echo "$ip" | awk -F. '{print $4"."$3"."$2"."$1}')
        local country_code=$(dig +short txt "$reversed_ip.origin.asn.cymru.com" | grep -o "| [A-Z][A-Z] |" | tr -d ' |')
        
        if [ -n "$country_code" ]; then
            geo_info="$country_code"
        fi
    fi
    
    # Return whatever we've found or "Unknown"
    if [ -n "$geo_info" ]; then
        echo "$geo_info"
    else
        echo "Unknown"
    fi
}

# Function to resolve IP to hostname
resolve_ip() {
    local ip="$1"
    local hostname
    
    hostname=$(getent hosts "$ip" | awk '{print $2}')
    
    if [ -n "$hostname" ]; then
        echo "$hostname"
    else
        echo "$ip"
    fi
}

# Function to initialize output file
initialize_output() {
    local format="$1"
    local file="$2"
    local target="$3"
    local target_file
    
    # If no file specified, use stdout
    if [ -z "$file" ]; then
        target_file="/dev/stdout"
    else
        target_file="$file"
    fi
    
    # Create headers based on format
    case "$format" in
        "csv")
            # CSV header
            {
                echo -n "Timestamp,Trace #,Hop #,IP,Hostname,RTT1,RTT2,RTT3"
                if [ "$SHOW_GEO" = true ]; then
                    echo -n ",Geolocation"
                fi
                echo
            } > "$target_file"
            ;;
        "json")
            # JSON header
            {
                echo "{"
                echo "  \"target\": \"$target\","
                echo "  \"start_time\": \"$(get_timestamp)\","
                echo "  \"parameters\": {"
                echo "    \"count\": $TRACE_COUNT,"
                echo "    \"max_hops\": $MAX_HOPS,"
                echo "    \"first_hop\": $FIRST_HOP,"
                echo "    \"wait_time\": $WAIT_TIME,"
                echo "    \"port\": $DEST_PORT,"
                echo "    \"loop_mode\": $LOOP_MODE,"
                echo "    \"resolve_hosts\": $RESOLVE_HOSTS,"
                echo "    \"show_geo\": $SHOW_GEO"
                echo "  },"
                echo "  \"traces\": ["
            } > "$target_file"
            ;;
        "txt")
            # Text header
            {
                echo "=== Traceroute to $target ==="
                echo "Started at: $(get_timestamp)"
                echo "Parameters: max_hops=$MAX_HOPS, wait_time=$WAIT_TIME, port=$DEST_PORT"
                echo
            } > "$target_file"
            ;;
    esac
}

# Function to finalize output file
finalize_output() {
    local format="$1"
    local file="$2"
    local target_file
    
    # If no file specified, use stdout
    if [ -z "$file" ]; then
        target_file="/dev/stdout"
    else
        target_file="$file"
    fi
    
    # Add footer based on format
    case "$format" in
        "json")
            # Close the JSON structure
            {
                echo "  ],"
                echo "  \"end_time\": \"$(get_timestamp)\""
                echo "}"
            } >> "$target_file"
            ;;
        "txt")
            # Text footer
            {
                echo
                echo "Completed at: $(get_timestamp)"
            } >> "$target_file"
            ;;
        *)
            # No special footer for CSV
            ;;
    esac
    
    # Show success message if output is not to stdout
    if [ -n "$file" ] && [ "$QUIET" = false ]; then
        log_success "Results have been saved to $file"
    fi
}

# Function to convert traceroute output to structured data
parse_traceroute() {
    local trace_output="$1"
    local trace_number="$2"
    local structured_data=()
    local hop_data=""
    local current_hop=0
    
    # Parse line by line
    while IFS= read -r line; do
        # Skip empty lines and header lines
        if [ -z "$line" ] || [[ "$line" =~ ^traceroute|^tracepath ]]; then
            continue
        fi
        
        # Extract hop number
        if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]] ]]; then
            current_hop="${BASH_REMATCH[1]}"
            
            # Extract IP address and RTT values
            local ip=""
            local rtts=()
            
            # Handle different traceroute output formats
            
            # Format for traceroute with IP addresses in parentheses
            if [[ "$line" =~ \(([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\) ]]; then
                ip="${BASH_REMATCH[1]}"
                # Extract RTTs
                rtts=($(echo "$line" | grep -oE '[0-9]+\.[0-9]+ ms' | sed 's/ ms//g'))
            # Format for traceroute without hostnames
            elif [[ "$line" =~ [[:space:]]([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)[[:space:]] ]]; then
                ip="${BASH_REMATCH[1]}"
                # Extract RTTs
                rtts=($(echo "$line" | grep -oE '[0-9]+\.[0-9]+ ms' | sed 's/ ms//g'))
            # Format for tracepath
            elif [[ "$line" =~ [[:space:]]([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)[[:space:]].*[[:space:]]([0-9]+\.[0-9]+)ms ]]; then
                ip="${BASH_REMATCH[1]}"
                rtts=("${BASH_REMATCH[2]}")
            fi
            
            # Skip if no IP found (e.g., timeouts)
            if [ -z "$ip" ]; then
                continue
            fi
            
            # Resolve hostname if requested
            local hostname="$ip"
            if [ "$RESOLVE_HOSTS" = true ]; then
                hostname=$(resolve_ip "$ip")
            fi
            
            # Get geolocation if requested
            local geo=""
            if [ "$SHOW_GEO" = true ]; then
                geo=$(get_geolocation "$ip")
            fi
            
            # Ensure we have at least 3 RTT values (pad with empty strings if needed)
            while [ ${#rtts[@]} -lt 3 ]; do
                rtts+=("")
            done
            
            # Add to structured data
            hop_data="$trace_number,$current_hop,$ip,$hostname,${rtts[0]},${rtts[1]},${rtts[2]}"
            if [ "$SHOW_GEO" = true ]; then
                hop_data="$hop_data,$geo"
            fi
            
            structured_data+=("$hop_data")
        fi
    done <<< "$trace_output"
    
    # Return the structured data
    for data in "${structured_data[@]}"; do
        echo "$data"
    done
}

# Function to run a single traceroute
run_traceroute() {
    local target="$1"
    local trace_cmd="$2"
    local trace_number="$3"
    local tmpfile="/tmp/traceroute_${trace_number}_$$"
    local timestamp=""
    
    # Get timestamp if requested
    if [ "$SHOW_TIMESTAMP" = true ]; then
        timestamp=$(get_timestamp)
    fi
    
    # Inform user if not in quiet mode
    if [ "$QUIET" = false ]; then
        echo -n "Running trace #$trace_number to $target... "
    fi
    
    # Build the traceroute command based on the available command and options
    local cmd=""
    if [ "$trace_cmd" = "traceroute" ]; then
        cmd="$trace_cmd $IP_VERSION -m $MAX_HOPS -w $WAIT_TIME -p $DEST_PORT -f $FIRST_HOP $target"
    else
        # tracepath has fewer options
        cmd="$trace_cmd $IP_VERSION -m $MAX_HOPS $target"
    fi
    
    # Run the command and capture output
    $cmd > "$tmpfile" 2>/dev/null
    
    # Check if trace was successful
    if [ $? -ne 0 ]; then
        log_error "Failed to run traceroute to $target"
        rm -f "$tmpfile"
        return 1
    fi
    
    # Parse the traceroute output
    local structured_data
    structured_data=$(parse_traceroute "$(cat "$tmpfile")" "$trace_number")
    
    # Process and output the data based on format
    case "$EXPORT_FORMAT" in
        "csv")
            # Add timestamp if requested
            if [ "$SHOW_TIMESTAMP" = true ]; then
                # Prepend timestamp to each line
                while IFS= read -r line; do
                    echo "$timestamp,$line" >> "$OUTPUT_FILE"
                done <<< "$structured_data"
            else
                # Output directly
                echo "$structured_data" >> "$OUTPUT_FILE"
            fi
            ;;
        "json")
            # Start trace object
            {
                # Add comma if not the first trace
                if [ "$trace_number" -gt 1 ]; then
                    echo ","
                fi
                echo "    {"
                echo "      \"number\": $trace_number,"
                if [ "$SHOW_TIMESTAMP" = true ]; then
                    echo "      \"timestamp\": \"$timestamp\","
                fi
                echo "      \"hops\": ["
            } >> "$OUTPUT_FILE"
            
            # Process each hop
            local first_hop=true
            while IFS= read -r line; do
                # Skip empty lines
                if [ -z "$line" ]; then
                    continue
                fi
                
                # Parse the CSV-like data
                IFS=',' read -r _ hop_num ip hostname rtt1 rtt2 rtt3 geo <<< "$line"
                
                # Add comma if not the first hop
                if [ "$first_hop" = "false" ]; then
                    echo "," >> "$OUTPUT_FILE"
                else
                    first_hop=false
                fi
                
                # Output hop data as JSON
                {
                    echo "        {"
                    echo "          \"hop\": $hop_num,"
                    echo "          \"ip\": \"$ip\","
                    echo "          \"hostname\": \"$hostname\","
                    echo "          \"rtt\": [\"$rtt1\", \"$rtt2\", \"$rtt3\"]"
                    if [ "$SHOW_GEO" = true ]; then
                        echo "          ,\"geo\": \"$geo\""
                    fi
                    echo -n "        }"
                } >> "$OUTPUT_FILE"
            done <<< "$structured_data"
            
            # Close the hops array and trace object
            {
                echo ""
                echo "      ]"
                echo -n "    }"
            } >> "$OUTPUT_FILE"
            ;;
        "txt")
            # Output trace information
            {
                echo "Trace #$trace_number"
                if [ "$SHOW_TIMESTAMP" = true ]; then
                    echo "Time: $timestamp"
                fi
                echo "-----------------------------------------"
                echo "Hop | IP Address      | Hostname        | RTT (ms)      | Geo Info"
                echo "-----------------------------------------"
            } >> "$OUTPUT_FILE"
            
            # Process each hop
            while IFS= read -r line; do
                # Skip empty lines
                if [ -z "$line" ]; then
                    continue
                fi
                
                # Parse the CSV-like data
                IFS=',' read -r _ hop_num ip hostname rtt1 rtt2 rtt3 geo <<< "$line"
                
                # Format RTT values
                local rtt_formatted="$rtt1"
                if [ -n "$rtt2" ]; then
                    rtt_formatted="$rtt_formatted, $rtt2"
                fi
                if [ -n "$rtt3" ]; then
                    rtt_formatted="$rtt_formatted, $rtt3"
                fi
                
                # Output hop data as formatted text
                printf "%-3s | %-15s | %-15s | %-13s" "$hop_num" "$ip" "$hostname" "$rtt_formatted" >> "$OUTPUT_FILE"
                
                if [ "$SHOW_GEO" = true ]; then
                    printf " | %s" "$geo" >> "$OUTPUT_FILE"
                fi
                
                echo "" >> "$OUTPUT_FILE"
            done <<< "$structured_data"
            
            echo "-----------------------------------------" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            ;;
    esac
    
    # Clean up temporary file
    rm -f "$tmpfile"
    
    # Inform user if not in quiet mode
    if [ "$QUIET" = false ]; then
        echo "done"
    fi
    
    return 0
}

# Function to calculate and show average RTT
show_average_rtt() {
    local tmpfile="$1"
    local output_file="$2"
    
    # Parse the data to calculate averages
    awk -F, '
    {
        # Extract hop number, IP, hostname, and RTTs
        hop = $3;
        ip = $4;
        hostname = $5;
        
        # Count valid RTTs and sum them
        count = 0;
        sum = 0;
        
        # Process RTT1
        if ($6 != "") {
            count++;
            sum += $6;
        }
        
        # Process RTT2
        if ($7 != "") {
            count++;
            sum += $7;
        }
        
        # Process RTT3
        if ($8 != "") {
            count++;
            sum += $8;
        }
        
        # Calculate average if we have valid measurements
        if (count > 0) {
            avg = sum / count;
            
            # Store in arrays indexed by hop number
            hops[hop] = hop;
            ips[hop] = ip;
            hostnames[hop] = hostname;
            rtts[hop] = avg;
            counts[hop] = count;
        }
    }
    
    END {
        # Print header
        print "=== Average RTT per Hop ===";
        print "Hop | IP Address      | Hostname        | Avg RTT (ms)  | Samples";
        print "---------------------------------------------------------------------";
        
        # Print data for each hop in order
        for (i = 1; i <= 100; i++) {
            if (i in hops) {
                printf "%-3s | %-15s | %-15s | %-13.2f | %d\n", 
                    hops[i], ips[i], hostnames[i], rtts[i], counts[i];
            }
        }
    }
    ' "$tmpfile" > "$output_file"
}

# Function to compare traces and show differences
show_trace_diff() {
    local tmpfile="$1"
    local output_file="$2"
    
    # Parse the data to extract routes and detect changes
    awk -F, '
    {
        trace = $2;
        hop = $3;
        ip = $4;
        
        # Store the IP for each trace and hop
        routes[trace, hop] = ip;
        
        # Keep track of the max trace number and hop number
        if (trace > max_trace) max_trace = trace;
        if (hop > max_hop) max_hop = hop;
    }
    
    END {
        # Print header
        print "=== Route Changes Detected ===";
        print "Hop | Trace | IP Address      | Change Type";
        print "-----------------------------------------------";
        
        # Compare each hop across traces
        for (h = 1; h <= max_hop; h++) {
            prev_ip = "";
            
            for (t = 1; t <= max_trace; t++) {
                curr_ip = routes[t, h];
                
                # Skip if no data for this hop in this trace
                if (curr_ip == "") continue;
                
                # If first trace or different from previous trace
                if (prev_ip == "" || curr_ip != prev_ip) {
                    change_type = (prev_ip == "") ? "Initial" : "Changed";
                    printf "%-3s | %-5s | %-15s | %s", h, t, curr_ip, change_type;
                    if (prev_ip != "") {
                        printf " (from %s)", prev_ip;
                    }
                    print "";
                    
                    prev_ip = curr_ip;
                }
            }
        }
    }
    ' "$tmpfile" > "$output_file"
}

# Main function
main() {
    print_header "Traceroute Logger"
    
    # Check prerequisites and get trace command
    local trace_cmd
    trace_cmd=$(check_prerequisites)
    
    # Initialize output file
    initialize_output "$EXPORT_FORMAT" "$OUTPUT_FILE" "$TARGET"
    
    # Create temporary file for processing
    local tmp_data_file="/tmp/traceroute_data_$$"
    > "$tmp_data_file"
    
    # Perform traces
    local trace_count=1
    local loop_iteration=1
    
    while true; do
        # Run a single trace
        if run_traceroute "$TARGET" "$trace_cmd" "$trace_count"; then
            # In loop mode, reset trace count after reaching the specified count
            if [ "$LOOP_MODE" = true ] && [ "$trace_count" -ge "$TRACE_COUNT" ]; then
                trace_count=1
                loop_iteration=$((loop_iteration + 1))
                
                if [ "$QUIET" = false ]; then
                    echo "Completed loop iteration $loop_iteration"
                fi
            else
                trace_count=$((trace_count + 1))
            fi
        else
            log_error "Failed to complete trace #$trace_count"
            trace_count=$((trace_count + 1))
        fi
        
        # Break if not in loop mode and all traces are done
        if [ "$LOOP_MODE" = false ] && [ "$trace_count" -gt "$TRACE_COUNT" ]; then
            break
        fi
        
        # Wait for the specified interval
        if [ "$TRACE_INTERVAL" -gt 0 ]; then
            if [ "$QUIET" = false ]; then
                echo "Waiting $TRACE_INTERVAL seconds before next trace..."
            fi
            sleep "$TRACE_INTERVAL"
        fi
    done
    
    # Finalize output file
    finalize_output "$EXPORT_FORMAT" "$OUTPUT_FILE"
    
    # Show average RTT if requested
    if [ "$SHOW_AVERAGE" = true ]; then
        if [ -z "$OUTPUT_FILE" ]; then
            show_average_rtt "$tmp_data_file" "/dev/stdout"
        else
            show_average_rtt "$tmp_data_file" "${OUTPUT_FILE}.avg"
            if [ "$QUIET" = false ]; then
                log_success "Average RTT saved to ${OUTPUT_FILE}.avg"
            fi
        fi
    fi
    
    # Show differences between traces if requested
    if [ "$SHOW_DIFF" = true ] && [ "$TRACE_COUNT" -gt 1 ]; then
        if [ -z "$OUTPUT_FILE" ]; then
            show_trace_diff "$tmp_data_file" "/dev/stdout"
        else
            show_trace_diff "$tmp_data_file" "${OUTPUT_FILE}.diff"
            if [ "$QUIET" = false ]; then
                log_success "Trace differences saved to ${OUTPUT_FILE}.diff"
            fi
        fi
    fi
    
    # Clean up
    rm -f "$tmp_data_file"
    
    if [ "$QUIET" = false ]; then
        log_success "Traceroute logging completed"
    fi
}

# Run the main function
main