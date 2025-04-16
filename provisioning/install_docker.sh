#!/bin/bash
#
# Script Name: install_docker.sh
# Description: Install and configure Docker across different Linux distributions
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./install_docker.sh [options]
#
# Options:
#   -v, --version <version>     Specify Docker version to install (default: latest)
#   -c, --compose               Also install Docker Compose
#   -C, --compose-version <ver> Specify Docker Compose version (default: latest)
#   -u, --user <username>       Add specified user to docker group
#   -m, --mirror <url>          Use alternative Docker repository mirror
#   -d, --data-root <path>      Set custom data root directory (default: /var/lib/docker)
#   -p, --proxy <url>           Configure Docker to use HTTP/HTTPS proxy
#   -r, --registry <url>        Add private registry
#   -f, --force                 Force installation even if Docker is already installed
#   -R, --remove-old            Remove old Docker versions before installing
#   -n, --no-start              Don't start Docker service after installation
#   -I, --insecure              Allow insecure registries (not recommended)
#   -D, --debug                 Enable debug mode
#   -h, --help                  Display this help message
#
# Examples:
#   ./install_docker.sh
#   ./install_docker.sh -c -u myuser
#   ./install_docker.sh -v 24.0.2 -C 2.20.2
#   ./install_docker.sh -d /mnt/docker -p http://proxy.example.com:8080
#
# Requirements:
#   - Root privileges (or sudo)
#   - Internet connection
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
DOCKER_VERSION="latest"
COMPOSE_VERSION="latest"
INSTALL_COMPOSE=false
USER_TO_ADD=""
MIRROR_URL=""
DATA_ROOT="/var/lib/docker"
PROXY_URL=""
REGISTRY_URL=""
FORCE_INSTALL=false
REMOVE_OLD=false
NO_START=false
ALLOW_INSECURE=false
DEBUG=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            DOCKER_VERSION="$2"
            shift 2
            ;;
        -c|--compose)
            INSTALL_COMPOSE=true
            shift
            ;;
        -C|--compose-version)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            COMPOSE_VERSION="$2"
            INSTALL_COMPOSE=true
            shift 2
            ;;
        -u|--user)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            USER_TO_ADD="$2"
            shift 2
            ;;
        -m|--mirror)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            MIRROR_URL="$2"
            shift 2
            ;;
        -d|--data-root)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            DATA_ROOT="$2"
            shift 2
            ;;
        -p|--proxy)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            PROXY_URL="$2"
            shift 2
            ;;
        -r|--registry)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            REGISTRY_URL="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_INSTALL=true
            shift
            ;;
        -R|--remove-old)
            REMOVE_OLD=true
            shift
            ;;
        -n|--no-start)
            NO_START=true
            shift
            ;;
        -I|--insecure)
            ALLOW_INSECURE=true
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

    log_info "Detected distribution: $DISTRO $VERSION (family: $DISTRO_FAMILY)"
}

# Check for existing Docker installation
check_existing_docker() {
    print_section "Checking for existing Docker installation"

    if command -v docker &>/dev/null; then
        DOCKER_INSTALLED=true
        CURRENT_DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
        log_info "Docker is already installed (version $CURRENT_DOCKER_VERSION)"
        
        if [ "$FORCE_INSTALL" = true ]; then
            log_warning "Force install option specified. Will reinstall Docker."
        elif [ "$REMOVE_OLD" = true ]; then
            log_warning "Remove old option specified. Will remove existing Docker and reinstall."
        else
            log_info "Use --force to reinstall or --remove-old to remove existing Docker before installation."
            
            # Check Docker functionality
            log_info "Verifying Docker functionality..."
            if docker info &>/dev/null; then
                log_success "Docker is functioning correctly."
            else
                log_warning "Docker seems to be installed but not functioning correctly."
                log_info "You may want to use --force to reinstall or --remove-old to remove existing Docker before installation."
            fi
            
            return 0
        fi
    else
        DOCKER_INSTALLED=false
        log_info "Docker is not installed."
    fi
}

# Remove old Docker versions
remove_old_docker() {
    if [ "$REMOVE_OLD" = true ] || [ "$FORCE_INSTALL" = true ] && [ "$DOCKER_INSTALLED" = true ]; then
        print_section "Removing existing Docker installation"

        # Stop the Docker service if it's running
        if systemctl is-active --quiet docker; then
            log_info "Stopping Docker service..."
            systemctl stop docker
        fi

        # The packages to remove depend on the distribution
        case "$DISTRO_FAMILY" in
            "debian")
                log_info "Removing Docker packages..."
                apt-get remove -y docker docker-engine docker.io containerd runc docker-compose docker-compose-plugin &>/dev/null || true
                if [ "$REMOVE_OLD" = true ]; then
                    log_info "Purging Docker packages and configuration..."
                    apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin &>/dev/null || true
                    # Remove data directory if it exists and --remove-old was specified
                    if [ -d "$DATA_ROOT" ]; then
                        log_warning "Removing Docker data directory: $DATA_ROOT"
                        rm -rf "$DATA_ROOT"
                    fi
                fi
                ;;
            "redhat")
                log_info "Removing Docker packages..."
                yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin &>/dev/null || true
                if [ "$REMOVE_OLD" = true ]; then
                    # Remove data directory if it exists and --remove-old was specified
                    if [ -d "$DATA_ROOT" ]; then
                        log_warning "Removing Docker data directory: $DATA_ROOT"
                        rm -rf "$DATA_ROOT"
                    fi
                fi
                ;;
            "suse")
                log_info "Removing Docker packages..."
                zypper remove -y docker docker-engine docker.io docker-compose &>/dev/null || true
                if [ "$REMOVE_OLD" = true ]; then
                    # Remove data directory if it exists and --remove-old was specified
                    if [ -d "$DATA_ROOT" ]; then
                        log_warning "Removing Docker data directory: $DATA_ROOT"
                        rm -rf "$DATA_ROOT"
                    fi
                fi
                ;;
            "arch")
                log_info "Removing Docker packages..."
                pacman -R --noconfirm docker docker-compose &>/dev/null || true
                if [ "$REMOVE_OLD" = true ]; then
                    # Remove data directory if it exists and --remove-old was specified
                    if [ -d "$DATA_ROOT" ]; then
                        log_warning "Removing Docker data directory: $DATA_ROOT"
                        rm -rf "$DATA_ROOT"
                    fi
                fi
                ;;
            *)
                log_warning "Unsupported distribution for Docker removal: $DISTRO_FAMILY"
                ;;
        esac

        log_success "Removed old Docker installations"
    fi
}

# Install Docker prerequisites
install_prerequisites() {
    print_section "Installing prerequisites"

    case "$DISTRO_FAMILY" in
        "debian")
            log_info "Updating package lists..."
            apt-get update

            log_info "Installing prerequisites..."
            apt-get install -y \
                ca-certificates \
                curl \
                gnupg \
                lsb-release \
                apt-transport-https \
                software-properties-common
            ;;
        "redhat")
            log_info "Installing prerequisites..."
            if [ "$DISTRO" = "fedora" ]; then
                dnf -y install \
                    dnf-plugins-core \
                    curl \
                    device-mapper-persistent-data \
                    lvm2
            else
                # RHEL/CentOS/Rocky/Alma
                yum -y install \
                    yum-utils \
                    curl \
                    device-mapper-persistent-data \
                    lvm2
            fi
            ;;
        "suse")
            log_info "Installing prerequisites..."
            zypper --non-interactive install \
                curl \
                ca-certificates \
                python3-pip
            ;;
        "arch")
            log_info "Installing prerequisites..."
            pacman -Sy --noconfirm \
                curl \
                gnupg \
                ca-certificates
            ;;
        *)
            log_error "Unsupported distribution for Docker installation: $DISTRO_FAMILY"
            exit 1
            ;;
    esac

    log_success "Prerequisites installed"
}

# Add Docker repository
add_docker_repository() {
    print_section "Adding Docker repository"

    case "$DISTRO_FAMILY" in
        "debian")
            # Set up Docker's apt repository
            log_info "Adding Docker GPG key..."
            
            # Create the directory for keyrings if it doesn't exist
            mkdir -p /etc/apt/keyrings

            # Download and add the Docker GPG key
            curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg

            # Set up the repository
            log_info "Setting up Docker repository..."
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DISTRO $(lsb_release -cs) stable" | \
                tee /etc/apt/sources.list.d/docker.list > /dev/null

            # Use mirror if specified
            if [ -n "$MIRROR_URL" ]; then
                log_info "Setting up Docker mirror repository..."
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $MIRROR_URL $(lsb_release -cs) stable" | \
                    tee /etc/apt/sources.list.d/docker-mirror.list > /dev/null
            fi

            # Update package lists
            log_info "Updating package lists..."
            apt-get update
            ;;
        "redhat")
            # Set up Docker's yum repository
            log_info "Adding Docker repository..."

            if [ "$DISTRO" = "fedora" ]; then
                # Fedora
                dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                
                # Use mirror if specified
                if [ -n "$MIRROR_URL" ]; then
                    log_info "Setting up Docker mirror repository..."
                    echo -e "[docker-ce-mirror]\nname=Docker CE Mirror\nbaseurl=$MIRROR_URL\nenabled=1\ngpgcheck=1\ngpgkey=https://download.docker.com/linux/fedora/gpg" | \
                        tee /etc/yum.repos.d/docker-ce-mirror.repo > /dev/null
                fi
            else
                # RHEL/CentOS/Rocky/Alma
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                
                # Use mirror if specified
                if [ -n "$MIRROR_URL" ]; then
                    log_info "Setting up Docker mirror repository..."
                    echo -e "[docker-ce-mirror]\nname=Docker CE Mirror\nbaseurl=$MIRROR_URL\nenabled=1\ngpgcheck=1\ngpgkey=https://download.docker.com/linux/centos/gpg" | \
                        tee /etc/yum.repos.d/docker-ce-mirror.repo > /dev/null
                fi
            fi
            ;;
        "suse")
            # Add Docker repository for openSUSE
            log_info "Adding Docker repository..."
            
            if [[ "$DISTRO" == "opensuse"* ]]; then
                # openSUSE
                zypper --non-interactive addrepo \
                    https://download.docker.com/linux/sles/docker-ce.repo
                
                # Use mirror if specified
                if [ -n "$MIRROR_URL" ]; then
                    log_info "Setting up Docker mirror repository..."
                    zypper --non-interactive addrepo "$MIRROR_URL" docker-ce-mirror
                fi
                
                # Refresh repositories
                zypper --non-interactive refresh
            else
                log_error "Unsupported SUSE distribution: $DISTRO"
                exit 1
            fi
            ;;
        "arch")
            # Docker is in the community repository for Arch Linux
            log_info "Docker is available in the community repository for Arch Linux"
            # No need to add a repository for Arch
            ;;
        *)
            log_error "Unsupported distribution for Docker installation: $DISTRO_FAMILY"
            exit 1
            ;;
    esac

    log_success "Docker repository added"
}

# Install Docker
install_docker() {
    print_section "Installing Docker"

    local install_version
    if [ "$DOCKER_VERSION" != "latest" ]; then
        install_version="-$DOCKER_VERSION"
    else
        install_version=""
    fi

    case "$DISTRO_FAMILY" in
        "debian")
            log_info "Installing Docker..."
            apt-get install -y docker-ce$install_version docker-ce-cli$install_version containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        "redhat")
            log_info "Installing Docker..."
            if [ "$DISTRO" = "fedora" ]; then
                # Fedora
                dnf -y install docker-ce$install_version docker-ce-cli$install_version containerd.io docker-buildx-plugin docker-compose-plugin
            else
                # RHEL/CentOS/Rocky/Alma
                yum -y install docker-ce$install_version docker-ce-cli$install_version containerd.io docker-buildx-plugin docker-compose-plugin
            fi
            ;;
        "suse")
            log_info "Installing Docker..."
            zypper --non-interactive install docker-ce$install_version docker-ce-cli$install_version containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        "arch")
            log_info "Installing Docker..."
            pacman -Sy --noconfirm docker containerd
            ;;
        *)
            log_error "Unsupported distribution for Docker installation: $DISTRO_FAMILY"
            exit 1
            ;;
    esac

    log_success "Docker installed"
}

# Install Docker Compose
install_docker_compose() {
    if [ "$INSTALL_COMPOSE" = true ]; then
        print_section "Installing Docker Compose"

        # Docker Compose v2 is now included as a plugin with Docker CE installations
        # We'll check if it's already installed first
        if docker compose version &>/dev/null; then
            COMPOSE_INSTALLED_VERSION=$(docker compose version --short)
            log_info "Docker Compose is already installed (version $COMPOSE_INSTALLED_VERSION)"
            
            # If a specific version was requested and it's different from the installed one
            if [ "$COMPOSE_VERSION" != "latest" ] && [ "$COMPOSE_VERSION" != "$COMPOSE_INSTALLED_VERSION" ]; then
                log_info "Requested Docker Compose version $COMPOSE_VERSION, but $COMPOSE_INSTALLED_VERSION is installed."
                log_info "Installing specified version..."
                install_specific_compose_version
            else
                log_success "Docker Compose is ready to use"
                return 0
            fi
        else
            # Check if we have the plugin but docker compose command is not working
            if [ -f /usr/libexec/docker/cli-plugins/docker-compose ] || [ -f /usr/local/lib/docker/cli-plugins/docker-compose ]; then
                log_info "Docker Compose plugin found but not working. Reinstalling..."
            fi
            
            # Install the Compose plugin or a specific version
            if [ "$COMPOSE_VERSION" != "latest" ]; then
                install_specific_compose_version
            else
                log_info "Installing Docker Compose via package manager..."
                
                case "$DISTRO_FAMILY" in
                    "debian")
                        apt-get install -y docker-compose-plugin
                        ;;
                    "redhat")
                        if [ "$DISTRO" = "fedora" ]; then
                            dnf -y install docker-compose-plugin
                        else
                            yum -y install docker-compose-plugin
                        fi
                        ;;
                    "suse")
                        zypper --non-interactive install docker-compose-plugin
                        ;;
                    "arch")
                        pacman -Sy --noconfirm docker-compose
                        ;;
                    *)
                        log_warning "Unsupported distribution for Docker Compose installation via package manager: $DISTRO_FAMILY"
                        install_specific_compose_version
                        ;;
                esac
            fi
        fi

        # Verify Docker Compose installation
        if docker compose version &>/dev/null; then
            COMPOSE_VERSION_INSTALLED=$(docker compose version --short)
            log_success "Docker Compose installed: $COMPOSE_VERSION_INSTALLED"
        else
            log_error "Failed to install Docker Compose"
            exit 1
        fi
    fi
}

# Install a specific version of Docker Compose
install_specific_compose_version() {
    log_info "Installing Docker Compose version $COMPOSE_VERSION..."
    
    # Create the Docker CLI plugins directory if it doesn't exist
    mkdir -p /usr/local/lib/docker/cli-plugins
    
    # Download the requested version of Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose
    
    # Make it executable
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    
    # Create a symlink for backward compatibility with docker-compose command
    ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
}

# Configure Docker
configure_docker() {
    print_section "Configuring Docker"

    # Create daemon.json if it doesn't exist
    if [ ! -d "/etc/docker" ]; then
        mkdir -p /etc/docker
    fi

    # Load existing config or create a new one
    if [ -f "/etc/docker/daemon.json" ]; then
        log_info "Loading existing Docker configuration..."
        daemon_config=$(cat /etc/docker/daemon.json)
    else
        log_info "Creating new Docker configuration..."
        daemon_config="{}"
    fi

    # Set custom data root if specified
    if [ "$DATA_ROOT" != "/var/lib/docker" ]; then
        log_info "Setting Docker data root to $DATA_ROOT..."
        daemon_config=$(echo "$daemon_config" | jq --arg path "$DATA_ROOT" '. + {"data-root": $path}')
        
        # Create the directory if it doesn't exist
        if [ ! -d "$DATA_ROOT" ]; then
            log_info "Creating data root directory: $DATA_ROOT"
            mkdir -p "$DATA_ROOT"
        fi
    fi

    # Configure proxy if specified
    if [ -n "$PROXY_URL" ]; then
        log_info "Configuring Docker to use proxy: $PROXY_URL..."
        
        # Create/update the Docker service directory for systemd
        mkdir -p /etc/systemd/system/docker.service.d
        
        # Create the HTTP proxy config
        cat > /etc/systemd/system/docker.service.d/http-proxy.conf << EOF
[Service]
Environment="HTTP_PROXY=$PROXY_URL"
Environment="HTTPS_PROXY=$PROXY_URL"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF
        log_info "Docker proxy configuration created in /etc/systemd/system/docker.service.d/http-proxy.conf"
        
        # Reload systemd
        systemctl daemon-reload
    fi

    # Configure registry if specified
    if [ -n "$REGISTRY_URL" ]; then
        log_info "Adding private registry: $REGISTRY_URL..."
        
        # Extract registry domain
        registry_domain=$(echo "$REGISTRY_URL" | cut -d/ -f3)
        
        # Update daemon.json to include the registry
        daemon_config=$(echo "$daemon_config" | jq --arg registry "$registry_domain" '. + {"registry-mirrors": [($registry | "https://" + .)]}')
    fi

    # Configure insecure registries if requested
    if [ "$ALLOW_INSECURE" = true ] && [ -n "$REGISTRY_URL" ]; then
        log_warning "Configuring Docker to allow insecure registry: $REGISTRY_URL (not recommended for production)"
        
        # Extract registry domain
        registry_domain=$(echo "$REGISTRY_URL" | cut -d/ -f3)
        
        # Update daemon.json to include the insecure registry
        daemon_config=$(echo "$daemon_config" | jq --arg registry "$registry_domain" '. + {"insecure-registries": [$registry]}')
    fi

    # Write the updated configuration
    echo "$daemon_config" > /etc/docker/daemon.json
    log_info "Docker configuration saved to /etc/docker/daemon.json"
    
    # Add user to docker group if specified
    if [ -n "$USER_TO_ADD" ]; then
        log_info "Adding user $USER_TO_ADD to docker group..."
        
        # Create the docker group if it doesn't exist
        if ! getent group docker > /dev/null; then
            groupadd docker
        fi
        
        # Add the user to the docker group
        usermod -aG docker "$USER_TO_ADD"
        log_success "User $USER_TO_ADD added to docker group"
    fi
}

# Start Docker service
start_docker_service() {
    if [ "$NO_START" != true ]; then
        print_section "Starting Docker service"

        log_info "Enabling Docker service to start at boot..."
        systemctl enable docker

        log_info "Starting Docker service..."
        systemctl restart docker

        # Check if Docker service is running
        if systemctl is-active --quiet docker; then
            log_success "Docker service is running"
        else
            log_error "Failed to start Docker service"
            log_info "Check the service status with: systemctl status docker"
            exit 1
        fi
    else
        log_info "Skipping Docker service start due to --no-start option"
        log_info "You can start Docker manually with: systemctl start docker"
    fi
}

# Verify Docker installation
verify_docker() {
    print_section "Verifying Docker installation"

    if [ "$NO_START" != true ]; then
        # Check Docker version
        log_info "Checking Docker version..."
        if docker --version; then
            log_success "Docker client is working"
        else
            log_error "Docker client is not working properly"
            exit 1
        fi

        # Check Docker daemon
        log_info "Checking Docker daemon..."
        if docker info &>/dev/null; then
            log_success "Docker daemon is running"
        else
            log_error "Docker daemon is not running or not accessible"
            log_info "Check the service status with: systemctl status docker"
            exit 1
        fi

        # Run hello-world container
        log_info "Running hello-world container..."
        if docker run --rm hello-world; then
            log_success "Docker container test passed"
        else
            log_error "Failed to run Docker container"
            exit 1
        fi

        # Check Docker Compose if installed
        if [ "$INSTALL_COMPOSE" = true ]; then
            log_info "Checking Docker Compose installation..."
            if docker compose version; then
                log_success "Docker Compose is working"
            else
                log_error "Docker Compose is not working properly"
                exit 1
            fi
        fi
    else
        log_info "Skipping Docker verification due to --no-start option"
    fi
}

# Print system information
print_system_info() {
    print_section "Docker System Information"

    if [ "$NO_START" != true ]; then
        # Print Docker version
        log_info "Docker version:"
        docker version
        
        # Print Docker info
        log_info "Docker system info:"
        docker info
        
        # Print Docker Compose version if installed
        if [ "$INSTALL_COMPOSE" = true ]; then
            log_info "Docker Compose version:"
            docker compose version
        fi
    else
        log_info "Skipping system information due to --no-start option"
    fi
}

# Main function
main() {
    print_header "Docker Installation Script"

    # Detect the Linux distribution
    detect_distribution

    # Check if we need jq
    if ! command -v jq &>/dev/null; then
        log_info "Installing jq for JSON processing..."
        case "$DISTRO_FAMILY" in
            "debian")
                apt-get update && apt-get install -y jq
                ;;
            "redhat")
                if [ "$DISTRO" = "fedora" ]; then
                    dnf -y install jq
                else
                    yum -y install jq
                fi
                ;;
            "suse")
                zypper --non-interactive install jq
                ;;
            "arch")
                pacman -Sy --noconfirm jq
                ;;
            *)
                log_warning "Unsupported distribution for automatic jq installation: $DISTRO_FAMILY"
                log_error "Please install jq manually"
                exit 1
                ;;
        esac
    fi

    # Check for existing Docker installation
    check_existing_docker

    # Skip the rest if Docker is already installed and we're not forcing reinstall
    if [ "$DOCKER_INSTALLED" = true ] && [ "$FORCE_INSTALL" != true ] && [ "$REMOVE_OLD" != true ]; then
        log_info "Docker is already installed. Use --force to reinstall."
        
        # Check if we need to install Docker Compose
        if [ "$INSTALL_COMPOSE" = true ]; then
            install_docker_compose
        fi
        
        # Check if we need to configure Docker
        if [ "$DATA_ROOT" != "/var/lib/docker" ] || [ -n "$PROXY_URL" ] || [ -n "$REGISTRY_URL" ] || [ -n "$USER_TO_ADD" ]; then
            configure_docker
            
            # Restart Docker if we've changed configuration and not using --no-start
            if [ "$NO_START" != true ]; then
                log_info "Restarting Docker service to apply configuration changes..."
                systemctl restart docker
            fi
        fi
        
        # Verify Docker installation
        if [ "$NO_START" != true ]; then
            verify_docker
            print_system_info
        fi
        
        print_header "Docker is already installed and configured"
        exit 0
    fi

    # Remove old Docker versions if needed
    remove_old_docker

    # Install prerequisites
    install_prerequisites

    # Add Docker repository
    add_docker_repository

    # Install Docker
    install_docker

    # Install Docker Compose if requested
    if [ "$INSTALL_COMPOSE" = true ]; then
        install_docker_compose
    fi

    # Configure Docker
    configure_docker

    # Start Docker service
    start_docker_service

    # Verify Docker installation
    verify_docker

    # Print system information
    print_system_info

    print_header "Docker Installation Complete"
    log_success "Docker has been successfully installed and configured"
    
    if [ -n "$USER_TO_ADD" ]; then
        log_info "User $USER_TO_ADD has been added to the docker group."
        log_info "The user may need to log out and log back in for the changes to take effect."
    fi
}

# Run the main function
main