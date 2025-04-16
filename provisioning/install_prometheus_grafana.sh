#!/bin/bash
#
# Script Name: install_prometheus_grafana.sh
# Description: Install and configure Prometheus monitoring system and Grafana dashboard
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./install_prometheus_grafana.sh [options]
#
# Options:
#   -p, --prometheus-port <port>  Set Prometheus port (default: 9090)
#   -g, --grafana-port <port>     Set Grafana port (default: 3000)
#   -r, --retention <days>        Data retention period in days (default: 15)
#   -s, --storage-path <path>     Storage path for Prometheus data (default: /var/lib/prometheus)
#   -n, --node-exporter           Install Node Exporter for host metrics
#   -a, --alertmanager            Install Alertmanager for alerts
#   -e, --email <email>           Email for alerts (requires --alertmanager)
#   -m, --smtp <server>           SMTP server for alerts (requires --alertmanager)
#   -u, --smtp-user <user>        SMTP username for alerts
#   -P, --smtp-pass <pass>        SMTP password for alerts
#   -d, --dashboards              Install basic Grafana dashboards
#   -x, --proxy <url>             HTTP proxy URL for installations
#   -f, --force                   Force reinstallation if already installed
#   -v, --version <version>       Specify Prometheus version (default: latest)
#   -G, --grafana-version <ver>   Specify Grafana version (default: latest)
#   -S, --systemd                 Install as systemd services (default)
#   -D, --docker                  Install using Docker containers
#   -y, --yes                     Answer yes to all prompts
#   -h, --help                    Display this help message
#
# Examples:
#   ./install_prometheus_grafana.sh
#   ./install_prometheus_grafana.sh -n -a -d
#   ./install_prometheus_grafana.sh -p 8080 -g 8081 -r 30 -S
#   ./install_prometheus_grafana.sh -D -n -a -e admin@example.com -m smtp.example.com
#
# Requirements:
#   - Root privileges (or sudo)
#   - Internet connection
#   - For Docker installation: Docker and Docker Compose
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
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
RETENTION_DAYS=15
STORAGE_PATH="/var/lib/prometheus"
INSTALL_NODE_EXPORTER=false
INSTALL_ALERTMANAGER=false
ALERT_EMAIL=""
SMTP_SERVER=""
SMTP_USER=""
SMTP_PASS=""
INSTALL_DASHBOARDS=false
PROXY_URL=""
FORCE_INSTALL=false
PROMETHEUS_VERSION="latest"
GRAFANA_VERSION="latest"
USE_SYSTEMD=true
USE_DOCKER=false
ASSUME_YES=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--prometheus-port)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ] || [ "$2" -gt 65535 ]; then
                log_error "Invalid port number: $2"
                exit 1
            fi
            PROMETHEUS_PORT="$2"
            shift 2
            ;;
        -g|--grafana-port)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ] || [ "$2" -gt 65535 ]; then
                log_error "Invalid port number: $2"
                exit 1
            fi
            GRAFANA_PORT="$2"
            shift 2
            ;;
        -r|--retention)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
                log_error "Invalid retention days: $2"
                exit 1
            fi
            RETENTION_DAYS="$2"
            shift 2
            ;;
        -s|--storage-path)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            STORAGE_PATH="$2"
            shift 2
            ;;
        -n|--node-exporter)
            INSTALL_NODE_EXPORTER=true
            shift
            ;;
        -a|--alertmanager)
            INSTALL_ALERTMANAGER=true
            shift
            ;;
        -e|--email)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            ALERT_EMAIL="$2"
            shift 2
            ;;
        -m|--smtp)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            SMTP_SERVER="$2"
            shift 2
            ;;
        -u|--smtp-user)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            SMTP_USER="$2"
            shift 2
            ;;
        -P|--smtp-pass)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            SMTP_PASS="$2"
            shift 2
            ;;
        -d|--dashboards)
            INSTALL_DASHBOARDS=true
            shift
            ;;
        -x|--proxy)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            PROXY_URL="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_INSTALL=true
            shift
            ;;
        -v|--version)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            PROMETHEUS_VERSION="$2"
            shift 2
            ;;
        -G|--grafana-version)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            GRAFANA_VERSION="$2"
            shift 2
            ;;
        -S|--systemd)
            USE_SYSTEMD=true
            USE_DOCKER=false
            shift
            ;;
        -D|--docker)
            USE_DOCKER=true
            USE_SYSTEMD=false
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

# Check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    # Check for existing installations
    if command -v prometheus &>/dev/null || command -v grafana-server &>/dev/null; then
        log_warning "Prometheus or Grafana is already installed"
        if [ "$FORCE_INSTALL" = true ]; then
            log_info "Force reinstallation enabled"
        else
            if [ "$ASSUME_YES" != true ]; then
                read -p "Do you want to proceed with reinstallation? [y/N]: " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Installation aborted by user"
                    exit 0
                fi
            fi
        fi
    fi
    
    # Check for Docker if using Docker installation
    if [ "$USE_DOCKER" = true ]; then
        if ! command -v docker &>/dev/null; then
            log_error "Docker is required for Docker installation method"
            log_info "Please install Docker first or use the systemd installation method"
            exit 1
        fi
        
        if ! command -v docker-compose &>/dev/null; then
            log_warning "Docker Compose not found, will be installed"
            install_docker_compose
        fi
    fi
    
    # Install required packages
    log_info "Installing required packages..."
    case "$DISTRO_FAMILY" in
        "debian")
            apt-get update
            apt-get install -y wget curl tar jq
            ;;
        "redhat")
            if [ "$DISTRO" = "fedora" ]; then
                dnf install -y wget curl tar jq
            else
                yum install -y wget curl tar jq
            fi
            ;;
        "suse")
            zypper install -y wget curl tar jq
            ;;
        "arch")
            pacman -Sy --noconfirm wget curl tar jq
            ;;
        *)
            log_warning "Unknown distribution, skipping package installation"
            log_warning "Make sure wget, curl, tar, and jq are installed"
            ;;
    esac
    
    # Apply proxy settings if provided
    if [ -n "$PROXY_URL" ]; then
        log_info "Setting up proxy for installations..."
        export http_proxy="$PROXY_URL"
        export https_proxy="$PROXY_URL"
        export HTTP_PROXY="$PROXY_URL"
        export HTTPS_PROXY="$PROXY_URL"
    fi
    
    log_success "Prerequisites check completed"
}

# Install Docker Compose if needed
install_docker_compose() {
    log_info "Installing Docker Compose..."
    
    # Install latest Docker Compose
    if command -v curl &>/dev/null; then
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    else
        wget -O /usr/local/bin/docker-compose "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    fi
    
    chmod +x /usr/local/bin/docker-compose
    
    # Verify installation
    if ! command -v docker-compose &>/dev/null; then
        log_error "Failed to install Docker Compose"
        exit 1
    fi
    
    log_success "Docker Compose installed successfully"
}

# Create users
create_users() {
    if [ "$USE_DOCKER" = true ]; then
        return 0
    fi
    
    print_section "Creating Users"
    
    # Create Prometheus user
    if ! id prometheus &>/dev/null; then
        log_info "Creating prometheus user..."
        useradd --no-create-home --shell /bin/false prometheus
    fi
    
    # Create Node Exporter user if needed
    if [ "$INSTALL_NODE_EXPORTER" = true ] && ! id node_exporter &>/dev/null; then
        log_info "Creating node_exporter user..."
        useradd --no-create-home --shell /bin/false node_exporter
    fi
    
    # Create Alertmanager user if needed
    if [ "$INSTALL_ALERTMANAGER" = true ] && ! id alertmanager &>/dev/null; then
        log_info "Creating alertmanager user..."
        useradd --no-create-home --shell /bin/false alertmanager
    fi
    
    # Create Grafana user
    if ! id grafana &>/dev/null; then
        log_info "Creating grafana user..."
        useradd --system --home /var/lib/grafana --shell /bin/false grafana
    fi
    
    log_success "Users created successfully"
}

# Install Prometheus with systemd service
install_prometheus_systemd() {
    print_section "Installing Prometheus (Systemd)"
    
    # Determine Prometheus version to install
    local PROMETHEUS_DL_VERSION
    if [ "$PROMETHEUS_VERSION" = "latest" ]; then
        log_info "Determining latest Prometheus version..."
        PROMETHEUS_DL_VERSION=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | jq -r .tag_name | sed 's/^v//')
    else
        PROMETHEUS_DL_VERSION="$PROMETHEUS_VERSION"
    fi
    
    log_info "Installing Prometheus version $PROMETHEUS_DL_VERSION..."
    
    # Create directories
    log_info "Creating directories..."
    mkdir -p "$STORAGE_PATH" /etc/prometheus /var/lib/prometheus
    
    # Download and extract Prometheus
    log_info "Downloading Prometheus..."
    local TEMP_DIR
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1
    
    if command -v curl &>/dev/null; then
        curl -L "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_DL_VERSION}/prometheus-${PROMETHEUS_DL_VERSION}.linux-amd64.tar.gz" -o prometheus.tar.gz
    else
        wget -O prometheus.tar.gz "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_DL_VERSION}/prometheus-${PROMETHEUS_DL_VERSION}.linux-amd64.tar.gz"
    fi
    
    # Extract, move, and set permissions
    tar xvf prometheus.tar.gz
    cd "prometheus-${PROMETHEUS_DL_VERSION}.linux-amd64" || exit 1
    
    log_info "Copying Prometheus files..."
    cp prometheus promtool /usr/local/bin/
    cp -r consoles/ console_libraries/ /etc/prometheus/
    
    # Create and configure prometheus.yml
    log_info "Creating Prometheus configuration..."
    cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Alertmanager configuration
EOF

    # Add Alertmanager configuration if needed
    if [ "$INSTALL_ALERTMANAGER" = true ]; then
        cat >> /etc/prometheus/prometheus.yml << EOF
alerting:
  alertmanagers:
  - static_configs:
    - targets:
      - localhost:9093

# Load rules once and periodically evaluate them
rule_files:
  - "/etc/prometheus/rules/*.yml"
EOF
    else
        cat >> /etc/prometheus/prometheus.yml << EOF
# Load rules once and periodically evaluate them
rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"
EOF
    fi

    # Add scrape configurations
    cat >> /etc/prometheus/prometheus.yml << EOF
# A scrape configuration containing exactly one endpoint to scrape:
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:${PROMETHEUS_PORT}']
EOF

    # Add Node Exporter if needed
    if [ "$INSTALL_NODE_EXPORTER" = true ]; then
        cat >> /etc/prometheus/prometheus.yml << EOF
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
EOF
    fi

    # Create alert rules directory if alertmanager is installed
    if [ "$INSTALL_ALERTMANAGER" = true ]; then
        mkdir -p /etc/prometheus/rules
        
        # Create example alert rules
        cat > /etc/prometheus/rules/alert.rules.yml << EOF
groups:
- name: example
  rules:
  - alert: HighCPULoad
    expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: High CPU load (instance {{ \$labels.instance }})
      description: CPU load is > 80%\n  VALUE = {{ \$value }}\n  LABELS = {{ \$labels }}

  - alert: HighMemoryLoad
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: High memory load (instance {{ \$labels.instance }})
      description: Memory load is > 80%\n  VALUE = {{ \$value }}\n  LABELS = {{ \$labels }}

  - alert: HighDiskUsage
    expr: (node_filesystem_size_bytes{fstype!="tmpfs"} - node_filesystem_free_bytes{fstype!="tmpfs"}) / node_filesystem_size_bytes{fstype!="tmpfs"} * 100 > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: High disk usage (instance {{ \$labels.instance }})
      description: Disk usage is > 80%\n  VALUE = {{ \$value }}\n  LABELS = {{ \$labels }}
EOF
    fi

    # Set permissions
    log_info "Setting permissions..."
    chown -R prometheus:prometheus /etc/prometheus "$STORAGE_PATH" /var/lib/prometheus
    chmod -R 775 /etc/prometheus "$STORAGE_PATH" /var/lib/prometheus
    
    # Create systemd service
    log_info "Creating Prometheus systemd service..."
    cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus Time Series Collection and Processing Server
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
    --config.file /etc/prometheus/prometheus.yml \\
    --storage.tsdb.path $STORAGE_PATH \\
    --storage.tsdb.retention.time=${RETENTION_DAYS}d \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries \\
    --web.listen-address=0.0.0.0:${PROMETHEUS_PORT} \\
    --web.enable-lifecycle

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd, enable and start service
    log_info "Starting Prometheus service..."
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus
    
    # Check service status
    log_info "Checking Prometheus service status..."
    if systemctl is-active --quiet prometheus; then
        log_success "Prometheus service is running"
    else
        log_error "Prometheus service failed to start"
        systemctl status prometheus
        exit 1
    fi
    
    # Clean up
    cd / || exit 1
    rm -rf "$TEMP_DIR"
    
    log_success "Prometheus installation completed"
}

# Install Node Exporter with systemd service
install_node_exporter_systemd() {
    if [ "$INSTALL_NODE_EXPORTER" != true ]; then
        return 0
    fi
    
    print_section "Installing Node Exporter (Systemd)"
    
    # Determine latest Node Exporter version
    log_info "Determining latest Node Exporter version..."
    local NODE_EXPORTER_VERSION
    NODE_EXPORTER_VERSION=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | jq -r .tag_name | sed 's/^v//')
    
    log_info "Installing Node Exporter version $NODE_EXPORTER_VERSION..."
    
    # Create temporary directory for download
    local TEMP_DIR
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1
    
    # Download and extract Node Exporter
    log_info "Downloading Node Exporter..."
    if command -v curl &>/dev/null; then
        curl -L "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" -o node_exporter.tar.gz
    else
        wget -O node_exporter.tar.gz "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    fi
    
    tar xvf node_exporter.tar.gz
    
    # Install Node Exporter binary
    log_info "Installing Node Exporter binary..."
    cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
    chown node_exporter:node_exporter /usr/local/bin/node_exporter
    
    # Create systemd service
    log_info "Creating Node Exporter systemd service..."
    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd, enable and start service
    log_info "Starting Node Exporter service..."
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter
    
    # Check service status
    log_info "Checking Node Exporter service status..."
    if systemctl is-active --quiet node_exporter; then
        log_success "Node Exporter service is running"
    else
        log_error "Node Exporter service failed to start"
        systemctl status node_exporter
        exit 1
    fi
    
    # Clean up
    cd / || exit 1
    rm -rf "$TEMP_DIR"
    
    log_success "Node Exporter installation completed"
}

# Install Alertmanager with systemd service
install_alertmanager_systemd() {
    if [ "$INSTALL_ALERTMANAGER" != true ]; then
        return 0
    fi
    
    print_section "Installing Alertmanager (Systemd)"
    
    # Determine latest Alertmanager version
    log_info "Determining latest Alertmanager version..."
    local ALERTMANAGER_VERSION
    ALERTMANAGER_VERSION=$(curl -s https://api.github.com/repos/prometheus/alertmanager/releases/latest | jq -r .tag_name | sed 's/^v//')
    
    log_info "Installing Alertmanager version $ALERTMANAGER_VERSION..."
    
    # Create directories
    log_info "Creating directories..."
    mkdir -p /etc/alertmanager /var/lib/alertmanager
    
    # Create temporary directory for download
    local TEMP_DIR
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1
    
    # Download and extract Alertmanager
    log_info "Downloading Alertmanager..."
    if command -v curl &>/dev/null; then
        curl -L "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz" -o alertmanager.tar.gz
    else
        wget -O alertmanager.tar.gz "https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
    fi
    
    tar xvf alertmanager.tar.gz
    
    # Install Alertmanager binaries
    log_info "Installing Alertmanager binary..."
    cp "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager" \
       "alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool" \
       /usr/local/bin/
    
    # Create Alertmanager configuration
    log_info "Creating Alertmanager configuration..."
    
    # Configure email notifications if specified
    if [ -n "$ALERT_EMAIL" ] && [ -n "$SMTP_SERVER" ]; then
        log_info "Setting up email notifications..."
        
        # Configure with SMTP authentication if provided
        if [ -n "$SMTP_USER" ] && [ -n "$SMTP_PASS" ]; then
            cat > /etc/alertmanager/alertmanager.yml << EOF
global:
  resolve_timeout: 5m
  smtp_from: "alertmanager@$(hostname -f)"
  smtp_smarthost: "${SMTP_SERVER}"
  smtp_auth_username: "${SMTP_USER}"
  smtp_auth_password: "${SMTP_PASS}"
  smtp_require_tls: true

route:
  group_by: ['alertname', 'job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'email-notifications'

receivers:
- name: 'email-notifications'
  email_configs:
  - to: '${ALERT_EMAIL}'
    send_resolved: true

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF
        else
            # Configure without SMTP authentication
            cat > /etc/alertmanager/alertmanager.yml << EOF
global:
  resolve_timeout: 5m
  smtp_from: "alertmanager@$(hostname -f)"
  smtp_smarthost: "${SMTP_SERVER}"

route:
  group_by: ['alertname', 'job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'email-notifications'

receivers:
- name: 'email-notifications'
  email_configs:
  - to: '${ALERT_EMAIL}'
    send_resolved: true

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF
        fi
    else
        # Default configuration without email notifications
        cat > /etc/alertmanager/alertmanager.yml << EOF
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'webhook'

receivers:
- name: 'webhook'
  webhook_configs:
  - url: 'http://localhost:9090/-/reload'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF
    fi
    
    # Set permissions
    log_info "Setting permissions..."
    chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager
    chmod -R 775 /etc/alertmanager /var/lib/alertmanager
    
    # Create systemd service
    log_info "Creating Alertmanager systemd service..."
    cat > /etc/systemd/system/alertmanager.service << EOF
[Unit]
Description=Alertmanager for Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \\
    --config.file=/etc/alertmanager/alertmanager.yml \\
    --storage.path=/var/lib/alertmanager \\
    --web.listen-address=0.0.0.0:9093

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd, enable and start service
    log_info "Starting Alertmanager service..."
    systemctl daemon-reload
    systemctl enable alertmanager
    systemctl start alertmanager
    
    # Check service status
    log_info "Checking Alertmanager service status..."
    if systemctl is-active --quiet alertmanager; then
        log_success "Alertmanager service is running"
    else
        log_error "Alertmanager service failed to start"
        systemctl status alertmanager
        exit 1
    fi
    
    # Clean up
    cd / || exit 1
    rm -rf "$TEMP_DIR"
    
    log_success "Alertmanager installation completed"
}

# Install Grafana with systemd service
install_grafana_systemd() {
    print_section "Installing Grafana (Systemd)"
    
    case "$DISTRO_FAMILY" in
        "debian")
            log_info "Installing Grafana from official repository..."
            apt-get install -y apt-transport-https software-properties-common
            
            # Add Grafana GPG key
            if command -v curl &>/dev/null; then
                curl -fsSL https://packages.grafana.com/gpg.key | gpg --dearmor -o /usr/share/keyrings/grafana-archive-keyring.gpg
            else
                wget -q -O - https://packages.grafana.com/gpg.key | gpg --dearmor -o /usr/share/keyrings/grafana-archive-keyring.gpg
            fi
            
            # Add Grafana repository
            echo "deb [signed-by=/usr/share/keyrings/grafana-archive-keyring.gpg] https://packages.grafana.com/oss/deb stable main" | tee /etc/apt/sources.list.d/grafana.list
            
            # Install Grafana
            apt-get update
            
            if [ "$GRAFANA_VERSION" = "latest" ]; then
                apt-get install -y grafana
            else
                apt-get install -y grafana=$GRAFANA_VERSION
            fi
            ;;
        "redhat")
            log_info "Installing Grafana from official repository..."
            
            # Add Grafana repository
            cat > /etc/yum.repos.d/grafana.repo << EOF
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
            
            # Install Grafana
            if [ "$DISTRO" = "fedora" ]; then
                if [ "$GRAFANA_VERSION" = "latest" ]; then
                    dnf install -y grafana
                else
                    dnf install -y grafana-$GRAFANA_VERSION
                fi
            else
                if [ "$GRAFANA_VERSION" = "latest" ]; then
                    yum install -y grafana
                else
                    yum install -y grafana-$GRAFANA_VERSION
                fi
            fi
            ;;
        "suse")
            log_info "Installing Grafana from official repository..."
            
            # Add Grafana repository
            zypper addrepo -g https://packages.grafana.com/oss/rpm grafana
            
            # Install Grafana
            if [ "$GRAFANA_VERSION" = "latest" ]; then
                zypper install -y grafana
            else
                zypper install -y grafana-$GRAFANA_VERSION
            fi
            ;;
        "arch")
            log_info "Installing Grafana from community repository..."
            pacman -Sy --noconfirm grafana
            ;;
        *)
            log_error "Unsupported distribution: $DISTRO_FAMILY"
            log_info "Installing Grafana manually from binary..."
            install_grafana_binary
            ;;
    esac
    
    # Configure Grafana
    log_info "Configuring Grafana..."
    sed -i "s/;http_port = 3000/http_port = $GRAFANA_PORT/" /etc/grafana/grafana.ini
    
    # Enable and start Grafana service
    log_info "Starting Grafana service..."
    systemctl daemon-reload
    systemctl enable grafana-server
    systemctl start grafana-server
    
    # Check service status
    log_info "Checking Grafana service status..."
    if systemctl is-active --quiet grafana-server; then
        log_success "Grafana service is running"
    else
        log_error "Grafana service failed to start"
        systemctl status grafana-server
        exit 1
    fi
    
    # Wait for Grafana to initialize
    log_info "Waiting for Grafana to initialize..."
    sleep 10
    
    # Configure Prometheus datasource in Grafana
    configure_grafana_datasource
    
    # Install dashboards if requested
    if [ "$INSTALL_DASHBOARDS" = true ]; then
        install_grafana_dashboards
    fi
    
    log_success "Grafana installation completed"
}

# Install Grafana from binary (fallback method)
install_grafana_binary() {
    log_info "Installing Grafana from binary..."
    
    # Determine Grafana version
    local GRAFANA_DL_VERSION
    if [ "$GRAFANA_VERSION" = "latest" ]; then
        GRAFANA_DL_VERSION=$(curl -s https://api.github.com/repos/grafana/grafana/releases/latest | jq -r .tag_name | sed 's/^v//')
    else
        GRAFANA_DL_VERSION="$GRAFANA_VERSION"
    fi
    
    log_info "Installing Grafana version $GRAFANA_DL_VERSION..."
    
    # Create directories
    mkdir -p /etc/grafana /var/lib/grafana /var/log/grafana
    
    # Download and extract Grafana
    local TEMP_DIR
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1
    
    if command -v curl &>/dev/null; then
        curl -L "https://dl.grafana.com/oss/release/grafana-${GRAFANA_DL_VERSION}.linux-amd64.tar.gz" -o grafana.tar.gz
    else
        wget -O grafana.tar.gz "https://dl.grafana.com/oss/release/grafana-${GRAFANA_DL_VERSION}.linux-amd64.tar.gz"
    fi
    
    tar xvf grafana.tar.gz
    
    # Copy files to appropriate locations
    cp -r "grafana-${GRAFANA_DL_VERSION}/bin" /usr/local/grafana
    cp -r "grafana-${GRAFANA_DL_VERSION}/conf" /etc/grafana/
    
    # Create configuration file
    cp /etc/grafana/conf/defaults.ini /etc/grafana/grafana.ini
    sed -i "s/;http_port = 3000/http_port = $GRAFANA_PORT/" /etc/grafana/grafana.ini
    
    # Set permissions
    chown -R grafana:grafana /etc/grafana /var/lib/grafana /var/log/grafana
    
    # Create systemd service
    cat > /etc/systemd/system/grafana-server.service << EOF
[Unit]
Description=Grafana server
Documentation=https://grafana.com/docs/
Wants=network-online.target
After=network-online.target

[Service]
User=grafana
Group=grafana
Type=simple
ExecStart=/usr/local/grafana/bin/grafana-server \
    --config=/etc/grafana/grafana.ini \
    --homepath /usr/local/grafana \
    --packaging=deb \
    cfg:server.http_port=$GRAFANA_PORT \
    cfg:server.router_logging=false \
    cfg:paths.data=/var/lib/grafana \
    cfg:paths.logs=/var/log/grafana

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd, enable and start service
    systemctl daemon-reload
    systemctl enable grafana-server
    systemctl start grafana-server
    
    # Clean up
    cd / || exit 1
    rm -rf "$TEMP_DIR"
}

# Configure Prometheus datasource in Grafana
configure_grafana_datasource() {
    log_info "Configuring Prometheus datasource in Grafana..."
    
    # Wait for Grafana API to be ready
    local max_retries=12
    local retry=0
    local grafana_url="http://localhost:${GRAFANA_PORT}"
    
    while [ $retry -lt $max_retries ]; do
        if curl -s "$grafana_url/api/health" | grep -q "ok"; then
            break
        fi
        log_info "Waiting for Grafana API to be ready... ($retry/$max_retries)"
        sleep 5
        retry=$((retry + 1))
    done
    
    if [ $retry -eq $max_retries ]; then
        log_warning "Timed out waiting for Grafana API, skipping datasource configuration"
        return
    fi
    
    # Create Prometheus datasource
    local datasource_json='{
        "name": "Prometheus",
        "type": "prometheus",
        "url": "http://localhost:'${PROMETHEUS_PORT}'",
        "access": "proxy",
        "isDefault": true
    }'
    
    curl -s -X POST -H "Content-Type: application/json" -d "$datasource_json" \
        -u admin:admin "$grafana_url/api/datasources"
    
    log_success "Prometheus datasource configured in Grafana"
}

# Install Grafana dashboards
install_grafana_dashboards() {
    log_info "Installing Grafana dashboards..."
    
    # Define dashboards to install (Grafana.com dashboard IDs)
    local dashboards=(
        "1860"  # Node Exporter Full
        "3662"  # Prometheus 2.0 Overview
        "9628"  # Prometheus Blackbox Exporter
    )
    
    local grafana_url="http://localhost:${GRAFANA_PORT}"
    
    # Create a folder for the dashboards
    local folder_json='{
        "uid": "prometheus",
        "title": "Prometheus Dashboards"
    }'
    
    local folder_response
    folder_response=$(curl -s -X POST -H "Content-Type: application/json" -d "$folder_json" \
        -u admin:admin "$grafana_url/api/folders")
    
    local folder_id
    folder_id=$(echo "$folder_response" | jq -r '.id')
    
    if [ -z "$folder_id" ] || [ "$folder_id" = "null" ]; then
        log_warning "Failed to create dashboard folder, using General folder"
        folder_id=0
    fi
    
    # Download and import each dashboard
    for dashboard_id in "${dashboards[@]}"; do
        log_info "Importing dashboard ID: $dashboard_id"
        
        # Download dashboard JSON
        local dashboard_json
        dashboard_json=$(curl -s "https://grafana.com/api/dashboards/${dashboard_id}/revisions/latest/download")
        
        # Prepare for import
        local import_json='{
            "dashboard": '$dashboard_json',
            "overwrite": true,
            "inputs": [
                {
                    "name": "DS_PROMETHEUS",
                    "type": "datasource",
                    "pluginId": "prometheus",
                    "value": "Prometheus"
                }
            ],
            "folderId": '$folder_id'
        }'
        
        # Import dashboard
        curl -s -X POST -H "Content-Type: application/json" -d "$import_json" \
            -u admin:admin "$grafana_url/api/dashboards/import"
    done
    
    log_success "Grafana dashboards installed"
}

# Install Docker-based deployment
install_docker_deployment() {
    print_section "Installing Docker Deployment"
    
    log_info "Creating Docker Compose setup..."
    
    # Create data directories
    mkdir -p "$STORAGE_PATH" /etc/prometheus /etc/alertmanager
    
    # Create Prometheus configuration
    log_info "Creating Prometheus configuration..."
    cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

EOF

    # Add Alertmanager configuration if needed
    if [ "$INSTALL_ALERTMANAGER" = true ]; then
        cat >> /etc/prometheus/prometheus.yml << EOF
alerting:
  alertmanagers:
  - static_configs:
    - targets:
      - alertmanager:9093

# Load rules once and periodically evaluate them
rule_files:
  - "/etc/prometheus/rules/*.yml"
EOF
        
        # Create alert rules directory
        mkdir -p /etc/prometheus/rules
        
        # Create example alert rules
        cat > /etc/prometheus/rules/alert.rules.yml << EOF
groups:
- name: example
  rules:
  - alert: HighCPULoad
    expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: High CPU load (instance {{ \$labels.instance }})
      description: CPU load is > 80%\n  VALUE = {{ \$value }}\n  LABELS = {{ \$labels }}

  - alert: HighMemoryLoad
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: High memory load (instance {{ \$labels.instance }})
      description: Memory load is > 80%\n  VALUE = {{ \$value }}\n  LABELS = {{ \$labels }}

  - alert: HighDiskUsage
    expr: (node_filesystem_size_bytes{fstype!="tmpfs"} - node_filesystem_free_bytes{fstype!="tmpfs"}) / node_filesystem_size_bytes{fstype!="tmpfs"} * 100 > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: High disk usage (instance {{ \$labels.instance }})
      description: Disk usage is > 80%\n  VALUE = {{ \$value }}\n  LABELS = {{ \$labels }}
EOF
    else
        cat >> /etc/prometheus/prometheus.yml << EOF
# Load rules once and periodically evaluate them
rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"
EOF
    fi

    # Add scrape configurations
    cat >> /etc/prometheus/prometheus.yml << EOF
# A scrape configuration containing exactly one endpoint to scrape:
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['prometheus:9090']
EOF

    # Add Node Exporter if needed
    if [ "$INSTALL_NODE_EXPORTER" = true ]; then
        cat >> /etc/prometheus/prometheus.yml << EOF
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['node-exporter:9100']
EOF
    fi

    # Create Alertmanager configuration if needed
    if [ "$INSTALL_ALERTMANAGER" = true ]; then
        log_info "Creating Alertmanager configuration..."
        
        # Configure email notifications if specified
        if [ -n "$ALERT_EMAIL" ] && [ -n "$SMTP_SERVER" ]; then
            log_info "Setting up email notifications..."
            
            # Configure with SMTP authentication if provided
            if [ -n "$SMTP_USER" ] && [ -n "$SMTP_PASS" ]; then
                cat > /etc/alertmanager/alertmanager.yml << EOF
global:
  resolve_timeout: 5m
  smtp_from: "alertmanager@$(hostname -f)"
  smtp_smarthost: "${SMTP_SERVER}"
  smtp_auth_username: "${SMTP_USER}"
  smtp_auth_password: "${SMTP_PASS}"
  smtp_require_tls: true

route:
  group_by: ['alertname', 'job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'email-notifications'

receivers:
- name: 'email-notifications'
  email_configs:
  - to: '${ALERT_EMAIL}'
    send_resolved: true

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF
            else
                # Configure without SMTP authentication
                cat > /etc/alertmanager/alertmanager.yml << EOF
global:
  resolve_timeout: 5m
  smtp_from: "alertmanager@$(hostname -f)"
  smtp_smarthost: "${SMTP_SERVER}"

route:
  group_by: ['alertname', 'job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'email-notifications'

receivers:
- name: 'email-notifications'
  email_configs:
  - to: '${ALERT_EMAIL}'
    send_resolved: true

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF
            fi
        else
            # Default configuration without email notifications
            cat > /etc/alertmanager/alertmanager.yml << EOF
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'webhook'

receivers:
- name: 'webhook'
  webhook_configs:
  - url: 'http://prometheus:9090/-/reload'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF
        fi
    fi

    # Create directory for Docker Compose file
    mkdir -p /opt/prometheus-stack
    
    # Create Docker Compose file
    log_info "Creating Docker Compose file..."
    cat > /opt/prometheus-stack/docker-compose.yml << EOF
version: '3'

services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - /etc/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
EOF

    # Add rules volume if alertmanager is enabled
    if [ "$INSTALL_ALERTMANAGER" = true ]; then
        cat >> /opt/prometheus-stack/docker-compose.yml << EOF
      - /etc/prometheus/rules:/etc/prometheus/rules
EOF
    fi

    # Continue with Prometheus configuration
    cat >> /opt/prometheus-stack/docker-compose.yml << EOF
      - ${STORAGE_PATH}:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=${RETENTION_DAYS}d'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--web.enable-lifecycle'
    ports:
      - ${PROMETHEUS_PORT}:9090
    restart: unless-stopped
EOF

    # Add Node Exporter if needed
    if [ "$INSTALL_NODE_EXPORTER" = true ]; then
        cat >> /opt/prometheus-stack/docker-compose.yml << EOF

  node-exporter:
    image: prom/node-exporter:latest
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    ports:
      - 9100:9100
    restart: unless-stopped
EOF
    fi

    # Add Alertmanager if needed
    if [ "$INSTALL_ALERTMANAGER" = true ]; then
        cat >> /opt/prometheus-stack/docker-compose.yml << EOF

  alertmanager:
    image: prom/alertmanager:latest
    volumes:
      - /etc/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml
    ports:
      - 9093:9093
    restart: unless-stopped
EOF
    fi

    # Add Grafana
    cat >> /opt/prometheus-stack/docker-compose.yml << EOF

  grafana:
    image: grafana/grafana:latest
    volumes:
      - grafana-storage:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    ports:
      - ${GRAFANA_PORT}:3000
    restart: unless-stopped
    depends_on:
      - prometheus
EOF

    # Add volumes
    cat >> /opt/prometheus-stack/docker-compose.yml << EOF

volumes:
  grafana-storage:
EOF

    # Create systemd service for docker-compose
    log_info "Creating systemd service for Docker Compose..."
    cat > /etc/systemd/system/prometheus-stack.service << EOF
[Unit]
Description=Prometheus Monitoring Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/prometheus-stack
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and start service
    log_info "Starting Docker services..."
    systemctl daemon-reload
    systemctl enable prometheus-stack
    systemctl start prometheus-stack
    
    # Configure Grafana datasource and dashboards
    if [ "$INSTALL_DASHBOARDS" = true ]; then
        log_info "Waiting for Grafana to initialize before installing dashboards..."
        sleep 20
        configure_grafana_datasource
        install_grafana_dashboards
    fi
    
    log_success "Docker-based deployment completed"
}

# Print installation summary
print_summary() {
    print_header "Installation Summary"
    
    # Print service status
    if [ "$USE_SYSTEMD" = true ]; then
        log_info "Prometheus Status: $(systemctl is-active prometheus)"
        log_info "Prometheus URL: http://$(hostname -I | awk '{print $1}'):${PROMETHEUS_PORT}"
        
        if [ "$INSTALL_NODE_EXPORTER" = true ]; then
            log_info "Node Exporter Status: $(systemctl is-active node_exporter)"
        fi
        
        if [ "$INSTALL_ALERTMANAGER" = true ]; then
            log_info "Alertmanager Status: $(systemctl is-active alertmanager)"
            log_info "Alertmanager URL: http://$(hostname -I | awk '{print $1}'):9093"
        fi
        
        log_info "Grafana Status: $(systemctl is-active grafana-server)"
        log_info "Grafana URL: http://$(hostname -I | awk '{print $1}'):${GRAFANA_PORT}"
        log_info "Grafana Login: admin/admin (change on first login)"
    else
        # For Docker installation
        log_info "Docker Deployment Status: $(systemctl is-active prometheus-stack)"
        log_info "Prometheus URL: http://$(hostname -I | awk '{print $1}'):${PROMETHEUS_PORT}"
        
        if [ "$INSTALL_ALERTMANAGER" = true ]; then
            log_info "Alertmanager URL: http://$(hostname -I | awk '{print $1}'):9093"
        fi
        
        log_info "Grafana URL: http://$(hostname -I | awk '{print $1}'):${GRAFANA_PORT}"
        log_info "Grafana Login: admin/admin (change on first login)"
    fi
    
    log_success "Installation completed successfully"
}

# Main function
main() {
    print_header "Prometheus & Grafana Installation Script"
    
    # Check if running as root
    check_root
    
    # Detect Linux distribution
    detect_distribution
    
    # Check prerequisites
    check_prerequisites
    
    if [ "$USE_SYSTEMD" = true ]; then
        # Create users
        create_users
        
        # Install components with systemd services
        install_prometheus_systemd
        install_node_exporter_systemd
        install_alertmanager_systemd
        install_grafana_systemd
    else
        # Install Docker-based deployment
        install_docker_deployment
    fi
    
    # Print installation summary
    print_summary
}

# Run the main function
main