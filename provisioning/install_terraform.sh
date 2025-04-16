#!/bin/bash
#
# Script Name: install_terraform.sh
# Description: Install and configure Terraform across different Linux distributions
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./install_terraform.sh [options]
#
# Options:
#   -v, --version <version>      Specify Terraform version (default: latest)
#   -i, --install-dir <dir>      Installation directory (default: /usr/local/bin)
#   -p, --provider <provider>    Install specific provider(s) (comma-separated)
#   -P, --plugins-dir <dir>      Terraform plugins directory (default: ~/.terraform.d/plugins)
#   -b, --binary-only            Install binary only (no completion, docs, etc.)
#   -d, --docs                   Install documentation
#   -c, --completion             Install shell completion
#   -C, --check-updates          Check for Terraform updates
#   -f, --force                  Force reinstallation if already installed
#   -t, --tfenv                  Install using tfenv for version management
#   -g, --global                 Global installation (system-wide)
#   -u, --user <username>        Install for specific user
#   -D, --debug                  Enable debug mode
#   -h, --help                   Display this help message
#
# Examples:
#   ./install_terraform.sh
#   ./install_terraform.sh -v 1.5.7 -c -d
#   ./install_terraform.sh -p aws,azurerm,google -t
#
# Requirements:
#   - Root privileges (or sudo) for global installation
#   - Internet connection
#   - curl or wget for downloading
#   - unzip for extracting the package
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
TF_VERSION="latest"
INSTALL_DIR="/usr/local/bin"
PROVIDER_LIST=""
PLUGINS_DIR="$HOME/.terraform.d/plugins"
BINARY_ONLY=false
INSTALL_DOCS=false
INSTALL_COMPLETION=false
CHECK_UPDATES=false
FORCE_INSTALL=false
USE_TFENV=false
GLOBAL_INSTALL=true
TARGET_USER=""
DEBUG=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            TF_VERSION="$2"
            shift 2
            ;;
        -i|--install-dir)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            INSTALL_DIR="$2"
            shift 2
            ;;
        -p|--provider)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            PROVIDER_LIST="$2"
            shift 2
            ;;
        -P|--plugins-dir)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            PLUGINS_DIR="$2"
            shift 2
            ;;
        -b|--binary-only)
            BINARY_ONLY=true
            shift
            ;;
        -d|--docs)
            INSTALL_DOCS=true
            shift
            ;;
        -c|--completion)
            INSTALL_COMPLETION=true
            shift
            ;;
        -C|--check-updates)
            CHECK_UPDATES=true
            shift
            ;;
        -f|--force)
            FORCE_INSTALL=true
            shift
            ;;
        -t|--tfenv)
            USE_TFENV=true
            shift
            ;;
        -g|--global)
            GLOBAL_INSTALL=true
            shift
            ;;
        -u|--user)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            TARGET_USER="$2"
            GLOBAL_INSTALL=false
            shift 2
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
    if [ "$GLOBAL_INSTALL" = true ] && [ $EUID -ne 0 ]; then
        log_error "This script must be run as root or with sudo for global installation"
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

# Check for required tools
check_prerequisites() {
    print_section "Checking prerequisites"
    local missing_tools=()
    
    # Check for curl or wget
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        missing_tools+=("curl or wget")
    fi
    
    # Check for unzip
    if ! command -v unzip &>/dev/null; then
        missing_tools+=("unzip")
    fi
    
    # Install missing tools if any
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_warning "Missing required tools: ${missing_tools[*]}"
        log_info "Attempting to install missing prerequisites..."
        
        case "$DISTRO_FAMILY" in
            "debian")
                apt-get update
                if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
                    apt-get install -y curl
                fi
                if ! command -v unzip &>/dev/null; then
                    apt-get install -y unzip
                fi
                ;;
            "redhat")
                if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
                    yum install -y curl
                fi
                if ! command -v unzip &>/dev/null; then
                    yum install -y unzip
                fi
                ;;
            "suse")
                if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
                    zypper install -y curl
                fi
                if ! command -v unzip &>/dev/null; then
                    zypper install -y unzip
                fi
                ;;
            "arch")
                if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
                    pacman -Sy --noconfirm curl
                fi
                if ! command -v unzip &>/dev/null; then
                    pacman -Sy --noconfirm unzip
                fi
                ;;
            *)
                log_error "Cannot install prerequisites automatically on this distribution"
                log_error "Please install the required tools manually: curl or wget, unzip"
                exit 1
                ;;
        esac
        
        # Check if installation was successful
        if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
            log_error "Failed to install curl or wget"
            exit 1
        fi
        if ! command -v unzip &>/dev/null; then
            log_error "Failed to install unzip"
            exit 1
        fi
        
        log_success "Successfully installed prerequisites"
    else
        log_success "All prerequisites are installed"
    fi
}

# Get the latest Terraform version
get_latest_version() {
    print_section "Checking for latest Terraform version"
    
    local latest_version
    if command -v curl &>/dev/null; then
        latest_version=$(curl -s https://api.releases.hashicorp.com/v1/releases/terraform/latest | grep -o '"version":"[^"]*' | cut -d'"' -f4)
    elif command -v wget &>/dev/null; then
        latest_version=$(wget -qO- https://api.releases.hashicorp.com/v1/releases/terraform/latest | grep -o '"version":"[^"]*' | cut -d'"' -f4)
    else
        log_error "Neither curl nor wget found"
        exit 1
    fi
    
    if [ -z "$latest_version" ]; then
        log_error "Failed to determine the latest Terraform version"
        exit 1
    fi
    
    log_info "Latest Terraform version: $latest_version"
    echo "$latest_version"
}

# Check for existing Terraform installation
check_existing_terraform() {
    print_section "Checking for existing Terraform installation"
    
    if command -v terraform &>/dev/null; then
        local current_version
        current_version=$(terraform version | head -n 1 | cut -d 'v' -f2)
        log_info "Terraform is already installed (version $current_version)"
        
        if [ "$CHECK_UPDATES" = true ]; then
            local latest_version
            latest_version=$(get_latest_version)
            
            if [ "$current_version" != "$latest_version" ]; then
                log_info "A newer version of Terraform is available: $latest_version"
                if [ "$FORCE_INSTALL" = true ]; then
                    log_info "Force install option specified. Will update Terraform."
                    return 0  # Continue with installation
                else
                    log_info "Use --force to update Terraform."
                    return 1  # Skip installation
                fi
            else
                log_info "You have the latest version of Terraform installed."
                if [ "$FORCE_INSTALL" = true ]; then
                    log_info "Force install option specified. Will reinstall Terraform."
                    return 0  # Continue with installation
                else
                    return 1  # Skip installation
                fi
            fi
        elif [ "$FORCE_INSTALL" = true ]; then
            log_info "Force install option specified. Will reinstall Terraform."
            return 0  # Continue with installation
        else
            log_info "Use --force to reinstall Terraform or --check-updates to check for updates."
            return 1  # Skip installation
        fi
    else
        log_info "Terraform is not installed."
        return 0  # Continue with installation
    fi
}

# Install Terraform using the HashiCorp repository
install_hashicorp_repository() {
    print_section "Installing Terraform via HashiCorp repository"
    
    case "$DISTRO_FAMILY" in
        "debian")
            # Add HashiCorp GPG key
            log_info "Adding HashiCorp GPG key..."
            wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
            
            # Add HashiCorp repository
            log_info "Adding HashiCorp repository..."
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
            
            # Update repository
            log_info "Updating package lists..."
            apt-get update
            
            # Install Terraform
            log_info "Installing Terraform..."
            apt-get install -y terraform
            ;;
        "redhat")
            # Add HashiCorp repository
            log_info "Adding HashiCorp repository..."
            cat > /etc/yum.repos.d/hashicorp.repo << EOF
[hashicorp]
name=HashiCorp Stable - $basearch
baseurl=https://rpm.releases.hashicorp.com/RHEL/\$releasever/\$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://rpm.releases.hashicorp.com/gpg
EOF
            
            # Install Terraform
            log_info "Installing Terraform..."
            if [ "$DISTRO" = "fedora" ]; then
                dnf install -y terraform
            else
                yum install -y terraform
            fi
            ;;
        "suse")
            # Add HashiCorp repository
            log_info "Adding HashiCorp repository..."
            zypper addrepo -g https://rpm.releases.hashicorp.com/SLES/hashicorp.repo
            
            # Import GPG key
            log_info "Importing HashiCorp GPG key..."
            rpm --import https://rpm.releases.hashicorp.com/gpg
            
            # Install Terraform
            log_info "Installing Terraform..."
            zypper install -y terraform
            ;;
        "arch")
            # Install Terraform from official repositories
            log_info "Installing Terraform from Arch repositories..."
            pacman -Sy --noconfirm terraform
            ;;
        *)
            log_error "Unsupported distribution for repository installation"
            log_info "Falling back to binary installation"
            install_terraform_binary
            ;;
    esac
    
    # Verify installation
    if command -v terraform &>/dev/null; then
        local version
        version=$(terraform version | head -n 1 | cut -d 'v' -f2)
        log_success "Terraform installed successfully (version $version)"
    else
        log_error "Failed to install Terraform via repository"
        log_info "Falling back to binary installation"
        install_terraform_binary
    fi
}

# Install Terraform binary
install_terraform_binary() {
    print_section "Installing Terraform binary"
    
    # Determine the version to install
    local version="$TF_VERSION"
    if [ "$version" = "latest" ]; then
        version=$(get_latest_version)
    fi
    
    # Determine the architecture
    local arch
    case $(uname -m) in
        x86_64)
            arch="amd64"
            ;;
        i386|i686)
            arch="386"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        armv7*)
            arch="arm"
            ;;
        *)
            log_error "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir" || exit 1
    
    # Set download URL
    local download_url="https://releases.hashicorp.com/terraform/${version}/terraform_${version}_linux_${arch}.zip"
    log_info "Downloading Terraform from: $download_url"
    
    # Download the file
    if command -v curl &>/dev/null; then
        curl -s -o terraform.zip "$download_url"
    elif command -v wget &>/dev/null; then
        wget -q -O terraform.zip "$download_url"
    else
        log_error "Neither curl nor wget found"
        exit 1
    fi
    
    # Check if download was successful
    if [ ! -f terraform.zip ]; then
        log_error "Failed to download Terraform"
        exit 1
    fi
    
    # Extract the file
    log_info "Extracting Terraform..."
    unzip -q terraform.zip
    
    # Check if binary was extracted successfully
    if [ ! -f terraform ]; then
        log_error "Failed to extract Terraform binary"
        exit 1
    fi
    
    # Make the binary executable
    chmod +x terraform
    
    # Install the binary
    log_info "Installing Terraform to $INSTALL_DIR/terraform..."
    
    # Create installation directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"
    
    # Move the binary to the installation directory
    if [ "$GLOBAL_INSTALL" = true ]; then
        # Global installation
        mv terraform "$INSTALL_DIR/terraform"
    else
        # User-specific installation
        if [ -n "$TARGET_USER" ]; then
            # Install for specified user
            local user_home
            user_home=$(eval echo ~"$TARGET_USER")
            local user_bin_dir="$user_home/bin"
            mkdir -p "$user_bin_dir"
            mv terraform "$user_bin_dir/terraform"
            chown "$TARGET_USER" "$user_bin_dir/terraform"
            log_info "Installed Terraform to $user_bin_dir/terraform"
            
            # Add the bin directory to USER_PATH if necessary
            if ! grep -q "export PATH=\"\$HOME/bin:\$PATH\"" "$user_home/.bashrc"; then
                echo 'export PATH="$HOME/bin:$PATH"' >> "$user_home/.bashrc"
                chown "$TARGET_USER" "$user_home/.bashrc"
                log_info "Added $user_bin_dir to PATH in .bashrc"
            fi
        else
            # Install for current user
            local user_bin_dir="$HOME/bin"
            mkdir -p "$user_bin_dir"
            mv terraform "$user_bin_dir/terraform"
            log_info "Installed Terraform to $user_bin_dir/terraform"
            
            # Add the bin directory to USER_PATH if necessary
            if ! grep -q "export PATH=\"\$HOME/bin:\$PATH\"" "$HOME/.bashrc"; then
                echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
                log_info "Added $user_bin_dir to PATH in .bashrc"
            fi
        fi
    fi
    
    # Clean up
    cd - >/dev/null || exit 1
    rm -rf "$temp_dir"
    
    # Verify installation
    local terraform_cmd
    if [ "$GLOBAL_INSTALL" = true ]; then
        terraform_cmd="$INSTALL_DIR/terraform"
    elif [ -n "$TARGET_USER" ]; then
        user_home=$(eval echo ~"$TARGET_USER")
        terraform_cmd="$user_home/bin/terraform"
    else
        terraform_cmd="$HOME/bin/terraform"
    fi
    
    if [ -f "$terraform_cmd" ]; then
        log_success "Terraform binary installed successfully"
    else
        log_error "Failed to install Terraform binary"
        exit 1
    fi
}

# Install Terraform using tfenv
install_tfenv() {
    print_section "Installing Terraform using tfenv"
    
    # Check if tfenv is already installed
    if command -v tfenv &>/dev/null; then
        log_info "tfenv is already installed"
    else
        log_info "Installing tfenv..."
        
        # Determine installation directory
        local tfenv_dir
        if [ "$GLOBAL_INSTALL" = true ]; then
            tfenv_dir="/usr/local/tfenv"
        elif [ -n "$TARGET_USER" ]; then
            tfenv_dir=$(eval echo ~"$TARGET_USER")/.tfenv
        else
            tfenv_dir="$HOME/.tfenv"
        fi
        
        # Clone tfenv repository
        git clone --depth=1 https://github.com/tfutils/tfenv.git "$tfenv_dir"
        
        # Create symlinks
        if [ "$GLOBAL_INSTALL" = true ]; then
            ln -sf "$tfenv_dir/bin/tfenv" /usr/local/bin/tfenv
            ln -sf "$tfenv_dir/bin/terraform" /usr/local/bin/terraform
        elif [ -n "$TARGET_USER" ]; then
            local user_bin_dir=$(eval echo ~"$TARGET_USER")/bin
            mkdir -p "$user_bin_dir"
            ln -sf "$tfenv_dir/bin/tfenv" "$user_bin_dir/tfenv"
            ln -sf "$tfenv_dir/bin/terraform" "$user_bin_dir/terraform"
            chown -R "$TARGET_USER" "$tfenv_dir"
            chown -R "$TARGET_USER" "$user_bin_dir"
        else
            mkdir -p "$HOME/bin"
            ln -sf "$tfenv_dir/bin/tfenv" "$HOME/bin/tfenv"
            ln -sf "$tfenv_dir/bin/terraform" "$HOME/bin/terraform"
            
            # Add the bin directory to USER_PATH if necessary
            if ! grep -q "export PATH=\"\$HOME/bin:\$PATH\"" "$HOME/.bashrc"; then
                echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
                log_info "Added $HOME/bin to PATH in .bashrc"
            fi
        fi
    fi
    
    # Install Terraform using tfenv
    log_info "Installing Terraform using tfenv..."
    
    # Determine the version to install
    local version="$TF_VERSION"
    if [ "$version" = "latest" ]; then
        version="latest"
    fi
    
    # Run tfenv as the target user if specified
    if [ -n "$TARGET_USER" ] && [ "$GLOBAL_INSTALL" = false ]; then
        if [ "$version" = "latest" ]; then
            su - "$TARGET_USER" -c "tfenv install latest"
            su - "$TARGET_USER" -c "tfenv use latest"
        else
            su - "$TARGET_USER" -c "tfenv install $version"
            su - "$TARGET_USER" -c "tfenv use $version"
        fi
    else
        if [ "$version" = "latest" ]; then
            tfenv install latest
            tfenv use latest
        else
            tfenv install "$version"
            tfenv use "$version"
        fi
    fi
    
    # Verify installation
    local terraform_cmd
    if [ "$GLOBAL_INSTALL" = true ]; then
        terraform_cmd="terraform"
    elif [ -n "$TARGET_USER" ]; then
        local user_bin_dir=$(eval echo ~"$TARGET_USER")/bin
        terraform_cmd="$user_bin_dir/terraform"
    else
        terraform_cmd="$HOME/bin/terraform"
    fi
    
    if command -v "$terraform_cmd" &>/dev/null; then
        local version
        version=$("$terraform_cmd" version | head -n 1 | cut -d 'v' -f2)
        log_success "Terraform installed successfully using tfenv (version $version)"
    else
        log_error "Failed to install Terraform using tfenv"
        log_info "Falling back to binary installation"
        install_terraform_binary
    fi
}

# Install specific Terraform providers
install_providers() {
    if [ -z "$PROVIDER_LIST" ]; then
        return
    fi
    
    print_section "Installing Terraform providers"
    
    # Create plugins directory if it doesn't exist
    if [ -n "$TARGET_USER" ]; then
        # Use target user's plugins directory
        PLUGINS_DIR=$(eval echo ~"$TARGET_USER")/.terraform.d/plugins
        mkdir -p "$PLUGINS_DIR"
        chown -R "$TARGET_USER" "$(dirname "$PLUGINS_DIR")"
    else
        # Use default plugins directory
        mkdir -p "$PLUGINS_DIR"
    fi
    
    # Split the provider list by commas
    IFS=',' read -ra PROVIDERS <<< "$PROVIDER_LIST"
    
    for provider in "${PROVIDERS[@]}"; do
        log_info "Initializing provider: $provider"
        
        # Create a temporary directory
        local temp_dir
        temp_dir=$(mktemp -d)
        cd "$temp_dir" || exit 1
        
        # Create a minimal Terraform configuration
        cat > main.tf << EOF
terraform {
  required_providers {
    $provider = {
      source = "hashicorp/$provider"
    }
  }
}

provider "$provider" {}
EOF
        
        # Initialize Terraform to download the provider
        if [ -n "$TARGET_USER" ]; then
            # Run as the target user
            su - "$TARGET_USER" -c "cd $temp_dir && terraform init"
        else
            # Run as the current user
            terraform init
        fi
        
        # Clean up
        cd - >/dev/null || exit 1
        rm -rf "$temp_dir"
        
        log_success "Provider $provider initialized"
    done
}

# Install shell completion
install_shell_completion() {
    if [ "$INSTALL_COMPLETION" != true ]; then
        return
    fi
    
    print_section "Installing shell completion"
    
    # Determine the user's shell
    local user_shell
    if [ -n "$TARGET_USER" ]; then
        user_shell=$(getent passwd "$TARGET_USER" | cut -d: -f7)
    else
        user_shell=$SHELL
    fi
    
    # Get the shell name
    local shell_name
    shell_name=$(basename "$user_shell")
    
    log_info "Detected shell: $shell_name"
    
    case "$shell_name" in
        bash)
            # Generate Bash completion
            log_info "Generating Bash completion..."
            
            if [ -n "$TARGET_USER" ]; then
                # Target user's completion file
                local user_home
                user_home=$(eval echo ~"$TARGET_USER")
                terraform -install-autocomplete
                cp /usr/local/etc/bash_completion.d/terraform.sh "$user_home/.bash_completion"
                chown "$TARGET_USER" "$user_home/.bash_completion"
            else
                # Current user's completion file
                terraform -install-autocomplete
            fi
            ;;
        zsh)
            # Generate Zsh completion
            log_info "Generating Zsh completion..."
            
            if [ -n "$TARGET_USER" ]; then
                # Target user's completion file
                local user_home
                user_home=$(eval echo ~"$TARGET_USER")
                mkdir -p "$user_home/.oh-my-zsh/custom/plugins/terraform"
                terraform -install-autocomplete
                cp /usr/local/etc/bash_completion.d/terraform.sh "$user_home/.oh-my-zsh/custom/plugins/terraform/_terraform"
                chown -R "$TARGET_USER" "$user_home/.oh-my-zsh"
                
                # Add the plugin to .zshrc if not already present
                if [ -f "$user_home/.zshrc" ] && ! grep -q "plugins=.*terraform" "$user_home/.zshrc"; then
                    if grep -q "plugins=(" "$user_home/.zshrc"; then
                        # Add terraform to existing plugins list
                        sed -i 's/plugins=(/plugins=(terraform /' "$user_home/.zshrc"
                    else
                        # Create new plugins line
                        echo 'plugins=(terraform)' >> "$user_home/.zshrc"
                    fi
                    chown "$TARGET_USER" "$user_home/.zshrc"
                fi
            else
                # Current user's completion file
                mkdir -p "$HOME/.oh-my-zsh/custom/plugins/terraform"
                terraform -install-autocomplete
                cp /usr/local/etc/bash_completion.d/terraform.sh "$HOME/.oh-my-zsh/custom/plugins/terraform/_terraform"
                
                # Add the plugin to .zshrc if not already present
                if [ -f "$HOME/.zshrc" ] && ! grep -q "plugins=.*terraform" "$HOME/.zshrc"; then
                    if grep -q "plugins=(" "$HOME/.zshrc"; then
                        # Add terraform to existing plugins list
                        sed -i 's/plugins=(/plugins=(terraform /' "$HOME/.zshrc"
                    else
                        # Create new plugins line
                        echo 'plugins=(terraform)' >> "$HOME/.zshrc"
                    fi
                fi
            fi
            ;;
        *)
            log_warning "Shell completion not supported for $shell_name"
            ;;
    esac
    
    log_success "Shell completion installed"
}

# Install documentation
install_documentation() {
    if [ "$INSTALL_DOCS" != true ]; then
        return
    fi
    
    print_section "Installing documentation"
    
    # Determine documentation directory
    local docs_dir
    if [ "$GLOBAL_INSTALL" = true ]; then
        docs_dir="/usr/local/share/terraform/docs"
    elif [ -n "$TARGET_USER" ]; then
        docs_dir=$(eval echo ~"$TARGET_USER")/.terraform/docs
    else
        docs_dir="$HOME/.terraform/docs"
    fi
    
    # Create documentation directory
    mkdir -p "$docs_dir"
    
    # Download documentation
    log_info "Downloading Terraform documentation..."
    
    # Get the current Terraform version
    local version
    if command -v terraform &>/dev/null; then
        version=$(terraform version | head -n 1 | cut -d 'v' -f2)
    elif [ "$TF_VERSION" != "latest" ]; then
        version="$TF_VERSION"
    else
        version=$(get_latest_version)
    fi
    
    # Documentation URL
    local docs_url="https://releases.hashicorp.com/terraform/${version}/terraform_${version}_docs.zip"
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir" || exit 1
    
    # Download documentation
    if command -v curl &>/dev/null; then
        curl -s -o docs.zip "$docs_url"
    elif command -v wget &>/dev/null; then
        wget -q -O docs.zip "$docs_url"
    else
        log_error "Neither curl nor wget found"
        exit 1
    fi
    
    # Check if download was successful
    if [ ! -f docs.zip ]; then
        log_warning "Failed to download documentation"
        log_info "Documentation might not be available for this version"
        cd - >/dev/null || exit 1
        rm -rf "$temp_dir"
        return
    fi
    
    # Extract documentation
    unzip -q docs.zip -d "$docs_dir"
    
    # Set permissions
    if [ -n "$TARGET_USER" ]; then
        chown -R "$TARGET_USER" "$(dirname "$docs_dir")"
    fi
    
    # Clean up
    cd - >/dev/null || exit 1
    rm -rf "$temp_dir"
    
    log_success "Documentation installed to $docs_dir"
}

# Main function
main() {
    print_header "Terraform Installation Script"
    
    # Check if running as root
    check_root
    
    # Detect distribution
    detect_distribution
    
    # Check prerequisites
    check_prerequisites
    
    # Check for existing Terraform installation
    if check_existing_terraform; then
        # Install Terraform
        if [ "$USE_TFENV" = true ]; then
            install_tfenv
        elif [ "$BINARY_ONLY" = true ] || [ "$TF_VERSION" != "latest" ]; then
            install_terraform_binary
        else
            install_hashicorp_repository
        fi
        
        # Install specific providers
        install_providers
        
        # Install shell completion
        install_shell_completion
        
        # Install documentation
        install_documentation
        
        # Verify installation
        local terraform_path
        if command -v terraform &>/dev/null; then
            terraform_path=$(command -v terraform)
        elif [ "$GLOBAL_INSTALL" = true ]; then
            terraform_path="$INSTALL_DIR/terraform"
        elif [ -n "$TARGET_USER" ]; then
            terraform_path=$(eval echo ~"$TARGET_USER")/bin/terraform
        else
            terraform_path="$HOME/bin/terraform"
        fi
        
        if [ -f "$terraform_path" ]; then
            log_success "Terraform has been successfully installed"
            log_info "Terraform path: $terraform_path"
            "$terraform_path" version
        else
            log_error "Terraform installation verification failed"
            exit 1
        fi
    fi
    
    print_header "Terraform Installation Complete"
}

# Run the main function
main