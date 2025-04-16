#!/bin/bash
#
# Script Name: get_public_ip.sh
# Description: Get public IP address using various methods
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./get_public_ip.sh [options]
#
# Options:
#   -m, --method <method>     Method to use: all|ipify|aws|cloudflare|ipecho|icanhazip|wtfismyip|
#                             ipinfo|ifconfig|dyndns|seeip (default: all - tries each until success)
#   -t, --timeout <seconds>   Timeout for HTTP requests (default: 5)
#   -4, --ipv4                Return only IPv4 address (default)
#   -6, --ipv6                Return only IPv6 address
#   -b, --both                Return both IPv4 and IPv6 addresses
#   -j, --json                Output in JSON format
#   -c, --csv                 Output in CSV format
#   -x, --no-newline          Don't print newline character
#   -a, --additional-info     Get additional information (ISP, location, etc.)
#   -f, --format <format>     Custom output format using placeholders: {ip}, {isp}, {country}, etc.
#   -l, --log <file>          Log to file
#   -s, --silent              Suppress all output except the IP address
#   -v, --verbose             Show detailed output
#   -h, --help                Display this help message
#
# Examples:
#   ./get_public_ip.sh
#   ./get_public_ip.sh -m ipify -4
#   ./get_public_ip.sh -a -j
#   ./get_public_ip.sh -f "IP: {ip}, Country: {country}"
#
# Requirements:
#   - curl or wget for HTTP requests
#   - jq for JSON parsing (optional, required for -a/--additional-info)
#
# License: MIT
# Repository: https://github.com/bashscript-hub

# Source the color_echo utility if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$SCRIPT_DIR/color_echo.sh" ]; then
    source "$SCRIPT_DIR/color_echo.sh"
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
METHOD="all"
TIMEOUT=5
IP_VERSION="ipv4"
OUTPUT_FORMAT="plain"
PRINT_NEWLINE=true
GET_ADDITIONAL_INFO=false
CUSTOM_FORMAT=""
LOG_FILE=""
SILENT=false
VERBOSE=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--method)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            case "$2" in
                all|ipify|aws|cloudflare|ipecho|icanhazip|wtfismyip|ipinfo|ifconfig|dyndns|seeip)
                    METHOD="$2"
                    ;;
                *)
                    log_error "Invalid method: $2"
                    log_error "Valid methods: all, ipify, aws, cloudflare, ipecho, icanhazip, wtfismyip, ipinfo, ifconfig, dyndns, seeip"
                    exit 1
                    ;;
            esac
            shift 2
            ;;
        -t|--timeout)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid timeout value: $2"
                exit 1
            fi
            TIMEOUT="$2"
            shift 2
            ;;
        -4|--ipv4)
            IP_VERSION="ipv4"
            shift
            ;;
        -6|--ipv6)
            IP_VERSION="ipv6"
            shift
            ;;
        -b|--both)
            IP_VERSION="both"
            shift
            ;;
        -j|--json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        -c|--csv)
            OUTPUT_FORMAT="csv"
            shift
            ;;
        -x|--no-newline)
            PRINT_NEWLINE=false
            shift
            ;;
        -a|--additional-info)
            GET_ADDITIONAL_INFO=true
            shift
            ;;
        -f|--format)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            CUSTOM_FORMAT="$2"
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
        -s|--silent)
            SILENT=true
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

# Function to log messages
log_message() {
    local message="$1"
    
    # Write to log file if specified
    if [ -n "$LOG_FILE" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
    fi
    
    # Print to stdout if not in silent mode
    if [ "$SILENT" = false ] && [ "$VERBOSE" = true ]; then
        log_info "$message"
    fi
}

# Function to check HTTP client availability
check_http_client() {
    if command -v curl &>/dev/null; then
        HTTP_CLIENT="curl"
        HTTP_CLIENT_CMD="curl -s --connect-timeout $TIMEOUT"
        if [ "$IP_VERSION" = "ipv4" ]; then
            HTTP_CLIENT_CMD="$HTTP_CLIENT_CMD -4"
        elif [ "$IP_VERSION" = "ipv6" ]; then
            HTTP_CLIENT_CMD="$HTTP_CLIENT_CMD -6"
        fi
    elif command -v wget &>/dev/null; then
        HTTP_CLIENT="wget"
        HTTP_CLIENT_CMD="wget -q -O - --timeout=$TIMEOUT"
        if [ "$IP_VERSION" = "ipv4" ]; then
            HTTP_CLIENT_CMD="$HTTP_CLIENT_CMD -4"
        elif [ "$IP_VERSION" = "ipv6" ]; then
            HTTP_CLIENT_CMD="$HTTP_CLIENT_CMD -6"
        fi
    else
        log_error "Neither curl nor wget found. Please install one of them."
        exit 1
    fi
    
    log_message "Using HTTP client: $HTTP_CLIENT"
}

# Function to check if jq is available
check_jq() {
    if [ "$GET_ADDITIONAL_INFO" = true ] || [ "$OUTPUT_FORMAT" = "json" ] || [ -n "$CUSTOM_FORMAT" ]; then
        if ! command -v jq &>/dev/null; then
            log_error "jq is required for additional info, JSON output, or custom format."
            log_error "Please install jq and try again."
            exit 1
        fi
    fi
}

# Function to get IP address from a specific service
get_ip_from_service() {
    local service="$1"
    local url=""
    local filter=""
    local ipv4_result=""
    local ipv6_result=""
    
    case "$service" in
        ipify)
            if [ "$IP_VERSION" = "ipv4" ] || [ "$IP_VERSION" = "both" ]; then
                url="https://api.ipify.org"
                ipv4_result=$($HTTP_CLIENT_CMD "$url" 2>/dev/null)
            fi
            if [ "$IP_VERSION" = "ipv6" ] || [ "$IP_VERSION" = "both" ]; then
                url="https://api6.ipify.org"
                ipv6_result=$($HTTP_CLIENT_CMD "$url" 2>/dev/null)
            fi
            ;;
        aws)
            if [ "$IP_VERSION" = "ipv4" ] || [ "$IP_VERSION" = "both" ]; then
                url="https://checkip.amazonaws.com"
                ipv4_result=$($HTTP_CLIENT_CMD "$url" 2>/dev/null | tr -d '\n')
            fi
            # AWS doesn't have IPv6 endpoint
            ;;
        cloudflare)
            if [ "$IP_VERSION" = "ipv4" ] || [ "$IP_VERSION" = "both" ]; then
                url="https://1.1.1.1/cdn-cgi/trace"
                ipv4_result=$($HTTP_CLIENT_CMD "$url" 2>/dev/null | grep ip= | cut -d= -f2)
            fi
            # Cloudflare may not return IPv6 reliably
            ;;
        ipecho)
            if [ "$IP_VERSION" = "ipv4" ] || [ "$IP_VERSION" = "both" ]; then
                url="https://ipecho.net/plain"
                ipv4_result=$($HTTP_CLIENT_CMD "$url" 2>/dev/null)
            fi
            # ipecho doesn't have IPv6 endpoint
            ;;
        icanhazip)
            if [ "$IP_VERSION" = "ipv4" ] || [ "$IP_VERSION" = "both" ]; then
                url="https://ipv4.icanhazip.com"
                ipv4_result=$($HTTP_CLIENT_CMD "$url" 2>/dev/null)
            fi
            if [ "$IP_VERSION" = "ipv6" ] || [ "$IP_VERSION" = "both" ]; then
                url="https://ipv6.icanhazip.com"
                ipv6_result=$($HTTP_CLIENT_CMD "$url" 2>/dev/null)
            fi
            ;;
        wtfismyip)
            if [ "$IP_VERSION" = "ipv4" ] || [ "$IP_VERSION" = "both" ]; then
                url="https://wtfismyip.com/text"
                ipv4_result=$($HTTP_CLIENT_CMD "$url" 2>/dev/null)
            fi
            # wtfismyip doesn't have specific IPv6 endpoint
            ;;
        ipinfo)
            if [ "$IP_VERSION" = "ipv4" ] || [ "$IP_VERSION" = "both" ]; then
                url="https://ipinfo.io/ip"
                ipv4_result=$($HTTP_CLIENT_CMD "$url" 2>/dev/null)
            fi
            # ipinfo doesn't have specific IPv6 endpoint
            ;;
        ifconfig)
            if [ "$IP_VERSION" = "ipv4" ] || [ "$IP_VERSION" = "both" ]; then
                url="https://ifconfig.me/ip"
                ipv4_result=$($HTTP_CLIENT_CMD "$url" 2>/dev/null)
            fi
            # ifconfig.me doesn't have specific IPv6 endpoint
            ;;
        dyndns)
            if [ "$IP_VERSION" = "ipv4" ] || [ "$IP_VERSION" = "both" ]; then
                url="https://checkip.dyndns.org/"
                ipv4_result=$($HTTP_CLIENT_CMD "$url" 2>/dev/null | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b')
            fi
            # dyndns doesn't have specific IPv6 endpoint
            ;;
        seeip)
            if [ "$IP_VERSION" = "ipv4" ] || [ "$IP_VERSION" = "both" ]; then
                url="https://api.seeip.org"
                ipv4_result=$($HTTP_CLIENT_CMD "$url" 2>/dev/null)
            fi
            # seeip doesn't have specific IPv6 endpoint
            ;;
        *)
            log_error "Invalid service: $service"
            return 1
            ;;
    esac
    
    # Verify results
    local valid_ipv4=false
    local valid_ipv6=false
    
    if [ -n "$ipv4_result" ] && [[ "$ipv4_result" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_message "Successfully retrieved IPv4 from $service: $ipv4_result"
        valid_ipv4=true
    elif [ -n "$ipv4_result" ]; then
        log_message "Invalid IPv4 result from $service: $ipv4_result"
    fi
    
    if [ -n "$ipv6_result" ] && [[ "$ipv6_result" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
        log_message "Successfully retrieved IPv6 from $service: $ipv6_result"
        valid_ipv6=true
    elif [ -n "$ipv6_result" ]; then
        log_message "Invalid IPv6 result from $service: $ipv6_result"
    fi
    
    # Return results based on requested IP version
    if [ "$IP_VERSION" = "ipv4" ] && [ "$valid_ipv4" = true ]; then
        echo "$ipv4_result"
        return 0
    elif [ "$IP_VERSION" = "ipv6" ] && [ "$valid_ipv6" = true ]; then
        echo "$ipv6_result"
        return 0
    elif [ "$IP_VERSION" = "both" ]; then
        # For "both", return success if at least one is valid
        if [ "$valid_ipv4" = true ] || [ "$valid_ipv6" = true ]; then
            echo "$ipv4_result:$ipv6_result"
            return 0
        fi
    fi
    
    # If we got here, no valid IP was found
    return 1
}

# Function to get IP address from all services
get_ip_from_all_services() {
    local services=("ipify" "aws" "cloudflare" "ipecho" "icanhazip" "wtfismyip" "ipinfo" "ifconfig" "dyndns" "seeip")
    
    for service in "${services[@]}"; do
        log_message "Trying to get IP from $service..."
        local result
        if result=$(get_ip_from_service "$service"); then
            echo "$result"
            return 0
        fi
    done
    
    log_error "Failed to get IP address from any service."
    return 1
}

# Function to get additional information about IP
get_additional_info() {
    local ip="$1"
    
    # Skip if no IP is provided or it's the both format (ipv4:ipv6)
    if [ -z "$ip" ] || [[ "$ip" == *:* && "$IP_VERSION" == "both" ]]; then
        log_error "Cannot get additional info: Invalid IP format"
        return 1
    fi
    
    # Get info from ipinfo.io
    log_message "Getting additional info for IP: $ip"
    local info
    info=$($HTTP_CLIENT_CMD "https://ipinfo.io/$ip/json" 2>/dev/null)
    
    if [ -z "$info" ]; then
        log_error "Failed to get additional info for IP: $ip"
        return 1
    fi
    
    echo "$info"
    return 0
}

# Function to format output
format_output() {
    local ip="$1"
    local additional_info="$2"
    
    # Handle IPv4:IPv6 format for "both" mode
    local ipv4=""
    local ipv6=""
    if [ "$IP_VERSION" = "both" ] && [[ "$ip" == *:* ]]; then
        ipv4="${ip%%:*}"
        ipv6="${ip#*:}"
    else
        if [ "$IP_VERSION" = "ipv4" ]; then
            ipv4="$ip"
        else
            ipv6="$ip"
        fi
    fi
    
    # Prepare output based on requested format
    case "$OUTPUT_FORMAT" in
        json)
            local json_output="{\"ipv4\":\"$ipv4\",\"ipv6\":\"$ipv6\"}"
            
            if [ -n "$additional_info" ]; then
                # Merge additional info with our JSON
                json_output=$(echo "$json_output" | jq --argjson info "$additional_info" '. + $info')
            fi
            
            echo "$json_output" | jq .
            ;;
        csv)
            if [ -n "$additional_info" ]; then
                local hostname=$(echo "$additional_info" | jq -r '.hostname // "N/A"')
                local city=$(echo "$additional_info" | jq -r '.city // "N/A"')
                local region=$(echo "$additional_info" | jq -r '.region // "N/A"')
                local country=$(echo "$additional_info" | jq -r '.country // "N/A"')
                local org=$(echo "$additional_info" | jq -r '.org // "N/A"')
                
                echo "ipv4,ipv6,hostname,city,region,country,org"
                echo "$ipv4,$ipv6,$hostname,$city,$region,$country,\"$org\""
            else
                echo "ipv4,ipv6"
                echo "$ipv4,$ipv6"
            fi
            ;;
        plain)
            if [ -n "$CUSTOM_FORMAT" ] && [ -n "$additional_info" ]; then
                # Replace placeholders in the custom format
                local formatted=$CUSTOM_FORMAT
                formatted=${formatted//\{ip\}/$ip}
                formatted=${formatted//\{ipv4\}/$ipv4}
                formatted=${formatted//\{ipv6\}/$ipv6}
                
                # Replace other placeholders using values from additional_info
                for key in hostname city region country loc postal org timezone; do
                    local value=$(echo "$additional_info" | jq -r ".$key // \"N/A\"")
                    formatted=${formatted//\{$key\}/$value}
                done
                
                echo "$formatted"
            else
                # Simple output
                echo "$ip"
            fi
            ;;
        *)
            log_error "Invalid output format: $OUTPUT_FORMAT"
            return 1
            ;;
    esac
}

# Main function
main() {
    # Check for HTTP client
    check_http_client
    
    # Check for jq if needed
    check_jq
    
    # Create log file if specified
    if [ -n "$LOG_FILE" ]; then
        touch "$LOG_FILE" 2>/dev/null
        if [ $? -ne 0 ]; then
            log_error "Cannot write to log file: $LOG_FILE"
            LOG_FILE=""
        else
            log_message "Started get_public_ip.sh"
        fi
    fi
    
    # Get IP address
    local ip_address=""
    if [ "$METHOD" = "all" ]; then
        ip_address=$(get_ip_from_all_services)
    else
        ip_address=$(get_ip_from_service "$METHOD")
    fi
    
    if [ -z "$ip_address" ]; then
        log_error "Failed to get IP address."
        exit 1
    fi
    
    # Get additional info if requested
    local additional_info=""
    if [ "$GET_ADDITIONAL_INFO" = true ]; then
        # For 'both' mode, we need to split the IP
        if [ "$IP_VERSION" = "both" ]; then
            local ipv4="${ip_address%%:*}"
            if [ -n "$ipv4" ] && [ "$ipv4" != "null" ]; then
                additional_info=$(get_additional_info "$ipv4")
            else
                local ipv6="${ip_address#*:}"
                if [ -n "$ipv6" ] && [ "$ipv6" != "null" ]; then
                    additional_info=$(get_additional_info "$ipv6")
                fi
            fi
        else
            additional_info=$(get_additional_info "$ip_address")
        fi
    fi
    
    # Format and print the output
    local output=$(format_output "$ip_address" "$additional_info")
    
    if [ "$PRINT_NEWLINE" = true ]; then
        echo "$output"
    else
        echo -n "$output"
    fi
    
    log_message "Completed get_public_ip.sh"
    exit 0
}

# Run the main function
main