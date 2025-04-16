#!/bin/bash
#
# Script Name: ip_blacklist_checker.sh
# Description: Check if IP addresses are listed on DNS blacklists/RBLs
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./ip_blacklist_checker.sh [options] <ip_address|domain|file>
#
# Options:
#   -i, --ip <address>         IP address to check
#   -d, --domain <name>        Domain to resolve and check
#   -f, --file <path>          File containing IP addresses or domains (one per line)
#   -l, --list <path>          Use custom blacklist file (default: built-in)
#   -o, --output <format>      Output format: text, csv, json (default: text)
#   -w, --write <file>         Write results to file
#   -t, --timeout <seconds>    DNS query timeout (default: 2)
#   -c, --concurrent <number>  Number of concurrent checks (default: 5)
#   -m, --mail                 Check mail-related blacklists only
#   -s, --spam                 Check spam-related blacklists only
#   -p, --proxy                Check proxy/VPN-related blacklists only
#   -a, --all                  Check all available blacklists (default)
#   -r, --report               Generate summary report
#   -n, --no-resolve           Don't resolve hostnames to IPs
#   -v, --verbose              Show detailed information
#   -q, --quiet                Show only blacklisted results
#   -h, --help                 Display this help message
#
# Examples:
#   ./ip_blacklist_checker.sh 8.8.8.8
#   ./ip_blacklist_checker.sh -d example.com -o json -w results.json
#   ./ip_blacklist_checker.sh -f ip_list.txt -r -v
#   ./ip_blacklist_checker.sh -i 192.168.1.1 -m -t 5
#
# Requirements:
#   - dig or host command for DNS lookups
#   - jq for JSON formatting (optional)
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
IP_ADDRESS=""
DOMAIN=""
INPUT_FILE=""
BLACKLIST_FILE=""
OUTPUT_FORMAT="text"
OUTPUT_FILE=""
DNS_TIMEOUT=2
CONCURRENT_CHECKS=5
CHECK_MAIL=false
CHECK_SPAM=false
CHECK_PROXY=false
CHECK_ALL=true
GENERATE_REPORT=false
NO_RESOLVE=false
VERBOSE=false
QUIET=false

# Function to display usage
display_usage() {
    grep -E '^# (Script Name:|Description:|Usage:|Options:|Examples:|Requirements:)' "$0" | sed 's/^# //'
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ip)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            IP_ADDRESS="$2"
            shift 2
            ;;
        -d|--domain)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            DOMAIN="$2"
            shift 2
            ;;
        -f|--file)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [ ! -f "$2" ]; then
                log_error "Input file not found: $2"
                exit 1
            fi
            INPUT_FILE="$2"
            shift 2
            ;;
        -l|--list)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [ ! -f "$2" ]; then
                log_error "Blacklist file not found: $2"
                exit 1
            fi
            BLACKLIST_FILE="$2"
            shift 2
            ;;
        -o|--output)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ ! "$2" =~ ^(text|csv|json)$ ]]; then
                log_error "Invalid output format: $2"
                log_error "Valid options: text, csv, json"
                exit 1
            fi
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -w|--write)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            OUTPUT_FILE="$2"
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
            DNS_TIMEOUT="$2"
            shift 2
            ;;
        -c|--concurrent)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
                log_error "Invalid number of concurrent checks: $2"
                exit 1
            fi
            CONCURRENT_CHECKS="$2"
            shift 2
            ;;
        -m|--mail)
            CHECK_MAIL=true
            CHECK_ALL=false
            shift
            ;;
        -s|--spam)
            CHECK_SPAM=true
            CHECK_ALL=false
            shift
            ;;
        -p|--proxy)
            CHECK_PROXY=true
            CHECK_ALL=false
            shift
            ;;
        -a|--all)
            CHECK_ALL=true
            shift
            ;;
        -r|--report)
            GENERATE_REPORT=true
            shift
            ;;
        -n|--no-resolve)
            NO_RESOLVE=true
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
        *)
            # If no option but a value, treat as IP address or domain
            if [ -z "$IP_ADDRESS" ] && [ -z "$DOMAIN" ] && [ -z "$INPUT_FILE" ]; then
                # Check if it's a valid IP address or domain
                if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    IP_ADDRESS="$1"
                else
                    DOMAIN="$1"
                fi
            else
                log_error "Unknown option or multiple targets: $1"
                log_error "Use --help to see available options"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check for input sources
if [ -z "$IP_ADDRESS" ] && [ -z "$DOMAIN" ] && [ -z "$INPUT_FILE" ]; then
    log_error "No IP address, domain, or input file specified"
    log_error "Use --help to see available options"
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    # Check for DNS lookup tools
    if ! command_exists "dig" && ! command_exists "host"; then
        log_error "Neither dig nor host command found"
        log_error "Please install dnsutils or bind-utils package"
        exit 1
    fi
    
    # Check for jq if using JSON output
    if [ "$OUTPUT_FORMAT" = "json" ] && ! command_exists "jq"; then
        log_warning "jq command not found"
        log_warning "JSON output will use a simpler format"
    fi
    
    log_success "All required tools are available"
}

# Built-in list of common DNS blacklists
get_blacklists() {
    local type="$1"
    local blacklists=()
    
    # Mail-related blacklists
    local mail_blacklists=(
        "zen.spamhaus.org:Spamhaus ZEN"
        "bl.spamcop.net:SpamCop"
        "dnsbl.sorbs.net:SORBS"
        "cbl.abuseat.org:Composite Blocking List"
        "b.barracudacentral.org:Barracuda"
        "bl.emailbasura.org:EmailBasura"
        "bl.spamcannibal.org:Spam Cannibal"
        "ubl.unsubscore.com:LashBack UBL"
        "dnsbl-1.uceprotect.net:UCEPROTECT Level 1"
        "mail-abuse.blacklist.jippg.org:JIPPG Mail Abuse"
    )
    
    # Spam-related blacklists
    local spam_blacklists=(
        "sbl.spamhaus.org:Spamhaus SBL"
        "xbl.spamhaus.org:Spamhaus XBL"
        "pbl.spamhaus.org:Spamhaus PBL"
        "spam.dnsbl.sorbs.net:SORBS Spam"
        "recent.spam.dnsbl.sorbs.net:SORBS Recent Spam"
        "l2.apews.org:APEWS Level 2"
        "bl.spamcop.net:SpamCop"
        "dnsbl.spfbl.net:SPFBL"
        "z.mailspike.net:MailSpike"
        "hostkarma.junkemailfilter.com:JunkEmailFilter"
    )
    
    # Proxy/VPN/TOR-related blacklists
    local proxy_blacklists=(
        "tor.dan.me.uk:TOR Exit Nodes"
        "torexit.dan.me.uk:TOR Exit Nodes (Dan.me.uk)"
        "exitnodes.tor.dnsbl.sectoor.de:TOR Exit Nodes (Sectoor.de)"
        "dnsbl.tornevall.org:TORNEVALL"
        "rbl.megarbl.net/torexit:MegaRBL TOR Exit Nodes"
        "proxy.bl.gweep.ca:Gweep Proxy"
        "cbl.abuseat.org:Composite Blocking List (Proxy Section)"
        "dnsbl.webequipped.com:WebEquipped Proxy"
        "socks.dnsbl.sorbs.net:SORBS SOCKS Proxy"
        "misc.dnsbl.sorbs.net:SORBS Misc Proxy"
    )
    
    # Return appropriate blacklists based on type
    case "$type" in
        "mail")
            blacklists=("${mail_blacklists[@]}")
            ;;
        "spam")
            blacklists=("${spam_blacklists[@]}")
            ;;
        "proxy")
            blacklists=("${proxy_blacklists[@]}")
            ;;
        "all")
            blacklists=("${mail_blacklists[@]}" "${spam_blacklists[@]}" "${proxy_blacklists[@]}")
            ;;
    esac
    
    for bl in "${blacklists[@]}"; do
        echo "$bl"
    done
}

# Function to resolve a domain to IP
resolve_domain() {
    local domain="$1"
    local ip=""
    
    if command_exists "dig"; then
        ip=$(dig +short "$domain" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    elif command_exists "host"; then
        ip=$(host "$domain" | grep 'has address' | head -1 | awk '{print $NF}')
    fi
    
    echo "$ip"
}

# Function to reverse an IP address for DNSBL lookup
reverse_ip() {
    local ip="$1"
    local reversed=""
    
    # Extract octets
    IFS='.' read -ra octets <<< "$ip"
    
    # Reverse the order
    reversed="${octets[3]}.${octets[2]}.${octets[1]}.${octets[0]}"
    
    echo "$reversed"
}

# Function to check an IP against a single blacklist
check_blacklist() {
    local ip="$1"
    local blacklist="$2"
    local description="$3"
    local timeout="$4"
    local result="OK"
    local status="CLEAN"
    local response=""
    
    # Reverse the IP address
    local reversed_ip
    reversed_ip=$(reverse_ip "$ip")
    
    # Check if the IP is blacklisted
    if command_exists "dig"; then
        # Use dig with timeout
        response=$(dig +time="$timeout" +tries=1 +short "$reversed_ip.$blacklist")
    elif command_exists "host"; then
        # Use host with timeout
        # Note: host doesn't have a direct timeout option, so we use timeout command
        # If timeout command is not available, use host without timeout
        if command_exists "timeout"; then
            response=$(timeout "$timeout" host "$reversed_ip.$blacklist" 2>/dev/null)
        else
            response=$(host "$reversed_ip.$blacklist" 2>/dev/null)
        fi
        
        # Extract IP from response if it exists
        if echo "$response" | grep -q "has address"; then
            response=$(echo "$response" | grep 'has address' | awk '{print $NF}')
        else
            response=""
        fi
    fi
    
    # Check if response is empty (not blacklisted) or not
    if [ -n "$response" ]; then
        result="LISTED"
        status="BLACKLISTED"
        
        # Get TXT record for more information if available
        local txt_record=""
        if command_exists "dig"; then
            txt_record=$(dig +time="$timeout" +tries=1 +short -t TXT "$reversed_ip.$blacklist" 2>/dev/null)
        elif command_exists "host"; then
            if command_exists "timeout"; then
                txt_record=$(timeout "$timeout" host -t TXT "$reversed_ip.$blacklist" 2>/dev/null | grep "descriptive text" | sed 's/.*descriptive text //g')
            else
                txt_record=$(host -t TXT "$reversed_ip.$blacklist" 2>/dev/null | grep "descriptive text" | sed 's/.*descriptive text //g')
            fi
        fi
        
        if [ -n "$txt_record" ]; then
            response="$response ($txt_record)"
        fi
    fi
    
    # Return result in CSV format: ip,blacklist,description,status,response
    echo "$ip,$blacklist,$description,$status,$response"
}

# Function to check an IP against all blacklists
check_ip_against_blacklists() {
    local ip="$1"
    local blacklists=("${@:2}")
    local tmpfile="/tmp/blacklist_results_$$_$ip"
    
    # Process each blacklist
    local count=0
    local blacklisted=0
    local fifo="/tmp/blacklist_fifo_$$"
    
    # Create a FIFO for parallelization
    if [ ! -p "$fifo" ]; then
        mkfifo "$fifo"
    fi
    
    # Start a background process to read from the FIFO
    exec 3<>"$fifo"
    
    # Fill the FIFO with initial "tokens"
    for ((i=0; i<CONCURRENT_CHECKS; i++)); do
        echo >&3
    done
    
    # If not in quiet mode, show progress
    if [ "$QUIET" = false ]; then
        log_info "Checking $ip against ${#blacklists[@]} blacklists..."
    fi
    
    # Check against each blacklist in parallel
    for bl in "${blacklists[@]}"; do
        # Get a token from the FIFO, blocking if none available
        read -u 3
        
        # Split blacklist into name and description
        IFS=':' read -r bl_name bl_desc <<< "$bl"
        
        # Run the check in background
        (
            result=$(check_blacklist "$ip" "$bl_name" "$bl_desc" "$DNS_TIMEOUT")
            
            # Print result
            echo "$result" >> "$tmpfile"
            
            # If verbose or not quiet, show individual results
            if [ "$VERBOSE" = true ] || ([ "$QUIET" = false ] && [ "$(echo "$result" | cut -d',' -f4)" = "BLACKLISTED" ]); then
                local res_ip res_bl res_desc res_status res_resp
                IFS=',' read -r res_ip res_bl res_desc res_status res_resp <<< "$result"
                
                if [ "$res_status" = "BLACKLISTED" ]; then
                    log_error "BLACKLISTED: $res_ip on $res_bl ($res_desc)"
                    if [ -n "$res_resp" ]; then
                        log_error "  Response: $res_resp"
                    fi
                elif [ "$VERBOSE" = true ]; then
                    log_info "CLEAN: $res_ip on $res_bl ($res_desc)"
                fi
            fi
            
            # Return the token to the FIFO
            echo >&3
        ) &
        
        # Count processed blacklists
        count=$((count + 1))
        
        # Show progress every 5 blacklists if not quiet and not verbose
        if [ "$QUIET" = false ] && [ "$VERBOSE" = false ] && [ $((count % 5)) -eq 0 ]; then
            echo -n "."
        fi
    done
    
    # Wait for all checks to complete
    wait
    
    # Close the FIFO
    exec 3>&-
    
    # Newline after progress dots
    if [ "$QUIET" = false ] && [ "$VERBOSE" = false ]; then
        echo
    fi
    
    # Count blacklisted results
    blacklisted=$(grep -c "BLACKLISTED" "$tmpfile")
    
    # Show summary if not in quiet mode
    if [ "$QUIET" = false ]; then
        if [ "$blacklisted" -gt 0 ]; then
            log_warning "$ip is blacklisted on $blacklisted of ${#blacklists[@]} checked blacklists"
        else
            log_success "$ip is not blacklisted on any of ${#blacklists[@]} checked blacklists"
        fi
    fi
    
    # Return the results
    cat "$tmpfile"
    
    # Clean up
    rm -f "$tmpfile"
}

# Function to process multiple IPs from a file
process_file() {
    local file="$1"
    local results=()
    local processed=0
    local total_ips=0
    
    # Count total lines in file (excluding empty lines and comments)
    total_ips=$(grep -v '^#' "$file" | grep -v '^$' | wc -l)
    
    # Process each IP or domain in the file
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
            continue
        fi
        
        # Determine if it's an IP or domain
        local ip=""
        if [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            ip="$line"
        else
            # It's a domain, resolve it if not using no-resolve
            if [ "$NO_RESOLVE" = false ]; then
                ip=$(resolve_domain "$line")
            fi
            
            # If no IP found or no-resolve is set, skip it
            if [ -z "$ip" ]; then
                log_warning "Could not resolve domain: $line, skipping"
                continue
            fi
        fi
        
        # Process the IP
        local ip_results
        ip_results=$(check_ip_against_blacklists "$ip" "${blacklists[@]}")
        results+=("$ip_results")
        
        # Increment processed count
        processed=$((processed + 1))
        
        # Show progress if not in quiet mode
        if [ "$QUIET" = false ] && [ "$VERBOSE" = false ]; then
            echo "Processed $processed of $total_ips IPs"
        fi
    done < <(grep -v '^#' "$file" | grep -v '^$')
    
    # Return all results
    for result in "${results[@]}"; do
        echo "$result"
    done
}

# Function to initialize output
initialize_output() {
    local format="$1"
    local file="$2"
    local target_file
    
    # If no file specified, don't write header
    if [ -z "$file" ]; then
        return
    fi
    
    target_file="$file"
    
    # Create headers based on format
    case "$format" in
        "csv")
            # CSV header
            echo "IP,Blacklist,Description,Status,Response" > "$target_file"
            ;;
        "json")
            # JSON header
            {
                echo "{"
                echo "  \"timestamp\": \"$(date "+%Y-%m-%d %H:%M:%S")\"," 
                echo "  \"results\": ["
            } > "$target_file"
            ;;
        "text")
            # Text header
            {
                echo "=== IP Blacklist Check Results ==="
                echo "Timestamp: $(date "+%Y-%m-%d %H:%M:%S")"
                echo "Options: mail=$CHECK_MAIL, spam=$CHECK_SPAM, proxy=$CHECK_PROXY, all=$CHECK_ALL"
                echo
                echo "Results:"
                echo "-----------------------------------------"
            } > "$target_file"
            ;;
    esac
}

# Function to append to output
append_to_output() {
    local line="$1"
    local format="$2"
    local file="$3"
    local is_first="$4"
    local target_file
    
    # If no file specified, print to stdout
    if [ -z "$file" ]; then
        case "$format" in
            "csv")
                echo "$line"
                ;;
            "json")
                # Parse the CSV line
                IFS=',' read -r ip blacklist description status response <<< "$line"
                
                # Format JSON
                if [ "$is_first" = "false" ]; then
                    echo ","
                fi
                
                echo "    {"
                echo "      \"ip\": \"$ip\","
                echo "      \"blacklist\": \"$blacklist\","
                echo "      \"description\": \"$description\","
                echo "      \"status\": \"$status\","
                echo "      \"response\": \"$response\""
                echo -n "    }"
                ;;
            "text")
                # Parse the CSV line
                IFS=',' read -r ip blacklist description status response <<< "$line"
                
                # Skip if status is CLEAN and not verbose
                if [ "$status" = "CLEAN" ] && [ "$VERBOSE" = false ]; then
                    return
                fi
                
                # Format text output
                if [ "$status" = "BLACKLISTED" ]; then
                    echo "BLACKLISTED: $ip on $blacklist ($description)"
                    if [ -n "$response" ]; then
                        echo "  Response: $response"
                    fi
                else
                    echo "CLEAN: $ip on $blacklist ($description)"
                fi
                ;;
        esac
        return
    fi
    
    target_file="$file"
    
    # Append based on format
    case "$format" in
        "csv")
            echo "$line" >> "$target_file"
            ;;
        "json")
            # Parse the CSV line
            IFS=',' read -r ip blacklist description status response <<< "$line"
            
            # Format JSON
            {
                if [ "$is_first" = "false" ]; then
                    echo ","
                fi
                
                echo "    {"
                echo "      \"ip\": \"$ip\","
                echo "      \"blacklist\": \"$blacklist\","
                echo "      \"description\": \"$description\","
                echo "      \"status\": \"$status\","
                echo "      \"response\": \"$response\""
                echo -n "    }"
            } >> "$target_file"
            ;;
        "text")
            # Parse the CSV line
            IFS=',' read -r ip blacklist description status response <<< "$line"
            
            # Skip if status is CLEAN and not verbose
            if [ "$status" = "CLEAN" ] && [ "$VERBOSE" = false ]; then
                return
            fi
            
            # Format text output
            {
                if [ "$status" = "BLACKLISTED" ]; then
                    echo "BLACKLISTED: $ip on $blacklist ($description)"
                    if [ -n "$response" ]; then
                        echo "  Response: $response"
                    fi
                else
                    echo "CLEAN: $ip on $blacklist ($description)"
                fi
            } >> "$target_file"
            ;;
    esac
}

# Function to finalize output
finalize_output() {
    local format="$1"
    local file="$2"
    
    # If no file specified, don't write footer
    if [ -z "$file" ]; then
        if [ "$format" = "json" ]; then
            echo -e "\n  ]\n}"
        fi
        return
    fi
    
    # Add footer based on format
    case "$format" in
        "json")
            # JSON footer
            echo -e "\n  ]\n}" >> "$file"
            ;;
        "text")
            # Text footer
            {
                echo "-----------------------------------------"
                echo "End of Results"
            } >> "$file"
            ;;
        *)
            # No special footer for CSV
            ;;
    esac
    
    # Show success message
    if [ "$QUIET" = false ]; then
        log_success "Results have been saved to $file"
    fi
}

# Function to generate summary report
generate_report() {
    local results="$1"
    local ip_blacklist_counts=()
    local blacklist_hit_counts=()
    local total_blacklisted=0
    
    # Count blacklisted IPs
    while IFS=',' read -r ip blacklist description status response; do
        if [ "$status" = "BLACKLISTED" ]; then
            # Increment count for this IP
            local found=false
            for i in "${!ip_blacklist_counts[@]}"; do
                IFS=':' read -r stored_ip count <<< "${ip_blacklist_counts[$i]}"
                if [ "$stored_ip" = "$ip" ]; then
                    count=$((count + 1))
                    ip_blacklist_counts[$i]="$ip:$count"
                    found=true
                    break
                fi
            done
            
            if [ "$found" = false ]; then
                ip_blacklist_counts+=("$ip:1")
            fi
            
            # Increment count for this blacklist
            found=false
            for i in "${!blacklist_hit_counts[@]}"; do
                IFS=':' read -r stored_bl count <<< "${blacklist_hit_counts[$i]}"
                if [ "$stored_bl" = "$blacklist" ]; then
                    count=$((count + 1))
                    blacklist_hit_counts[$i]="$blacklist:$count"
                    found=true
                    break
                fi
            done
            
            if [ "$found" = false ]; then
                blacklist_hit_counts+=("$blacklist:1")
            fi
            
            total_blacklisted=$((total_blacklisted + 1))
        fi
    done <<< "$results"
    
    # Generate report
    echo
    echo "=== Blacklist Check Summary Report ==="
    echo "Timestamp: $(date "+%Y-%m-%d %H:%M:%S")"
    echo
    
    # IPs by blacklist count
    echo "IPs by Number of Blacklists:"
    echo "-----------------------------------------"
    if [ ${#ip_blacklist_counts[@]} -eq 0 ]; then
        echo "No IPs were found on any blacklists"
    else
        # Sort by count (highest first)
        IFS=$'\n' sorted_ips=($(for pair in "${ip_blacklist_counts[@]}"; do
            echo "$pair"
        done | sort -t: -k2 -nr))
        
        for pair in "${sorted_ips[@]}"; do
            IFS=':' read -r ip count <<< "$pair"
            echo "$ip: Listed on $count blacklists"
        done
    fi
    echo
    
    # Blacklists by hit count
    echo "Blacklists by Number of Hits:"
    echo "-----------------------------------------"
    if [ ${#blacklist_hit_counts[@]} -eq 0 ]; then
        echo "No blacklists had any hits"
    else
        # Sort by count (highest first)
        IFS=$'\n' sorted_bls=($(for pair in "${blacklist_hit_counts[@]}"; do
            echo "$pair"
        done | sort -t: -k2 -nr))
        
        for pair in "${sorted_bls[@]}"; do
            IFS=':' read -r blacklist count <<< "$pair"
            echo "$blacklist: $count IP(s) listed"
        done
    fi
    echo
    
    # Overall statistics
    echo "Overall Statistics:"
    echo "-----------------------------------------"
    # Calculate total IPs checked (unique IPs)
    local all_ips=()
    while IFS=',' read -r ip _ _ _ _; do
        if ! [[ " ${all_ips[*]} " =~ " $ip " ]]; then
            all_ips+=("$ip")
        fi
    done <<< "$results"
    
    local total_ips=${#all_ips[@]}
    local blacklisted_ips=${#ip_blacklist_counts[@]}
    local clean_ips=$((total_ips - blacklisted_ips))
    
    echo "Total IPs checked: $total_ips"
    echo "Blacklisted IPs: $blacklisted_ips ($(( blacklisted_ips * 100 / total_ips ))%)"
    echo "Clean IPs: $clean_ips ($(( clean_ips * 100 / total_ips ))%)"
    echo "Total blacklist hits: $total_blacklisted"
    echo
}

# Main function
main() {
    print_header "IP Blacklist Checker"
    
    # Check prerequisites
    check_prerequisites
    
    # Determine which blacklists to check
    local blacklists_type="all"
    if [ "$CHECK_MAIL" = true ]; then
        blacklists_type="mail"
    elif [ "$CHECK_SPAM" = true ]; then
        blacklists_type="spam"
    elif [ "$CHECK_PROXY" = true ]; then
        blacklists_type="proxy"
    fi
    
    # Get blacklists
    local blacklists=()
    if [ -n "$BLACKLIST_FILE" ]; then
        # Read blacklists from file
        while IFS= read -r line; do
            # Skip empty lines and comments
            if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
                continue
            fi
            blacklists+=("$line")
        done < "$BLACKLIST_FILE"
    else
        # Use built-in blacklists
        readarray -t blacklists < <(get_blacklists "$blacklists_type")
    fi
    
    if [ "${#blacklists[@]}" -eq 0 ]; then
        log_error "No blacklists found to check against"
        exit 1
    fi
    
    if [ "$VERBOSE" = true ] && [ "$QUIET" = false ]; then
        log_info "Using ${#blacklists[@]} blacklists for checking"
    fi
    
    # Initialize output
    initialize_output "$OUTPUT_FORMAT" "$OUTPUT_FILE"
    
    # Store all results
    local all_results=""
    local is_first=true
    
    # Process based on input type
    if [ -n "$IP_ADDRESS" ]; then
        # Check a single IP address
        readarray -t ip_results < <(check_ip_against_blacklists "$IP_ADDRESS" "${blacklists[@]}")
        for result in "${ip_results[@]}"; do
            append_to_output "$result" "$OUTPUT_FORMAT" "$OUTPUT_FILE" "$is_first"
            is_first=false
            all_results+="$result"$'\n'
        done
    elif [ -n "$DOMAIN" ]; then
        # Resolve domain to IP
        local ip=""
        if [ "$NO_RESOLVE" = false ]; then
            ip=$(resolve_domain "$DOMAIN")
        fi
        
        if [ -z "$ip" ]; then
            log_error "Could not resolve domain: $DOMAIN"
            exit 1
        fi
        
        if [ "$QUIET" = false ]; then
            log_info "Resolved $DOMAIN to $ip"
        fi
        
        # Check the resolved IP
        readarray -t ip_results < <(check_ip_against_blacklists "$ip" "${blacklists[@]}")
        for result in "${ip_results[@]}"; do
            append_to_output "$result" "$OUTPUT_FORMAT" "$OUTPUT_FILE" "$is_first"
            is_first=false
            all_results+="$result"$'\n'
        done
    elif [ -n "$INPUT_FILE" ]; then
        # Process multiple IPs/domains from file
        readarray -t file_results < <(process_file "$INPUT_FILE")
        for result in "${file_results[@]}"; do
            append_to_output "$result" "$OUTPUT_FORMAT" "$OUTPUT_FILE" "$is_first"
            is_first=false
            all_results+="$result"$'\n'
        done
    fi
    
    # Finalize output
    finalize_output "$OUTPUT_FORMAT" "$OUTPUT_FILE"
    
    # Generate report if requested
    if [ "$GENERATE_REPORT" = true ]; then
        generate_report "$all_results"
    fi
    
    if [ "$QUIET" = false ]; then
        log_success "Blacklist checking completed"
    fi
}

# Run the main function
main