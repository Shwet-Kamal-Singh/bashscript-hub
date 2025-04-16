#!/bin/bash
#
# Script Name: port_scanner.sh
# Description: Scan for open ports on target hosts with various scanning options
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./port_scanner.sh [options] <target>
#
# Options:
#   -p, --ports <range>        Port range to scan (e.g., 1-1000 or 22,80,443) (default: common ports)
#   -t, --timeout <seconds>    Connection timeout in seconds (default: 1)
#   -T, --threads <number>     Number of parallel scanning threads (default: 10)
#   -s, --scan-type <type>     Scan type: tcp, udp, syn (default: tcp)
#   -b, --banner               Attempt to grab service banners from open ports
#   -w, --wait <ms>            Wait time between connection attempts in milliseconds (default: 0)
#   -r, --resolvers <file>     Use custom DNS resolvers from file
#   -o, --output <file>        Save results to file
#   -j, --json                 Output results in JSON format
#   -c, --csv                  Output results in CSV format
#   -x, --xml                  Output results in XML format
#   -v, --verbose              Verbose output with detailed information
#   -q, --quiet                Only display open ports
#   -z, --zenmap               Output results compatible with Zenmap/Nmap format
#   -n, --no-resolve           Do not resolve hostnames
#   -i, --input <file>         Read targets from file (one per line)
#   -h, --help                 Display this help message
#
# Examples:
#   ./port_scanner.sh 192.168.1.1
#   ./port_scanner.sh -p 22,80,443 example.com
#   ./port_scanner.sh -p 1-1000 -t 2 -T 20 -b 192.168.1.0/24
#   ./port_scanner.sh -p 1-65535 -o scan_results.txt 10.0.0.1-10.0.0.10
#
# Requirements:
#   - Bash 4.0+
#   - nc (netcat) or /dev/tcp support
#   - Standard Linux/Unix tools: grep, awk, sed
#   - Optional: nmap (for advanced scanning features)
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
PORTS=""
TIMEOUT=1
THREADS=10
SCAN_TYPE="tcp"
GRAB_BANNER=false
WAIT_TIME=0
RESOLVERS_FILE=""
OUTPUT_FILE=""
JSON_OUTPUT=false
CSV_OUTPUT=false
XML_OUTPUT=false
VERBOSE=false
QUIET=false
ZENMAP_FORMAT=false
NO_RESOLVE=false
INPUT_FILE=""
TARGETS=()

# Common ports to scan if no ports are specified
COMMON_PORTS="21,22,23,25,53,80,110,111,135,139,143,443,445,993,995,1723,3306,3389,5900,8080"

# Function to display usage
display_usage() {
    grep -E '^# (Script Name:|Description:|Usage:|Options:|Examples:|Requirements:)' "$0" | sed 's/^# //'
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--ports)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            PORTS="$2"
            shift 2
            ;;
        -t|--timeout)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
                log_error "Invalid timeout value: $2"
                exit 1
            fi
            TIMEOUT="$2"
            shift 2
            ;;
        -T|--threads)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
                log_error "Invalid threads value: $2"
                exit 1
            fi
            THREADS="$2"
            shift 2
            ;;
        -s|--scan-type)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "tcp" && "$2" != "udp" && "$2" != "syn" ]]; then
                log_error "Invalid scan type: $2"
                log_error "Valid options: tcp, udp, syn"
                exit 1
            fi
            SCAN_TYPE="$2"
            shift 2
            ;;
        -b|--banner)
            GRAB_BANNER=true
            shift
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
        -r|--resolvers)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [ ! -f "$2" ]; then
                log_error "Resolvers file not found: $2"
                exit 1
            fi
            RESOLVERS_FILE="$2"
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
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -c|--csv)
            CSV_OUTPUT=true
            shift
            ;;
        -x|--xml)
            XML_OUTPUT=true
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
        -z|--zenmap)
            ZENMAP_FORMAT=true
            shift
            ;;
        -n|--no-resolve)
            NO_RESOLVE=true
            shift
            ;;
        -i|--input)
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
            TARGETS+=("$1")
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
    
    # Check for netcat
    if ! command_exists "nc"; then
        log_warning "netcat (nc) is not installed"
        log_info "Checking for /dev/tcp support..."
        
        if [ -e "/dev/tcp" ] || [ "$(echo 'echo -e "HEAD / HTTP/1.0\n\n" > /dev/tcp/example.com/80 2>/dev/null; echo $?' | bash)" = "0" ]; then
            log_info "/dev/tcp is supported, will use it for scanning"
        else
            log_error "Neither netcat nor /dev/tcp support is available"
            log_error "Please install netcat (nc) or use a shell with /dev/tcp support"
            exit 1
        fi
    fi
    
    # Check for advanced scan types
    if [ "$SCAN_TYPE" = "syn" ] || [ "$SCAN_TYPE" = "udp" ]; then
        if ! command_exists "nmap"; then
            log_error "nmap is required for $SCAN_TYPE scanning"
            log_error "Please install nmap or use tcp scan type"
            exit 1
        fi
    fi
    
    # Check for other tools
    local missing_tools=()
    
    for tool in grep awk sed; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ "${#missing_tools[@]}" -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to parse targets
parse_targets() {
    print_section "Parsing Targets"
    
    # Read targets from input file if specified
    if [ -n "$INPUT_FILE" ]; then
        log_info "Reading targets from $INPUT_FILE"
        while IFS= read -r line; do
            # Skip empty lines and comments
            if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
                TARGETS+=("$line")
            fi
        done < "$INPUT_FILE"
    fi
    
    # Check if we have any targets
    if [ ${#TARGETS[@]} -eq 0 ]; then
        log_error "No targets specified"
        log_error "Use ./port_scanner.sh [options] <target> or -i <input_file>"
        exit 1
    fi
    
    # Expand IP ranges in targets
    local expanded_targets=()
    
    for target in "${TARGETS[@]}"; do
        # Check if it's an IP range like 192.168.1.1-192.168.1.10
        if [[ "$target" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)-([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
            local start_ip="${BASH_REMATCH[1]}"
            local end_ip="${BASH_REMATCH[2]}"
            
            # Convert IPs to numbers for comparison
            local start_ip_num=$(ip_to_num "$start_ip")
            local end_ip_num=$(ip_to_num "$end_ip")
            
            if [ "$start_ip_num" -gt "$end_ip_num" ]; then
                log_error "Invalid IP range: $target (start IP > end IP)"
                exit 1
            fi
            
            # Add each IP in the range
            for ((ip_num=start_ip_num; ip_num<=end_ip_num; ip_num++)); do
                expanded_targets+=("$(num_to_ip "$ip_num")")
            done
        # Check if it's a CIDR notation like 192.168.1.0/24
        elif [[ "$target" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/([0-9]+)$ ]]; then
            local base_ip="${BASH_REMATCH[1]}"
            local cidr="${BASH_REMATCH[2]}"
            
            if [ "$cidr" -lt 0 ] || [ "$cidr" -gt 32 ]; then
                log_error "Invalid CIDR value in $target"
                exit 1
            fi
            
            # Calculate network range
            local ip_num=$(ip_to_num "$base_ip")
            local mask=$((0xffffffff << (32 - cidr)))
            local network=$((ip_num & mask))
            local broadcast=$((network | (0xffffffff >> cidr)))
            
            # For small networks, generate all IPs
            if [ "$cidr" -ge 24 ]; then
                for ((i=network+1; i<broadcast; i++)); do
                    expanded_targets+=("$(num_to_ip "$i")")
                done
            else
                # For large networks, just add the CIDR notation
                expanded_targets+=("$target")
            fi
        # Check if it's a simple range like 192.168.1.1-10
        elif [[ "$target" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.)([0-9]+)-([0-9]+)$ ]]; then
            local prefix="${BASH_REMATCH[1]}"
            local start="${BASH_REMATCH[2]}"
            local end="${BASH_REMATCH[3]}"
            
            if [ "$start" -gt "$end" ] || [ "$start" -lt 1 ] || [ "$end" -gt 255 ]; then
                log_error "Invalid IP range: $target"
                exit 1
            fi
            
            for ((i=start; i<=end; i++)); do
                expanded_targets+=("$prefix$i")
            done
        else
            # Just a regular target
            expanded_targets+=("$target")
        fi
    done
    
    TARGETS=("${expanded_targets[@]}")
    
    log_info "Found ${#TARGETS[@]} target(s) to scan"
    
    if [ "$VERBOSE" = true ]; then
        log_info "Targets:"
        for target in "${TARGETS[@]}"; do
            echo "- $target"
        done
    fi
}

# Function to parse ports
parse_ports() {
    print_section "Parsing Ports"
    
    # Use common ports if no ports are specified
    if [ -z "$PORTS" ]; then
        PORTS="$COMMON_PORTS"
        log_info "No ports specified, using common ports: $PORTS"
    fi
    
    # Parse port ranges
    local parsed_ports=()
    
    IFS=',' read -ra PORT_RANGES <<< "$PORTS"
    for range in "${PORT_RANGES[@]}"; do
        if [[ "$range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            
            if [ "$start" -gt "$end" ] || [ "$start" -lt 1 ] || [ "$end" -gt 65535 ]; then
                log_error "Invalid port range: $range"
                exit 1
            fi
            
            for ((port=start; port<=end; port++)); do
                parsed_ports+=("$port")
            done
        elif [[ "$range" =~ ^[0-9]+$ ]]; then
            if [ "$range" -lt 1 ] || [ "$range" -gt 65535 ]; then
                log_error "Invalid port: $range"
                exit 1
            fi
            parsed_ports+=("$range")
        else
            log_error "Invalid port specification: $range"
            exit 1
        fi
    done
    
    # Remove duplicates and sort
    readarray -t PARSED_PORTS < <(printf '%s\n' "${parsed_ports[@]}" | sort -nu)
    
    log_info "Scanning ${#PARSED_PORTS[@]} port(s)"
    
    if [ "$VERBOSE" = true ]; then
        if [ ${#PARSED_PORTS[@]} -le 20 ]; then
            log_info "Ports: ${PARSED_PORTS[*]}"
        else
            log_info "Ports: ${PARSED_PORTS[0]}, ${PARSED_PORTS[1]}, ${PARSED_PORTS[2]} ... (${#PARSED_PORTS[@]} total)"
        fi
    fi
}

# Convert IP address to number
ip_to_num() {
    local ip="$1"
    local IFS='.'
    read -ra octets <<< "$ip"
    echo "$((octets[0] * 256**3 + octets[1] * 256**2 + octets[2] * 256 + octets[3]))"
}

# Convert number to IP address
num_to_ip() {
    local num="$1"
    local octet1=$((num >> 24 & 255))
    local octet2=$((num >> 16 & 255))
    local octet3=$((num >> 8 & 255))
    local octet4=$((num & 255))
    echo "$octet1.$octet2.$octet3.$octet4"
}

# Function to check if a port is open using nc
check_port_nc() {
    local host="$1"
    local port="$2"
    local type="$3"
    local timeout="$4"
    
    local nc_opts="-z -w$timeout"
    if [ "$type" = "udp" ]; then
        nc_opts="$nc_opts -u"
    fi
    
    nc $nc_opts "$host" "$port" &>/dev/null
    return $?
}

# Function to check if a port is open using /dev/tcp
check_port_tcp() {
    local host="$1"
    local port="$2"
    local timeout="$3"
    
    (echo > "/dev/tcp/$host/$port") >/dev/null 2>&1
    return $?
}

# Function to check if a port is open using nmap for SYN scan
check_port_nmap() {
    local host="$1"
    local port="$2"
    local type="$3"
    local timeout="$4"
    
    local scan_type="-sS"
    if [ "$type" = "udp" ]; then
        scan_type="-sU"
    fi
    
    nmap -T4 -Pn $scan_type -p "$port" --host-timeout "${timeout}s" "$host" | grep -q "open"
    return $?
}

# Function to get service banner
get_banner() {
    local host="$1"
    local port="$2"
    local timeout="$3"
    local banner=""
    
    # Different commands based on common ports
    case "$port" in
        21) # FTP
            banner=$(echo -e "QUIT\r\n" | nc -w "$timeout" "$host" "$port" 2>/dev/null | head -1)
            ;;
        22) # SSH
            banner=$(nc -w "$timeout" "$host" "$port" </dev/null 2>/dev/null | head -1)
            ;;
        25|587) # SMTP
            banner=$(echo -e "QUIT\r\n" | nc -w "$timeout" "$host" "$port" 2>/dev/null | head -1)
            ;;
        80|443|8080) # HTTP/HTTPS
            banner=$(echo -e "HEAD / HTTP/1.0\r\n\r\n" | nc -w "$timeout" "$host" "$port" 2>/dev/null | head -1)
            ;;
        110) # POP3
            banner=$(echo -e "QUIT\r\n" | nc -w "$timeout" "$host" "$port" 2>/dev/null | head -1)
            ;;
        143) # IMAP
            banner=$(echo -e "a1 LOGOUT\r\n" | nc -w "$timeout" "$host" "$port" 2>/dev/null | head -1)
            ;;
        3306) # MySQL
            banner=$(nc -w "$timeout" "$host" "$port" </dev/null 2>/dev/null | strings | head -1)
            ;;
        5432) # PostgreSQL
            banner=$(echo -e "\x00\x00\x00\x08\x04\xd2\x16\x2f" | nc -w "$timeout" "$host" "$port" 2>/dev/null | strings | head -1)
            ;;
        *)
            # Generic banner grab
            banner=$(echo -e "\r\n" | nc -w "$timeout" "$host" "$port" 2>/dev/null | strings | head -1)
            ;;
    esac
    
    # Clean up banner (remove control chars, limit length)
    banner=$(echo "$banner" | tr -cd '[:print:]' | cut -c1-50)
    
    echo "$banner"
}

# Function to resolve hostname
resolve_hostname() {
    local host="$1"
    
    # Skip if it's an IP address or if no-resolve is enabled
    if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [ "$NO_RESOLVE" = true ]; then
        echo "$host"
        return
    fi
    
    # Use custom resolvers if specified
    if [ -n "$RESOLVERS_FILE" ]; then
        local resolver
        resolver=$(shuf -n 1 "$RESOLVERS_FILE")
        
        if [ -n "$resolver" ]; then
            local result
            result=$(dig +short "@$resolver" "$host" | grep -v ";" | head -1)
            
            if [ -n "$result" ]; then
                echo "$result"
                return
            fi
        fi
    fi
    
    # Default resolution
    local result
    result=$(getent hosts "$host" | awk '{print $1}' | head -1)
    
    if [ -n "$result" ]; then
        echo "$result"
    else
        echo "$host"
    fi
}

# Function to initialize output file
initialize_output_file() {
    if [ -n "$OUTPUT_FILE" ]; then
        # Clear the file if it exists
        > "$OUTPUT_FILE"
        
        # Initialize JSON output
        if [ "$JSON_OUTPUT" = true ]; then
            echo "{" > "$OUTPUT_FILE"
            echo '  "scan_info": {' >> "$OUTPUT_FILE"
            echo "    \"scan_time\": \"$(date)\"," >> "$OUTPUT_FILE"
            echo "    \"targets\": ${#TARGETS[@]}," >> "$OUTPUT_FILE"
            echo "    \"ports\": ${#PARSED_PORTS[@]}" >> "$OUTPUT_FILE"
            echo "  }," >> "$OUTPUT_FILE"
            echo '  "results": [' >> "$OUTPUT_FILE"
        fi
        
        # Initialize CSV output
        if [ "$CSV_OUTPUT" = true ]; then
            echo "host,ip,port,status,service,banner" > "$OUTPUT_FILE"
        fi
        
        # Initialize XML output
        if [ "$XML_OUTPUT" = true ]; then
            echo '<?xml version="1.0" encoding="UTF-8"?>' > "$OUTPUT_FILE"
            echo '<portscanner>' >> "$OUTPUT_FILE"
            echo "  <scantime>$(date)</scantime>" >> "$OUTPUT_FILE"
            echo "  <targets>$(printf '%s,' "${TARGETS[@]}")</targets>" >> "$OUTPUT_FILE"
        fi
        
        # Initialize Zenmap/Nmap compatible output
        if [ "$ZENMAP_FORMAT" = true ]; then
            echo "Starting Port Scanner at $(date)" > "$OUTPUT_FILE"
            echo "Scan type: $SCAN_TYPE   Scan ports: ${PARSED_PORTS[*]}" >> "$OUTPUT_FILE"
            echo "=================================================" >> "$OUTPUT_FILE"
        fi
    fi
}

# Function to append to output file in specified format
append_to_output_file() {
    local target="$1"
    local ip="$2"
    local port="$3"
    local status="$4"
    local service="$5"
    local banner="$6"
    
    if [ -n "$OUTPUT_FILE" ]; then
        # JSON format
        if [ "$JSON_OUTPUT" = true ]; then
            # Use a marker to tell us if we need to add a comma
            local marker_file="/tmp/port_scanner_json_marker_$$"
            if [ -f "$marker_file" ]; then
                echo "," >> "$OUTPUT_FILE"
            else
                touch "$marker_file"
            fi
            
            echo "    {" >> "$OUTPUT_FILE"
            echo "      \"host\": \"$target\"," >> "$OUTPUT_FILE"
            echo "      \"ip\": \"$ip\"," >> "$OUTPUT_FILE"
            echo "      \"port\": $port," >> "$OUTPUT_FILE"
            echo "      \"status\": \"$status\"," >> "$OUTPUT_FILE"
            echo "      \"service\": \"$service\"," >> "$OUTPUT_FILE"
            echo "      \"banner\": \"$banner\"" >> "$OUTPUT_FILE"
            echo "    }" >> "$OUTPUT_FILE"
        fi
        
        # CSV format
        if [ "$CSV_OUTPUT" = true ]; then
            # Escape quotes in banner
            local escaped_banner="${banner//\"/\"\"}"
            echo "\"$target\",\"$ip\",$port,\"$status\",\"$service\",\"$escaped_banner\"" >> "$OUTPUT_FILE"
        fi
        
        # XML format
        if [ "$XML_OUTPUT" = true ]; then
            echo "  <host>" >> "$OUTPUT_FILE"
            echo "    <hostname>$target</hostname>" >> "$OUTPUT_FILE"
            echo "    <ip>$ip</ip>" >> "$OUTPUT_FILE"
            echo "    <port>$port</port>" >> "$OUTPUT_FILE"
            echo "    <status>$status</status>" >> "$OUTPUT_FILE"
            echo "    <service>$service</service>" >> "$OUTPUT_FILE"
            # XML escape for banner
            local escaped_banner="${banner//&/&amp;}"
            escaped_banner="${escaped_banner//</&lt;}"
            escaped_banner="${escaped_banner//>/&gt;}"
            escaped_banner="${escaped_banner//\"/&quot;}"
            escaped_banner="${escaped_banner//'/&apos;}"
            echo "    <banner>$escaped_banner</banner>" >> "$OUTPUT_FILE"
            echo "  </host>" >> "$OUTPUT_FILE"
        fi
        
        # Zenmap/Nmap compatible format
        if [ "$ZENMAP_FORMAT" = true ]; then
            if [ "$status" = "open" ]; then
                echo "$port/$service open  $banner" >> "$OUTPUT_FILE"
            fi
        fi
    fi
}

# Function to finalize output file
finalize_output_file() {
    if [ -n "$OUTPUT_FILE" ]; then
        # Finalize JSON output
        if [ "$JSON_OUTPUT" = true ]; then
            echo -e "\n  ]\n}" >> "$OUTPUT_FILE"
            # Remove temp marker file
            rm -f "/tmp/port_scanner_json_marker_$$"
        fi
        
        # Finalize XML output
        if [ "$XML_OUTPUT" = true ]; then
            echo "</portscanner>" >> "$OUTPUT_FILE"
        fi
        
        # Finalize Zenmap/Nmap compatible output
        if [ "$ZENMAP_FORMAT" = true ]; then
            echo "=================================================" >> "$OUTPUT_FILE"
            echo "Port scan completed at $(date)" >> "$OUTPUT_FILE"
        fi
        
        log_success "Scan results saved to $OUTPUT_FILE"
    fi
}

# Determine service name by port
get_service_name() {
    local port="$1"
    
    case "$port" in
        20|21) echo "ftp" ;;
        22) echo "ssh" ;;
        23) echo "telnet" ;;
        25) echo "smtp" ;;
        53) echo "domain" ;;
        80) echo "http" ;;
        110) echo "pop3" ;;
        111) echo "rpcbind" ;;
        135) echo "msrpc" ;;
        139) echo "netbios-ssn" ;;
        143) echo "imap" ;;
        443) echo "https" ;;
        445) echo "microsoft-ds" ;;
        993) echo "imaps" ;;
        995) echo "pop3s" ;;
        1723) echo "pptp" ;;
        3306) echo "mysql" ;;
        3389) echo "ms-wbt-server" ;;
        5432) echo "postgresql" ;;
        5900) echo "vnc" ;;
        8080) echo "http-proxy" ;;
        *) echo "unknown" ;;
    esac
}

# Main scan function
perform_scan() {
    print_section "Starting Port Scan"
    
    local total_targets=${#TARGETS[@]}
    local total_ports=${#PARSED_PORTS[@]}
    local total_scans=$((total_targets * total_ports))
    local completed_scans=0
    local start_time=$(date +%s)
    
    log_info "Scanning $total_targets host(s) and $total_ports port(s) ($total_scans total scans)"
    log_info "Scan started at $(date)"
    
    # Initialize output file
    initialize_output_file
    
    # Create a temporary fifo for parallel processing
    local fifo="/tmp/port_scanner_fifo_$$"
    mkfifo "$fifo"
    
    # Start background handler for the fifo
    exec 3<>"$fifo"
    rm "$fifo"
    
    # Fill the fifo with initial "slots"
    for ((i=0; i<THREADS; i++)); do
        echo >&3
    done
    
    # Function to process each host:port combination
    scan_target_port() {
        local target="$1"
        local port="$2"
        local ip
        
        # Resolve hostname to IP
        ip=$(resolve_hostname "$target")
        
        # Get service name
        local service
        service=$(get_service_name "$port")
        
        # Check if port is open
        local is_open=false
        local result=1
        
        if [ "$VERBOSE" = true ] && [ "$QUIET" = false ]; then
            echo -n "Scanning $target:$port... "
        fi
        
        # Choose scan method based on scan type and available tools
        if [ "$SCAN_TYPE" = "tcp" ]; then
            if command_exists "nc"; then
                check_port_nc "$ip" "$port" "tcp" "$TIMEOUT"
                result=$?
            else
                check_port_tcp "$ip" "$port" "$TIMEOUT"
                result=$?
            fi
        elif [ "$SCAN_TYPE" = "udp" ]; then
            check_port_nmap "$ip" "$port" "udp" "$TIMEOUT"
            result=$?
        elif [ "$SCAN_TYPE" = "syn" ]; then
            check_port_nmap "$ip" "$port" "syn" "$TIMEOUT"
            result=$?
        fi
        
        # Determine if port is open
        if [ $result -eq 0 ]; then
            is_open=true
        fi
        
        # Get banner if requested and port is open
        local banner=""
        if [ "$GRAB_BANNER" = true ] && [ "$is_open" = true ]; then
            banner=$(get_banner "$ip" "$port" "$TIMEOUT")
        fi
        
        # Output result
        if [ "$is_open" = true ]; then
            if [ "$QUIET" = false ]; then
                if [ "$VERBOSE" = true ]; then
                    if [ -n "$banner" ]; then
                        log_success "OPEN: $port/$service on $target ($ip) - $banner"
                    else
                        log_success "OPEN: $port/$service on $target ($ip)"
                    fi
                else
                    if [ -n "$banner" ]; then
                        log_success "OPEN: $target:$port ($service) - $banner"
                    else
                        log_success "OPEN: $target:$port ($service)"
                    fi
                fi
            else
                echo "$target:$port is open"
            fi
            
            # Add to output file
            append_to_output_file "$target" "$ip" "$port" "open" "$service" "$banner"
        else
            if [ "$VERBOSE" = true ] && [ "$QUIET" = false ]; then
                log_info "CLOSED: $port/$service on $target ($ip)"
            fi
            
            # Add to output file if not in quiet mode
            if [ "$JSON_OUTPUT" = true ] || [ "$CSV_OUTPUT" = true ] || [ "$XML_OUTPUT" = true ]; then
                append_to_output_file "$target" "$ip" "$port" "closed" "$service" ""
            fi
        fi
        
        # Update progress counter
        completed_scans=$((completed_scans + 1))
        
        if [ "$QUIET" = false ] && [ $((completed_scans % 10)) -eq 0 ]; then
            local elapsed_time=$(($(date +%s) - start_time))
            local scans_per_second=0
            
            if [ "$elapsed_time" -gt 0 ]; then
                scans_per_second=$((completed_scans / elapsed_time))
            fi
            
            local percent=$((completed_scans * 100 / total_scans))
            local eta=0
            
            if [ "$scans_per_second" -gt 0 ]; then
                eta=$(((total_scans - completed_scans) / scans_per_second))
            fi
            
            printf "\rProgress: %d/%d (%d%%) - %d scans/sec - ETA: %d:%02d:%02d" \
                "$completed_scans" "$total_scans" "$percent" "$scans_per_second" \
                $((eta / 3600)) $(((eta % 3600) / 60)) $((eta % 60))
        fi
        
        # Wait if wait time is specified
        if [ "$WAIT_TIME" -gt 0 ]; then
            sleep "0.$(printf "%03d" "$WAIT_TIME")"
        fi
        
        # Release a slot in the fifo
        echo >&3
    }
    
    # Execute scans in parallel
    for target in "${TARGETS[@]}"; do
        for port in "${PARSED_PORTS[@]}"; do
            # Wait for a slot in the fifo
            read -u 3
            
            # Execute scan in background
            (scan_target_port "$target" "$port"; ) &
        done
    done
    
    # Wait for all background jobs to finish
    wait
    
    # Close the fifo
    exec 3>&-
    
    # Clear progress line
    if [ "$QUIET" = false ]; then
        echo
    fi
    
    # Finalize output file
    finalize_output_file
    
    # Print final stats
    local elapsed_time=$(($(date +%s) - start_time))
    local minutes=$((elapsed_time / 60))
    local seconds=$((elapsed_time % 60))
    
    if [ "$QUIET" = false ]; then
        log_info "Scan completed at $(date)"
        log_info "Total scan time: ${minutes}m ${seconds}s"
        log_info "Scans per second: $((total_scans / (elapsed_time > 0 ? elapsed_time : 1)))"
    fi
}

# Main function
main() {
    print_header "Port Scanner"
    
    # Check prerequisites
    check_prerequisites
    
    # Parse targets and ports
    parse_targets
    parse_ports
    
    # Perform the scan
    perform_scan
    
    log_success "Scan completed"
}

# Run the main function
main