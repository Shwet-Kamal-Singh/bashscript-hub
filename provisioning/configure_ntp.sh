#!/bin/bash
#
# Script Name: configure_ntp.sh
# Description: Configure NTP services across different Linux distributions
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./configure_ntp.sh [options]
#
# Options:
#   -s, --server <ntp_server>    Specify custom NTP server(s) (comma-separated)
#   -p, --pool <ntp_pool>        Specify custom NTP pool(s) (comma-separated)
#   -i, --install-only           Only install NTP service, don't configure
#   -c, --check-only             Only check NTP status, don't install or configure
#   -r, --restart                Restart NTP service after configuration
#   -t, --timeserver-type <type> Force specific NTP implementation (chrony, ntpd, systemd-timesyncd)
#   -v, --verbose                Show detailed output
#   -h, --help                   Display this help message
#
# Examples:
#   ./configure_ntp.sh
#   ./configure_ntp.sh -s time.google.com,time.cloudflare.com
#   ./configure_ntp.sh -p pool.ntp.org -r -v
#   ./configure_ntp.sh -t chrony -v
#
# Requirements:
#   - Root privileges (or sudo)
#   - Package manager (apt, yum, dnf)
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
VERBOSE=false
RESTART=false
INSTALL_ONLY=false
CHECK_ONLY=false
TIMESERVER_TYPE="auto"
CUSTOM_SERVERS=""
CUSTOM_POOLS=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--server)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            CUSTOM_SERVERS="$2"
            shift 2
            ;;
        -p|--pool)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            CUSTOM_POOLS="$2"
            shift 2
            ;;
        -i|--install-only)
            INSTALL_ONLY=true
            shift
            ;;
        -c|--check-only)
            CHECK_ONLY=true
            shift
            ;;
        -r|--restart)
            RESTART=true
            shift
            ;;
        -t|--timeserver-type)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "chrony" && "$2" != "ntpd" && "$2" != "systemd-timesyncd" ]]; then
                log_error "Invalid timeserver type: $2"
                log_error "Valid options: chrony, ntpd, systemd-timesyncd"
                exit 1
            fi
            TIMESERVER_TYPE="$2"
            shift 2
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

    if [ "$VERBOSE" = true ]; then
        log_info "Detected distribution: $DISTRO $VERSION (family: $DISTRO_FAMILY)"
    fi
}

# Detect package manager
detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt-get"
        PKG_INSTALL="$PKG_MANAGER install -y"
        PKG_UPDATE="$PKG_MANAGER update"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        PKG_INSTALL="$PKG_MANAGER install -y"
        PKG_UPDATE="$PKG_MANAGER check-update"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="$PKG_MANAGER install -y"
        PKG_UPDATE="$PKG_MANAGER check-update"
    elif command -v zypper &>/dev/null; then
        PKG_MANAGER="zypper"
        PKG_INSTALL="$PKG_MANAGER install -y"
        PKG_UPDATE="$PKG_MANAGER refresh"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
        PKG_INSTALL="$PKG_MANAGER -S --noconfirm"
        PKG_UPDATE="$PKG_MANAGER -Sy"
    else
        log_error "No supported package manager found"
        exit 1
    fi

    if [ "$VERBOSE" = true ]; then
        log_info "Using package manager: $PKG_MANAGER"
    fi
}

# Determine which NTP implementation to use
determine_ntp_implementation() {
    # If user specified a timeserver type, use that
    if [ "$TIMESERVER_TYPE" != "auto" ]; then
        NTP_IMPLEMENTATION="$TIMESERVER_TYPE"
        return
    fi

    # Check what's installed or recommended for the distribution
    case "$DISTRO_FAMILY" in
        "debian")
            # Modern Ubuntu and Debian use systemd-timesyncd by default,
            # but chrony is available and more feature-rich
            if command -v systemctl &>/dev/null && systemctl list-unit-files systemd-timesyncd.service &>/dev/null; then
                NTP_IMPLEMENTATION="systemd-timesyncd"
            elif command -v chronyd &>/dev/null; then
                NTP_IMPLEMENTATION="chrony"
            elif command -v ntpd &>/dev/null; then
                NTP_IMPLEMENTATION="ntpd"
            else
                NTP_IMPLEMENTATION="chrony"  # Default to chrony if nothing is installed
            fi
            ;;
        "redhat")
            # RHEL 8+ and derivatives use chrony by default
            if command -v chronyd &>/dev/null; then
                NTP_IMPLEMENTATION="chrony"
            elif command -v ntpd &>/dev/null; then
                NTP_IMPLEMENTATION="ntpd"
            else
                NTP_IMPLEMENTATION="chrony"  # Default to chrony
            fi
            ;;
        "suse")
            # openSUSE typically uses chrony
            if command -v chronyd &>/dev/null; then
                NTP_IMPLEMENTATION="chrony"
            elif command -v ntpd &>/dev/null; then
                NTP_IMPLEMENTATION="ntpd"
            else
                NTP_IMPLEMENTATION="chrony"  # Default to chrony
            fi
            ;;
        "arch")
            # Arch Linux supports both but generally recommends systemd-timesyncd for simple setups
            if command -v systemctl &>/dev/null && systemctl list-unit-files systemd-timesyncd.service &>/dev/null; then
                NTP_IMPLEMENTATION="systemd-timesyncd"
            elif command -v chronyd &>/dev/null; then
                NTP_IMPLEMENTATION="chrony"
            elif command -v ntpd &>/dev/null; then
                NTP_IMPLEMENTATION="ntpd"
            else
                NTP_IMPLEMENTATION="systemd-timesyncd"
            fi
            ;;
        *)
            # Default to chrony for unknown distributions
            NTP_IMPLEMENTATION="chrony"
            ;;
    esac

    if [ "$VERBOSE" = true ]; then
        log_info "Selected NTP implementation: $NTP_IMPLEMENTATION"
    fi
}

# Install NTP packages
install_ntp() {
    print_section "Installing NTP Implementation"

    local pkg_name
    local svc_name

    case "$NTP_IMPLEMENTATION" in
        "chrony")
            pkg_name="chrony"
            svc_name="chronyd"
            ;;
        "ntpd")
            if [ "$DISTRO_FAMILY" = "debian" ]; then
                pkg_name="ntp"
            else
                pkg_name="ntp"
            fi
            svc_name="ntpd"
            ;;
        "systemd-timesyncd")
            if [ "$DISTRO_FAMILY" = "debian" ]; then
                pkg_name="systemd"  # Already installed with systemd
            elif [ "$DISTRO_FAMILY" = "arch" ]; then
                pkg_name="systemd"  # Already installed with systemd
            else
                pkg_name="systemd"  # Most distributions have systemd-timesyncd included with systemd
            fi
            svc_name="systemd-timesyncd"
            ;;
        *)
            log_error "Unsupported NTP implementation: $NTP_IMPLEMENTATION"
            exit 1
            ;;
    esac

    # Update package repositories
    log_info "Updating package repositories..."
    $PKG_UPDATE >/dev/null 2>&1

    # Install the appropriate package
    log_info "Installing $pkg_name..."
    if ! $PKG_INSTALL "$pkg_name"; then
        log_error "Failed to install $pkg_name"
        exit 1
    fi

    log_success "Successfully installed $pkg_name"
}

# Configure chrony
configure_chrony() {
    local config_file="/etc/chrony.conf"
    local fallback_config_file="/etc/chrony/chrony.conf"
    
    # Determine the actual config file location
    if [ -f "$config_file" ]; then
        true  # Use the default
    elif [ -f "$fallback_config_file" ]; then
        config_file="$fallback_config_file"
    else
        log_error "Chrony configuration file not found"
        exit 1
    fi

    print_section "Configuring Chrony"
    log_info "Using configuration file: $config_file"

    # Create a backup of the original config
    local backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$config_file" "$backup_file"
    log_info "Backup created: $backup_file"

    # Start building the new configuration
    local new_config
    local server_entries=""
    local pool_entries=""

    # Process custom servers if specified
    if [ -n "$CUSTOM_SERVERS" ]; then
        IFS=',' read -ra SERVERS <<< "$CUSTOM_SERVERS"
        for server in "${SERVERS[@]}"; do
            server_entries+="server $server iburst\n"
        done
    fi

    # Process custom pools if specified
    if [ -n "$CUSTOM_POOLS" ]; then
        IFS=',' read -ra POOLS <<< "$CUSTOM_POOLS"
        for pool in "${POOLS[@]}"; do
            pool_entries+="pool $pool iburst\n"
        done
    fi

    # If no custom servers or pools are specified, use defaults
    if [ -z "$server_entries" ] && [ -z "$pool_entries" ]; then
        pool_entries="pool pool.ntp.org iburst\n"
    fi

    # Create the new configuration
    new_config="# Configured by $0 on $(date)\n\n"
    new_config+="# Server and pool entries\n"
    new_config+="$server_entries"
    new_config+="$pool_entries\n"
    new_config+="# Allow NTP client access from local network\n"
    new_config+="allow 127.0.0.1/8\n\n"
    new_config+="# Record the rate at which the system clock gains/losses time\n"
    new_config+="driftfile /var/lib/chrony/drift\n\n"
    new_config+="# Allow the system clock to be stepped in the first three updates\n"
    new_config+="makestep 1.0 3\n\n"
    new_config+="# Enable kernel synchronization of the real-time clock (RTC)\n"
    new_config+="rtcsync\n\n"
    new_config+="# Enable hardware timestamping on all interfaces that support it\n"
    new_config+="hwtimestamp *\n\n"
    new_config+="# Specify directory for log files\n"
    new_config+="logdir /var/log/chrony\n\n"
    new_config+="# Select which information is logged\n"
    new_config+="log measurements statistics tracking\n"

    # Write the new configuration
    echo -e "$new_config" > "$config_file"
    log_success "Chrony configuration updated"
}

# Configure ntpd
configure_ntpd() {
    local config_file="/etc/ntp.conf"
    
    if [ ! -f "$config_file" ]; then
        log_error "NTP configuration file not found: $config_file"
        exit 1
    fi

    print_section "Configuring NTPd"
    log_info "Using configuration file: $config_file"

    # Create a backup of the original config
    local backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$config_file" "$backup_file"
    log_info "Backup created: $backup_file"

    # Start building the new configuration
    local new_config
    local server_entries=""
    local pool_entries=""

    # Process custom servers if specified
    if [ -n "$CUSTOM_SERVERS" ]; then
        IFS=',' read -ra SERVERS <<< "$CUSTOM_SERVERS"
        for server in "${SERVERS[@]}"; do
            server_entries+="server $server iburst\n"
        done
    fi

    # Process custom pools if specified
    if [ -n "$CUSTOM_POOLS" ]; then
        IFS=',' read -ra POOLS <<< "$CUSTOM_POOLS"
        for pool in "${POOLS[@]}"; do
            pool_entries+="pool $pool iburst\n"
        done
    fi

    # If no custom servers or pools are specified, use defaults
    if [ -z "$server_entries" ] && [ -z "$pool_entries" ]; then
        server_entries="server 0.pool.ntp.org iburst\n"
        server_entries+="server 1.pool.ntp.org iburst\n"
        server_entries+="server 2.pool.ntp.org iburst\n"
        server_entries+="server 3.pool.ntp.org iburst\n"
    fi

    # Create the new configuration
    new_config="# Configured by $0 on $(date)\n\n"
    new_config+="# Server and pool entries\n"
    new_config+="$server_entries"
    new_config+="$pool_entries\n"
    new_config+="# Restrict default access\n"
    new_config+="restrict -4 default kod notrap nomodify nopeer noquery limited\n"
    new_config+="restrict -6 default kod notrap nomodify nopeer noquery limited\n\n"
    new_config+="# Allow localhost\n"
    new_config+="restrict 127.0.0.1\n"
    new_config+="restrict ::1\n\n"
    new_config+="# Drift file location\n"
    new_config+="driftfile /var/lib/ntp/drift\n\n"
    new_config+="# Log file location\n"
    new_config+="logfile /var/log/ntp.log\n"

    # Write the new configuration
    echo -e "$new_config" > "$config_file"
    log_success "NTPd configuration updated"
}

# Configure systemd-timesyncd
configure_systemd_timesyncd() {
    local config_file="/etc/systemd/timesyncd.conf"
    
    if [ ! -f "$config_file" ]; then
        log_error "systemd-timesyncd configuration file not found: $config_file"
        exit 1
    fi

    print_section "Configuring systemd-timesyncd"
    log_info "Using configuration file: $config_file"

    # Create a backup of the original config
    local backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$config_file" "$backup_file"
    log_info "Backup created: $backup_file"

    # Process custom servers and pools
    local ntp_entries=""
    if [ -n "$CUSTOM_SERVERS" ]; then
        ntp_entries+="$CUSTOM_SERVERS"
    fi

    if [ -n "$CUSTOM_POOLS" ]; then
        if [ -n "$ntp_entries" ]; then
            ntp_entries+=",$CUSTOM_POOLS"
        else
            ntp_entries+="$CUSTOM_POOLS"
        fi
    fi

    # If no entries, use defaults
    if [ -z "$ntp_entries" ]; then
        ntp_entries="pool.ntp.org"
    fi

    # Create the new configuration
    local new_config
    new_config="# Configured by $0 on $(date)\n\n"
    new_config+="[Time]\n"
    new_config+="NTP=$ntp_entries\n"
    new_config+="FallbackNTP=0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org\n"
    new_config+="#RootDistanceMaxSec=5\n"
    new_config+="#PollIntervalMinSec=32\n"
    new_config+="#PollIntervalMaxSec=2048\n"

    # Write the new configuration
    echo -e "$new_config" > "$config_file"
    log_success "systemd-timesyncd configuration updated"
}

# Start or restart the NTP service
start_ntp_service() {
    print_section "Starting NTP Service"

    local service_name

    case "$NTP_IMPLEMENTATION" in
        "chrony")
            service_name="chronyd"
            # On some distributions, the service is called chrony instead of chronyd
            if ! systemctl list-unit-files | grep -q "^chronyd\.service"; then
                service_name="chrony"
            fi
            ;;
        "ntpd")
            service_name="ntpd"
            # On Debian/Ubuntu, the service is called ntp instead of ntpd
            if [ "$DISTRO_FAMILY" = "debian" ]; then
                service_name="ntp"
            fi
            ;;
        "systemd-timesyncd")
            service_name="systemd-timesyncd"
            ;;
        *)
            log_error "Unsupported NTP implementation: $NTP_IMPLEMENTATION"
            exit 1
            ;;
    esac

    # Enable the service to start at boot
    log_info "Enabling $service_name service..."
    systemctl enable "$service_name"

    # Start/restart the service
    if [ "$RESTART" = true ]; then
        log_info "Restarting $service_name service..."
        systemctl restart "$service_name"
    else
        log_info "Starting $service_name service..."
        systemctl start "$service_name"
    fi

    # Check if the service is running
    if systemctl is-active --quiet "$service_name"; then
        log_success "$service_name service is running"
    else
        log_error "$service_name service failed to start"
        exit 1
    fi
}

# Check NTP status
check_ntp_status() {
    print_header "NTP Status Check"

    local command

    case "$NTP_IMPLEMENTATION" in
        "chrony")
            command="chronyc sources"
            log_info "Checking chrony status..."
            if ! $command; then
                log_error "Failed to check chrony status"
                return 1
            fi
            
            log_info "Checking chrony tracking..."
            if ! chronyc tracking; then
                log_error "Failed to check chrony tracking"
                return 1
            fi
            ;;
        "ntpd")
            command="ntpq -p"
            log_info "Checking NTPd status..."
            if ! $command; then
                log_error "Failed to check NTPd status"
                return 1
            fi
            ;;
        "systemd-timesyncd")
            command="timedatectl show-timesync"
            log_info "Checking systemd-timesyncd status..."
            if ! $command; then
                # Fallback to timedatectl status if show-timesync is not available
                timedatectl status | grep -E "NTP |synchronized:"
            fi
            ;;
        *)
            log_error "Unsupported NTP implementation: $NTP_IMPLEMENTATION"
            return 1
            ;;
    esac

    # Show current time and date
    log_info "Current system time: $(date)"

    # Show if system clock uses UTC
    if timedatectl status | grep -q "RTC in local TZ: no"; then
        log_info "System clock uses UTC time"
    else
        log_warning "System clock does not use UTC time"
    fi

    return 0
}

# Main function
main() {
    print_header "NTP Configuration"

    # Detect the Linux distribution
    detect_distribution

    # Detect the package manager
    detect_package_manager

    # Check if we should only check the status
    if [ "$CHECK_ONLY" = true ]; then
        # Determine which NTP implementation to check
        determine_ntp_implementation
        check_ntp_status
        exit $?
    fi

    # Determine which NTP implementation to use
    determine_ntp_implementation

    # Install NTP
    install_ntp

    # Skip configuration if install-only is specified
    if [ "$INSTALL_ONLY" = true ]; then
        log_info "Install-only mode. Skipping configuration."
    else
        # Configure NTP based on the selected implementation
        case "$NTP_IMPLEMENTATION" in
            "chrony")
                configure_chrony
                ;;
            "ntpd")
                configure_ntpd
                ;;
            "systemd-timesyncd")
                configure_systemd_timesyncd
                ;;
            *)
                log_error "Unsupported NTP implementation: $NTP_IMPLEMENTATION"
                exit 1
                ;;
        esac
    fi

    # Start or restart the NTP service
    start_ntp_service

    # Check NTP status
    check_ntp_status

    print_header "NTP Configuration Complete"
    log_success "NTP has been successfully configured using $NTP_IMPLEMENTATION"
}

# Run the main function
main