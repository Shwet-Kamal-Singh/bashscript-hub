#!/bin/bash
#
# Script Name: check_dns_latency.sh
# Description: Check DNS resolution latency for domains across various nameservers
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./check_dns_latency.sh [options] <domain1> [domain2] [domain3] ...
#
# Options:
#   -n, --nameservers <list>    Comma-separated list of nameservers to use (default: system DNS)
#   -c, --count <number>        Number of queries per domain (default: 3)
#   -t, --timeout <seconds>     Timeout for each query in seconds (default: 2)
#   -w, --wait <ms>             Wait time between queries in milliseconds (default: 100)
#   -r, --record <type>         DNS record type to query (default: A)
#                               Supported types: A, AAAA, MX, NS, TXT, SOA, CNAME, PTR
#   -p, --public-resolvers      Use well-known public DNS resolvers (Cloudflare, Google, etc.)
#   -s, --sort <field>          Sort results by: name, server, min, avg, max, stdev (default: avg)
#   -f, --format <format>       Output format: table, csv, json (default: table)
#   -o, --output <file>         Save results to file
#   -q, --quiet                 Suppress progress information
#   -v, --verbose               Show detailed information for each query
#   -h, --help                  Display this help message
#
# Examples:
#   ./check_dns_latency.sh example.com
#   ./check_dns_latency.sh -n 8.8.8.8,1.1.1.1 -c 5 example.com github.com
#   ./check_dns_latency.sh -p -r MX -o dns_latency.csv -f csv gmail.com outlook.com
#
# Requirements:
#   - dig (part of the dnsutils package)
#   - bash 4.0+
#   - bc for floating-point arithmetic
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
NAMESERVERS=""
QUERY_COUNT=3
TIMEOUT=2
WAIT_TIME=100
RECORD_TYPE="A"
USE_PUBLIC_RESOLVERS=false
SORT_FIELD="avg"
OUTPUT_FORMAT="table"
OUTPUT_FILE=""
QUIET_MODE=false
VERBOSE_MODE=false
DOMAINS=()

# Well-known public DNS resolvers
PUBLIC_RESOLVERS=(
    "8.8.8.8:Google Public DNS"
    "8.8.4.4:Google Public DNS"
    "1.1.1.1:Cloudflare DNS"
    "1.0.0.1:Cloudflare DNS"
    "9.9.9.9:Quad9 DNS"
    "149.112.112.112:Quad9 DNS"
    "208.67.222.222:OpenDNS"
    "208.67.220.220:OpenDNS"
    "64.6.64.6:Verisign Public DNS"
    "64.6.65.6:Verisign Public DNS"
)

# Function to display usage
display_usage() {
    grep -E '^# (Script Name:|Description:|Usage:|Options:|Examples:|Requirements:)' "$0" | sed 's/^# //'
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--nameservers)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            NAMESERVERS="$2"
            shift 2
            ;;
        -c|--count)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
                log_error "Invalid count: $2"
                exit 1
            fi
            QUERY_COUNT="$2"
            shift 2
            ;;
        -t|--timeout)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
                log_error "Invalid timeout: $2"
                exit 1
            fi
            TIMEOUT="$2"
            shift 2
            ;;
        -w|--wait)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 0 ]; then
                log_error "Invalid wait time: $2"
                exit 1
            fi
            WAIT_TIME="$2"
            shift 2
            ;;
        -r|--record)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            # Convert to uppercase
            RECORD_TYPE="$(echo "$2" | tr '[:lower:]' '[:upper:]')"
            # Validate record type
            if [[ ! "$RECORD_TYPE" =~ ^(A|AAAA|MX|NS|TXT|SOA|CNAME|PTR)$ ]]; then
                log_error "Invalid record type: $2"
                log_error "Supported types: A, AAAA, MX, NS, TXT, SOA, CNAME, PTR"
                exit 1
            fi
            shift 2
            ;;
        -p|--public-resolvers)
            USE_PUBLIC_RESOLVERS=true
            shift
            ;;
        -s|--sort)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ ! "$2" =~ ^(name|server|min|avg|max|stdev)$ ]]; then
                log_error "Invalid sort field: $2"
                log_error "Supported fields: name, server, min, avg, max, stdev"
                exit 1
            fi
            SORT_FIELD="$2"
            shift 2
            ;;
        -f|--format)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ ! "$2" =~ ^(table|csv|json)$ ]]; then
                log_error "Invalid output format: $2"
                log_error "Supported formats: table, csv, json"
                exit 1
            fi
            OUTPUT_FORMAT="$2"
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
        -q|--quiet)
            QUIET_MODE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE_MODE=true
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
            DOMAINS+=("$1")
            shift
            ;;
    esac
done

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    # Check for dig command
    if ! command_exists "dig"; then
        log_error "The 'dig' command is required but not found"
        log_error "Please install the dnsutils package (or bind-utils on some systems)"
        exit 1
    fi
    
    # Check for bc (for floating-point arithmetic)
    if ! command_exists "bc"; then
        log_warning "The 'bc' command is not found. Some calculations may not work correctly."
    fi
    
    log_success "All prerequisites met"
}

# Function to validate domains
validate_domains() {
    print_section "Validating Domains"
    
    if [ ${#DOMAINS[@]} -eq 0 ]; then
        log_error "No domains specified"
        log_error "Usage: $0 [options] <domain1> [domain2] [domain3] ..."
        exit 1
    fi
    
    # Validate domain format
    for domain in "${DOMAINS[@]}"; do
        # Simple domain validation (allows IDNs and IPv4 for reverse lookups)
        if [[ ! "$domain" =~ ^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] && 
           [[ ! "$domain" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] &&
           [[ ! "$domain" =~ ^xn--[a-zA-Z0-9]+$ ]]; then
            log_warning "Domain may be invalid: $domain"
        fi
    done
    
    log_info "Processing ${#DOMAINS[@]} domain(s)"
}

# Function to get nameservers
get_nameservers() {
    print_section "Configuring Nameservers"
    
    # Array to store nameservers
    NAMESERVER_LIST=()
    
    # Use user-specified nameservers if provided
    if [ -n "$NAMESERVERS" ]; then
        IFS=',' read -ra NS_ARRAY <<< "$NAMESERVERS"
        for ns in "${NS_ARRAY[@]}"; do
            # Trim whitespace
            ns=$(echo "$ns" | xargs)
            # Add to list with a generic description
            NAMESERVER_LIST+=("$ns:User-specified nameserver")
        done
        log_info "Using ${#NAMESERVER_LIST[@]} user-specified nameserver(s)"
    fi
    
    # Add public resolvers if requested
    if [ "$USE_PUBLIC_RESOLVERS" = true ]; then
        for resolver in "${PUBLIC_RESOLVERS[@]}"; do
            NAMESERVER_LIST+=("$resolver")
        done
        log_info "Added ${#PUBLIC_RESOLVERS[@]} public resolvers"
    fi
    
    # If no nameservers specified, use system default
    if [ ${#NAMESERVER_LIST[@]} -eq 0 ]; then
        NAMESERVER_LIST+=("system:System default resolver")
        log_info "Using system default resolver"
    fi
}

# Function to query DNS and measure latency
query_dns() {
    local domain="$1"
    local nameserver="$2"
    local query_count="$3"
    local timeout="$4"
    local record_type="$5"
    
    # Array to store query times
    local -a query_times=()
    local ns_option=""
    
    # Add @ prefix if not using system resolver
    if [ "$nameserver" != "system" ]; then
        ns_option="@$nameserver"
    fi
    
    # Perform the queries
    for ((i=1; i<=query_count; i++)); do
        if [ "$VERBOSE_MODE" = true ] && [ "$QUIET_MODE" = false ]; then
            echo -n "Querying $domain ($record_type) on $nameserver (query $i/$query_count)... "
        elif [ "$QUIET_MODE" = false ]; then
            echo -n "."
        fi
        
        # Measure the query time using dig
        local result
        result=$(dig +tries=1 +time="$timeout" +stats "$ns_option" "$domain" "$record_type" 2>/dev/null)
        local status=$?
        
        # Check if dig was successful
        if [ $status -eq 0 ]; then
            # Extract query time from dig output
            local query_time
            query_time=$(echo "$result" | grep "Query time:" | awk '{print $4}')
            
            # Check if we got a valid query time
            if [ -n "$query_time" ]; then
                query_times+=("$query_time")
                
                if [ "$VERBOSE_MODE" = true ] && [ "$QUIET_MODE" = false ]; then
                    echo "${query_time}ms"
                fi
            else
                if [ "$VERBOSE_MODE" = true ] && [ "$QUIET_MODE" = false ]; then
                    echo "failed (no time information)"
                fi
            fi
        else
            if [ "$VERBOSE_MODE" = true ] && [ "$QUIET_MODE" = false ]; then
                echo "failed (dig error)"
            fi
        fi
        
        # Wait between queries if not the last one
        if [ "$i" -lt "$query_count" ] && [ "$WAIT_TIME" -gt 0 ]; then
            sleep "0.$(printf "%03d" "$WAIT_TIME")"
        fi
    done
    
    # Calculate statistics if we have results
    if [ ${#query_times[@]} -gt 0 ]; then
        # Calculate min, max, and average
        local min_time=9999
        local max_time=0
        local total_time=0
        
        for time in "${query_times[@]}"; do
            if [ "$time" -lt "$min_time" ]; then
                min_time=$time
            fi
            if [ "$time" -gt "$max_time" ]; then
                max_time=$time
            fi
            total_time=$((total_time + time))
        done
        
        local avg_time=0
        local stdev=0
        
        if [ ${#query_times[@]} -gt 0 ]; then
            # Calculate average with one decimal place
            if command_exists "bc"; then
                avg_time=$(echo "scale=1; $total_time / ${#query_times[@]}" | bc)
            else
                avg_time=$((total_time / ${#query_times[@]}))
            fi
            
            # Calculate standard deviation if bc is available
            if command_exists "bc" && [ ${#query_times[@]} -gt 1 ]; then
                local sum_squared_diff=0
                for time in "${query_times[@]}"; do
                    local diff
                    diff=$(echo "scale=1; $time - $avg_time" | bc)
                    local squared_diff
                    squared_diff=$(echo "$diff * $diff" | bc)
                    sum_squared_diff=$(echo "$sum_squared_diff + $squared_diff" | bc)
                done
                stdev=$(echo "scale=1; sqrt($sum_squared_diff / (${#query_times[@]} - 1))" | bc)
            fi
        fi
        
        # Show success rate
        local success_rate
        success_rate=$(echo "scale=1; ${#query_times[@]} * 100 / $query_count" | bc)
        
        echo "$domain,$nameserver,$min_time,$avg_time,$max_time,$stdev,$success_rate,${#query_times[@]},$query_count"
    else
        # No successful queries
        echo "$domain,$nameserver,0,0,0,0,0,0,$query_count"
    fi
}

# Function to initialize output file
initialize_output() {
    if [ -n "$OUTPUT_FILE" ]; then
        # Initialize file with appropriate header
        case "$OUTPUT_FORMAT" in
            "csv")
                echo "Domain,Nameserver,Min (ms),Avg (ms),Max (ms),StDev,Success Rate (%),Successful Queries,Total Queries" > "$OUTPUT_FILE"
                ;;
            "json")
                echo "{" > "$OUTPUT_FILE"
                echo "  \"query_information\": {" >> "$OUTPUT_FILE"
                echo "    \"timestamp\": \"$(date)\"," >> "$OUTPUT_FILE"
                echo "    \"domains\": ${#DOMAINS[@]}," >> "$OUTPUT_FILE"
                echo "    \"nameservers\": ${#NAMESERVER_LIST[@]}," >> "$OUTPUT_FILE"
                echo "    \"record_type\": \"$RECORD_TYPE\"," >> "$OUTPUT_FILE"
                echo "    \"queries_per_domain\": $QUERY_COUNT" >> "$OUTPUT_FILE"
                echo "  }," >> "$OUTPUT_FILE"
                echo "  \"results\": [" >> "$OUTPUT_FILE"
                ;;
            *)
                # For table format, we'll just create an empty file
                > "$OUTPUT_FILE"
                ;;
        esac
    fi
}

# Function to append to output file
append_to_output() {
    local line="$1"
    local format="$2"
    local file="$3"
    local first="$4"
    
    if [ -n "$file" ]; then
        # Parse the CSV line
        IFS=',' read -r domain nameserver min_time avg_time max_time stdev success_rate success_count total_count <<< "$line"
        
        case "$format" in
            "csv")
                echo "$line" >> "$file"
                ;;
            "json")
                # Add comma if not the first entry
                if [ "$first" = "false" ]; then
                    echo "," >> "$file"
                fi
                
                # Format JSON
                echo "    {" >> "$file"
                echo "      \"domain\": \"$domain\"," >> "$file"
                echo "      \"nameserver\": \"$nameserver\"," >> "$file"
                echo "      \"min_time_ms\": $min_time," >> "$file"
                echo "      \"avg_time_ms\": $avg_time," >> "$file"
                echo "      \"max_time_ms\": $max_time," >> "$file"
                echo "      \"standard_deviation\": $stdev," >> "$file"
                echo "      \"success_rate_percent\": $success_rate," >> "$file"
                echo "      \"successful_queries\": $success_count," >> "$file"
                echo "      \"total_queries\": $total_count" >> "$file"
                echo -n "    }" >> "$file"
                ;;
            *)
                # For table format, we'll handle at the end
                ;;
        esac
    fi
}

# Function to finalize output file
finalize_output() {
    if [ -n "$OUTPUT_FILE" ]; then
        case "$OUTPUT_FORMAT" in
            "json")
                echo -e "\n  ]\n}" >> "$OUTPUT_FILE"
                ;;
            "table")
                # Format table output
                (
                    echo "Domain,Nameserver,Min (ms),Avg (ms),Max (ms),StDev,Success Rate (%),Successful Queries,Total Queries"
                    cat /tmp/dns_latency_results_$$
                ) | column -t -s ',' > "$OUTPUT_FILE"
                ;;
        esac
        
        log_success "Results saved to $OUTPUT_FILE"
    fi
}

# Function to display results
display_results() {
    # Display table header
    if [ "$QUIET_MODE" = false ]; then
        print_section "DNS Query Results"
        printf "%-30s %-25s %10s %10s %10s %10s %15s %15s %15s\n" \
            "Domain" "Nameserver" "Min (ms)" "Avg (ms)" "Max (ms)" "StDev" "Success Rate" "Success/Total" "Provider"
        echo "-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
    fi
    
    # Sort the results based on the sort field
    local sort_option
    case "$SORT_FIELD" in
        "name") sort_option="-k1,1" ;;
        "server") sort_option="-k2,2" ;;
        "min") sort_option="-k3,3n" ;;
        "avg") sort_option="-k4,4n" ;;
        "max") sort_option="-k5,5n" ;;
        "stdev") sort_option="-k6,6n" ;;
        *) sort_option="-k4,4n" ;; # Default to avg
    esac
    
    # Process and display each line of results
    while IFS=',' read -r domain nameserver min_time avg_time max_time stdev success_rate success_count total_count; do
        # Skip header line
        if [ "$domain" = "Domain" ]; then
            continue
        fi
        
        # Extract nameserver provider if available
        local provider=""
        if [[ "$nameserver" == *":"* ]]; then
            IFS=':' read -ra NS_PARTS <<< "$nameserver"
            nameserver="${NS_PARTS[0]}"
            provider="${NS_PARTS[1]}"
        fi
        
        # Display the results in a nicely formatted table
        if [ "$QUIET_MODE" = false ]; then
            printf "%-30s %-25s %10s %10s %10s %10s %14s%% %7s/%-7s %15s\n" \
                "$domain" "$nameserver" "$min_time" "$avg_time" "$max_time" "$stdev" \
                "$success_rate" "$success_count" "$total_count" "$provider"
        fi
    done < <(sort "$sort_option" /tmp/dns_latency_results_$$)
    
    if [ "$QUIET_MODE" = false ]; then
        echo
    fi
}

# Main function
main() {
    print_header "DNS Latency Checker"
    
    # Check prerequisites
    check_prerequisites
    
    # Validate domains
    validate_domains
    
    # Get nameservers
    get_nameservers
    
    # Initialize temporary results file
    > /tmp/dns_latency_results_$$
    
    # Initialize output file
    initialize_output
    
    # Header for temporary results file
    echo "Domain,Nameserver,Min (ms),Avg (ms),Max (ms),StDev,Success Rate (%),Successful Queries,Total Queries" > /tmp/dns_latency_results_$$
    
    print_section "Running DNS Queries"
    
    # Track if this is the first result for JSON output
    local first_result=true
    
    # Total number of queries to perform
    local total_queries=$((${#DOMAINS[@]} * ${#NAMESERVER_LIST[@]}))
    local completed_queries=0
    
    # Query each domain on each nameserver
    for domain in "${DOMAINS[@]}"; do
        for nameserver_entry in "${NAMESERVER_LIST[@]}"; do
            # Extract nameserver from entry
            local nameserver="${nameserver_entry%%:*}"
            
            if [ "$QUIET_MODE" = false ]; then
                log_info "Querying $domain ($RECORD_TYPE) on $nameserver..."
            fi
            
            # Run the query and get results
            result=$(query_dns "$domain" "$nameserver" "$QUERY_COUNT" "$TIMEOUT" "$RECORD_TYPE")
            
            # Append to temporary file
            echo "$result" >> /tmp/dns_latency_results_$$
            
            # Append to output file
            if [ -n "$OUTPUT_FILE" ]; then
                local first_flag="false"
                if [ "$first_result" = "true" ]; then
                    first_flag="true"
                    first_result=false
                fi
                append_to_output "$result" "$OUTPUT_FORMAT" "$OUTPUT_FILE" "$first_flag"
            fi
            
            # Update progress
            completed_queries=$((completed_queries + 1))
            if [ "$QUIET_MODE" = false ] && [ "$VERBOSE_MODE" = false ]; then
                printf "\rProgress: %d/%d (%d%%)" "$completed_queries" "$total_queries" $((completed_queries * 100 / total_queries))
            fi
        done
    done
    
    # Clear progress line
    if [ "$QUIET_MODE" = false ] && [ "$VERBOSE_MODE" = false ]; then
        echo
    fi
    
    # Display results
    display_results
    
    # Finalize output file
    finalize_output
    
    # Clean up
    rm -f /tmp/dns_latency_results_$$
    
    log_success "DNS latency check completed"
}

# Run the main function
main