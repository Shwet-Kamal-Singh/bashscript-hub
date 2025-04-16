#!/bin/bash
#
# Script Name: ssh_hardening.sh
# Description: Apply SSH security hardening best practices to the system
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./ssh_hardening.sh [options]
#
# Options:
#   -p, --port <port>              Change SSH port (default: 22)
#   -k, --key-auth-only            Disable password authentication
#   -r, --root-login <yes|no|prohibit-password>
#                                  Control root login (default: prohibit-password)
#   -m, --max-auth-tries <num>     Set maximum authentication attempts (default: 4)
#   -l, --login-grace-time <sec>   Set login grace time in seconds (default: 60)
#   -i, --idle-timeout <min>       Set client alive interval in minutes (default: 15)
#   -a, --allowed-users <list>     Comma-separated list of allowed users
#   -g, --allowed-groups <list>    Comma-separated list of allowed groups
#   -c, --ciphers <list>           Comma-separated list of allowed ciphers
#   -M, --macs <list>              Comma-separated list of allowed MACs
#   -K, --kex <list>               Comma-separated list of allowed key exchange algorithms
#   -2, --protocol-2-only          Force Protocol 2 only
#   -t, --tcp-forwarding <yes|no>  Control TCP forwarding (default: no)
#   -x, --x11-forwarding <yes|no>  Control X11 forwarding (default: no)
#   -b, --backup                   Create a backup of the original config
#   -A, --audit-only               Only audit the SSH configuration, don't make changes
#   -v, --verbose                  Show detailed output
#   -h, --help                     Display this help message
#
# Examples:
#   ./ssh_hardening.sh
#   ./ssh_hardening.sh -p 2222 -k -r no -b
#   ./ssh_hardening.sh -a admin,user1 -g sudo,wheel
#   ./ssh_hardening.sh -A -v
#
# Requirements:
#   - Root privileges (or sudo)
#   - OpenSSH server installed
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
SSH_PORT=22
KEY_AUTH_ONLY=false
ROOT_LOGIN="prohibit-password"
MAX_AUTH_TRIES=4
LOGIN_GRACE_TIME=60
IDLE_TIMEOUT=15
ALLOWED_USERS=""
ALLOWED_GROUPS=""
CIPHERS=""
MACS=""
KEX_ALGORITHMS=""
PROTOCOL_2_ONLY=true
TCP_FORWARDING="no"
X11_FORWARDING="no"
CREATE_BACKUP=false
AUDIT_ONLY=false
VERBOSE=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ] || [ "$2" -gt 65535 ]; then
                log_error "Invalid port number: $2"
                exit 1
            fi
            SSH_PORT="$2"
            shift 2
            ;;
        -k|--key-auth-only)
            KEY_AUTH_ONLY=true
            shift
            ;;
        -r|--root-login)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "yes" && "$2" != "no" && "$2" != "prohibit-password" ]]; then
                log_error "Invalid root login option: $2"
                log_error "Valid options: yes, no, prohibit-password"
                exit 1
            fi
            ROOT_LOGIN="$2"
            shift 2
            ;;
        -m|--max-auth-tries)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid max auth tries: $2"
                exit 1
            fi
            MAX_AUTH_TRIES="$2"
            shift 2
            ;;
        -l|--login-grace-time)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid login grace time: $2"
                exit 1
            fi
            LOGIN_GRACE_TIME="$2"
            shift 2
            ;;
        -i|--idle-timeout)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid idle timeout: $2"
                exit 1
            fi
            IDLE_TIMEOUT="$2"
            shift 2
            ;;
        -a|--allowed-users)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            ALLOWED_USERS="$2"
            shift 2
            ;;
        -g|--allowed-groups)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            ALLOWED_GROUPS="$2"
            shift 2
            ;;
        -c|--ciphers)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            CIPHERS="$2"
            shift 2
            ;;
        -M|--macs)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            MACS="$2"
            shift 2
            ;;
        -K|--kex)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            KEX_ALGORITHMS="$2"
            shift 2
            ;;
        -2|--protocol-2-only)
            PROTOCOL_2_ONLY=true
            shift
            ;;
        -t|--tcp-forwarding)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "yes" && "$2" != "no" ]]; then
                log_error "Invalid TCP forwarding option: $2"
                log_error "Valid options: yes, no"
                exit 1
            fi
            TCP_FORWARDING="$2"
            shift 2
            ;;
        -x|--x11-forwarding)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "yes" && "$2" != "no" ]]; then
                log_error "Invalid X11 forwarding option: $2"
                log_error "Valid options: yes, no"
                exit 1
            fi
            X11_FORWARDING="$2"
            shift 2
            ;;
        -b|--backup)
            CREATE_BACKUP=true
            shift
            ;;
        -A|--audit-only)
            AUDIT_ONLY=true
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
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root or with sudo"
    exit 1
fi

# Find SSH configuration file
find_ssh_config() {
    local config_file=""
    
    # Look for the configuration file in common locations
    for file in /etc/ssh/sshd_config /usr/local/etc/ssh/sshd_config /usr/local/etc/sshd_config; do
        if [ -f "$file" ]; then
            config_file="$file"
            break
        fi
    done
    
    if [ -z "$config_file" ]; then
        log_error "Cannot find SSH server configuration file"
        exit 1
    fi
    
    echo "$config_file"
}

# Check if SSH server is installed
check_ssh_installed() {
    print_section "Checking for SSH server"
    
    if ! command -v sshd &>/dev/null; then
        log_error "OpenSSH server (sshd) is not installed"
        exit 1
    fi
    
    log_success "OpenSSH server is installed"
    if [ "$VERBOSE" = true ]; then
        sshd -V
    fi
}

# Create a backup of the SSH configuration
backup_config() {
    local config_file="$1"
    local backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    
    print_section "Creating backup of SSH configuration"
    
    if ! cp "$config_file" "$backup_file"; then
        log_error "Failed to create backup of SSH configuration"
        exit 1
    fi
    
    log_success "Created backup: $backup_file"
}

# Get secure recommendations for cryptographic settings
get_secure_recommendations() {
    print_section "Determining secure cryptographic settings"
    
    # Get SSH version
    SSH_VERSION=$(sshd -V 2>&1 | grep -oP 'OpenSSH_\K[0-9]+\.[0-9]+' || echo "7.0")
    MAJOR_VERSION=$(echo "$SSH_VERSION" | cut -d. -f1)
    MINOR_VERSION=$(echo "$SSH_VERSION" | cut -d. -f2)
    
    if [ "$VERBOSE" = true ]; then
        log_info "Detected OpenSSH version: $SSH_VERSION"
    fi
    
    # Default secure ciphers 
    if [ -z "$CIPHERS" ]; then
        if (( MAJOR_VERSION >= 7 && MINOR_VERSION >= 6 )); then
            # Newer OpenSSH versions
            CIPHERS="chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
        else
            # Older OpenSSH versions
            CIPHERS="chacha20-poly1305@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
        fi
    fi
    
    # Default secure MACs
    if [ -z "$MACS" ]; then
        if (( MAJOR_VERSION >= 7 && MINOR_VERSION >= 6 )); then
            # Newer OpenSSH versions
            MACS="hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256"
        else
            # Older OpenSSH versions
            MACS="hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com"
        fi
    fi
    
    # Default secure key exchange algorithms
    if [ -z "$KEX_ALGORITHMS" ]; then
        if (( MAJOR_VERSION >= 7 && MINOR_VERSION >= 6 )); then
            # Newer OpenSSH versions
            KEX_ALGORITHMS="curve25519-sha256@libssh.org,curve25519-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256"
        else
            # Older OpenSSH versions
            KEX_ALGORITHMS="curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256,diffie-hellman-group14-sha1"
        fi
    fi
}

# Audit SSH configuration
audit_ssh_config() {
    local config_file="$1"
    
    print_header "SSH Configuration Audit"
    
    # Function to check a setting
    check_setting() {
        local setting="$1"
        local expected="$2"
        local recommendation="$3"
        
        local current_value
        current_value=$(grep -E "^[[:space:]]*$setting[[:space:]]+" "$config_file" | cut -d' ' -f2-)
        
        if [ -z "$current_value" ]; then
            log_warning "Setting $setting is not configured"
            log_info "Recommendation: $setting $expected ($recommendation)"
            return 1
        elif [ "$current_value" = "$expected" ]; then
            log_success "Setting $setting is correctly set to $expected"
            return 0
        else
            log_warning "Setting $setting is set to $current_value, should be $expected"
            log_info "Recommendation: $setting $expected ($recommendation)"
            return 1
        fi
    }
    
    # Port
    check_setting "Port" "$SSH_PORT" "Change default SSH port to reduce automated attacks"
    
    # Protocol
    if [ "$PROTOCOL_2_ONLY" = true ]; then
        check_setting "Protocol" "2" "Use only SSH Protocol version 2"
    fi
    
    # Authentication settings
    if [ "$KEY_AUTH_ONLY" = true ]; then
        check_setting "PasswordAuthentication" "no" "Disable password authentication"
        check_setting "ChallengeResponseAuthentication" "no" "Disable challenge-response authentication"
    fi
    
    # Root login
    check_setting "PermitRootLogin" "$ROOT_LOGIN" "Control root login permissions"
    
    # Auth tries and timing
    check_setting "MaxAuthTries" "$MAX_AUTH_TRIES" "Limit authentication attempts"
    check_setting "LoginGraceTime" "$LOGIN_GRACE_TIME" "Limit authentication time window"
    check_setting "ClientAliveInterval" "$((IDLE_TIMEOUT * 60))" "Set idle timeout"
    check_setting "ClientAliveCountMax" "0" "Disconnect after idle timeout"
    
    # Forwarding
    check_setting "AllowTcpForwarding" "$TCP_FORWARDING" "Control TCP forwarding"
    check_setting "X11Forwarding" "$X11_FORWARDING" "Control X11 forwarding"
    
    # Crypto settings
    check_setting "Ciphers" "$CIPHERS" "Use secure ciphers"
    check_setting "MACs" "$MACS" "Use secure message authentication codes"
    check_setting "KexAlgorithms" "$KEX_ALGORITHMS" "Use secure key exchange algorithms"
    
    # Other security settings
    check_setting "UsePAM" "yes" "Use PAM for authentication"
    check_setting "PermitEmptyPasswords" "no" "Disallow empty passwords"
    check_setting "IgnoreRhosts" "yes" "Ignore .rhosts files"
    check_setting "HostbasedAuthentication" "no" "Disable host-based authentication"
    check_setting "PermitUserEnvironment" "no" "Don't allow users to set environment options"
    
    # Check for AllowUsers/AllowGroups if specified
    if [ -n "$ALLOWED_USERS" ]; then
        current_value=$(grep -E "^[[:space:]]*AllowUsers[[:space:]]+" "$config_file" | cut -d' ' -f2-)
        if [ -z "$current_value" ]; then
            log_warning "Setting AllowUsers is not configured"
            log_info "Recommendation: AllowUsers $ALLOWED_USERS (Restrict SSH access to specific users)"
        else
            log_info "Current AllowUsers: $current_value"
            log_info "Recommended AllowUsers: $ALLOWED_USERS"
        fi
    fi
    
    if [ -n "$ALLOWED_GROUPS" ]; then
        current_value=$(grep -E "^[[:space:]]*AllowGroups[[:space:]]+" "$config_file" | cut -d' ' -f2-)
        if [ -z "$current_value" ]; then
            log_warning "Setting AllowGroups is not configured"
            log_info "Recommendation: AllowGroups $ALLOWED_GROUPS (Restrict SSH access to specific groups)"
        else
            log_info "Current AllowGroups: $current_value"
            log_info "Recommended AllowGroups: $ALLOWED_GROUPS"
        fi
    fi
    
    # SSH keys security
    print_section "SSH Key Security Check"
    
    # Check host keys permissions
    log_info "Checking SSH host keys permissions..."
    find /etc/ssh -name 'ssh_host_*_key' -exec ls -l {} \; | while read -r line; do
        if echo "$line" | grep -vq -- "-rw-------"; then
            log_warning "Insecure permissions on host key: $line"
            log_info "Recommendation: chmod 600 [key_file]"
        else
            log_success "Secure permissions on host key: $line"
        fi
    done
    
    # Check for moduli file (for DH key exchange)
    if [ -f /etc/ssh/moduli ]; then
        log_info "Checking for weak Diffie-Hellman moduli..."
        weak_moduli=$(awk '$5 < 3071' /etc/ssh/moduli | wc -l)
        if [ "$weak_moduli" -gt 0 ]; then
            log_warning "Found $weak_moduli weak moduli entries (<3072 bits)"
            log_info "Recommendation: Remove weak DH moduli with: awk '\$5 >= 3071' /etc/ssh/moduli > /etc/ssh/moduli.strong && mv /etc/ssh/moduli.strong /etc/ssh/moduli"
        else
            log_success "No weak moduli found"
        fi
    fi
    
    # Check running SSH processes
    print_section "SSH Process Check"
    
    ps -ef | grep -i ssh | grep -v grep | while read -r line; do
        log_info "$line"
    done
    
    # Check for active SSH connections
    print_section "Active SSH Connections"
    
    netstat -tnp | grep -i ssh | while read -r line; do
        log_info "$line"
    done
}

# Modify SSH configuration
modify_ssh_config() {
    local config_file="$1"
    local temp_file=$(mktemp)
    
    print_header "Hardening SSH Configuration"
    
    # Read existing configuration
    cat "$config_file" > "$temp_file"
    
    # Function to update or add a setting
    update_setting() {
        local setting="$1"
        local value="$2"
        local description="$3"
        
        log_info "Setting $setting to $value ($description)"
        
        # Check if setting exists
        if grep -qE "^[[:space:]]*$setting[[:space:]]+" "$temp_file"; then
            # Replace existing setting
            sed -i "s/^[[:space:]]*$setting[[:space:]]\+.*/$setting $value/g" "$temp_file"
        else
            # Add new setting
            echo "" >> "$temp_file"
            echo "# $description" >> "$temp_file"
            echo "$setting $value" >> "$temp_file"
        fi
    }
    
    # Update basic settings
    update_setting "Port" "$SSH_PORT" "SSH port"
    
    if [ "$PROTOCOL_2_ONLY" = true ]; then
        update_setting "Protocol" "2" "SSH protocol version"
    fi
    
    # Authentication settings
    if [ "$KEY_AUTH_ONLY" = true ]; then
        update_setting "PasswordAuthentication" "no" "Disable password authentication"
        update_setting "ChallengeResponseAuthentication" "no" "Disable challenge-response authentication"
        update_setting "PubkeyAuthentication" "yes" "Enable public key authentication"
    else
        update_setting "PasswordAuthentication" "yes" "Allow password authentication"
        update_setting "PubkeyAuthentication" "yes" "Enable public key authentication"
    fi
    
    # Root login settings
    update_setting "PermitRootLogin" "$ROOT_LOGIN" "Control root login permissions"
    
    # Authentication limits
    update_setting "MaxAuthTries" "$MAX_AUTH_TRIES" "Maximum authentication tries before disconnecting"
    update_setting "LoginGraceTime" "$LOGIN_GRACE_TIME" "Time limit for authentication in seconds"
    
    # Connection settings
    update_setting "ClientAliveInterval" "$((IDLE_TIMEOUT * 60))" "Time in seconds before sending alive message"
    update_setting "ClientAliveCountMax" "0" "Number of alive messages without response before disconnecting"
    
    # Forwarding settings
    update_setting "AllowTcpForwarding" "$TCP_FORWARDING" "Control TCP forwarding"
    update_setting "X11Forwarding" "$X11_FORWARDING" "Control X11 forwarding"
    
    # Security settings
    update_setting "UsePAM" "yes" "Use PAM for authentication"
    update_setting "PermitEmptyPasswords" "no" "Disallow empty passwords"
    update_setting "IgnoreRhosts" "yes" "Ignore .rhosts files"
    update_setting "HostbasedAuthentication" "no" "Disable host-based authentication"
    update_setting "PermitUserEnvironment" "no" "Don't allow users to set environment options"
    
    # Logging
    update_setting "LogLevel" "VERBOSE" "Set logging level"
    update_setting "SyslogFacility" "AUTH" "Set syslog facility"
    
    # Cryptography settings
    update_setting "Ciphers" "$CIPHERS" "Specify allowed ciphers"
    update_setting "MACs" "$MACS" "Specify allowed message authentication codes"
    update_setting "KexAlgorithms" "$KEX_ALGORITHMS" "Specify allowed key exchange algorithms"
    
    # User/Group restrictions
    if [ -n "$ALLOWED_USERS" ]; then
        update_setting "AllowUsers" "$ALLOWED_USERS" "Allow only specific users"
    fi
    
    if [ -n "$ALLOWED_GROUPS" ]; then
        update_setting "AllowGroups" "$ALLOWED_GROUPS" "Allow only specific groups"
    fi
    
    # Add banner info
    update_setting "Banner" "/etc/issue.net" "Display login banner"
    
    # Disable agent forwarding
    update_setting "AllowAgentForwarding" "no" "Disable SSH agent forwarding"
    
    # Disable gateway ports
    update_setting "GatewayPorts" "no" "Disable gateway ports"
    
    # User environment
    update_setting "PermitUserEnvironment" "no" "Disable user environment processing"
    
    # Strict mode
    update_setting "StrictModes" "yes" "Enable strict mode"
    
    # Authentication attempts per connection
    update_setting "MaxAuthTries" "$MAX_AUTH_TRIES" "Max authentication tries"
    
    # Disable host based authentication
    update_setting "HostbasedAuthentication" "no" "Disable host based authentication"
    
    # Restrict access to .ssh directory
    update_setting "StrictModes" "yes" "Check permissions on .ssh directory before accepting login"
    
    # Write the updated configuration
    cat "$temp_file" > "$config_file"
    rm "$temp_file"
    
    log_success "SSH configuration has been hardened"
}

# Check and fix SSH host key permissions
fix_host_key_permissions() {
    print_section "Fixing SSH host key permissions"
    
    # Fix host key permissions
    find /etc/ssh -name "ssh_host_*_key" -exec chmod 600 {} \;
    find /etc/ssh -name "ssh_host_*_key.pub" -exec chmod 644 {} \;
    
    log_success "SSH host key permissions fixed"
}

# Remove weak DH moduli
remove_weak_moduli() {
    print_section "Removing weak Diffie-Hellman moduli"
    
    if [ -f /etc/ssh/moduli ]; then
        log_info "Backing up original moduli file..."
        cp /etc/ssh/moduli /etc/ssh/moduli.bak
        
        log_info "Removing weak moduli (less than 3072 bits)..."
        awk '$5 >= 3071' /etc/ssh/moduli > /etc/ssh/moduli.strong
        mv /etc/ssh/moduli.strong /etc/ssh/moduli
        
        log_success "Weak Diffie-Hellman moduli removed"
    else
        log_warning "No moduli file found at /etc/ssh/moduli"
    fi
}

# Create a secure banner
create_secure_banner() {
    print_section "Creating secure login banner"
    
    if [ ! -f /etc/issue.net ] || grep -q "Ubuntu\|Debian\|CentOS\|Red Hat\|Fedora" /etc/issue.net; then
        # Create a secure banner message
        cat > /etc/issue.net << 'EOL'
***************************************************************************
                       AUTHORIZED ACCESS ONLY

This system is restricted to authorized users for authorized purposes only.
Unauthorized access is prohibited and may be subject to legal action.
All activities may be monitored and recorded.

***************************************************************************
EOL
        log_success "Created secure login banner in /etc/issue.net"
    else
        log_info "Custom login banner already exists in /etc/issue.net"
    fi
}

# Restart SSH service
restart_ssh_service() {
    print_section "Restarting SSH service"
    
    # First test the configuration
    log_info "Testing SSH configuration..."
    if ! sshd -t; then
        log_error "SSH configuration test failed"
        if [ "$CREATE_BACKUP" = true ]; then
            log_info "You can restore the backup and try again"
        fi
        exit 1
    fi
    
    log_success "SSH configuration test passed"
    
    # Look for the SSH service name
    local service_name=""
    if systemctl list-units --type=service | grep -q ssh.service; then
        service_name="ssh"
    elif systemctl list-units --type=service | grep -q sshd.service; then
        service_name="sshd"
    fi
    
    if [ -n "$service_name" ]; then
        log_info "Restarting $service_name service..."
        systemctl restart "$service_name"
        
        # Check if service restarted successfully
        if systemctl is-active --quiet "$service_name"; then
            log_success "$service_name service restarted successfully"
        else
            log_error "Failed to restart $service_name service"
            exit 1
        fi
    else
        log_warning "Could not determine SSH service name, please restart manually"
        log_info "You can restart with: systemctl restart ssh or systemctl restart sshd"
    fi
    
    # Show port SSH is listening on
    log_info "SSH service is listening on:"
    if command -v ss &>/dev/null; then
        ss -tlnp | grep -i ssh
    elif command -v netstat &>/dev/null; then
        netstat -tlnp | grep -i ssh
    fi
}

# Display Post-Hardening Instructions
show_post_instructions() {
    print_header "Post-Hardening Instructions"
    
    if [ "$SSH_PORT" != "22" ]; then
        log_warning "SSH port has been changed to $SSH_PORT"
        log_info "Make sure to update your SSH client connection settings and firewall rules"
        log_info "Example SSH command: ssh -p $SSH_PORT user@hostname"
    fi
    
    if [ "$KEY_AUTH_ONLY" = true ]; then
        log_warning "Password authentication has been disabled"
        log_info "Make sure you have set up SSH keys for all users before disconnecting"
        log_info "To create and set up SSH keys:"
        log_info "  1. On client: ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519"
        log_info "  2. On client: ssh-copy-id -p $SSH_PORT user@hostname"
        log_info "  3. Test connection: ssh -p $SSH_PORT user@hostname"
    fi
    
    if [ "$ROOT_LOGIN" = "no" ]; then
        log_warning "Root login has been disabled"
        log_info "Make sure you have a regular user account with sudo privileges"
    fi
    
    log_info "Additional security measures to consider:"
    log_info "  1. Set up a firewall (e.g., ufw, firewalld, iptables) to restrict SSH access"
    log_info "  2. Install and configure fail2ban to block brute force attempts"
    log_info "  3. Consider setting up multi-factor authentication (MFA) for SSH"
    log_info "  4. Regularly audit SSH logs for suspicious activity"
    log_info "  5. Keep your system and SSH server updated"
}

# Main function
main() {
    print_header "SSH Hardening Script"
    
    # Check if OpenSSH server is installed
    check_ssh_installed
    
    # Find SSH configuration file
    SSH_CONFIG=$(find_ssh_config)
    log_info "Using SSH configuration file: $SSH_CONFIG"
    
    # Create a backup if requested
    if [ "$CREATE_BACKUP" = true ]; then
        backup_config "$SSH_CONFIG"
    fi
    
    # Get secure cryptographic settings
    get_secure_recommendations
    
    # Audit SSH configuration
    audit_ssh_config "$SSH_CONFIG"
    
    # Exit if audit-only mode
    if [ "$AUDIT_ONLY" = true ]; then
        print_header "SSH Audit Complete"
        log_info "No changes were made (audit-only mode)"
        exit 0
    fi
    
    # Modify SSH configuration
    modify_ssh_config "$SSH_CONFIG"
    
    # Fix SSH host key permissions
    fix_host_key_permissions
    
    # Remove weak DH moduli
    remove_weak_moduli
    
    # Create a secure banner
    create_secure_banner
    
    # Restart SSH service
    restart_ssh_service
    
    # Show post-hardening instructions
    show_post_instructions
    
    print_header "SSH Hardening Complete"
    log_success "SSH has been successfully hardened"
}

# Run the main function
main