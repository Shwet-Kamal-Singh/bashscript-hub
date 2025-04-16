#!/bin/bash
#
# Script Name: install_ansible.sh
# Description: Install and configure Ansible across different Linux distributions
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./install_ansible.sh [options]
#
# Options:
#   -v, --version <version>      Specify Ansible version (default: latest)
#   -m, --method <method>        Installation method: pkg|pip|src (default: auto-detect)
#   -p, --pip-version <version>  Specify pip version to use (default: system default)
#   -i, --inventory <file>       Initialize with custom inventory file
#   -c, --config <file>          Initialize with custom ansible.cfg file
#   -P, --python <path>          Specify Python interpreter path
#   -r, --requirements <file>    Install requirements from file
#   -g, --galaxy <requirements>  Install Ansible Galaxy requirements
#   -u, --user <username>        Install for specific user (non-root installation)
#   -V, --virtualenv <path>      Install in Python virtual environment
#   -s, --system-wide            Force system-wide installation (default)
#   -b, --become                 Use become for privilege escalation
#   -f, --force                  Force reinstallation if already installed
#   -d, --dry-run                Show what would be done without making changes
#   -D, --debug                  Enable debug mode
#   -h, --help                   Display this help message
#
# Examples:
#   ./install_ansible.sh
#   ./install_ansible.sh -v 2.15.2 -m pip
#   ./install_ansible.sh -P /usr/bin/python3.10 -g requirements.yml
#
# Requirements:
#   - Root privileges (or sudo) for system-wide installation
#   - Internet connection
#   - Python (2.7+ or 3.5+)
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
ANSIBLE_VERSION="latest"
INSTALL_METHOD="auto"
PIP_VERSION=""
INVENTORY_FILE=""
CONFIG_FILE=""
PYTHON_PATH=""
REQUIREMENTS_FILE=""
GALAXY_REQUIREMENTS=""
TARGET_USER=""
VIRTUALENV_PATH=""
SYSTEM_WIDE=true
USE_BECOME=false
FORCE_INSTALL=false
DRY_RUN=false
DEBUG=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            ANSIBLE_VERSION="$2"
            shift 2
            ;;
        -m|--method)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "pkg" && "$2" != "pip" && "$2" != "src" ]]; then
                log_error "Invalid installation method: $2"
                log_error "Valid options: pkg, pip, src"
                exit 1
            fi
            INSTALL_METHOD="$2"
            shift 2
            ;;
        -p|--pip-version)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            PIP_VERSION="$2"
            shift 2
            ;;
        -i|--inventory)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            INVENTORY_FILE="$2"
            shift 2
            ;;
        -c|--config)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            CONFIG_FILE="$2"
            shift 2
            ;;
        -P|--python)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            PYTHON_PATH="$2"
            shift 2
            ;;
        -r|--requirements)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            REQUIREMENTS_FILE="$2"
            shift 2
            ;;
        -g|--galaxy)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            GALAXY_REQUIREMENTS="$2"
            shift 2
            ;;
        -u|--user)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            TARGET_USER="$2"
            SYSTEM_WIDE=false
            shift 2
            ;;
        -V|--virtualenv)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            VIRTUALENV_PATH="$2"
            SYSTEM_WIDE=false
            shift 2
            ;;
        -s|--system-wide)
            SYSTEM_WIDE=true
            shift
            ;;
        -b|--become)
            USE_BECOME=true
            shift
            ;;
        -f|--force)
            FORCE_INSTALL=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -D|--debug)
            DEBUG=true
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

# Enable debug mode if requested
if [ "$DEBUG" = true ]; then
    set -x
fi

# Check if running with root/sudo
check_root() {
    if [ "$SYSTEM_WIDE" = true ] && [ $EUID -ne 0 ]; then
        log_error "This script must be run as root or with sudo for system-wide installation"
        log_error "Use --user option for non-root installation"
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

    log_info "Using package manager: $PKG_MANAGER"
}

# Check for existing Ansible installation
check_existing_ansible() {
    print_section "Checking for existing Ansible installation"

    if command -v ansible &>/dev/null; then
        ANSIBLE_INSTALLED=true
        CURRENT_ANSIBLE_VERSION=$(ansible --version | head -n 1 | awk '{print $2}')
        log_info "Ansible is already installed (version $CURRENT_ANSIBLE_VERSION)"
        
        if [ "$FORCE_INSTALL" = true ]; then
            log_warning "Force install option specified. Will reinstall Ansible."
            return 0
        else
            log_info "Use --force to reinstall Ansible."
            return 1
        fi
    else
        ANSIBLE_INSTALLED=false
        log_info "Ansible is not installed."
        return 0
    fi
}

# Determine installation method based on distribution
determine_install_method() {
    if [ "$INSTALL_METHOD" != "auto" ]; then
        log_info "Using specified installation method: $INSTALL_METHOD"
        return
    fi
    
    case "$DISTRO_FAMILY" in
        "debian")
            if [ "$DISTRO" = "ubuntu" ] && [ "${VERSION%.*}" -ge 20 ]; then
                INSTALL_METHOD="pkg"
            else
                INSTALL_METHOD="pip"
            fi
            ;;
        "redhat")
            if [ "$DISTRO" = "fedora" ] || [ "${VERSION%.*}" -ge 8 ]; then
                INSTALL_METHOD="pkg"
            else
                INSTALL_METHOD="pip"
            fi
            ;;
        "suse")
            INSTALL_METHOD="pip"
            ;;
        "arch")
            INSTALL_METHOD="pkg"
            ;;
        *)
            INSTALL_METHOD="pip"
            ;;
    esac
    
    log_info "Selected installation method: $INSTALL_METHOD"
}

# Install Ansible via package manager
install_ansible_pkg() {
    print_section "Installing Ansible via package manager"
    
    # Update package repositories
    log_info "Updating package repositories..."
    if [ "$DRY_RUN" = false ]; then
        $PKG_UPDATE >/dev/null 2>&1
    else
        log_info "[DRY RUN] Would update package repositories"
    fi
    
    # Install prerequisites
    log_info "Installing prerequisites..."
    case "$DISTRO_FAMILY" in
        "debian")
            if [ "$DRY_RUN" = false ]; then
                $PKG_INSTALL software-properties-common >/dev/null 2>&1
                
                # Add Ansible repository for specific version if not latest
                if [ "$ANSIBLE_VERSION" != "latest" ]; then
                    log_info "Adding Ansible PPA..."
                    apt-add-repository --yes --update ppa:ansible/ansible >/dev/null 2>&1
                fi
            else
                log_info "[DRY RUN] Would install prerequisites and add Ansible repository if needed"
            fi
            ;;
        "redhat")
            if [ "$DRY_RUN" = false ]; then
                # Enable EPEL repository for RHEL/CentOS
                if [ "$DISTRO" != "fedora" ]; then
                    log_info "Enabling EPEL repository..."
                    $PKG_INSTALL epel-release >/dev/null 2>&1
                fi
            else
                log_info "[DRY RUN] Would enable EPEL repository if needed"
            fi
            ;;
        "arch")
            # No additional prerequisites needed for Arch
            ;;
        *)
            log_warning "Unsupported distribution for package installation: $DISTRO_FAMILY"
            log_info "Falling back to pip installation method"
            install_ansible_pip
            return
            ;;
    esac
    
    # Install Ansible
    log_info "Installing Ansible..."
    if [ "$DRY_RUN" = false ]; then
        if [ "$ANSIBLE_VERSION" = "latest" ]; then
            $PKG_INSTALL ansible >/dev/null 2>&1
        else
            # Version-specific installation (if possible)
            case "$DISTRO_FAMILY" in
                "debian")
                    $PKG_INSTALL "ansible=$ANSIBLE_VERSION*" >/dev/null 2>&1 || $PKG_INSTALL ansible >/dev/null 2>&1
                    ;;
                "redhat")
                    $PKG_INSTALL "ansible-$ANSIBLE_VERSION" >/dev/null 2>&1 || $PKG_INSTALL ansible >/dev/null 2>&1
                    ;;
                "arch")
                    # Arch typically only offers the latest version
                    $PKG_INSTALL ansible >/dev/null 2>&1
                    ;;
            esac
        fi
        
        if ! command -v ansible &>/dev/null; then
            log_error "Failed to install Ansible via package manager"
            log_info "Falling back to pip installation method"
            install_ansible_pip
            return
        fi
    else
        log_info "[DRY RUN] Would install Ansible via package manager"
    fi
    
    log_success "Ansible installed via package manager"
}

# Install Ansible via pip
install_ansible_pip() {
    print_section "Installing Ansible via pip"
    
    # Find the right Python and pip versions
    local pip_cmd="pip"
    local python_cmd="python"
    
    # Use specified Python path if provided
    if [ -n "$PYTHON_PATH" ]; then
        python_cmd="$PYTHON_PATH"
        
        # Extract pip version from Python path
        if [[ "$PYTHON_PATH" == *"python3"* ]]; then
            pip_cmd="pip3"
        elif [[ "$PYTHON_PATH" == *"python2"* ]]; then
            pip_cmd="pip2"
        fi
    else
        # Try to find Python 3 first, then Python 2 as fallback
        if command -v python3 &>/dev/null; then
            python_cmd="python3"
            pip_cmd="pip3"
        elif command -v python2 &>/dev/null; then
            python_cmd="python2"
            pip_cmd="pip2"
        fi
    fi
    
    # Use specified pip version if provided
    if [ -n "$PIP_VERSION" ]; then
        if [[ "$PIP_VERSION" == "pip3" ]]; then
            pip_cmd="pip3"
        elif [[ "$PIP_VERSION" == "pip2" ]]; then
            pip_cmd="pip2"
        else
            pip_cmd="$PIP_VERSION"
        fi
    fi
    
    # Check if Python and pip are available
    if ! command -v "$python_cmd" &>/dev/null; then
        log_error "Python command '$python_cmd' not found"
        exit 1
    fi
    
    # Install prerequisites
    log_info "Installing pip and development packages..."
    if [ "$DRY_RUN" = false ]; then
        case "$DISTRO_FAMILY" in
            "debian")
                if [[ "$python_cmd" == *"python3"* ]]; then
                    $PKG_INSTALL python3 python3-pip python3-dev build-essential >/dev/null 2>&1
                else
                    $PKG_INSTALL python python-pip python-dev build-essential >/dev/null 2>&1
                fi
                ;;
            "redhat")
                if [[ "$python_cmd" == *"python3"* ]]; then
                    $PKG_INSTALL python3 python3-pip python3-devel gcc >/dev/null 2>&1
                else
                    $PKG_INSTALL python python-pip python-devel gcc >/dev/null 2>&1
                fi
                ;;
            "suse")
                if [[ "$python_cmd" == *"python3"* ]]; then
                    $PKG_INSTALL python3 python3-pip python3-devel gcc >/dev/null 2>&1
                else
                    $PKG_INSTALL python python-pip python-devel gcc >/dev/null 2>&1
                fi
                ;;
            "arch")
                $PKG_INSTALL python python-pip base-devel >/dev/null 2>&1
                ;;
            *)
                log_warning "Unsupported distribution for prerequisite installation: $DISTRO_FAMILY"
                log_warning "Trying to continue with existing Python installation"
                ;;
        esac
    else
        log_info "[DRY RUN] Would install pip and development packages"
    fi
    
    # Install virtualenv if required
    if [ -n "$VIRTUALENV_PATH" ]; then
        log_info "Installing virtualenv..."
        if [ "$DRY_RUN" = false ]; then
            "$pip_cmd" install virtualenv >/dev/null 2>&1
            
            # Create virtual environment
            log_info "Creating virtual environment at $VIRTUALENV_PATH..."
            "$python_cmd" -m virtualenv "$VIRTUALENV_PATH" >/dev/null 2>&1
            
            # Update pip_cmd to use the virtual environment
            pip_cmd="$VIRTUALENV_PATH/bin/pip"
        else
            log_info "[DRY RUN] Would create virtual environment at $VIRTUALENV_PATH"
        fi
    fi
    
    # Install Ansible
    log_info "Installing Ansible via pip..."
    if [ "$DRY_RUN" = false ]; then
        if [ "$ANSIBLE_VERSION" = "latest" ]; then
            if [ "$SYSTEM_WIDE" = true ]; then
                "$pip_cmd" install --upgrade ansible >/dev/null 2>&1
            else
                # If installing for a specific user
                if [ -n "$TARGET_USER" ]; then
                    if [ -n "$VIRTUALENV_PATH" ]; then
                        # Already using virtualenv
                        "$pip_cmd" install --upgrade ansible >/dev/null 2>&1
                    else
                        # User-specific installation
                        su - "$TARGET_USER" -c "$pip_cmd install --user --upgrade ansible" >/dev/null 2>&1
                    fi
                else
                    # Current user installation
                    "$pip_cmd" install --user --upgrade ansible >/dev/null 2>&1
                fi
            fi
        else
            # Version-specific installation
            if [ "$SYSTEM_WIDE" = true ]; then
                "$pip_cmd" install --upgrade "ansible==$ANSIBLE_VERSION" >/dev/null 2>&1
            else
                # If installing for a specific user
                if [ -n "$TARGET_USER" ]; then
                    if [ -n "$VIRTUALENV_PATH" ]; then
                        # Already using virtualenv
                        "$pip_cmd" install --upgrade "ansible==$ANSIBLE_VERSION" >/dev/null 2>&1
                    else
                        # User-specific installation
                        su - "$TARGET_USER" -c "$pip_cmd install --user --upgrade ansible==$ANSIBLE_VERSION" >/dev/null 2>&1
                    fi
                else
                    # Current user installation
                    "$pip_cmd" install --user --upgrade "ansible==$ANSIBLE_VERSION" >/dev/null 2>&1
                fi
            fi
        fi
        
        # Check if Ansible was installed successfully
        if ! command -v ansible &>/dev/null; then
            # Check virtualenv path
            if [ -n "$VIRTUALENV_PATH" ] && [ -f "$VIRTUALENV_PATH/bin/ansible" ]; then
                log_success "Ansible installed in virtualenv at $VIRTUALENV_PATH/bin/ansible"
            else
                log_error "Failed to install Ansible via pip"
                exit 1
            fi
        fi
    else
        log_info "[DRY RUN] Would install Ansible via pip"
    fi
    
    log_success "Ansible installed via pip"
}

# Install Ansible from source
install_ansible_src() {
    print_section "Installing Ansible from source"
    
    # Install prerequisites
    log_info "Installing prerequisites for source installation..."
    if [ "$DRY_RUN" = false ]; then
        case "$DISTRO_FAMILY" in
            "debian")
                $PKG_INSTALL git python3 python3-pip python3-dev build-essential >/dev/null 2>&1
                ;;
            "redhat")
                $PKG_INSTALL git python3 python3-pip python3-devel gcc >/dev/null 2>&1
                ;;
            "suse")
                $PKG_INSTALL git python3 python3-pip python3-devel gcc >/dev/null 2>&1
                ;;
            "arch")
                $PKG_INSTALL git python python-pip base-devel >/dev/null 2>&1
                ;;
            *)
                log_warning "Unsupported distribution for prerequisite installation: $DISTRO_FAMILY"
                log_warning "Trying to continue with existing Python installation"
                ;;
        esac
    else
        log_info "[DRY RUN] Would install prerequisites for source installation"
    fi
    
    # Clone Ansible repository
    log_info "Cloning Ansible repository..."
    if [ "$DRY_RUN" = false ]; then
        TMP_DIR=$(mktemp -d)
        git clone --depth 1 https://github.com/ansible/ansible.git "$TMP_DIR" >/dev/null 2>&1
        
        # Check out specific version if requested
        if [ "$ANSIBLE_VERSION" != "latest" ]; then
            cd "$TMP_DIR" || exit 1
            git checkout "v$ANSIBLE_VERSION" >/dev/null 2>&1 || \
            git checkout "stable-$ANSIBLE_VERSION" >/dev/null 2>&1 || \
            git checkout "release$ANSIBLE_VERSION" >/dev/null 2>&1 || \
            log_warning "Could not find specific version tag, using latest version"
            cd - || exit 1
        fi
        
        # Install from source
        log_info "Installing Ansible from source..."
        cd "$TMP_DIR" || exit 1
        
        if [ "$SYSTEM_WIDE" = true ]; then
            pip3 install -e . >/dev/null 2>&1
        else
            if [ -n "$TARGET_USER" ]; then
                if [ -n "$VIRTUALENV_PATH" ]; then
                    # Install in virtualenv
                    "$VIRTUALENV_PATH/bin/pip" install -e . >/dev/null 2>&1
                else
                    # User-specific installation
                    su - "$TARGET_USER" -c "cd $TMP_DIR && pip3 install --user -e ." >/dev/null 2>&1
                fi
            else
                # Current user installation
                pip3 install --user -e . >/dev/null 2>&1
            fi
        fi
        
        # Clean up
        cd - || exit 1
        rm -rf "$TMP_DIR"
        
        # Check if Ansible was installed successfully
        if ! command -v ansible &>/dev/null; then
            # Check virtualenv path
            if [ -n "$VIRTUALENV_PATH" ] && [ -f "$VIRTUALENV_PATH/bin/ansible" ]; then
                log_success "Ansible installed in virtualenv at $VIRTUALENV_PATH/bin/ansible"
            else
                log_error "Failed to install Ansible from source"
                exit 1
            fi
        fi
    else
        log_info "[DRY RUN] Would clone and install Ansible from source"
    fi
    
    log_success "Ansible installed from source"
}

# Install Ansible
install_ansible() {
    print_section "Installing Ansible"
    
    # Determine installation method
    determine_install_method
    
    # Install Ansible using the appropriate method
    case "$INSTALL_METHOD" in
        "pkg")
            install_ansible_pkg
            ;;
        "pip")
            install_ansible_pip
            ;;
        "src")
            install_ansible_src
            ;;
        *)
            log_error "Unknown installation method: $INSTALL_METHOD"
            exit 1
            ;;
    esac
}

# Configure Ansible
configure_ansible() {
    print_section "Configuring Ansible"
    
    # Create Ansible configuration directory
    local ansible_config_dir
    if [ -n "$TARGET_USER" ]; then
        # User-specific configuration
        if [ -n "$VIRTUALENV_PATH" ]; then
            ansible_config_dir="$VIRTUALENV_PATH/etc/ansible"
        else
            ansible_config_dir="/home/$TARGET_USER/.ansible"
        fi
    else
        # System-wide configuration
        ansible_config_dir="/etc/ansible"
    fi
    
    log_info "Creating Ansible configuration directory: $ansible_config_dir"
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$ansible_config_dir"
        
        # Set appropriate ownership
        if [ -n "$TARGET_USER" ]; then
            chown -R "$TARGET_USER" "$ansible_config_dir"
        fi
    else
        log_info "[DRY RUN] Would create Ansible configuration directory"
    fi
    
    # Set up inventory file
    local inventory_path="$ansible_config_dir/hosts"
    if [ -n "$INVENTORY_FILE" ]; then
        # Use the provided inventory file
        if [ -f "$INVENTORY_FILE" ]; then
            log_info "Using provided inventory file: $INVENTORY_FILE"
            if [ "$DRY_RUN" = false ]; then
                cp "$INVENTORY_FILE" "$inventory_path"
                
                # Set appropriate ownership
                if [ -n "$TARGET_USER" ]; then
                    chown "$TARGET_USER" "$inventory_path"
                fi
            else
                log_info "[DRY RUN] Would copy inventory file to $inventory_path"
            fi
        else
            log_warning "Provided inventory file not found: $INVENTORY_FILE"
            log_info "Creating default inventory file"
            if [ "$DRY_RUN" = false ]; then
                echo "[localhost]
127.0.0.1 ansible_connection=local" > "$inventory_path"
                
                # Set appropriate ownership
                if [ -n "$TARGET_USER" ]; then
                    chown "$TARGET_USER" "$inventory_path"
                fi
            else
                log_info "[DRY RUN] Would create default inventory file"
            fi
        fi
    else
        # Create a default inventory file
        log_info "Creating default inventory file"
        if [ "$DRY_RUN" = false ]; then
            echo "[localhost]
127.0.0.1 ansible_connection=local" > "$inventory_path"
            
            # Set appropriate ownership
            if [ -n "$TARGET_USER" ]; then
                chown "$TARGET_USER" "$inventory_path"
            fi
        else
            log_info "[DRY RUN] Would create default inventory file"
        fi
    fi
    
    # Set up configuration file
    local config_path="$ansible_config_dir/ansible.cfg"
    if [ -n "$CONFIG_FILE" ]; then
        # Use the provided configuration file
        if [ -f "$CONFIG_FILE" ]; then
            log_info "Using provided configuration file: $CONFIG_FILE"
            if [ "$DRY_RUN" = false ]; then
                cp "$CONFIG_FILE" "$config_path"
                
                # Set appropriate ownership
                if [ -n "$TARGET_USER" ]; then
                    chown "$TARGET_USER" "$config_path"
                fi
            else
                log_info "[DRY RUN] Would copy configuration file to $config_path"
            fi
        else
            log_warning "Provided configuration file not found: $CONFIG_FILE"
            log_info "Creating default configuration file"
            if [ "$DRY_RUN" = false ]; then
                echo "[defaults]
inventory = $inventory_path
host_key_checking = False
retry_files_enabled = False
gathering = smart" > "$config_path"
                
                # Set appropriate ownership
                if [ -n "$TARGET_USER" ]; then
                    chown "$TARGET_USER" "$config_path"
                fi
            else
                log_info "[DRY RUN] Would create default configuration file"
            fi
        fi
    else
        # Create a default configuration file
        log_info "Creating default configuration file"
        if [ "$DRY_RUN" = false ]; then
            echo "[defaults]
inventory = $inventory_path
host_key_checking = False
retry_files_enabled = False
gathering = smart" > "$config_path"
            
            # Set appropriate ownership
            if [ -n "$TARGET_USER" ]; then
                chown "$TARGET_USER" "$config_path"
            fi
        else
            log_info "[DRY RUN] Would create default configuration file"
        fi
    fi
    
    log_success "Ansible configured"
}

# Install Ansible Galaxy requirements
install_galaxy_requirements() {
    if [ -n "$GALAXY_REQUIREMENTS" ]; then
        print_section "Installing Ansible Galaxy requirements"
        
        if [ -f "$GALAXY_REQUIREMENTS" ]; then
            log_info "Installing Galaxy requirements from: $GALAXY_REQUIREMENTS"
            if [ "$DRY_RUN" = false ]; then
                # Determine the correct command to use
                local ansible_galaxy_cmd="ansible-galaxy"
                if [ -n "$VIRTUALENV_PATH" ]; then
                    ansible_galaxy_cmd="$VIRTUALENV_PATH/bin/ansible-galaxy"
                fi
                
                # Install Galaxy requirements
                if [ -n "$TARGET_USER" ] && [ -z "$VIRTUALENV_PATH" ]; then
                    # User-specific installation
                    su - "$TARGET_USER" -c "$ansible_galaxy_cmd install -r $GALAXY_REQUIREMENTS" >/dev/null 2>&1
                else
                    # System-wide or virtualenv installation
                    $ansible_galaxy_cmd install -r "$GALAXY_REQUIREMENTS" >/dev/null 2>&1
                fi
                
                log_success "Ansible Galaxy requirements installed"
            else
                log_info "[DRY RUN] Would install Galaxy requirements from $GALAXY_REQUIREMENTS"
            fi
        else
            log_warning "Provided Galaxy requirements file not found: $GALAXY_REQUIREMENTS"
        fi
    fi
}

# Install Python requirements
install_python_requirements() {
    if [ -n "$REQUIREMENTS_FILE" ]; then
        print_section "Installing Python requirements"
        
        if [ -f "$REQUIREMENTS_FILE" ]; then
            log_info "Installing Python requirements from: $REQUIREMENTS_FILE"
            if [ "$DRY_RUN" = false ]; then
                # Determine the correct pip command to use
                local pip_cmd="pip3"
                if [ -n "$VIRTUALENV_PATH" ]; then
                    pip_cmd="$VIRTUALENV_PATH/bin/pip"
                fi
                
                # Install Python requirements
                if [ -n "$TARGET_USER" ] && [ -z "$VIRTUALENV_PATH" ]; then
                    # User-specific installation
                    su - "$TARGET_USER" -c "$pip_cmd install --user -r $REQUIREMENTS_FILE" >/dev/null 2>&1
                else
                    # System-wide or virtualenv installation
                    if [ "$SYSTEM_WIDE" = true ]; then
                        $pip_cmd install -r "$REQUIREMENTS_FILE" >/dev/null 2>&1
                    else
                        $pip_cmd install --user -r "$REQUIREMENTS_FILE" >/dev/null 2>&1
                    fi
                fi
                
                log_success "Python requirements installed"
            else
                log_info "[DRY RUN] Would install Python requirements from $REQUIREMENTS_FILE"
            fi
        else
            log_warning "Provided Python requirements file not found: $REQUIREMENTS_FILE"
        fi
    fi
}

# Verify Ansible installation
verify_ansible() {
    print_section "Verifying Ansible installation"
    
    # Determine the correct ansible command to use
    local ansible_cmd="ansible"
    if [ -n "$VIRTUALENV_PATH" ]; then
        ansible_cmd="$VIRTUALENV_PATH/bin/ansible"
    fi
    
    # Check if Ansible is available
    if command -v "$ansible_cmd" &>/dev/null || [ -n "$VIRTUALENV_PATH" ] && [ -f "$VIRTUALENV_PATH/bin/ansible" ]; then
        log_success "Ansible is available"
    else
        log_error "Ansible is not available in the PATH"
        log_info "If you installed in a virtualenv, you need to activate it first:"
        log_info "source $VIRTUALENV_PATH/bin/activate"
        exit 1
    fi
    
    # Check Ansible version
    if [ "$DRY_RUN" = false ]; then
        log_info "Checking Ansible version..."
        
        if [ -n "$TARGET_USER" ] && [ -z "$VIRTUALENV_PATH" ]; then
            # User-specific installation
            su - "$TARGET_USER" -c "$ansible_cmd --version"
        else
            # System-wide or virtualenv installation
            $ansible_cmd --version
        fi
    else
        log_info "[DRY RUN] Would check Ansible version"
    fi
    
    # Test Ansible functionality
    if [ "$DRY_RUN" = false ]; then
        log_info "Testing Ansible functionality..."
        
        if [ -n "$TARGET_USER" ] && [ -z "$VIRTUALENV_PATH" ]; then
            # User-specific installation
            if su - "$TARGET_USER" -c "$ansible_cmd localhost -m ping" | grep -q "SUCCESS"; then
                log_success "Ansible ping test passed"
            else
                log_warning "Ansible ping test failed"
            fi
        else
            # System-wide or virtualenv installation
            if $ansible_cmd localhost -m ping | grep -q "SUCCESS"; then
                log_success "Ansible ping test passed"
            else
                log_warning "Ansible ping test failed"
            fi
        fi
    else
        log_info "[DRY RUN] Would test Ansible functionality"
    fi
}

# Display post-installation instructions
show_post_instructions() {
    print_header "Post-Installation Instructions"
    
    # Determine the correct ansible command to use
    local ansible_cmd="ansible"
    local ansible_dir="/etc/ansible"
    if [ -n "$VIRTUALENV_PATH" ]; then
        ansible_cmd="$VIRTUALENV_PATH/bin/ansible"
        ansible_dir="$VIRTUALENV_PATH/etc/ansible"
    elif [ -n "$TARGET_USER" ]; then
        ansible_dir="/home/$TARGET_USER/.ansible"
    fi
    
    log_info "Ansible installed and configured successfully."
    
    log_info "Configuration directory: $ansible_dir"
    log_info "Inventory file: $ansible_dir/hosts"
    log_info "Configuration file: $ansible_dir/ansible.cfg"
    
    if [ -n "$VIRTUALENV_PATH" ]; then
        log_info "Virtualenv activation: source $VIRTUALENV_PATH/bin/activate"
    fi
    
    log_info "Basic Ansible commands:"
    log_info "  $ansible_cmd --version                # Show Ansible version"
    log_info "  $ansible_cmd all -m ping             # Ping all hosts in inventory"
    log_info "  $ansible_cmd-playbook playbook.yml   # Run an Ansible playbook"
    log_info "  $ansible_cmd-galaxy list             # List installed Ansible Galaxy collections/roles"
    
    log_info "Ansible documentation: https://docs.ansible.com/"
}

# Main function
main() {
    print_header "Ansible Installation Script"
    
    # Check for root/sudo if installing system-wide
    check_root
    
    # Detect Linux distribution
    detect_distribution
    
    # Detect package manager
    detect_package_manager
    
    # Check for existing Ansible installation
    if check_existing_ansible; then
        # Install Ansible
        install_ansible
        
        # Configure Ansible
        configure_ansible
        
        # Install Galaxy requirements if specified
        install_galaxy_requirements
        
        # Install Python requirements if specified
        install_python_requirements
        
        # Verify Ansible installation
        verify_ansible
        
        # Show post-installation instructions
        show_post_instructions
        
        print_header "Ansible Installation Complete"
        log_success "Ansible has been successfully installed and configured"
    else
        print_header "Ansible Installation Skipped"
        log_info "Ansible is already installed. Use --force to reinstall."
        exit 0
    fi
}

# Run the main function
main