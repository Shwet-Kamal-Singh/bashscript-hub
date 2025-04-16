#!/bin/bash
#
# Script Name: firewall_rules_report.sh
# Description: Generate detailed reports of active firewall rules across various firewall types
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./firewall_rules_report.sh [options]
#
# Options:
#   -t, --type <type>          Firewall type to check: auto, iptables, nftables, ufw, firewalld, all (default: auto)
#   -f, --format <format>      Output format: plain, csv, json, html, xml (default: plain)
#   -o, --output <file>        Save report to file (default: output to console)
#   -i, --interface <iface>    Filter rules by network interface
#   -p, --port <number>        Filter rules by port number
#   -s, --show-defaults        Show default chains/rules (might be verbose)
#   -r, --resolve-ips          Resolve IP addresses to hostnames where possible
#   -a, --all-rules            Include inactive/disabled firewall configurations too
#   -S, --summary              Show summary of rules instead of detailed output
#   -z, --zones                For firewalld, show rules grouped by zones
#   -b, --by-service           Group rules by service (if supported by firewall type)
#   -d, --diff <file>          Compare rules with previously saved report
#   -c, --color                Use colorized output (default for terminal)
#   -n, --no-color             Disable colorized output
#   -v, --verbose              Show detailed information and statistics
#   -q, --quiet                Suppress informational output
#   -h, --help                 Display this help message
#
# Examples:
#   ./firewall_rules_report.sh
#   ./firewall_rules_report.sh -t iptables -o iptables_rules.txt
#   ./firewall_rules_report.sh -t firewalld -z -f html -o firewall_report.html
#   ./firewall_rules_report.sh -S -r -i eth0 -p 22
#
# Requirements:
#   - Root privileges (or sudo) for accessing firewall configurations
#   - Appropriate firewall utilities (iptables, nft, ufw, firewall-cmd) depending on type
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
FIREWALL_TYPE="auto"
OUTPUT_FORMAT="plain"
OUTPUT_FILE=""
FILTER_INTERFACE=""
FILTER_PORT=""
SHOW_DEFAULTS=false
RESOLVE_IPS=false
INCLUDE_INACTIVE=false
SHOW_SUMMARY=false
SHOW_ZONES=false
GROUP_BY_SERVICE=false
DIFF_FILE=""
USE_COLOR=true
VERBOSE=false
QUIET=false

# Check if output is to a terminal (for color auto-detection)
if [ ! -t 1 ]; then
    USE_COLOR=false
fi

# Function to display usage
display_usage() {
    grep -E '^# (Script Name:|Description:|Usage:|Options:|Examples:|Requirements:)' "$0" | sed 's/^# //'
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ ! "$2" =~ ^(auto|iptables|nftables|ufw|firewalld|all)$ ]]; then
                log_error "Invalid firewall type: $2"
                log_error "Valid options: auto, iptables, nftables, ufw, firewalld, all"
                exit 1
            fi
            FIREWALL_TYPE="$2"
            shift 2
            ;;
        -f|--format)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ ! "$2" =~ ^(plain|csv|json|html|xml)$ ]]; then
                log_error "Invalid output format: $2"
                log_error "Valid options: plain, csv, json, html, xml"
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
        -i|--interface)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            FILTER_INTERFACE="$2"
            shift 2
            ;;
        -p|--port)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ] || [ "$2" -gt 65535 ]; then
                log_error "Invalid port number: $2"
                exit 1
            fi
            FILTER_PORT="$2"
            shift 2
            ;;
        -s|--show-defaults)
            SHOW_DEFAULTS=true
            shift
            ;;
        -r|--resolve-ips)
            RESOLVE_IPS=true
            shift
            ;;
        -a|--all-rules)
            INCLUDE_INACTIVE=true
            shift
            ;;
        -S|--summary)
            SHOW_SUMMARY=true
            shift
            ;;
        -z|--zones)
            SHOW_ZONES=true
            shift
            ;;
        -b|--by-service)
            GROUP_BY_SERVICE=true
            shift
            ;;
        -d|--diff)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [ ! -f "$2" ]; then
                log_error "Diff file not found: $2"
                exit 1
            fi
            DIFF_FILE="$2"
            shift 2
            ;;
        -c|--color)
            USE_COLOR=true
            shift
            ;;
        -n|--no-color)
            USE_COLOR=false
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

# Function to check if running with root privileges
check_root() {
    if [ $EUID -ne 0 ]; then
        log_warning "This script may require root privileges to access all firewall information"
        log_warning "Some information may be incomplete or inaccessible"
        
        # Check if sudo is available
        if command_exists "sudo"; then
            log_info "Consider running with sudo: sudo $0 $*"
        else
            log_warning "sudo not available, proceeding with limited privileges"
        fi
    fi
}

# Function to detect active firewall types
detect_firewall_types() {
    print_section "Detecting Firewall Types"
    
    local detected_types=()
    
    # Check for iptables
    if command_exists "iptables" && iptables -L -n &>/dev/null; then
        detected_types+=("iptables")
    fi
    
    # Check for nftables
    if command_exists "nft" && nft list tables &>/dev/null; then
        detected_types+=("nftables")
    fi
    
    # Check for UFW
    if command_exists "ufw" && ufw status &>/dev/null; then
        detected_types+=("ufw")
    fi
    
    # Check for firewalld
    if command_exists "firewall-cmd" && firewall-cmd --state &>/dev/null; then
        detected_types+=("firewalld")
    fi
    
    if [ ${#detected_types[@]} -eq 0 ]; then
        log_warning "No active firewall detected on the system"
        return 1
    fi
    
    log_info "Detected firewall types: ${detected_types[*]}"
    
    # If auto mode, select the first active firewall
    if [ "$FIREWALL_TYPE" = "auto" ]; then
        FIREWALL_TYPE="${detected_types[0]}"
        log_info "Auto-selected firewall type: $FIREWALL_TYPE"
    elif [ "$FIREWALL_TYPE" != "all" ]; then
        # Check if the selected firewall is available
        local found=false
        for fw in "${detected_types[@]}"; do
            if [ "$fw" = "$FIREWALL_TYPE" ]; then
                found=true
                break
            fi
        done
        
        if [ "$found" = false ] && [ "$INCLUDE_INACTIVE" = false ]; then
            log_warning "Selected firewall type '$FIREWALL_TYPE' is not active"
            log_warning "Use --all-rules to include inactive firewalls"
            return 1
        fi
    fi
    
    return 0
}

# Function to format timestamp
format_timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# Function to initialize output file with appropriate header
initialize_output() {
    local format="$1"
    local file="$2"
    local target
    
    # Determine output target (file or stdout)
    if [ -n "$file" ]; then
        target="$file"
    else
        target="/dev/stdout"
    fi
    
    # Create appropriate header based on format
    case "$format" in
        "csv")
            echo "Firewall,Table,Chain,Position,Rule,Protocol,Source,Destination,Interface,Port,Action,Extra" > "$target"
            ;;
        "json")
            cat > "$target" << EOF
{
  "report_info": {
    "timestamp": "$(format_timestamp)",
    "firewall_type": "$FIREWALL_TYPE",
    "hostname": "$(hostname)",
    "generated_by": "firewall_rules_report.sh"
  },
  "rules": [
EOF
            ;;
        "html")
            cat > "$target" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Firewall Rules Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .summary { background-color: #e7f3fe; padding: 10px; border-left: 5px solid #2196F3; margin: 20px 0; }
        .accept { color: green; }
        .drop, .reject { color: red; }
        .timestamp { color: #666; font-size: 0.8em; }
        .firewall-section { margin-top: 30px; border-top: 1px solid #eee; padding-top: 20px; }
    </style>
</head>
<body>
    <h1>Firewall Rules Report</h1>
    <p class="timestamp">Generated on: $(format_timestamp) | Host: $(hostname)</p>
    <p>Firewall type: <strong>$FIREWALL_TYPE</strong></p>
EOF
            ;;
        "xml")
            cat > "$target" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<FirewallReport>
  <ReportInfo>
    <Timestamp>$(format_timestamp)</Timestamp>
    <Hostname>$(hostname)</Hostname>
    <FirewallType>$FIREWALL_TYPE</FirewallType>
    <GeneratedBy>firewall_rules_report.sh</GeneratedBy>
  </ReportInfo>
EOF
            ;;
        *)
            # Plain text format
            cat > "$target" << EOF
=== Firewall Rules Report ===

Generated on: $(format_timestamp)
Hostname: $(hostname)
Firewall type: $FIREWALL_TYPE

EOF
            ;;
    esac
}

# Function to finalize output file
finalize_output() {
    local format="$1"
    local file="$2"
    local target
    
    # Determine output target (file or stdout)
    if [ -n "$file" ]; then
        target="$file"
    else
        target="/dev/stdout"
    fi
    
    # Add appropriate footer based on format
    case "$format" in
        "json")
            cat >> "$target" << EOF

  ]
}
EOF
            ;;
        "html")
            cat >> "$target" << EOF
</body>
</html>
EOF
            ;;
        "xml")
            cat >> "$target" << EOF
</FirewallReport>
EOF
            ;;
        *)
            # Nothing special needed for plain text or CSV
            ;;
    esac
    
    if [ -n "$file" ] && [ "$QUIET" = false ]; then
        log_success "Report saved to $file"
    fi
}

# Function to resolve IP address to hostname
resolve_ip() {
    local ip="$1"
    
    # Skip resolution for special addresses
    if [[ "$ip" == "0.0.0.0/0" || "$ip" == "::/0" || "$ip" == "0.0.0.0" || "$ip" == "127.0.0.1" ]]; then
        echo "$ip"
        return
    fi
    
    # Extract CIDR notation if present
    local cidr=""
    if [[ "$ip" == */* ]]; then
        cidr="/${ip#*/}"
        ip="${ip%/*}"
    fi
    
    # Try to resolve the IP
    local hostname
    hostname=$(getent hosts "$ip" | awk '{print $2}')
    
    if [ -n "$hostname" ]; then
        echo "$hostname$cidr ($ip$cidr)"
    else
        echo "$ip$cidr"
    fi
}

# Function to get iptables rules
get_iptables_rules() {
    print_section "Getting IPTables Rules"
    
    local tmpfile="/tmp/iptables_rules_$$"
    
    # Get list of tables
    local tables=("filter" "nat" "mangle" "raw")
    if iptables -t security -L &>/dev/null; then
        tables+=("security")
    fi
    
    local first_rule=true
    
    for table in "${tables[@]}"; do
        if [ "$VERBOSE" = true ] && [ "$QUIET" = false ]; then
            log_info "Processing table: $table"
        fi
        
        # Get rules for the current table
        iptables -t "$table" -L -n -v --line-numbers > "$tmpfile"
        
        # Process each chain
        local current_chain=""
        local chain_policy=""
        
        while IFS= read -r line; do
            # Check if line contains a chain declaration
            if [[ "$line" =~ ^Chain\ ([^\ ]+)\ \(policy\ ([^)]+)\) ]]; then
                current_chain="${BASH_REMATCH[1]}"
                chain_policy="${BASH_REMATCH[2]}"
                
                # Skip default chains if not showing defaults
                if [ "$SHOW_DEFAULTS" = false ] && [[ "$current_chain" =~ ^(INPUT|FORWARD|OUTPUT|PREROUTING|POSTROUTING)$ ]]; then
                    if [ "$VERBOSE" = true ] && [ "$QUIET" = false ]; then
                        log_info "Skipping default chain: $current_chain"
                    fi
                    current_chain=""
                    continue
                fi
                
                if [ "$VERBOSE" = true ] && [ "$QUIET" = false ]; then
                    log_info "Processing chain: $current_chain (policy: $chain_policy)"
                fi
                
                continue
            elif [[ "$line" =~ ^Chain\ ([^\ ]+) ]]; then
                current_chain="${BASH_REMATCH[1]}"
                chain_policy="no policy"
                
                # Skip processing if no active chain
                if [ -z "$current_chain" ]; then
                    continue
                fi
                
                if [ "$VERBOSE" = true ] && [ "$QUIET" = false ]; then
                    log_info "Processing chain: $current_chain (no policy)"
                fi
                
                continue
            fi
            
            # Skip processing if no active chain or header line
            if [ -z "$current_chain" ] || [[ "$line" =~ ^num\ +pkts ]]; then
                continue
            fi
            
            # Skip empty lines
            if [ -z "$line" ]; then
                continue
            fi
            
            # Process rule line
            # Format: num pkts bytes target prot opt in out source destination [options]
            read -r num pkts bytes target prot opt in out source destination rest <<< "$line"
            
            # Apply filters if specified
            if [ -n "$FILTER_INTERFACE" ] && [ "$in" != "$FILTER_INTERFACE" ] && [ "$out" != "$FILTER_INTERFACE" ]; then
                continue
            fi
            
            if [ -n "$FILTER_PORT" ]; then
                if ! echo "$rest" | grep -q -E "dpt:$FILTER_PORT|spt:$FILTER_PORT|dports?\ $FILTER_PORT|sports?\ $FILTER_PORT"; then
                    continue
                fi
            fi
            
            # Resolve IP addresses if requested
            if [ "$RESOLVE_IPS" = true ]; then
                source=$(resolve_ip "$source")
                destination=$(resolve_ip "$destination")
            fi
            
            # Extract port information if present
            local port=""
            if [[ "$rest" =~ dpt:([0-9]+) ]]; then
                port="${BASH_REMATCH[1]}"
            elif [[ "$rest" =~ spt:([0-9]+) ]]; then
                port="${BASH_REMATCH[1]}"
            elif [[ "$rest" =~ dports?\ ([0-9]+) ]]; then
                port="${BASH_REMATCH[1]}"
            elif [[ "$rest" =~ sports?\ ([0-9]+) ]]; then
                port="${BASH_REMATCH[1]}"
            fi
            
            # Format and output rule based on selected format
            case "$OUTPUT_FORMAT" in
                "csv")
                    echo "iptables,$table,$current_chain,$num,\"Rule #$num\",$prot,$source,$destination,$in/$out,$port,$target,\"$rest\"" >> "$OUTPUT_FILE"
                    ;;
                "json")
                    # Add comma if not the first rule
                    if [ "$first_rule" = "false" ]; then
                        echo "," >> "$OUTPUT_FILE"
                    else
                        first_rule=false
                    fi
                    
                    cat >> "$OUTPUT_FILE" << EOF
    {
      "firewall": "iptables",
      "table": "$table",
      "chain": "$current_chain",
      "position": $num,
      "protocol": "$prot",
      "source": "$source",
      "destination": "$destination",
      "in_interface": "$in",
      "out_interface": "$out",
      "port": "$port",
      "action": "$target",
      "packets": $pkts,
      "bytes": $bytes,
      "extra": "$rest"
    }
EOF
                    ;;
                "html")
                    # If this is the first rule for this table/chain, create a new table
                    if [ "$first_rule" = "true" ]; then
                        first_rule=false
                        
                        cat >> "$OUTPUT_FILE" << EOF
    <div class="firewall-section">
    <h2>IPTables Rules - Table: $table</h2>
    <table>
        <tr>
            <th>Chain</th>
            <th>Rule #</th>
            <th>Protocol</th>
            <th>Source</th>
            <th>Destination</th>
            <th>Interface (in/out)</th>
            <th>Port</th>
            <th>Action</th>
            <th>Options</th>
        </tr>
EOF
                    fi
                    
                    # Color the action/target based on its value
                    local class=""
                    if [[ "$target" == "ACCEPT" ]]; then
                        class="accept"
                    elif [[ "$target" == "DROP" || "$target" == "REJECT" ]]; then
                        class="drop"
                    fi
                    
                    cat >> "$OUTPUT_FILE" << EOF
        <tr>
            <td>$current_chain</td>
            <td>$num</td>
            <td>$prot</td>
            <td>$source</td>
            <td>$destination</td>
            <td>$in/$out</td>
            <td>$port</td>
            <td class="$class">$target</td>
            <td>$rest</td>
        </tr>
EOF
                    ;;
                "xml")
                    cat >> "$OUTPUT_FILE" << EOF
  <Rule>
    <Firewall>iptables</Firewall>
    <Table>$table</Table>
    <Chain>$current_chain</Chain>
    <Position>$num</Position>
    <Protocol>$prot</Protocol>
    <Source>$source</Source>
    <Destination>$destination</Destination>
    <InInterface>$in</InInterface>
    <OutInterface>$out</OutInterface>
    <Port>$port</Port>
    <Action>$target</Action>
    <Packets>$pkts</Packets>
    <Bytes>$bytes</Bytes>
    <Extra>$rest</Extra>
  </Rule>
EOF
                    ;;
                *)
                    # Plain text format
                    echo "Table: $table | Chain: $current_chain | Rule: $num" >> "$OUTPUT_FILE"
                    echo "  Protocol: $prot" >> "$OUTPUT_FILE"
                    echo "  Source: $source" >> "$OUTPUT_FILE"
                    echo "  Destination: $destination" >> "$OUTPUT_FILE"
                    echo "  Interface (in/out): $in/$out" >> "$OUTPUT_FILE"
                    echo "  Action: $target" >> "$OUTPUT_FILE"
                    if [ -n "$port" ]; then
                        echo "  Port: $port" >> "$OUTPUT_FILE"
                    fi
                    echo "  Options: $rest" >> "$OUTPUT_FILE"
                    echo "  Packets/Bytes: $pkts/$bytes" >> "$OUTPUT_FILE"
                    echo "" >> "$OUTPUT_FILE"
                    ;;
            esac
        done < "$tmpfile"
        
        # If HTML format and we've processed rules, close the table
        if [ "$OUTPUT_FORMAT" = "html" ] && [ "$first_rule" = "false" ]; then
            echo "    </table>" >> "$OUTPUT_FILE"
            echo "    </div>" >> "$OUTPUT_FILE"
            first_rule=true
        fi
    done
    
    # Clean up
    rm -f "$tmpfile"
    
    if [ "$QUIET" = false ]; then
        log_success "IPTables rules processed"
    fi
}

# Function to get nftables rules
get_nftables_rules() {
    print_section "Getting NFTables Rules"
    
    local tmpfile="/tmp/nftables_rules_$$"
    
    # Get all nftables rules in JSON format for easier parsing
    nft -j list ruleset > "$tmpfile"
    
    # Check if there are any rules
    if [ "$(cat "$tmpfile" | grep -c "rule")" -eq 0 ]; then
        log_warning "No NFTables rules found"
        rm -f "$tmpfile"
        return
    fi
    
    # TODO: Implement detailed NFTables parsing
    # For now, just include the raw output in text format
    if [ "$OUTPUT_FORMAT" = "plain" ]; then
        echo "=== NFTables Rules ===" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        nft list ruleset >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    else
        log_warning "Detailed NFTables parsing is not implemented for $OUTPUT_FORMAT format"
        log_warning "Use '--format plain' for NFTables rules"
    fi
    
    # Clean up
    rm -f "$tmpfile"
    
    if [ "$QUIET" = false ]; then
        log_success "NFTables rules processed"
    fi
}

# Function to get UFW rules
get_ufw_rules() {
    print_section "Getting UFW Rules"
    
    local tmpfile="/tmp/ufw_rules_$$"
    
    # Check if UFW is enabled
    ufw status > "$tmpfile"
    
    if grep -q "inactive" "$tmpfile"; then
        log_warning "UFW is inactive"
        if [ "$INCLUDE_INACTIVE" = false ]; then
            rm -f "$tmpfile"
            return
        fi
    fi
    
    # Get verbose output for more details
    ufw status verbose > "$tmpfile"
    
    # Output in selected format
    case "$OUTPUT_FORMAT" in
        "plain")
            echo "=== UFW Rules ===" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            cat "$tmpfile" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            ;;
        *)
            # For other formats, we'd need to parse the UFW output
            # This is a simplified implementation
            log_warning "Detailed UFW parsing is not implemented for $OUTPUT_FORMAT format"
            log_warning "Use '--format plain' for UFW rules"
            ;;
    esac
    
    # Clean up
    rm -f "$tmpfile"
    
    if [ "$QUIET" = false ]; then
        log_success "UFW rules processed"
    fi
}

# Function to get firewalld rules
get_firewalld_rules() {
    print_section "Getting FirewallD Rules"
    
    # Check if firewalld is running
    if ! firewall-cmd --state &>/dev/null; then
        log_warning "FirewallD is not running"
        if [ "$INCLUDE_INACTIVE" = false ]; then
            return
        fi
    fi
    
    local tmpfile="/tmp/firewalld_rules_$$"
    
    # Get list of zones
    local zones
    zones=$(firewall-cmd --get-zones 2>/dev/null)
    
    if [ -z "$zones" ]; then
        log_warning "No FirewallD zones found"
        return
    fi
    
    # Process each zone
    for zone in $zones; do
        if [ "$VERBOSE" = true ] && [ "$QUIET" = false ]; then
            log_info "Processing zone: $zone"
        fi
        
        # Get zone details
        firewall-cmd --zone="$zone" --list-all > "$tmpfile"
        
        # Output in selected format
        case "$OUTPUT_FORMAT" in
            "plain")
                echo "=== FirewallD Zone: $zone ===" >> "$OUTPUT_FILE"
                echo "" >> "$OUTPUT_FILE"
                cat "$tmpfile" >> "$OUTPUT_FILE"
                echo "" >> "$OUTPUT_FILE"
                ;;
            *)
                # For other formats, we'd need to parse the FirewallD output
                # This is a simplified implementation
                log_warning "Detailed FirewallD parsing is not implemented for $OUTPUT_FORMAT format"
                log_warning "Use '--format plain' for FirewallD rules"
                ;;
        esac
    done
    
    # Clean up
    rm -f "$tmpfile"
    
    if [ "$QUIET" = false ]; then
        log_success "FirewallD rules processed"
    fi
}

# Function to compare with a previous report (diff)
compare_with_previous() {
    local current_file="$1"
    local previous_file="$2"
    
    print_section "Comparing with Previous Report"
    
    if [ ! -f "$previous_file" ]; then
        log_error "Previous report file not found: $previous_file"
        return 1
    fi
    
    # Create a temporary file for the diff output
    local diff_output="/tmp/firewall_diff_$$"
    
    # Perform diff
    if diff -u "$previous_file" "$current_file" > "$diff_output"; then
        log_info "No differences found between current and previous report"
    else
        log_info "Differences found between current and previous report:"
        echo ""
        cat "$diff_output"
        echo ""
    fi
    
    # Clean up
    rm -f "$diff_output"
}

# Main function
main() {
    print_header "Firewall Rules Report"
    
    # Check if running as root
    check_root
    
    # Detect firewall types
    detect_firewall_types || true
    
    # Initialize output
    initialize_output "$OUTPUT_FORMAT" "$OUTPUT_FILE"
    
    # Generate reports based on firewall type
    if [ "$FIREWALL_TYPE" = "iptables" ] || [ "$FIREWALL_TYPE" = "all" ]; then
        if command_exists "iptables"; then
            get_iptables_rules
        else
            log_warning "iptables command not found, skipping IPTables rules"
        fi
    fi
    
    if [ "$FIREWALL_TYPE" = "nftables" ] || [ "$FIREWALL_TYPE" = "all" ]; then
        if command_exists "nft"; then
            get_nftables_rules
        else
            log_warning "nft command not found, skipping NFTables rules"
        fi
    fi
    
    if [ "$FIREWALL_TYPE" = "ufw" ] || [ "$FIREWALL_TYPE" = "all" ]; then
        if command_exists "ufw"; then
            get_ufw_rules
        else
            log_warning "ufw command not found, skipping UFW rules"
        fi
    fi
    
    if [ "$FIREWALL_TYPE" = "firewalld" ] || [ "$FIREWALL_TYPE" = "all" ]; then
        if command_exists "firewall-cmd"; then
            get_firewalld_rules
        else
            log_warning "firewall-cmd command not found, skipping FirewallD rules"
        fi
    fi
    
    # Finalize output
    finalize_output "$OUTPUT_FORMAT" "$OUTPUT_FILE"
    
    # Compare with previous report if requested
    if [ -n "$DIFF_FILE" ]; then
        compare_with_previous "$OUTPUT_FILE" "$DIFF_FILE"
    fi
    
    if [ "$QUIET" = false ]; then
        log_success "Firewall rules report completed"
    fi
}

# Run the main function
main