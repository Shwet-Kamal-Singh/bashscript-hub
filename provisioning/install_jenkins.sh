#!/bin/bash
#
# Script Name: install_jenkins.sh
# Description: Install and configure Jenkins CI server across different Linux distributions
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./install_jenkins.sh [options]
#
# Options:
#   -v, --version <version>      Specify Jenkins version (default: latest)
#   -p, --port <port>            Set HTTP port for Jenkins (default: 8080)
#   -a, --ajp-port <port>        Set AJP port for Jenkins (default: disabled)
#   -j, --java-opts <opts>       Set JAVA_OPTS for Jenkins
#   -h, --home <dir>             Set JENKINS_HOME directory (default: /var/lib/jenkins)
#   -u, --user <user>            Set Jenkins user (default: jenkins)
#   -i, --install-plugins <list> Install specified plugins (comma-separated)
#   -P, --proxy <url>            Configure HTTP proxy for Jenkins
#   -s, --ssl                    Configure Jenkins with SSL
#   -c, --cert <path>            Path to SSL certificate (for use with --ssl)
#   -k, --key <path>             Path to SSL key (for use with --ssl)
#   -r, --reverse-proxy          Configure for reverse proxy
#   -b, --backup <path>          Backup existing Jenkins installation
#   -n, --no-start               Don't start Jenkins after installation
#   -S, --skip-wizard            Skip Jenkins setup wizard
#   -d, --debug                  Enable debug mode
#   -f, --force                  Force reinstallation if already installed
#   -y, --yes                    Answer yes to all prompts
#   -h, --help                   Display this help message
#
# Examples:
#   ./install_jenkins.sh
#   ./install_jenkins.sh -p 9090 -j "-Xmx2g -Djava.awt.headless=true"
#   ./install_jenkins.sh -i "git,pipeline,docker,blueocean"
#   ./install_jenkins.sh -s -c /etc/ssl/certs/jenkins.crt -k /etc/ssl/private/jenkins.key
#
# Requirements:
#   - Root privileges (or sudo)
#   - Java 11 or later
#   - wget or curl for downloading
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
JENKINS_VERSION="latest"
HTTP_PORT=8080
AJP_PORT=""
JAVA_OPTS=""
JENKINS_HOME="/var/lib/jenkins"
JENKINS_USER="jenkins"
PLUGINS_LIST=""
PROXY_URL=""
USE_SSL=false
SSL_CERT=""
SSL_KEY=""
REVERSE_PROXY=false
BACKUP_PATH=""
START_JENKINS=true
SKIP_WIZARD=false
DEBUG=false
FORCE_INSTALL=false
ASSUME_YES=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            JENKINS_VERSION="$2"
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
            HTTP_PORT="$2"
            shift 2
            ;;
        -a|--ajp-port)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ] || [ "$2" -gt 65535 ]; then
                log_error "Invalid port number: $2"
                exit 1
            fi
            AJP_PORT="$2"
            shift 2
            ;;
        -j|--java-opts)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            JAVA_OPTS="$2"
            shift 2
            ;;
        -h|--home)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            JENKINS_HOME="$2"
            shift 2
            ;;
        -u|--user)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            JENKINS_USER="$2"
            shift 2
            ;;
        -i|--install-plugins)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            PLUGINS_LIST="$2"
            shift 2
            ;;
        -P|--proxy)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            PROXY_URL="$2"
            shift 2
            ;;
        -s|--ssl)
            USE_SSL=true
            shift
            ;;
        -c|--cert)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            SSL_CERT="$2"
            shift 2
            ;;
        -k|--key)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            SSL_KEY="$2"
            shift 2
            ;;
        -r|--reverse-proxy)
            REVERSE_PROXY=true
            shift
            ;;
        -b|--backup)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            BACKUP_PATH="$2"
            shift 2
            ;;
        -n|--no-start)
            START_JENKINS=false
            shift
            ;;
        -S|--skip-wizard)
            SKIP_WIZARD=true
            shift
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -f|--force)
            FORCE_INSTALL=true
            shift
            ;;
        -y|--yes)
            ASSUME_YES=true
            shift
            ;;
        --help)
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

# Check for required tools
check_prerequisites() {
    print_section "Checking prerequisites"
    local missing_tools=()
    
    # Check for wget or curl
    if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
        missing_tools+=("wget or curl")
    fi
    
    # Install missing tools if any
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_warning "Missing required tools: ${missing_tools[*]}"
        if [ "$ASSUME_YES" = true ]; then
            log_info "Installing missing tools automatically..."
        else
            read -p "Do you want to install the missing tools? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Required tools are missing. Aborting."
                exit 1
            fi
        fi
        
        case "$DISTRO_FAMILY" in
            "debian")
                apt-get update
                apt-get install -y wget
                ;;
            "redhat")
                if [ "$DISTRO" = "fedora" ]; then
                    dnf install -y wget
                else
                    yum install -y wget
                fi
                ;;
            "suse")
                zypper install -y wget
                ;;
            "arch")
                pacman -Sy --noconfirm wget
                ;;
            *)
                log_error "Cannot install prerequisites automatically on this distribution"
                exit 1
                ;;
        esac
        
        log_success "Required tools installed"
    else
        log_success "All required tools are installed"
    fi
}

# Check for Java installation
check_java() {
    print_section "Checking Java installation"
    
    # Check if Java is installed
    if ! command -v java &>/dev/null; then
        log_warning "Java is not installed"
        if [ "$ASSUME_YES" = true ]; then
            log_info "Installing Java automatically..."
            install_java
        else
            read -p "Do you want to install Java? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Java is required for Jenkins. Aborting."
                exit 1
            else
                install_java
            fi
        fi
    else
        # Check Java version
        JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        JAVA_MAJOR_VERSION=$(echo "$JAVA_VERSION" | awk -F '.' '{print $1}')
        
        if [ "$JAVA_MAJOR_VERSION" -lt 11 ]; then
            log_warning "Java version $JAVA_VERSION detected. Jenkins requires Java 11 or later."
            if [ "$ASSUME_YES" = true ]; then
                log_info "Installing required Java version automatically..."
                install_java
            else
                read -p "Do you want to install a compatible Java version? (y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_error "Compatible Java version is required for Jenkins. Aborting."
                    exit 1
                else
                    install_java
                fi
            fi
        else
            log_success "Java $JAVA_VERSION is installed (compatible with Jenkins)"
        fi
    fi
}

# Install Java
install_java() {
    print_section "Installing Java"
    
    case "$DISTRO_FAMILY" in
        "debian")
            log_info "Installing OpenJDK 11..."
            apt-get update
            apt-get install -y openjdk-11-jdk
            ;;
        "redhat")
            log_info "Installing OpenJDK 11..."
            if [ "$DISTRO" = "fedora" ]; then
                dnf install -y java-11-openjdk
            else
                yum install -y java-11-openjdk
            fi
            ;;
        "suse")
            log_info "Installing OpenJDK 11..."
            zypper install -y java-11-openjdk
            ;;
        "arch")
            log_info "Installing OpenJDK 11..."
            pacman -Sy --noconfirm jdk11-openjdk
            ;;
        *)
            log_error "Cannot install Java automatically on this distribution"
            exit 1
            ;;
    esac
    
    # Verify Java installation
    if ! command -v java &>/dev/null; then
        log_error "Failed to install Java"
        exit 1
    fi
    
    # Get installed Java version
    JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    log_success "Java $JAVA_VERSION installed successfully"
}

# Check for existing Jenkins installation
check_existing_jenkins() {
    print_section "Checking for existing Jenkins installation"
    
    # Check if Jenkins service exists
    if systemctl list-unit-files jenkins.service &>/dev/null; then
        JENKINS_INSTALLED=true
        
        # Check if Jenkins is running
        if systemctl is-active --quiet jenkins; then
            JENKINS_RUNNING=true
            log_info "Jenkins is already installed and running"
            
            # Get current Jenkins version
            if [ -f /var/cache/jenkins/war/META-INF/MANIFEST.MF ]; then
                CURRENT_VERSION=$(grep -i "Jenkins-Version" /var/cache/jenkins/war/META-INF/MANIFEST.MF | cut -d' ' -f2)
                log_info "Current Jenkins version: $CURRENT_VERSION"
            else
                log_warning "Could not determine current Jenkins version"
            fi
        else
            JENKINS_RUNNING=false
            log_info "Jenkins is installed but not running"
        fi
        
        if [ "$FORCE_INSTALL" = true ]; then
            log_warning "Force install option specified. Will reinstall Jenkins."
            return 0
        else
            if [ "$ASSUME_YES" = true ]; then
                log_info "Jenkins is already installed. Use --force to reinstall."
                exit 0
            else
                read -p "Jenkins is already installed. Do you want to proceed with reinstallation? (y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Installation aborted by user."
                    exit 0
                fi
                return 0
            fi
        fi
    else
        JENKINS_INSTALLED=false
        log_info "Jenkins is not installed"
        return 0
    fi
}

# Backup existing Jenkins installation
backup_jenkins() {
    if [ -z "$BACKUP_PATH" ]; then
        return 0
    fi
    
    print_section "Backing up existing Jenkins installation"
    
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_PATH"
    
    # Stop Jenkins service
    if systemctl is-active --quiet jenkins; then
        log_info "Stopping Jenkins service for backup..."
        systemctl stop jenkins
    fi
    
    # Backup Jenkins home directory
    if [ -d "$JENKINS_HOME" ]; then
        log_info "Backing up Jenkins home directory to $BACKUP_PATH/jenkins_home_$(date +%Y%m%d%H%M%S).tar.gz"
        tar -czf "$BACKUP_PATH/jenkins_home_$(date +%Y%m%d%H%M%S).tar.gz" -C "$(dirname "$JENKINS_HOME")" "$(basename "$JENKINS_HOME")"
    fi
    
    # Backup Jenkins configuration files
    log_info "Backing up Jenkins configuration files"
    if [ -f /etc/default/jenkins ]; then
        cp /etc/default/jenkins "$BACKUP_PATH/jenkins_default_$(date +%Y%m%d%H%M%S)"
    fi
    
    if [ -f /etc/sysconfig/jenkins ]; then
        cp /etc/sysconfig/jenkins "$BACKUP_PATH/jenkins_sysconfig_$(date +%Y%m%d%H%M%S)"
    fi
    
    log_success "Jenkins backup completed"
}

# Install Jenkins via package manager
install_jenkins_pkg() {
    print_section "Installing Jenkins via package manager"
    
    case "$DISTRO_FAMILY" in
        "debian")
            log_info "Adding Jenkins repository key..."
            if command -v curl &>/dev/null; then
                curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
            else
                wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
            fi
            
            log_info "Adding Jenkins repository..."
            echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
            
            log_info "Updating package lists..."
            apt-get update
            
            log_info "Installing Jenkins..."
            apt-get install -y jenkins
            ;;
        "redhat")
            log_info "Adding Jenkins repository..."
            if [ "$DISTRO" = "fedora" ]; then
                # Fedora uses dnf
                cat > /etc/yum.repos.d/jenkins.repo << 'EOF'
[jenkins]
name=Jenkins
baseurl=https://pkg.jenkins.io/redhat-stable/
gpgcheck=1
gpgkey=https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
enabled=1
EOF
                dnf install -y jenkins
            else
                # RHEL/CentOS use yum
                cat > /etc/yum.repos.d/jenkins.repo << 'EOF'
[jenkins]
name=Jenkins
baseurl=https://pkg.jenkins.io/redhat-stable/
gpgcheck=1
gpgkey=https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
enabled=1
EOF
                yum install -y jenkins
            fi
            ;;
        "suse")
            log_info "Adding Jenkins repository..."
            zypper addrepo -f https://pkg.jenkins.io/opensuse-stable/ jenkins
            
            log_info "Importing Jenkins repository key..."
            if command -v curl &>/dev/null; then
                curl -fsSL https://pkg.jenkins.io/opensuse-stable/jenkins.io-2023.key > /tmp/jenkins.key
            else
                wget -q -O /tmp/jenkins.key https://pkg.jenkins.io/opensuse-stable/jenkins.io-2023.key
            fi
            rpm --import /tmp/jenkins.key
            rm /tmp/jenkins.key
            
            log_info "Installing Jenkins..."
            zypper install -y jenkins
            ;;
        "arch")
            log_info "Installing Jenkins from AUR..."
            if ! command -v yay &>/dev/null && ! command -v paru &>/dev/null; then
                log_warning "AUR helper (yay or paru) not found"
                log_info "Installing Jenkins manually from AUR..."
                
                # Create a temporary build user if we're root
                local has_tmp_user=false
                if [ "$(id -u)" -eq 0 ]; then
                    if ! id -u aur_builder &>/dev/null; then
                        log_info "Creating temporary AUR builder user..."
                        useradd -m aur_builder
                        echo "aur_builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/aur_builder
                        has_tmp_user=true
                    fi
                    
                    # Set up the build directory
                    mkdir -p /tmp/jenkins_build
                    chown -R aur_builder:aur_builder /tmp/jenkins_build
                    
                    # Switch to the AUR builder user
                    cd /tmp/jenkins_build || exit 1
                    su - aur_builder -c "cd /tmp/jenkins_build && \
                                        git clone https://aur.archlinux.org/jenkins.git && \
                                        cd jenkins && \
                                        makepkg -si --noconfirm"
                    
                    # Clean up
                    if [ "$has_tmp_user" = true ]; then
                        log_info "Removing temporary AUR builder user..."
                        rm /etc/sudoers.d/aur_builder
                        userdel -r aur_builder
                    fi
                    rm -rf /tmp/jenkins_build
                else
                    # If not root, we can build directly
                    cd /tmp || exit 1
                    git clone https://aur.archlinux.org/jenkins.git
                    cd jenkins || exit 1
                    makepkg -si --noconfirm
                    cd /tmp && rm -rf jenkins
                fi
            else
                # Use AUR helper if available
                if command -v yay &>/dev/null; then
                    yay -S --noconfirm jenkins
                elif command -v paru &>/dev/null; then
                    paru -S --noconfirm jenkins
                fi
            fi
            ;;
        *)
            log_error "Unsupported distribution for package installation: $DISTRO_FAMILY"
            log_info "Falling back to WAR file installation"
            install_jenkins_war
            return
            ;;
    esac
    
    log_success "Jenkins installed via package manager"
}

# Install Jenkins via WAR file
install_jenkins_war() {
    print_section "Installing Jenkins via WAR file"
    
    # Create Jenkins user if it doesn't exist
    if ! id "$JENKINS_USER" &>/dev/null; then
        log_info "Creating Jenkins user: $JENKINS_USER"
        useradd -m -d "$JENKINS_HOME" -s /bin/false "$JENKINS_USER"
    fi
    
    # Create Jenkins home directory if it doesn't exist
    if [ ! -d "$JENKINS_HOME" ]; then
        log_info "Creating Jenkins home directory: $JENKINS_HOME"
        mkdir -p "$JENKINS_HOME"
        chown -R "$JENKINS_USER":"$JENKINS_USER" "$JENKINS_HOME"
    fi
    
    # Download Jenkins WAR file
    log_info "Downloading Jenkins WAR file..."
    if [ "$JENKINS_VERSION" = "latest" ]; then
        JENKINS_URL="https://get.jenkins.io/war-stable/latest/jenkins.war"
    else
        JENKINS_URL="https://get.jenkins.io/war-stable/$JENKINS_VERSION/jenkins.war"
    fi
    
    if command -v curl &>/dev/null; then
        curl -fsSL -o /usr/share/jenkins/jenkins.war "$JENKINS_URL"
    else
        wget -q -O /usr/share/jenkins/jenkins.war "$JENKINS_URL"
    fi
    
    # Create systemd service file
    log_info "Creating systemd service file for Jenkins..."
    cat > /etc/systemd/system/jenkins.service << EOF
[Unit]
Description=Jenkins Continuous Integration Server
Requires=network.target
After=network.target

[Service]
Type=forking
User=$JENKINS_USER
Group=$JENKINS_USER
Environment="JENKINS_HOME=$JENKINS_HOME"
Environment="JENKINS_WAR=/usr/share/jenkins/jenkins.war"
Environment="JENKINS_PORT=$HTTP_PORT"
EOF

    # Add AJP port if specified
    if [ -n "$AJP_PORT" ]; then
        echo "Environment=\"JENKINS_AJP_PORT=$AJP_PORT\"" >> /etc/systemd/system/jenkins.service
    fi

    # Add Java options if specified
    if [ -n "$JAVA_OPTS" ]; then
        echo "Environment=\"JAVA_OPTS=$JAVA_OPTS\"" >> /etc/systemd/system/jenkins.service
    fi

    # Complete the service file
    cat >> /etc/systemd/system/jenkins.service << 'EOF'
ExecStart=/usr/bin/java $JAVA_OPTS -jar $JENKINS_WAR --httpPort=$JENKINS_PORT
ExecReload=/bin/kill -HUP $MAINPID
SuccessExitStatus=143
Restart=on-failure
RestartSec=5
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    log_info "Reloading systemd configuration..."
    systemctl daemon-reload
    
    # Enable Jenkins service
    log_info "Enabling Jenkins service..."
    systemctl enable jenkins
    
    log_success "Jenkins installed via WAR file"
}

# Configure Jenkins
configure_jenkins() {
    print_section "Configuring Jenkins"
    
    # Determine configuration file path based on distribution
    local config_file=""
    case "$DISTRO_FAMILY" in
        "debian")
            config_file="/etc/default/jenkins"
            ;;
        "redhat"|"suse")
            config_file="/etc/sysconfig/jenkins"
            ;;
        *)
            log_warning "No standard configuration file for this distribution"
            return
            ;;
    esac
    
    # Check if configuration file exists
    if [ ! -f "$config_file" ]; then
        log_warning "Jenkins configuration file not found: $config_file"
        return
    fi
    
    log_info "Configuring Jenkins settings in $config_file"
    
    # Update HTTP port
    if grep -q "^JENKINS_PORT=" "$config_file"; then
        sed -i "s/^JENKINS_PORT=.*/JENKINS_PORT=$HTTP_PORT/" "$config_file"
    else
        echo "JENKINS_PORT=$HTTP_PORT" >> "$config_file"
    fi
    
    # Update AJP port if specified
    if [ -n "$AJP_PORT" ]; then
        if grep -q "^JENKINS_AJP_PORT=" "$config_file"; then
            sed -i "s/^JENKINS_AJP_PORT=.*/JENKINS_AJP_PORT=$AJP_PORT/" "$config_file"
        else
            echo "JENKINS_AJP_PORT=$AJP_PORT" >> "$config_file"
        fi
    fi
    
    # Update Java options if specified
    if [ -n "$JAVA_OPTS" ]; then
        if grep -q "^JAVA_OPTS=" "$config_file"; then
            sed -i "s|^JAVA_OPTS=.*|JAVA_OPTS=\"$JAVA_OPTS\"|" "$config_file"
        else
            echo "JAVA_OPTS=\"$JAVA_OPTS\"" >> "$config_file"
        fi
    fi
    
    # Update Jenkins home directory
    if grep -q "^JENKINS_HOME=" "$config_file"; then
        sed -i "s|^JENKINS_HOME=.*|JENKINS_HOME=$JENKINS_HOME|" "$config_file"
    else
        echo "JENKINS_HOME=$JENKINS_HOME" >> "$config_file"
    fi
    
    # Configure for reverse proxy if requested
    if [ "$REVERSE_PROXY" = true ]; then
        log_info "Configuring Jenkins for reverse proxy..."
        if grep -q "^JENKINS_ARGS=" "$config_file"; then
            if ! grep -q -- "--prefix=" "$config_file"; then
                sed -i "s|^JENKINS_ARGS=.*|&--prefix=/jenkins |" "$config_file"
            fi
        else
            echo 'JENKINS_ARGS="--prefix=/jenkins"' >> "$config_file"
        fi
        
        # Configure Jenkins URL
        if [ ! -d "$JENKINS_HOME" ]; then
            mkdir -p "$JENKINS_HOME"
        fi
        
        if [ ! -f "$JENKINS_HOME/jenkins.model.JenkinsLocationConfiguration.xml" ]; then
            cat > "$JENKINS_HOME/jenkins.model.JenkinsLocationConfiguration.xml" << EOF
<?xml version='1.1' encoding='UTF-8'?>
<jenkins.model.JenkinsLocationConfiguration>
  <jenkinsUrl>http://localhost:$HTTP_PORT/jenkins/</jenkinsUrl>
</jenkins.model.JenkinsLocationConfiguration>
EOF
            chown "$JENKINS_USER":"$JENKINS_USER" "$JENKINS_HOME/jenkins.model.JenkinsLocationConfiguration.xml"
        else
            log_warning "Jenkins location configuration file already exists, not modifying"
        fi
    fi
    
    # Configure SSL if requested
    if [ "$USE_SSL" = true ]; then
        log_info "Configuring Jenkins with SSL..."
        
        # Check for required SSL files
        if [ -z "$SSL_CERT" ] || [ -z "$SSL_KEY" ]; then
            log_error "SSL configuration requires both certificate and key"
            log_error "Use --cert and --key options to specify SSL certificate and key files"
            return 1
        fi
        
        if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
            log_error "SSL certificate or key file not found"
            return 1
        fi
        
        # Install and configure Nginx as SSL proxy
        log_info "Installing and configuring Nginx as SSL proxy..."
        case "$DISTRO_FAMILY" in
            "debian")
                apt-get update
                apt-get install -y nginx
                ;;
            "redhat")
                if [ "$DISTRO" = "fedora" ]; then
                    dnf install -y nginx
                else
                    yum install -y nginx
                fi
                ;;
            "suse")
                zypper install -y nginx
                ;;
            "arch")
                pacman -Sy --noconfirm nginx
                ;;
            *)
                log_error "Cannot install Nginx automatically on this distribution"
                return 1
                ;;
        esac
        
        # Create Nginx configuration
        log_info "Creating Nginx configuration for Jenkins..."
        cat > /etc/nginx/conf.d/jenkins.conf << EOF
server {
    listen 443 ssl;
    server_name localhost;

    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://localhost:$HTTP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 80;
    server_name localhost;
    return 301 https://\$host\$request_uri;
}
EOF
        
        # Reload Nginx
        log_info "Reloading Nginx configuration..."
        systemctl enable nginx
        systemctl restart nginx
    fi
    
    # Configure HTTP proxy if specified
    if [ -n "$PROXY_URL" ]; then
        log_info "Configuring HTTP proxy: $PROXY_URL"
        
        # Create proxy configuration file
        if [ ! -d "$JENKINS_HOME" ]; then
            mkdir -p "$JENKINS_HOME"
        fi
        
        cat > "$JENKINS_HOME/proxy.xml" << EOF
<?xml version='1.1' encoding='UTF-8'?>
<proxy>
  <name>proxy</name>
  <url>$PROXY_URL</url>
</proxy>
EOF
        chown "$JENKINS_USER":"$JENKINS_USER" "$JENKINS_HOME/proxy.xml"
    fi
    
    # Skip wizard if requested
    if [ "$SKIP_WIZARD" = true ]; then
        log_info "Configuring Jenkins to skip setup wizard..."
        
        if [ ! -d "$JENKINS_HOME" ]; then
            mkdir -p "$JENKINS_HOME"
        fi
        
        touch "$JENKINS_HOME/jenkins.install.InstallUtil.lastExecVersion"
        chown "$JENKINS_USER":"$JENKINS_USER" "$JENKINS_HOME/jenkins.install.InstallUtil.lastExecVersion"
    fi
    
    log_success "Jenkins configuration complete"
}

# Install Jenkins plugins
install_plugins() {
    if [ -z "$PLUGINS_LIST" ]; then
        return 0
    fi
    
    print_section "Installing Jenkins plugins"
    
    # Create plugins directory if it doesn't exist
    if [ ! -d "$JENKINS_HOME/plugins" ]; then
        mkdir -p "$JENKINS_HOME/plugins"
        chown "$JENKINS_USER":"$JENKINS_USER" "$JENKINS_HOME/plugins"
    fi
    
    # Get Jenkins CLI jar
    log_info "Downloading Jenkins CLI..."
    if [ ! -f "/tmp/jenkins-cli.jar" ]; then
        # Wait for Jenkins to start
        log_info "Waiting for Jenkins to start..."
        local max_attempts=30
        local attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if curl -s -f http://localhost:$HTTP_PORT >/dev/null; then
                break
            fi
            attempt=$((attempt + 1))
            log_info "Waiting for Jenkins to start (attempt $attempt/$max_attempts)..."
            sleep 5
        done
        
        if [ $attempt -eq $max_attempts ]; then
            log_error "Timed out waiting for Jenkins to start"
            return 1
        fi
        
        # Wait a bit longer for Jenkins to fully initialize
        sleep 10
        
        # Download CLI
        if command -v curl &>/dev/null; then
            curl -s -o /tmp/jenkins-cli.jar http://localhost:$HTTP_PORT/jnlpJars/jenkins-cli.jar
        else
            wget -q -O /tmp/jenkins-cli.jar http://localhost:$HTTP_PORT/jnlpJars/jenkins-cli.jar
        fi
    fi
    
    # Get initial admin password
    local admin_password=""
    if [ -f "$JENKINS_HOME/secrets/initialAdminPassword" ]; then
        admin_password=$(cat "$JENKINS_HOME/secrets/initialAdminPassword")
    else
        log_warning "Jenkins initial admin password not found"
        log_info "Plugins will be installed manually into the plugins directory"
        
        # Install plugins directly to the plugins directory
        IFS=',' read -ra PLUGINS <<< "$PLUGINS_LIST"
        for plugin in "${PLUGINS[@]}"; do
            log_info "Installing plugin: $plugin"
            
            # Download plugin
            plugin_url="https://updates.jenkins.io/latest/$plugin.hpi"
            if command -v curl &>/dev/null; then
                curl -s -o "$JENKINS_HOME/plugins/$plugin.hpi" "$plugin_url"
            else
                wget -q -O "$JENKINS_HOME/plugins/$plugin.hpi" "$plugin_url"
            fi
            
            # Set correct permissions
            chown "$JENKINS_USER":"$JENKINS_USER" "$JENKINS_HOME/plugins/$plugin.hpi"
        done
        
        log_info "Plugins installed. Jenkins needs to be restarted to load them."
        return 0
    fi
    
    # Install plugins using Jenkins CLI
    log_info "Installing plugins using Jenkins CLI..."
    IFS=',' read -ra PLUGINS <<< "$PLUGINS_LIST"
    for plugin in "${PLUGINS[@]}"; do
        log_info "Installing plugin: $plugin"
        java -jar /tmp/jenkins-cli.jar -s http://localhost:$HTTP_PORT -auth admin:"$admin_password" install-plugin "$plugin"
    done
    
    log_info "Restarting Jenkins to apply plugin changes..."
    java -jar /tmp/jenkins-cli.jar -s http://localhost:$HTTP_PORT -auth admin:"$admin_password" safe-restart
    
    log_success "Jenkins plugins installed"
}

# Start Jenkins service
start_jenkins() {
    if [ "$START_JENKINS" = false ]; then
        log_info "Skipping Jenkins start as requested"
        return 0
    fi
    
    print_section "Starting Jenkins service"
    
    log_info "Starting Jenkins service..."
    systemctl start jenkins
    
    # Check if Jenkins started
    if systemctl is-active --quiet jenkins; then
        log_success "Jenkins service started successfully"
        
        # Get initial admin password
        if [ -f "$JENKINS_HOME/secrets/initialAdminPassword" ]; then
            local password=$(cat "$JENKINS_HOME/secrets/initialAdminPassword")
            log_info "Jenkins initial admin password: $password"
        else
            log_info "Jenkins initial admin password not found. It may take a moment to generate."
            log_info "You can find it later at: $JENKINS_HOME/secrets/initialAdminPassword"
        fi
        
        # Display access information
        log_info "Jenkins is now accessible at: http://localhost:$HTTP_PORT"
        if [ "$USE_SSL" = true ]; then
            log_info "Jenkins is also accessible via HTTPS at: https://localhost"
        fi
    else
        log_error "Failed to start Jenkins service"
        log_info "Check the service status with: systemctl status jenkins"
        return 1
    fi
}

# Main function
main() {
    print_header "Jenkins Installation Script"
    
    # Check if running as root
    check_root
    
    # Detect Linux distribution
    detect_distribution
    
    # Check prerequisites
    check_prerequisites
    
    # Check for Java
    check_java
    
    # Check for existing Jenkins installation
    check_existing_jenkins
    
    # Backup existing Jenkins installation if requested
    backup_jenkins
    
    # Install Jenkins
    install_jenkins_pkg
    
    # Configure Jenkins
    configure_jenkins
    
    # Start Jenkins
    start_jenkins
    
    # Install plugins if specified
    if [ -n "$PLUGINS_LIST" ]; then
        install_plugins
    fi
    
    print_header "Jenkins Installation Complete"
    log_success "Jenkins has been successfully installed and configured"
    
    # Display access information
    local jenkins_url="http://localhost:$HTTP_PORT"
    if [ "$USE_SSL" = true ]; then
        jenkins_url="https://localhost"
    fi
    
    log_info "Jenkins URL: $jenkins_url"
    log_info "Jenkins home directory: $JENKINS_HOME"
    
    if [ "$SKIP_WIZARD" = false ]; then
        log_info "Complete the setup wizard in your browser to finish the installation."
    else
        log_info "Setup wizard was skipped. Jenkins is ready to use."
    fi
}

# Run the main function
main