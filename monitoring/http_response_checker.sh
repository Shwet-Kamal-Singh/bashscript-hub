#!/bin/bash
#
# http_response_checker.sh - Check HTTP response status and performance
#
# This script checks HTTP/HTTPS endpoints for response status, response time,
# and optionally validates response content. It can be used for monitoring
# websites, APIs, and web services with support for alerting on failures.
#
# Usage:
#   ./http_response_checker.sh [options] <url>...
#
# Options:
#   -m, --method <method>        HTTP method (GET, POST, etc.; default: GET)
#   -d, --data <data>            Request data for POST/PUT requests
#   -H, --header <header>        HTTP header (can be used multiple times)
#   -u, --user <username:password> Basic authentication
#   -t, --timeout <seconds>      Connection timeout (default: 10)
#   -r, --retries <number>       Number of retries on failure (default: 1)
#   -e, --expect <status>        Expected HTTP status code (default: 200)
#   -p, --pattern <regex>        Pattern to search for in response body
#   -i, --insecure               Ignore SSL certificate errors
#   -c, --connect-time <seconds> Maximum acceptable connect time (for alerts)
#   -s, --time <seconds>         Maximum acceptable response time (for alerts)
#   -o, --output <file>          Write results to file
#   -a, --append                 Append to output file instead of overwriting
#   -f, --format <format>        Output format (text, csv, json; default: text)
#   -q, --quiet                  Only output failures
#   -v, --verbose                Display detailed output
#   -h, --help                   Display this help message
#
# Requirements:
#   - curl or wget for HTTP requests
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
METHOD="GET"
DATA=""
HEADERS=()
BASIC_AUTH=""
TIMEOUT=10
RETRIES=1
EXPECTED_STATUS=200
PATTERN=""
INSECURE=false
MAX_CONNECT_TIME=0
MAX_RESPONSE_TIME=0
OUTPUT_FILE=""
APPEND=false
FORMAT="text"
QUIET=false
VERBOSE=false
URLS=()

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options] <url>..."
    echo ""
    echo "Check HTTP response status and performance."
    echo ""
    echo "Options:"
    echo "  -m, --method <method>        HTTP method (GET, POST, etc.; default: GET)"
    echo "  -d, --data <data>            Request data for POST/PUT requests"
    echo "  -H, --header <header>        HTTP header (can be used multiple times)"
    echo "  -u, --user <username:password> Basic authentication"
    echo "  -t, --timeout <seconds>      Connection timeout (default: 10)"
    echo "  -r, --retries <number>       Number of retries on failure (default: 1)"
    echo "  -e, --expect <status>        Expected HTTP status code (default: 200)"
    echo "  -p, --pattern <regex>        Pattern to search for in response body"
    echo "  -i, --insecure               Ignore SSL certificate errors"
    echo "  -c, --connect-time <seconds> Maximum acceptable connect time (for alerts)"
    echo "  -s, --time <seconds>         Maximum acceptable response time (for alerts)"
    echo "  -o, --output <file>          Write results to file"
    echo "  -a, --append                 Append to output file instead of overwriting"
    echo "  -f, --format <format>        Output format (text, csv, json; default: text)"
    echo "  -q, --quiet                  Only output failures"
    echo "  -v, --verbose                Display detailed output"
    echo "  -h, --help                   Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") https://example.com"
    echo "  $(basename "$0") -e 200,301,302 -t 5 -r 3 https://api.example.com/health"
    echo "  $(basename "$0") -m POST -d '{\"key\":\"value\"}' -H 'Content-Type: application/json' https://api.example.com/data"
    echo "  $(basename "$0") -p 'Welcome' -c 1 -s 2 -f json https://example.com https://example.org"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -m|--method)
                METHOD="$2"
                # Validate HTTP method
                case "${METHOD^^}" in
                    GET|POST|PUT|DELETE|HEAD|OPTIONS|PATCH)
                        METHOD="${METHOD^^}"
                        ;;
                    *)
                        log_error "Invalid HTTP method: $METHOD"
                        log_error "Valid methods: GET, POST, PUT, DELETE, HEAD, OPTIONS, PATCH"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -d|--data)
                DATA="$2"
                shift 2
                ;;
            -H|--header)
                HEADERS+=("$2")
                shift 2
                ;;
            -u|--user)
                BASIC_AUTH="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -lt 1 ]; then
                    log_error "Timeout must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -r|--retries)
                RETRIES="$2"
                if ! [[ "$RETRIES" =~ ^[0-9]+$ ]]; then
                    log_error "Retries must be a non-negative integer"
                    exit 1
                fi
                shift 2
                ;;
            -e|--expect)
                EXPECTED_STATUS="$2"
                # Validate status codes (allow comma-separated list)
                if ! [[ "$EXPECTED_STATUS" =~ ^[0-9,]+$ ]]; then
                    log_error "Expected status must be a number or comma-separated list of numbers"
                    exit 1
                fi
                shift 2
                ;;
            -p|--pattern)
                PATTERN="$2"
                shift 2
                ;;
            -i|--insecure)
                INSECURE=true
                shift
                ;;
            -c|--connect-time)
                MAX_CONNECT_TIME="$2"
                if ! [[ "$MAX_CONNECT_TIME" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( $(echo "$MAX_CONNECT_TIME <= 0" | bc -l) )); then
                    log_error "Connect time must be a positive number"
                    exit 1
                fi
                shift 2
                ;;
            -s|--time)
                MAX_RESPONSE_TIME="$2"
                if ! [[ "$MAX_RESPONSE_TIME" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( $(echo "$MAX_RESPONSE_TIME <= 0" | bc -l) )); then
                    log_error "Response time must be a positive number"
                    exit 1
                fi
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
                # Assume argument is a URL
                URLS+=("$1")
                shift
                ;;
        esac
    done
    
    # Validate required arguments
    if [ ${#URLS[@]} -eq 0 ]; then
        log_error "At least one URL must be provided"
        show_usage
        exit 1
    fi
    
    # Validate URLs
    for url in "${URLS[@]}"; do
        if [[ ! "$url" =~ ^https?:// ]]; then
            log_warning "URL '$url' does not start with http:// or https://"
            log_warning "Adding http:// prefix"
            URLS["${#URLS[@]}"]=http://$url
        fi
    done
}

# Function to check for required commands
check_requirements() {
    # Check if curl or wget is available
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        log_error "Neither curl nor wget is available"
        log_error "Please install curl or wget for your distribution:"
        log_error "  - Debian/Ubuntu: sudo apt-get install curl"
        log_error "  - RHEL/CentOS: sudo yum install curl"
        log_error "  - Fedora: sudo dnf install curl"
        exit 1
    fi
    
    # Check for other required utilities
    local missing_cmds=()
    for cmd in grep awk; do
        if ! command -v $cmd &>/dev/null; then
            missing_cmds+=("$cmd")
        fi
    done
    
    if [ ${#missing_cmds[@]} -gt 0 ]; then
        log_error "Missing required commands: ${missing_cmds[*]}"
        log_error "Please install the required packages for your distribution:"
        log_error "  - Debian/Ubuntu: sudo apt-get install grep gawk"
        log_error "  - RHEL/CentOS: sudo yum install grep gawk"
        log_error "  - Fedora: sudo dnf install grep gawk"
        exit 1
    fi
    
    # Check for bc (used for floating point comparison)
    if [ "$MAX_CONNECT_TIME" != "0" ] || [ "$MAX_RESPONSE_TIME" != "0" ]; then
        if ! command -v bc &>/dev/null; then
            log_error "Timing checks require 'bc' for calculations, but it's not installed"
            log_error "Please install bc for your distribution:"
            log_error "  - Debian/Ubuntu: sudo apt-get install bc"
            log_error "  - RHEL/CentOS: sudo yum install bc"
            log_error "  - Fedora: sudo dnf install bc"
            exit 1
        fi
    fi
}

# Function to build curl command
build_curl_command() {
    local url="$1"
    local output_file="$2"
    
    if ! command -v curl &>/dev/null; then
        return 1
    fi
    
    local cmd="curl -s -o \"$output_file\" -w \"%{http_code} %{time_connect} %{time_total}\" -X $METHOD"
    
    # Add timeout
    cmd+=" --connect-timeout $TIMEOUT --max-time $((TIMEOUT * 2))"
    
    # Add retries
    if [ "$RETRIES" -gt 0 ]; then
        cmd+=" --retry $RETRIES"
    fi
    
    # Add basic auth if specified
    if [ -n "$BASIC_AUTH" ]; then
        cmd+=" -u \"$BASIC_AUTH\""
    fi
    
    # Add headers
    for header in "${HEADERS[@]}"; do
        cmd+=" -H \"$header\""
    fi
    
    # Add data if specified
    if [ -n "$DATA" ]; then
        cmd+=" -d \"$DATA\""
    fi
    
    # Add insecure flag if specified
    if [ "$INSECURE" = true ]; then
        cmd+=" -k"
    fi
    
    # Add URL
    cmd+=" \"$url\""
    
    echo "$cmd"
}

# Function to build wget command
build_wget_command() {
    local url="$1"
    local output_file="$2"
    
    if ! command -v wget &>/dev/null; then
        return 1
    fi
    
    local cmd="wget -q -O \"$output_file\" --server-response"
    
    # Add timeout
    cmd+=" --timeout=$TIMEOUT"
    
    # Add retries
    if [ "$RETRIES" -gt 0 ]; then
        cmd+=" --tries=$((RETRIES + 1))"
    fi
    
    # Add basic auth if specified
    if [ -n "$BASIC_AUTH" ]; then
        cmd+=" --http-user=\"${BASIC_AUTH%%:*}\" --http-password=\"${BASIC_AUTH#*:}\""
    fi
    
    # Add headers
    for header in "${HEADERS[@]}"; do
        cmd+=" --header=\"$header\""
    fi
    
    # Add method and data if specified
    if [ "$METHOD" != "GET" ]; then
        cmd+=" --method=$METHOD"
        
        if [ -n "$DATA" ]; then
            cmd+=" --body-data=\"$DATA\""
        fi
    fi
    
    # Add insecure flag if specified
    if [ "$INSECURE" = true ]; then
        cmd+=" --no-check-certificate"
    fi
    
    # Add URL
    cmd+=" \"$url\" 2>&1"
    
    echo "$cmd"
}

# Function to check HTTP response using curl
check_with_curl() {
    local url="$1"
    local temp_file
    temp_file=$(mktemp)
    
    local curl_cmd
    curl_cmd=$(build_curl_command "$url" "$temp_file")
    
    if [ "$VERBOSE" = true ]; then
        log_debug "Executing: $curl_cmd"
    fi
    
    # Execute curl command
    local response
    response=$(eval "$curl_cmd")
    local exit_code=$?
    
    # Parse response
    local status_code
    local connect_time
    local total_time
    
    read -r status_code connect_time total_time <<< "$response"
    
    # Check for pattern in response if specified
    local pattern_match=false
    if [ -n "$PATTERN" ] && grep -q "$PATTERN" "$temp_file"; then
        pattern_match=true
    fi
    
    # Clean up temp file
    rm -f "$temp_file"
    
    # Return results
    echo "$status_code $connect_time $total_time $pattern_match $exit_code"
}

# Function to check HTTP response using wget
check_with_wget() {
    local url="$1"
    local temp_file
    temp_file=$(mktemp)
    local headers_file
    headers_file=$(mktemp)
    
    local wget_cmd
    wget_cmd=$(build_wget_command "$url" "$temp_file")
    
    if [ "$VERBOSE" = true ]; then
        log_debug "Executing: $wget_cmd"
    fi
    
    # Execute wget command
    local response
    response=$(eval "$wget_cmd" 2> "$headers_file")
    local exit_code=$?
    
    # Parse response for status code
    local status_code
    status_code=$(grep -i "HTTP/" "$headers_file" | tail -n1 | awk '{print $2}')
    
    # Wget doesn't provide timing info, so use default values
    local connect_time="0.0"
    local total_time="0.0"
    
    # Check for pattern in response if specified
    local pattern_match=false
    if [ -n "$PATTERN" ] && grep -q "$PATTERN" "$temp_file"; then
        pattern_match=true
    fi
    
    # Clean up temp files
    rm -f "$temp_file" "$headers_file"
    
    # Return results
    echo "$status_code $connect_time $total_time $pattern_match $exit_code"
}

# Function to check HTTP response
check_http_response() {
    local url="$1"
    
    log_info "Checking URL: $url"
    
    # Try curl first, fallback to wget
    local result
    if command -v curl &>/dev/null; then
        result=$(check_with_curl "$url")
    else
        result=$(check_with_wget "$url")
    fi
    
    # Parse result
    local status_code
    local connect_time
    local total_time
    local pattern_match
    local exit_code
    
    read -r status_code connect_time total_time pattern_match exit_code <<< "$result"
    
    # Handle command failure
    if [ "$exit_code" -ne 0 ]; then
        log_error "Failed to connect to $url (exit code: $exit_code)"
        echo "ERROR" "$connect_time" "$total_time" false "$exit_code"
        return
    fi
    
    # Check status code against expected codes
    local status_ok=false
    IFS=',' read -ra EXPECTED_CODES <<< "$EXPECTED_STATUS"
    for code in "${EXPECTED_CODES[@]}"; do
        if [ "$status_code" = "$code" ]; then
            status_ok=true
            break
        fi
    done
    
    # Check pattern match if specified
    local pattern_ok=true
    if [ -n "$PATTERN" ] && [ "$pattern_match" != "true" ]; then
        pattern_ok=false
    fi
    
    # Check timing if specified
    local timing_ok=true
    if [ "$MAX_CONNECT_TIME" != "0" ] && (( $(echo "$connect_time > $MAX_CONNECT_TIME" | bc -l) )); then
        timing_ok=false
    fi
    
    if [ "$MAX_RESPONSE_TIME" != "0" ] && (( $(echo "$total_time > $MAX_RESPONSE_TIME" | bc -l) )); then
        timing_ok=false
    fi
    
    # Determine overall status
    local overall_status
    if [ "$status_ok" = true ] && [ "$pattern_ok" = true ] && [ "$timing_ok" = true ]; then
        overall_status="OK"
    else
        overall_status="FAIL"
    fi
    
    # Return result
    echo "$status_code" "$connect_time" "$total_time" "$pattern_match" "$overall_status"
}

# Function to format output
format_output() {
    local timestamp="$1"
    local url="$2"
    local status_code="$3"
    local connect_time="$4"
    local total_time="$5"
    local pattern_match="$6"
    local overall_status="$7"
    
    case "$FORMAT" in
        text)
            printf "%-20s %-50s %-10s %-15s %-15s %-15s %-10s\n" \
                "$timestamp" "$url" "$status_code" "${connect_time}s" "${total_time}s" "$pattern_match" "$overall_status"
            ;;
        csv)
            printf "%s,%s,%s,%s,%s,%s,%s\n" \
                "$timestamp" "$url" "$status_code" "$connect_time" "$total_time" "$pattern_match" "$overall_status"
            ;;
        json)
            printf '{"timestamp":"%s","url":"%s","status_code":"%s","connect_time":%.6f,"total_time":%.6f,"pattern_match":%s,"status":"%s"}\n' \
                "$timestamp" "$url" "$status_code" "$connect_time" "$total_time" "$pattern_match" "$overall_status"
            ;;
    esac
}

# Function to print header
print_header() {
    case "$FORMAT" in
        text)
            printf "%-20s %-50s %-10s %-15s %-15s %-15s %-10s\n" \
                "TIMESTAMP" "URL" "STATUS" "CONNECT TIME" "TOTAL TIME" "PATTERN MATCH" "RESULT"
            printf "%-20s %-50s %-10s %-15s %-15s %-15s %-10s\n" \
                "--------------------" "--------------------------------------------------" "----------" "---------------" "---------------" "---------------" "----------"
            ;;
        csv)
            printf "%s,%s,%s,%s,%s,%s,%s\n" \
                "timestamp" "url" "status_code" "connect_time" "total_time" "pattern_match" "status"
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

# Main execution
main() {
    parse_arguments "$@"
    check_requirements
    
    log_info "Starting HTTP response checker"
    
    # Initialize counts
    local success_count=0
    local failure_count=0
    
    # Initialize output
    local output=""
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
    
    # Check each URL
    for url in "${URLS[@]}"; do
        # Get current timestamp
        local timestamp
        timestamp=$(date "+%Y-%m-%d %H:%M:%S")
        
        # Check URL
        local result
        result=$(check_http_response "$url")
        
        # Parse result
        local status_code
        local connect_time
        local total_time
        local pattern_match
        local overall_status
        
        read -r status_code connect_time total_time pattern_match overall_status <<< "$result"
        
        # Update counts
        if [ "$overall_status" = "OK" ]; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi
        
        # Format output
        if [ "$overall_status" != "OK" ] || [ "$QUIET" = false ]; then
            local formatted_output
            formatted_output=$(format_output "$timestamp" "$url" "$status_code" "$connect_time" "$total_time" "$pattern_match" "$overall_status")
            
            # Handle JSON format specially for continuous output
            if [ "$FORMAT" = "json" ] && [ -z "$OUTPUT_FILE" ]; then
                if [ "$json_first_item" = true ]; then
                    json_first_item=false
                    echo '['
                else
                    echo ','
                fi
                echo "$formatted_output" | tr -d '\n'
            else
                # Write to file or stdout
                if [ -n "$OUTPUT_FILE" ]; then
                    write_to_file "$formatted_output" "$OUTPUT_FILE" true
                else
                    echo "$formatted_output"
                fi
            fi
        fi
        
        # Log success or failure
        if [ "$overall_status" = "OK" ]; then
            log_success "URL $url - Status: $status_code, Time: ${total_time}s"
        else
            local reason=""
            
            # Determine failure reason
            if [ "$status_code" = "ERROR" ]; then
                reason="Connection error"
            else
                local status_ok=false
                IFS=',' read -ra EXPECTED_CODES <<< "$EXPECTED_STATUS"
                for code in "${EXPECTED_CODES[@]}"; do
                    if [ "$status_code" = "$code" ]; then
                        status_ok=true
                        break
                    fi
                done
                
                if [ "$status_ok" = false ]; then
                    reason="Unexpected status code: $status_code (expected: $EXPECTED_STATUS)"
                elif [ -n "$PATTERN" ] && [ "$pattern_match" != "true" ]; then
                    reason="Pattern not found: $PATTERN"
                elif [ "$MAX_CONNECT_TIME" != "0" ] && (( $(echo "$connect_time > $MAX_CONNECT_TIME" | bc -l) )); then
                    reason="Connect time too slow: ${connect_time}s (max: ${MAX_CONNECT_TIME}s)"
                elif [ "$MAX_RESPONSE_TIME" != "0" ] && (( $(echo "$total_time > $MAX_RESPONSE_TIME" | bc -l) )); then
                    reason="Response time too slow: ${total_time}s (max: ${MAX_RESPONSE_TIME}s)"
                fi
            fi
            
            log_error "URL $url - Failed: $reason"
        fi
    done
    
    # Print footer for JSON format
    if [ "$FORMAT" = "json" ] && [ -z "$OUTPUT_FILE" ]; then
        echo
        echo ']'
    fi
    
    # Print summary
    log_info "HTTP check summary: $success_count successful, $failure_count failed"
    
    # Set exit code based on results
    if [ $failure_count -gt 0 ]; then
        exit 1
    fi
    
    exit 0
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi