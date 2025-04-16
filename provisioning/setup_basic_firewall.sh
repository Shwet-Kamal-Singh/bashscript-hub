#!/bin/bash
#
# Script Name: setup_basic_firewall.sh
# Description: Set up basic firewall rules across different Linux distributions
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./setup_basic_firewall.sh [options]
#
# Options:
#   -t, --type <type>            Firewall type: auto|ufw|firewalld|iptables (default: auto)
#   -s, --ssh-port <port>        SSH port to allow (default: 22)
#   -p, --ports <ports>          Additional ports to open (comma-separated, e.g., 80,443)
#   -i, --interfaces <list>      Network interfaces to apply rules (comma-separated)
#   -r, --reject                 Use reject instead of drop for blocked traffic
#   -l, --limit-ssh              Enable SSH connection rate limiting
#   -I, --ipv4-only              Apply rules only to IPv4 (default: IPv4 and IPv6)
#   -6, --ipv6-only              Apply rules only to IPv6
#   -L, --log-dropped            Log dropped packets
#   -S, --services <list>        Additional services to allow (comma-separated, e.g., http,https)
#   -d, --default <policy>       Default policy: deny|allow (default: deny)
#   -a, --allow-established      Allow established and related connections (default: true)
#   -f, --save-rules             Save rules to be persistent across reboots
#   -D, --disable                Disable firewall and remove rules
#   -b, --backup                 Create a backup of existing rules
#   -v, --verbose                Show detailed output
#   -h, --help                   Display this help message
#
# Examples:
#   ./setup_basic_firewall.sh
#   ./setup_basic_firewall.sh -t ufw -p 80,443,8080 -l
#   ./setup_basic_firewall.sh -t firewalld -S http,https,mysql
#
# Requirements:
#   - Root privileges (or sudo)
#   - One of: ufw, firewalld, or iptables
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
SSH_PORT=22
ADDITIONAL_PORTS=""
NETWORK_INTERFACES=""
USE_REJECT=false
LIMIT_SSH=false
IPV4_ONLY=false
IPV6_ONLY=false
LOG_DROPPED=false
ADDITIONAL_SERVICES=""
DEFAULT_POLICY="deny"
ALLOW_ESTABLISHED=true
SAVE_RULES=true
DISABLE_FIREWALL=false
CREATE_BACKUP=false
VERBOSE=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "auto" && "$2" != "ufw" && "$2" != "firewalld" && "$2" != "iptables" ]]; then
                log_error "Invalid firewall type: $2"
                log_error "Valid options: auto, ufw, firewalld, iptables"
                exit 1
            fi
            FIREWALL_TYPE="$2"
            shift 2
            ;;
        -s|--ssh-port)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ] || [ "$2" -gt 65535 ]; then
                log_error "Invalid SSH port: $2"
                exit 1
            fi
            SSH_PORT="$2"
            shift 2
            ;;
        -p|--ports)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            # Validate that all ports are numbers
            if ! [[ "$2" =~ ^[0-9,]+$ ]]; then
                log_error "Invalid port list format: $2"
                log_error "Format should be comma-separated numbers, e.g., 80,443,8080"
                exit 1
            fi
            ADDITIONAL_PORTS="$2"
            shift 2
            ;;
        -i|--interfaces)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            NETWORK_INTERFACES="$2"
            shift 2
            ;;
        -r|--reject)
            USE_REJECT=true
            shift
            ;;
        -l|--limit-ssh)
            LIMIT_SSH=true
            shift
            ;;
        -I|--ipv4-only)
            IPV4_ONLY=true
            shift
            ;;
        -6|--ipv6-only)
            IPV6_ONLY=true
            shift
            ;;
        -L|--log-dropped)
            LOG_DROPPED=true
            shift
            ;;
        -S|--services)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            ADDITIONAL_SERVICES="$2"
            shift 2
            ;;
        -d|--default)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "deny" && "$2" != "allow" ]]; then
                log_error "Invalid default policy: $2"
                log_error "Valid options: deny, allow"
                exit 1
            fi
            DEFAULT_POLICY="$2"
            shift 2
            ;;
        -a|--allow-established)
            ALLOW_ESTABLISHED=true
            shift
            ;;
        -f|--save-rules)
            SAVE_RULES=true
            shift
            ;;
        -D|--disable)
            DISABLE_FIREWALL=true
            shift
            ;;
        -b|--backup)
            CREATE_BACKUP=true
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

# Check if running with root/sudo
check_root() {
    if [ $EUID -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Detect Linux distribution
detect_distribution() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        DISTRO="$ID"
        VERSION="$VERSION_ID"
    elif [ -f /etc/lsb-release ]; then
        # shellcheck disable=SC1091
        source /etc/lsb-release
        DISTRO="$DISTRIB_ID"
        VERSION="$DISTRIB_RELEASE"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
        VERSION=$(cat /etc/debian_version)
    elif [ -f /etc/redhat-release ]; then
        DISTRO=$(grep -oP '(?<=^)[^[:space:]]+' /etc/redhat-release | tr '[:upper:]' '[:lower:]')
        VERSION=$(grep -oP '(?<=release )[[:digit:]]+' /etc/redhat-release)
    else
        DISTRO="unknown"
        VERSION="unknown"
    fi

    # Normalize distro names
    case "$DISTRO" in
        "ubuntu"|"debian"|"linuxmint")
            DISTRO_FAMILY="debian"
            ;;
        "rhel"|"centos"|"fedora"|"rocky"|"almalinux"|"ol")
            DISTRO_FAMILY="redhat"
            ;;
        "opensuse"*|"sles")
            DISTRO_FAMILY="suse"
            ;;
        "arch"|"manjaro")
            DISTRO_FAMILY="arch"
            ;;
        *)
            DISTRO_FAMILY="unknown"
            ;;
    esac

    log_info "Detected distribution: $DISTRO $VERSION (family: $DISTRO_FAMILY)"
}

# Detect and select firewall
detect_firewall() {
    if [ "$FIREWALL_TYPE" != "auto" ]; then
        # Check if the specified firewall is available
        case "$FIREWALL_TYPE" in
            "ufw")
                if ! command -v ufw &>/dev/null; then
                    log_error "UFW is not installed"
                    exit 1
                fi
                ;;
            "firewalld")
                if ! command -v firewall-cmd &>/dev/null; then
                    log_error "FirewallD is not installed"
                    exit 1
                fi
                ;;
            "iptables")
                if ! command -v iptables &>/dev/null; then
                    log_error "iptables is not installed"
                    exit 1
                fi
                ;;
        esac
        log_info "Using specified firewall: $FIREWALL_TYPE"
        return
    fi

    # Detect available firewalls
    local available_firewalls=()
    
    if command -v ufw &>/dev/null; then
        available_firewalls+=("ufw")
    fi
    
    if command -v firewall-cmd &>/dev/null; then
        available_firewalls+=("firewalld")
    fi
    
    if command -v iptables &>/dev/null; then
        available_firewalls+=("iptables")
    fi
    
    if [ ${#available_firewalls[@]} -eq 0 ]; then
        log_error "No supported firewall found"
        log_error "Please install ufw, firewalld, or iptables"
        exit 1
    fi
    
    # Select the preferred firewall based on distribution and availability
    if [ "$DISTRO_FAMILY" = "debian" ] && [[ " ${available_firewalls[*]} " =~ " ufw " ]]; then
        FIREWALL_TYPE="ufw"
    elif [ "$DISTRO_FAMILY" = "redhat" ] && [[ " ${available_firewalls[*]} " =~ " firewalld " ]]; then
        FIREWALL_TYPE="firewalld"
    elif [ "$DISTRO_FAMILY" = "suse" ] && [[ " ${available_firewalls[*]} " =~ " firewalld " ]]; then
        FIREWALL_TYPE="firewalld"
    elif [ "$DISTRO_FAMILY" = "arch" ] && [[ " ${available_firewalls[*]} " =~ " ufw " ]]; then
        FIREWALL_TYPE="ufw"
    else
        # Fallback to the first available firewall
        FIREWALL_TYPE="${available_firewalls[0]}"
    fi
    
    log_info "Selected firewall: $FIREWALL_TYPE"
}

# Get the list of network interfaces
get_network_interfaces() {
    if [ -n "$NETWORK_INTERFACES" ]; then
        return
    fi
    
    # Get all active network interfaces except lo
    local interfaces=$(ip -o link show up | awk -F': ' '{print $2}' | grep -v 'lo')
    NETWORK_INTERFACES=$(echo "$interfaces" | tr '\n' ',' | sed 's/,$//')
    
    if [ -z "$NETWORK_INTERFACES" ]; then
        log_warning "No active network interfaces found"
        log_info "Using default interface settings"
    else
        log_info "Detected network interfaces: $NETWORK_INTERFACES"
    fi
}

# Create a backup of existing firewall rules
backup_firewall_rules() {
    if [ "$CREATE_BACKUP" != true ]; then
        return
    fi
    
    print_section "Backing up current firewall rules"
    
    local backup_dir="/root/firewall_backup"
    local backup_file="$backup_dir/$(date +%Y%m%d%H%M%S)_${FIREWALL_TYPE}_backup"
    
    # Create backup directory if it doesn't exist
    mkdir -p "$backup_dir"
    
    case "$FIREWALL_TYPE" in
        "ufw")
            ufw status verbose > "$backup_file"
            ;;
        "firewalld")
            firewall-cmd --list-all --permanent > "$backup_file"
            ;;
        "iptables")
            iptables-save > "$backup_file"
            if ! [ "$IPV4_ONLY" = true ]; then
                ip6tables-save > "${backup_file}_ipv6"
            fi
            ;;
    esac
    
    log_success "Firewall rules backed up to $backup_file"
}

# Disable firewall and remove rules
disable_firewall() {
    print_section "Disabling firewall"
    
    case "$FIREWALL_TYPE" in
        "ufw")
            log_info "Disabling UFW..."
            ufw disable
            ;;
        "firewalld")
            log_info "Disabling FirewallD..."
            systemctl stop firewalld
            systemctl disable firewalld
            ;;
        "iptables")
            log_info "Clearing iptables rules..."
            # Flush all chains
            iptables -F
            iptables -X
            iptables -t nat -F
            iptables -t nat -X
            iptables -t mangle -F
            iptables -t mangle -X
            
            # Set default policies to ACCEPT
            iptables -P INPUT ACCEPT
            iptables -P FORWARD ACCEPT
            iptables -P OUTPUT ACCEPT
            
            # Save rules if requested
            if [ "$SAVE_RULES" = true ]; then
                if [ -f /etc/debian_version ]; then
                    iptables-save > /etc/iptables/rules.v4
                elif [ -f /etc/redhat-release ]; then
                    iptables-save > /etc/sysconfig/iptables
                fi
            fi
            
            # Do the same for IPv6 if not IPv4 only
            if [ "$IPV4_ONLY" != true ]; then
                ip6tables -F
                ip6tables -X
                ip6tables -t nat -F
                ip6tables -t nat -X
                ip6tables -t mangle -F
                ip6tables -t mangle -X
                ip6tables -P INPUT ACCEPT
                ip6tables -P FORWARD ACCEPT
                ip6tables -P OUTPUT ACCEPT
                
                if [ "$SAVE_RULES" = true ]; then
                    if [ -f /etc/debian_version ]; then
                        ip6tables-save > /etc/iptables/rules.v6
                    elif [ -f /etc/redhat-release ]; then
                        ip6tables-save > /etc/sysconfig/ip6tables
                    fi
                fi
            fi
            ;;
    esac
    
    log_success "Firewall disabled and rules cleared"
}

# Configure UFW firewall
configure_ufw() {
    print_section "Configuring UFW Firewall"
    
    # Reset UFW to default settings
    log_info "Resetting UFW to default settings..."
    ufw --force reset
    
    # Set default policies
    log_info "Setting default policies..."
    if [ "$DEFAULT_POLICY" = "deny" ]; then
        ufw default deny incoming
    else
        ufw default allow incoming
    fi
    ufw default allow outgoing
    
    # Allow SSH
    log_info "Allowing SSH on port $SSH_PORT..."
    if [ "$LIMIT_SSH" = true ]; then
        ufw limit "$SSH_PORT/tcp" comment "SSH"
    else
        ufw allow "$SSH_PORT/tcp" comment "SSH"
    fi
    
    # Allow additional ports
    if [ -n "$ADDITIONAL_PORTS" ]; then
        log_info "Allowing additional ports: $ADDITIONAL_PORTS"
        IFS=',' read -ra PORTS <<< "$ADDITIONAL_PORTS"
        for port in "${PORTS[@]}"; do
            ufw allow "$port/tcp" comment "Custom port $port"
            ufw allow "$port/udp" comment "Custom port $port"
        done
    fi
    
    # Allow additional services
    if [ -n "$ADDITIONAL_SERVICES" ]; then
        log_info "Allowing additional services: $ADDITIONAL_SERVICES"
        IFS=',' read -ra SERVICES <<< "$ADDITIONAL_SERVICES"
        for service in "${SERVICES[@]}"; do
            ufw allow "$service" comment "Service $service"
        done
    fi
    
    # Configure logging if requested
    if [ "$LOG_DROPPED" = true ]; then
        log_info "Enabling logging for dropped packets..."
        ufw logging on
    else
        ufw logging off
    fi
    
    # Enable IPv6 if not IPv4 only
    if [ "$IPV4_ONLY" = true ]; then
        log_info "Disabling IPv6 support..."
        sed -i 's/IPV6=yes/IPV6=no/' /etc/default/ufw
    elif [ "$IPV6_ONLY" = true ]; then
        log_warning "UFW cannot run in IPv6-only mode, will use dual-stack"
        sed -i 's/IPV6=no/IPV6=yes/' /etc/default/ufw
    else
        log_info "Enabling IPv6 support..."
        sed -i 's/IPV6=no/IPV6=yes/' /etc/default/ufw
    fi
    
    # Enable UFW
    log_info "Enabling UFW..."
    echo "y" | ufw enable
    
    # Display status
    ufw status verbose
    
    log_success "UFW configuration complete"
}

# Configure FirewallD firewall
configure_firewalld() {
    print_section "Configuring FirewallD"
    
    # Start and enable FirewallD
    log_info "Starting FirewallD service..."
    systemctl start firewalld
    systemctl enable firewalld
    
    # Determine default zone
    local default_zone=$(firewall-cmd --get-default-zone)
    log_info "Default zone: $default_zone"
    
    # Set default policies
    log_info "Setting default policies..."
    if [ "$DEFAULT_POLICY" = "deny" ]; then
        firewall-cmd --permanent --set-target=DROP --zone="$default_zone"
    else
        firewall-cmd --permanent --set-target=ACCEPT --zone="$default_zone"
    fi
    
    # Allow established connections if requested
    if [ "$ALLOW_ESTABLISHED" = true ]; then
        log_info "Allowing established and related connections..."
        # This is enabled by default in FirewallD
    fi
    
    # Allow SSH
    log_info "Allowing SSH on port $SSH_PORT..."
    if [ "$SSH_PORT" = "22" ]; then
        firewall-cmd --permanent --add-service=ssh --zone="$default_zone"
    else
        firewall-cmd --permanent --remove-service=ssh --zone="$default_zone" 2>/dev/null
        firewall-cmd --permanent --add-port="$SSH_PORT/tcp" --zone="$default_zone"
    fi
    
    # Add rate limiting for SSH if requested
    if [ "$LIMIT_SSH" = true ]; then
        log_info "Adding rate limiting for SSH..."
        if [ "$SSH_PORT" = "22" ]; then
            firewall-cmd --permanent --add-rich-rule="rule service name=ssh limit value=3/m accept" --zone="$default_zone"
        else
            firewall-cmd --permanent --add-rich-rule="rule port port=$SSH_PORT protocol=tcp limit value=3/m accept" --zone="$default_zone"
        fi
    fi
    
    # Allow additional ports
    if [ -n "$ADDITIONAL_PORTS" ]; then
        log_info "Allowing additional ports: $ADDITIONAL_PORTS"
        IFS=',' read -ra PORTS <<< "$ADDITIONAL_PORTS"
        for port in "${PORTS[@]}"; do
            firewall-cmd --permanent --add-port="$port/tcp" --zone="$default_zone"
            firewall-cmd --permanent --add-port="$port/udp" --zone="$default_zone"
        done
    fi
    
    # Allow additional services
    if [ -n "$ADDITIONAL_SERVICES" ]; then
        log_info "Allowing additional services: $ADDITIONAL_SERVICES"
        IFS=',' read -ra SERVICES <<< "$ADDITIONAL_SERVICES"
        for service in "${SERVICES[@]}"; do
            firewall-cmd --permanent --add-service="$service" --zone="$default_zone"
        done
    fi
    
    # Configure interfaces if specified
    if [ -n "$NETWORK_INTERFACES" ]; then
        log_info "Configuring network interfaces: $NETWORK_INTERFACES"
        IFS=',' read -ra INTERFACES <<< "$NETWORK_INTERFACES"
        for interface in "${INTERFACES[@]}"; do
            firewall-cmd --permanent --add-interface="$interface" --zone="$default_zone"
        done
    fi
    
    # Configure logging if requested
    if [ "$LOG_DROPPED" = true ]; then
        log_info "Enabling logging for dropped packets..."
        firewall-cmd --permanent --set-log-denied=all
    else
        firewall-cmd --permanent --set-log-denied=off
    fi
    
    # Configure IPv4/IPv6
    if [ "$IPV4_ONLY" = true ]; then
        log_info "Configuring for IPv4 only..."
        firewall-cmd --permanent --set-ipv6-state=no
    elif [ "$IPV6_ONLY" = true ]; then
        log_info "Configuring for IPv6 only..."
        # Note: FirewallD doesn't have a straightforward way to disable IPv4 only
        log_warning "FirewallD cannot run in IPv6-only mode, will use dual-stack"
    else
        log_info "Configuring for dual-stack IPv4/IPv6..."
        firewall-cmd --permanent --set-ipv6-state=yes
    fi
    
    # Apply changes
    log_info "Applying changes..."
    firewall-cmd --reload
    
    # Display status
    firewall-cmd --list-all
    
    log_success "FirewallD configuration complete"
}

# Configure iptables firewall
configure_iptables() {
    print_section "Configuring iptables"
    
    # Flush existing rules
    log_info "Flushing existing rules..."
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    
    # Do the same for IPv6 if not IPv4 only
    if [ "$IPV4_ONLY" != true ]; then
        ip6tables -F
        ip6tables -X
        ip6tables -t nat -F
        ip6tables -t nat -X
        ip6tables -t mangle -F
        ip6tables -t mangle -X
    fi
    
    # Set default policies
    log_info "Setting default policies..."
    if [ "$DEFAULT_POLICY" = "deny" ]; then
        if [ "$USE_REJECT" = true ]; then
            # Use REJECT as default policy (via rules, since policy can only be ACCEPT or DROP)
            iptables -P INPUT ACCEPT
            iptables -P FORWARD ACCEPT
            iptables -A INPUT -j REJECT
            iptables -A FORWARD -j REJECT
        else
            iptables -P INPUT DROP
            iptables -P FORWARD DROP
        fi
    else
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
    fi
    iptables -P OUTPUT ACCEPT
    
    # Do the same for IPv6 if not IPv4 only
    if [ "$IPV4_ONLY" != true ]; then
        if [ "$DEFAULT_POLICY" = "deny" ]; then
            if [ "$USE_REJECT" = true ]; then
                ip6tables -P INPUT ACCEPT
                ip6tables -P FORWARD ACCEPT
                ip6tables -A INPUT -j REJECT
                ip6tables -A FORWARD -j REJECT
            else
                ip6tables -P INPUT DROP
                ip6tables -P FORWARD DROP
            fi
        else
            ip6tables -P INPUT ACCEPT
            ip6tables -P FORWARD ACCEPT
        fi
        ip6tables -P OUTPUT ACCEPT
    fi
    
    # Allow loopback traffic
    log_info "Allowing loopback traffic..."
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    if [ "$IPV4_ONLY" != true ]; then
        ip6tables -A INPUT -i lo -j ACCEPT
        ip6tables -A OUTPUT -o lo -j ACCEPT
    fi
    
    # Allow established and related connections
    if [ "$ALLOW_ESTABLISHED" = true ]; then
        log_info "Allowing established and related connections..."
        iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        
        if [ "$IPV4_ONLY" != true ]; then
            ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
            ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        fi
    fi
    
    # Allow SSH
    log_info "Allowing SSH on port $SSH_PORT..."
    if [ "$LIMIT_SSH" = true ]; then
        iptables -A INPUT -p tcp --dport "$SSH_PORT" -m conntrack --ctstate NEW -m recent --set
        iptables -A INPUT -p tcp --dport "$SSH_PORT" -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
        iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
        
        if [ "$IPV4_ONLY" != true ]; then
            ip6tables -A INPUT -p tcp --dport "$SSH_PORT" -m conntrack --ctstate NEW -m recent --set
            ip6tables -A INPUT -p tcp --dport "$SSH_PORT" -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
            ip6tables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
        fi
    else
        iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
        
        if [ "$IPV4_ONLY" != true ]; then
            ip6tables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
        fi
    fi
    
    # Allow additional ports
    if [ -n "$ADDITIONAL_PORTS" ]; then
        log_info "Allowing additional ports: $ADDITIONAL_PORTS"
        IFS=',' read -ra PORTS <<< "$ADDITIONAL_PORTS"
        for port in "${PORTS[@]}"; do
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
            iptables -A INPUT -p udp --dport "$port" -j ACCEPT
            
            if [ "$IPV4_ONLY" != true ]; then
                ip6tables -A INPUT -p tcp --dport "$port" -j ACCEPT
                ip6tables -A INPUT -p udp --dport "$port" -j ACCEPT
            fi
        done
    fi
    
    # Allow ICMP (ping)
    log_info "Allowing ICMP traffic..."
    iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
    
    if [ "$IPV4_ONLY" != true ]; then
        # Allow ICMPv6 for IPv6 to work properly
        ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
    fi
    
    # Configure logging if requested
    if [ "$LOG_DROPPED" = true ]; then
        log_info "Enabling logging for dropped packets..."
        iptables -A INPUT -j LOG --log-prefix "iptables-dropped: " --log-level 4
        
        if [ "$IPV4_ONLY" != true ]; then
            ip6tables -A INPUT -j LOG --log-prefix "ip6tables-dropped: " --log-level 4
        fi
    fi
    
    # Add final drop/reject rule for INPUT chain if default policy is ACCEPT
    if [ "$DEFAULT_POLICY" = "allow" ]; then
        if [ "$USE_REJECT" = true ]; then
            iptables -A INPUT -j REJECT
            
            if [ "$IPV4_ONLY" != true ]; then
                ip6tables -A INPUT -j REJECT
            fi
        else
            iptables -A INPUT -j DROP
            
            if [ "$IPV4_ONLY" != true ]; then
                ip6tables -A INPUT -j DROP
            fi
        fi
    fi
    
    # Save rules if requested
    if [ "$SAVE_RULES" = true ]; then
        log_info "Saving rules..."
        if [ -f /etc/debian_version ]; then
            # Debian/Ubuntu
            if command -v iptables-save &>/dev/null; then
                mkdir -p /etc/iptables
                iptables-save > /etc/iptables/rules.v4
                
                if [ "$IPV4_ONLY" != true ]; then
                    ip6tables-save > /etc/iptables/rules.v6
                fi
                
                # Create systemd service to restore rules on boot
                cat > /etc/systemd/system/iptables-restore.service << EOF
[Unit]
Description=Restore iptables firewall rules
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
ExecStart=/sbin/ip6tables-restore /etc/iptables/rules.v6
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
                systemctl enable iptables-restore.service
            else
                log_warning "iptables-save command not found, rules may not persist after reboot"
            fi
        elif [ -f /etc/redhat-release ]; then
            # RHEL/CentOS/Fedora
            if command -v iptables-save &>/dev/null; then
                iptables-save > /etc/sysconfig/iptables
                
                if [ "$IPV4_ONLY" != true ]; then
                    ip6tables-save > /etc/sysconfig/ip6tables
                fi
                
                # Create systemd service for restoration if it doesn't exist
                if [ ! -f /usr/lib/systemd/system/iptables.service ]; then
                    cat > /etc/systemd/system/iptables.service << EOF
[Unit]
Description=IPv4 firewall with iptables
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/sysconfig/iptables
ExecStop=/sbin/iptables-save -c > /etc/sysconfig/iptables
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
                    systemctl enable iptables.service
                fi
                
                if [ "$IPV4_ONLY" != true ] && [ ! -f /usr/lib/systemd/system/ip6tables.service ]; then
                    cat > /etc/systemd/system/ip6tables.service << EOF
[Unit]
Description=IPv6 firewall with ip6tables
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/ip6tables-restore /etc/sysconfig/ip6tables
ExecStop=/sbin/ip6tables-save -c > /etc/sysconfig/ip6tables
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
                    systemctl enable ip6tables.service
                fi
            else
                log_warning "iptables-save command not found, rules may not persist after reboot"
            fi
        else
            log_warning "Unknown distribution, rules may not persist after reboot"
            log_info "Manually save rules with: iptables-save > /etc/iptables.rules"
        fi
    fi
    
    # Display rules
    log_info "Current IPv4 rules:"
    iptables -L -v
    
    if [ "$IPV4_ONLY" != true ]; then
        log_info "Current IPv6 rules:"
        ip6tables -L -v
    fi
    
    log_success "iptables configuration complete"
}

# Main function
main() {
    print_header "Basic Firewall Setup"
    
    # Check if running as root
    check_root
    
    # Detect distribution
    detect_distribution
    
    # Detect firewall
    detect_firewall
    
    # Get network interfaces
    get_network_interfaces
    
    # Create a backup if requested
    backup_firewall_rules
    
    # Check if we should disable the firewall
    if [ "$DISABLE_FIREWALL" = true ]; then
        disable_firewall
        exit 0
    fi
    
    # Configure the selected firewall
    case "$FIREWALL_TYPE" in
        "ufw")
            configure_ufw
            ;;
        "firewalld")
            configure_firewalld
            ;;
        "iptables")
            configure_iptables
            ;;
        *)
            log_error "Unknown firewall type: $FIREWALL_TYPE"
            exit 1
            ;;
    esac
    
    print_header "Firewall Setup Complete"
    log_success "Basic firewall has been set up successfully"
}

# Run the main function
main