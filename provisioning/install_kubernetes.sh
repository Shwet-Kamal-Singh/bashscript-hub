#!/bin/bash
#
# Script Name: install_kubernetes.sh
# Description: Install and configure Kubernetes (K8s) cluster across Linux distributions
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./install_kubernetes.sh [options]
#
# Options:
#   -v, --version <version>      Specify Kubernetes version (default: latest)
#   -r, --role <role>            Node role: master|worker|single (default: single)
#   -i, --ip <ip_address>        API server advertise address (default: auto-detect)
#   -p, --pod-network <cidr>     Pod network CIDR (default: 10.244.0.0/16)
#   -n, --cni <provider>         CNI provider: flannel|calico|weave (default: flannel)
#   -t, --token <token>          Join token for worker nodes
#   -a, --api-server <address>   API server address for worker nodes
#   -c, --cert-key <key>         Certificate key for control plane join
#   -s, --service-cidr <cidr>    Service CIDR (default: 10.96.0.0/12)
#   -d, --dns-domain <domain>    DNS domain (default: cluster.local)
#   -N, --node-name <name>       Set node name (default: hostname)
#   -I, --ingress <type>         Install Ingress controller: nginx|traefik|none (default: none)
#   -m, --metallb                Install MetalLB load balancer
#   -l, --metallb-range <range>  MetalLB IP range (e.g., 192.168.1.240-192.168.1.250)
#   -S, --storage <type>         Install storage: local-path|longhorn|none (default: none)
#   -R, --runtime <runtime>      Container runtime: containerd|docker|crio (default: containerd)
#   -H, --helm                   Install Helm package manager
#   -D, --dashboard              Install Kubernetes Dashboard
#   -P, --prometheus             Install Prometheus monitoring stack
#   -f, --force                  Force reinstallation if already installed
#   -k, --kubeconfig <path>      Kubeconfig file path (default: /etc/kubernetes/admin.conf)
#   -A, --all-in-one             Install all components (Ingress, MetalLB, Storage, Helm, Dashboard)
#   -w, --wait                   Wait for cluster to be ready before proceeding
#   -y, --yes                    Answer yes to all prompts
#   -h, --help                   Display this help message
#
# Examples:
#   ./install_kubernetes.sh
#   ./install_kubernetes.sh -r master -i 192.168.1.10 -n calico
#   ./install_kubernetes.sh -r worker -t <token> -a <api_server>
#   ./install_kubernetes.sh -A -v 1.26.0 -w
#
# Requirements:
#   - Root privileges (or sudo)
#   - Internet connection
#   - Linux with systemd
#   - At least 2 CPUs and 2GB RAM
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
K8S_VERSION="latest"
NODE_ROLE="single"
API_SERVER_IP=""
POD_NETWORK_CIDR="10.244.0.0/16"
CNI_PROVIDER="flannel"
JOIN_TOKEN=""
API_SERVER_ADDRESS=""
CERTIFICATE_KEY=""
SERVICE_CIDR="10.96.0.0/12"
DNS_DOMAIN="cluster.local"
NODE_NAME=""
INGRESS_TYPE="none"
INSTALL_METALLB=false
METALLB_RANGE=""
STORAGE_TYPE="none"
CONTAINER_RUNTIME="containerd"
INSTALL_HELM=false
INSTALL_DASHBOARD=false
INSTALL_PROMETHEUS=false
FORCE_INSTALL=false
KUBECONFIG_PATH="/etc/kubernetes/admin.conf"
ALL_IN_ONE=false
WAIT_READY=false
ASSUME_YES=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            K8S_VERSION="$2"
            shift 2
            ;;
        -r|--role)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "master" && "$2" != "worker" && "$2" != "single" ]]; then
                log_error "Invalid role: $2"
                log_error "Valid options: master, worker, single"
                exit 1
            fi
            NODE_ROLE="$2"
            shift 2
            ;;
        -i|--ip)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            API_SERVER_IP="$2"
            shift 2
            ;;
        -p|--pod-network)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            POD_NETWORK_CIDR="$2"
            shift 2
            ;;
        -n|--cni)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "flannel" && "$2" != "calico" && "$2" != "weave" ]]; then
                log_error "Invalid CNI provider: $2"
                log_error "Valid options: flannel, calico, weave"
                exit 1
            fi
            CNI_PROVIDER="$2"
            shift 2
            ;;
        -t|--token)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            JOIN_TOKEN="$2"
            shift 2
            ;;
        -a|--api-server)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            API_SERVER_ADDRESS="$2"
            shift 2
            ;;
        -c|--cert-key)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            CERTIFICATE_KEY="$2"
            shift 2
            ;;
        -s|--service-cidr)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            SERVICE_CIDR="$2"
            shift 2
            ;;
        -d|--dns-domain)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            DNS_DOMAIN="$2"
            shift 2
            ;;
        -N|--node-name)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            NODE_NAME="$2"
            shift 2
            ;;
        -I|--ingress)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "nginx" && "$2" != "traefik" && "$2" != "none" ]]; then
                log_error "Invalid ingress type: $2"
                log_error "Valid options: nginx, traefik, none"
                exit 1
            fi
            INGRESS_TYPE="$2"
            shift 2
            ;;
        -m|--metallb)
            INSTALL_METALLB=true
            shift
            ;;
        -l|--metallb-range)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            METALLB_RANGE="$2"
            INSTALL_METALLB=true
            shift 2
            ;;
        -S|--storage)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "local-path" && "$2" != "longhorn" && "$2" != "none" ]]; then
                log_error "Invalid storage type: $2"
                log_error "Valid options: local-path, longhorn, none"
                exit 1
            fi
            STORAGE_TYPE="$2"
            shift 2
            ;;
        -R|--runtime)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "containerd" && "$2" != "docker" && "$2" != "crio" ]]; then
                log_error "Invalid container runtime: $2"
                log_error "Valid options: containerd, docker, crio"
                exit 1
            fi
            CONTAINER_RUNTIME="$2"
            shift 2
            ;;
        -H|--helm)
            INSTALL_HELM=true
            shift
            ;;
        -D|--dashboard)
            INSTALL_DASHBOARD=true
            shift
            ;;
        -P|--prometheus)
            INSTALL_PROMETHEUS=true
            shift
            ;;
        -f|--force)
            FORCE_INSTALL=true
            shift
            ;;
        -k|--kubeconfig)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            KUBECONFIG_PATH="$2"
            shift 2
            ;;
        -A|--all-in-one)
            ALL_IN_ONE=true
            INGRESS_TYPE="nginx"
            INSTALL_METALLB=true
            STORAGE_TYPE="local-path"
            INSTALL_HELM=true
            INSTALL_DASHBOARD=true
            shift
            ;;
        -w|--wait)
            WAIT_READY=true
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

# Check system requirements
check_system_requirements() {
    print_section "Checking System Requirements"
    
    # Check CPU cores
    CPU_CORES=$(grep -c "^processor" /proc/cpuinfo)
    if [ "$CPU_CORES" -lt 2 ]; then
        log_warning "Kubernetes requires at least 2 CPU cores, but only $CPU_CORES were detected"
        if [ "$ASSUME_YES" != true ]; then
            read -p "Continue anyway? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Aborting installation due to insufficient resources"
                exit 1
            fi
        fi
    else
        log_success "CPU requirement met: $CPU_CORES cores detected"
    fi
    
    # Check memory
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
    if [ "$TOTAL_MEM_MB" -lt 2048 ]; then
        log_warning "Kubernetes requires at least 2GB of RAM, but only $TOTAL_MEM_MB MB were detected"
        if [ "$ASSUME_YES" != true ]; then
            read -p "Continue anyway? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Aborting installation due to insufficient resources"
                exit 1
            fi
        fi
    else
        log_success "Memory requirement met: $TOTAL_MEM_MB MB detected"
    fi
    
    # Check if systemd is used
    if ! command -v systemctl &>/dev/null; then
        log_error "Systemd is required for Kubernetes"
        exit 1
    else
        log_success "Systemd detected"
    fi
    
    # Check if kubelet or kubeadm is already installed
    if command -v kubelet &>/dev/null || command -v kubeadm &>/dev/null; then
        log_warning "Kubernetes components are already installed"
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
}

# Detect primary IP address if not specified
detect_primary_ip() {
    if [ -z "$API_SERVER_IP" ]; then
        # Try to get the primary IP address
        if command -v ip &>/dev/null; then
            # Find the default route interface
            DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
            if [ -n "$DEFAULT_IFACE" ]; then
                # Get the IP of the default interface
                API_SERVER_IP=$(ip -4 addr show "$DEFAULT_IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
            fi
        fi
        
        # Fallback methods if the above didn't work
        if [ -z "$API_SERVER_IP" ]; then
            if command -v hostname &>/dev/null; then
                API_SERVER_IP=$(hostname -I | awk '{print $1}')
            elif command -v ifconfig &>/dev/null; then
                API_SERVER_IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)
            fi
        fi
        
        if [ -z "$API_SERVER_IP" ]; then
            log_error "Could not detect the server IP address automatically"
            log_error "Please provide the API server IP with the --ip option"
            exit 1
        fi
    fi
    
    log_info "Using API server IP: $API_SERVER_IP"
}

# Set up system prerequisites
setup_prerequisites() {
    print_section "Setting up System Prerequisites"
    
    # Disable swap
    log_info "Disabling swap..."
    swapoff -a
    
    # Permanently disable swap in /etc/fstab
    sed -i '/swap/s/^\(.*\)$/#\1/g' /etc/fstab
    
    # Load required kernel modules
    log_info "Loading kernel modules..."
    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
    
    modprobe overlay
    modprobe br_netfilter
    
    # Set up required sysctl parameters
    log_info "Setting up kernel parameters..."
    cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    
    sysctl --system
    
    # Install dependencies based on the distribution
    log_info "Installing dependencies..."
    
    case "$DISTRO_FAMILY" in
        "debian")
            apt-get update
            apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            ;;
        "redhat")
            if [ "$DISTRO" = "fedora" ]; then
                dnf install -y ca-certificates curl
            else
                yum install -y ca-certificates curl
            fi
            ;;
        "suse")
            zypper install -y ca-certificates curl
            ;;
        "arch")
            pacman -Sy --noconfirm ca-certificates curl
            ;;
        *)
            log_error "Unsupported distribution: $DISTRO_FAMILY"
            exit 1
            ;;
    esac
    
    log_success "System prerequisites set up successfully"
}

# Install container runtime
install_container_runtime() {
    print_section "Installing Container Runtime: $CONTAINER_RUNTIME"
    
    case "$CONTAINER_RUNTIME" in
        "containerd")
            install_containerd
            ;;
        "docker")
            install_docker
            ;;
        "crio")
            install_crio
            ;;
        *)
            log_error "Unsupported container runtime: $CONTAINER_RUNTIME"
            exit 1
            ;;
    esac
}

# Install containerd
install_containerd() {
    log_info "Installing containerd..."
    
    case "$DISTRO_FAMILY" in
        "debian")
            # Install containerd from Docker's repository
            curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$DISTRO $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
            apt-get install -y containerd.io
            ;;
        "redhat")
            if [ "$DISTRO" = "fedora" ]; then
                dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                dnf install -y containerd.io
            else
                yum install -y yum-utils
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                yum install -y containerd.io
            fi
            ;;
        "suse")
            # Add Docker's official repository
            zypper addrepo https://download.docker.com/linux/sles/docker-ce.repo
            zypper refresh
            zypper install -y containerd.io
            ;;
        "arch")
            pacman -Sy --noconfirm containerd
            ;;
        *)
            log_error "Unsupported distribution for containerd: $DISTRO_FAMILY"
            exit 1
            ;;
    esac
    
    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml > /dev/null
    
    # Set SystemdCgroup = true for containerd
    sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
    
    # Restart containerd
    systemctl restart containerd
    systemctl enable containerd
    
    log_success "Containerd installed and configured"
}

# Install Docker
install_docker() {
    log_info "Installing Docker..."
    
    case "$DISTRO_FAMILY" in
        "debian")
            # Add Docker's official GPG key
            curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$DISTRO $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        "redhat")
            if [ "$DISTRO" = "fedora" ]; then
                dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                dnf install -y docker-ce docker-ce-cli containerd.io
            else
                yum install -y yum-utils
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                yum install -y docker-ce docker-ce-cli containerd.io
            fi
            ;;
        "suse")
            # Add Docker's official repository
            zypper addrepo https://download.docker.com/linux/sles/docker-ce.repo
            zypper refresh
            zypper install -y docker-ce docker-ce-cli containerd.io
            ;;
        "arch")
            pacman -Sy --noconfirm docker
            ;;
        *)
            log_error "Unsupported distribution for Docker: $DISTRO_FAMILY"
            exit 1
            ;;
    esac
    
    # Configure Docker for Kubernetes
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    log_success "Docker installed and configured"
}

# Install CRI-O
install_crio() {
    log_info "Installing CRI-O..."
    
    # Set CRI-O version based on Kubernetes version
    local VERSION_SELECTOR="stable"
    if [ "$K8S_VERSION" != "latest" ]; then
        local MAJOR_VERSION
        local MINOR_VERSION
        MAJOR_VERSION=$(echo "$K8S_VERSION" | cut -d. -f1)
        MINOR_VERSION=$(echo "$K8S_VERSION" | cut -d. -f2)
        VERSION_SELECTOR="$MAJOR_VERSION.$MINOR_VERSION"
    fi
    
    case "$DISTRO_FAMILY" in
        "debian")
            # Add CRI-O repository
            echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$DISTRO/ /" | tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list > /dev/null
            echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION_SELECTOR/$DISTRO/ /" | tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION_SELECTOR.list > /dev/null
            
            mkdir -p /usr/share/keyrings
            curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$DISTRO/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-archive-keyring.gpg
            curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION_SELECTOR/$DISTRO/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-crio-archive-keyring.gpg
            
            apt-get update
            apt-get install -y cri-o cri-o-runc
            ;;
        "redhat")
            # Add CRI-O repositories
            curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_8/devel:kubic:libcontainers:stable.repo
            curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$VERSION_SELECTOR.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION_SELECTOR/CentOS_8/devel:kubic:libcontainers:stable:cri-o:$VERSION_SELECTOR.repo
            
            if [ "$DISTRO" = "fedora" ]; then
                dnf install -y cri-o
            else
                yum install -y cri-o
            fi
            ;;
        "suse")
            # Add CRI-O repositories
            zypper ar -f https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/openSUSE_Leap_15.2/devel:kubic:libcontainers:stable.repo
            zypper ar -f https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION_SELECTOR/openSUSE_Leap_15.2/devel:kubic:libcontainers:stable:cri-o:$VERSION_SELECTOR.repo
            zypper refresh
            zypper install -y cri-o
            ;;
        "arch")
            # CRI-O can be installed from AUR
            log_warning "CRI-O installation on Arch Linux requires manual intervention"
            log_info "Please install CRI-O manually from AUR"
            log_info "Falling back to containerd"
            install_containerd
            return
            ;;
        *)
            log_error "Unsupported distribution for CRI-O: $DISTRO_FAMILY"
            exit 1
            ;;
    esac
    
    # Start and enable CRI-O
    systemctl start crio
    systemctl enable crio
    
    log_success "CRI-O installed and configured"
}

# Install Kubernetes components
install_kubernetes() {
    print_section "Installing Kubernetes Components"
    
    # Determine version parameter
    local VERSION_PARAM=""
    if [ "$K8S_VERSION" != "latest" ]; then
        VERSION_PARAM="-$(echo "$K8S_VERSION" | cut -d. -f1,2)"
    fi
    
    case "$DISTRO_FAMILY" in
        "debian")
            # Add Kubernetes repository key
            curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
            
            # Add Kubernetes repository
            echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
            
            # Install Kubernetes components
            apt-get update
            if [ "$K8S_VERSION" = "latest" ]; then
                apt-get install -y kubelet kubeadm kubectl
            else
                apt-get install -y kubelet=$K8S_VERSION-* kubeadm=$K8S_VERSION-* kubectl=$K8S_VERSION-*
                apt-mark hold kubelet kubeadm kubectl
            fi
            ;;
        "redhat")
            # Add Kubernetes repository
            cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOF
            
            # Install Kubernetes components
            if [ "$DISTRO" = "fedora" ]; then
                dnf install -y kubelet$VERSION_PARAM kubeadm$VERSION_PARAM kubectl$VERSION_PARAM
                
                if [ "$K8S_VERSION" != "latest" ]; then
                    dnf versionlock add kubelet kubeadm kubectl
                fi
            else
                yum install -y kubelet$VERSION_PARAM kubeadm$VERSION_PARAM kubectl$VERSION_PARAM
                
                if [ "$K8S_VERSION" != "latest" ]; then
                    yum versionlock add kubelet kubeadm kubectl
                fi
            fi
            ;;
        "suse")
            # Add Kubernetes repository
            zypper ar -f https://pkgs.k8s.io/core:/stable:/v1.28/rpm/ kubernetes
            zypper refresh
            
            # Install Kubernetes components
            zypper install -y kubelet$VERSION_PARAM kubeadm$VERSION_PARAM kubectl$VERSION_PARAM
            ;;
        "arch")
            # Kubernetes can be installed from community repository
            pacman -Sy --noconfirm kubectl kubeadm kubelet
            ;;
        *)
            log_error "Unsupported distribution for Kubernetes: $DISTRO_FAMILY"
            exit 1
            ;;
    esac
    
    # Enable kubelet service
    systemctl enable kubelet
    
    log_success "Kubernetes components installed"
}

# Initialize Kubernetes cluster
initialize_kubernetes() {
    print_section "Initializing Kubernetes Cluster"
    
    # Set node name if provided
    local node_name_arg=""
    if [ -n "$NODE_NAME" ]; then
        node_name_arg="--node-name=$NODE_NAME"
    fi
    
    # Prepare kubeadm init parameters
    local init_params="--apiserver-advertise-address=$API_SERVER_IP --pod-network-cidr=$POD_NETWORK_CIDR --service-cidr=$SERVICE_CIDR --kubernetes-version=$K8S_VERSION $node_name_arg"
    
    # Add DNS domain if not default
    if [ "$DNS_DOMAIN" != "cluster.local" ]; then
        init_params="$init_params --service-dns-domain=$DNS_DOMAIN"
    fi
    
    if [ "$NODE_ROLE" = "master" ] || [ "$NODE_ROLE" = "single" ]; then
        # Initialize control plane
        log_info "Initializing Kubernetes control plane..."
        log_info "Running: kubeadm init $init_params"
        
        kubeadm init $init_params
        
        # Check if initialization was successful
        if [ $? -ne 0 ]; then
            log_error "Failed to initialize Kubernetes control plane"
            exit 1
        fi
        
        # Set up kubeconfig for the root user
        log_info "Setting up kubeconfig for root user..."
        mkdir -p /root/.kube
        cp -i /etc/kubernetes/admin.conf /root/.kube/config
        chown $(id -u):$(id -g) /root/.kube/config
        
        # Create kubeconfig directory for non-root user if running as sudo
        if [ -n "$SUDO_USER" ]; then
            log_info "Setting up kubeconfig for $SUDO_USER..."
            mkdir -p /home/$SUDO_USER/.kube
            cp -i /etc/kubernetes/admin.conf /home/$SUDO_USER/.kube/config
            chown -R $SUDO_USER:$(id -g -n $SUDO_USER) /home/$SUDO_USER/.kube
        fi
        
        # Set KUBECONFIG environment variable
        export KUBECONFIG=/etc/kubernetes/admin.conf
        
        # Allow scheduling pods on the master node for single-node cluster
        if [ "$NODE_ROLE" = "single" ]; then
            log_info "Untainting control-plane node to allow scheduling regular pods..."
            kubectl taint nodes --all node-role.kubernetes.io/control-plane-
            kubectl taint nodes --all node-role.kubernetes.io/master- 2>/dev/null || true
        fi
        
        # Generate join command for worker nodes
        log_info "Generating join command for worker nodes..."
        kubeadm token create --print-join-command > /tmp/kubeadm_join_cmd.sh
        chmod +x /tmp/kubeadm_join_cmd.sh
        
        # Extract join token and certificate key for control plane joins
        JOIN_TOKEN=$(kubeadm token list | awk 'NR==2{print $1}')
        CERTIFICATE_KEY=$(kubeadm init phase upload-certs --upload-certs | tail -n 1)
        API_SERVER_ADDRESS="$API_SERVER_IP:6443"
        
        log_info "Join token: $JOIN_TOKEN"
        log_info "Certificate key: $CERTIFICATE_KEY"
        log_info "API server address: $API_SERVER_ADDRESS"
        
        log_success "Kubernetes control plane initialized successfully"
    elif [ "$NODE_ROLE" = "worker" ]; then
        # Check if required parameters for worker node are provided
        if [ -z "$JOIN_TOKEN" ] || [ -z "$API_SERVER_ADDRESS" ]; then
            log_error "Missing required parameters for worker node"
            log_error "Please provide --token and --api-server options"
            exit 1
        fi
        
        # Join worker node to the cluster
        log_info "Joining worker node to the cluster..."
        kubeadm join "$API_SERVER_ADDRESS" --token "$JOIN_TOKEN" --discovery-token-unsafe-skip-ca-verification $node_name_arg
        
        if [ $? -ne 0 ]; then
            log_error "Failed to join worker node to the cluster"
            exit 1
        fi
        
        log_success "Worker node joined the cluster successfully"
    fi
}

# Install CNI network plugin
install_cni() {
    print_section "Installing CNI Network Plugin: $CNI_PROVIDER"
    
    # Skip if not master or single node
    if [ "$NODE_ROLE" != "master" ] && [ "$NODE_ROLE" != "single" ]; then
        log_info "Skipping CNI installation on worker node"
        return
    fi
    
    # Install the selected CNI plugin
    case "$CNI_PROVIDER" in
        "flannel")
            log_info "Installing Flannel CNI..."
            kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
            ;;
        "calico")
            log_info "Installing Calico CNI..."
            kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/tigera-operator.yaml
            kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/custom-resources.yaml
            ;;
        "weave")
            log_info "Installing Weave Net CNI..."
            kubectl apply -f "https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s-1.11.yaml"
            ;;
        *)
            log_error "Unsupported CNI provider: $CNI_PROVIDER"
            exit 1
            ;;
    esac
    
    log_success "CNI plugin installed successfully"
}

# Wait for the cluster to be ready
wait_for_cluster_ready() {
    if [ "$WAIT_READY" = false ]; then
        return
    fi
    
    print_section "Waiting for Cluster Readiness"
    
    # Skip if worker node
    if [ "$NODE_ROLE" = "worker" ]; then
        log_info "Skipping wait on worker node"
        return
    fi
    
    # Wait for nodes to be ready
    log_info "Waiting for nodes to be ready..."
    local timeout=120
    local interval=5
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if kubectl get nodes | grep -v "NotReady" | grep -q "Ready"; then
            log_success "Node(s) are ready"
            break
        fi
        log_info "Waiting for nodes to be ready... ($elapsed/$timeout seconds)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    if [ $elapsed -ge $timeout ]; then
        log_warning "Timeout waiting for nodes to be ready"
    fi
    
    # Wait for all pods to be running
    log_info "Waiting for all pods to be running..."
    elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if ! kubectl get pods --all-namespaces | grep -v "Running" | grep -v "Completed" | grep -q "ContainerCreating\\|Pending\\|Error\\|CrashLoopBackOff\\|Terminating"; then
            log_success "All pods are running or completed"
            break
        fi
        log_info "Waiting for all pods to be running... ($elapsed/$timeout seconds)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    if [ $elapsed -ge $timeout ]; then
        log_warning "Timeout waiting for all pods to be running"
    fi
}

# Install Helm package manager
install_helm() {
    if [ "$INSTALL_HELM" = false ]; then
        return
    fi
    
    # Skip if worker node
    if [ "$NODE_ROLE" = "worker" ]; then
        log_info "Skipping Helm installation on worker node"
        return
    fi
    
    print_section "Installing Helm Package Manager"
    
    # Download and install Helm
    log_info "Downloading and installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod +x get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
    
    # Add stable repository
    log_info "Adding Helm stable repository..."
    helm repo add stable https://charts.helm.sh/stable
    helm repo update
    
    log_success "Helm installed successfully"
}

# Install Ingress controller
install_ingress() {
    if [ "$INGRESS_TYPE" = "none" ]; then
        return
    fi
    
    # Skip if worker node
    if [ "$NODE_ROLE" = "worker" ]; then
        log_info "Skipping Ingress installation on worker node"
        return
    fi
    
    print_section "Installing Ingress Controller: $INGRESS_TYPE"
    
    # Wait for cluster to be ready
    wait_for_cluster_ready
    
    # Install the selected Ingress controller
    case "$INGRESS_TYPE" in
        "nginx")
            log_info "Installing NGINX Ingress Controller..."
            if [ "$INSTALL_HELM" = true ]; then
                helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
                helm repo update
                helm install nginx-ingress ingress-nginx/ingress-nginx
            else
                kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
            fi
            ;;
        "traefik")
            log_info "Installing Traefik Ingress Controller..."
            if [ "$INSTALL_HELM" = true ]; then
                helm repo add traefik https://helm.traefik.io/traefik
                helm repo update
                helm install traefik traefik/traefik
            else
                kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v2.10.3/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
                kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v2.10.3/docs/content/reference/dynamic-configuration/kubernetes-crd-rbac.yml
            fi
            ;;
        *)
            log_error "Unsupported Ingress controller: $INGRESS_TYPE"
            exit 1
            ;;
    esac
    
    log_success "Ingress controller installed successfully"
}

# Install MetalLB load balancer
install_metallb() {
    if [ "$INSTALL_METALLB" = false ]; then
        return
    fi
    
    # Skip if worker node
    if [ "$NODE_ROLE" = "worker" ]; then
        log_info "Skipping MetalLB installation on worker node"
        return
    fi
    
    print_section "Installing MetalLB Load Balancer"
    
    # Check if MetalLB address range is provided
    if [ -z "$METALLB_RANGE" ] && [ "$ASSUME_YES" != true ]; then
        log_warning "No IP address range specified for MetalLB"
        read -p "Please enter IP address range (e.g., 192.168.1.240-192.168.1.250): " METALLB_RANGE
        
        if [ -z "$METALLB_RANGE" ]; then
            log_error "IP address range is required for MetalLB"
            exit 1
        fi
    elif [ -z "$METALLB_RANGE" ]; then
        log_error "IP address range is required for MetalLB with --yes option"
        exit 1
    fi
    
    # Wait for cluster to be ready
    wait_for_cluster_ready
    
    # Install MetalLB
    log_info "Installing MetalLB..."
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml
    
    # Wait for MetalLB to be ready
    log_info "Waiting for MetalLB to be ready..."
    sleep 30
    
    # Configure MetalLB address pool
    log_info "Configuring MetalLB address pool..."
    cat > /tmp/metallb-config.yaml << EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - $METALLB_RANGE
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default
EOF
    
    kubectl apply -f /tmp/metallb-config.yaml
    rm /tmp/metallb-config.yaml
    
    log_success "MetalLB installed and configured successfully"
}

# Install storage solution
install_storage() {
    if [ "$STORAGE_TYPE" = "none" ]; then
        return
    fi
    
    # Skip if worker node
    if [ "$NODE_ROLE" = "worker" ]; then
        log_info "Skipping storage installation on worker node"
        return
    fi
    
    print_section "Installing Storage Solution: $STORAGE_TYPE"
    
    # Wait for cluster to be ready
    wait_for_cluster_ready
    
    # Install the selected storage solution
    case "$STORAGE_TYPE" in
        "local-path")
            log_info "Installing Rancher Local Path Provisioner..."
            kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.23/deploy/local-path-storage.yaml
            kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
            ;;
        "longhorn")
            log_info "Installing Longhorn..."
            if [ "$INSTALL_HELM" = true ]; then
                helm repo add longhorn https://charts.longhorn.io
                helm repo update
                helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace
            else
                kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.4.1/deploy/longhorn.yaml
            fi
            kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
            ;;
        *)
            log_error "Unsupported storage type: $STORAGE_TYPE"
            exit 1
            ;;
    esac
    
    log_success "Storage solution installed successfully"
}

# Install Kubernetes Dashboard
install_dashboard() {
    if [ "$INSTALL_DASHBOARD" = false ]; then
        return
    fi
    
    # Skip if worker node
    if [ "$NODE_ROLE" = "worker" ]; then
        log_info "Skipping Dashboard installation on worker node"
        return
    fi
    
    print_section "Installing Kubernetes Dashboard"
    
    # Wait for cluster to be ready
    wait_for_cluster_ready
    
    # Install Dashboard
    log_info "Installing Kubernetes Dashboard..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
    
    # Create admin service account
    log_info "Creating admin service account for Dashboard..."
    cat > /tmp/dashboard-admin.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF
    
    kubectl apply -f /tmp/dashboard-admin.yaml
    rm /tmp/dashboard-admin.yaml
    
    # Get access token
    log_info "Generating access token for Dashboard..."
    sleep 5
    SECRET_NAME=$(kubectl -n kubernetes-dashboard get serviceaccount/admin-user -o jsonpath='{.secrets[0].name}')
    if [ -z "$SECRET_NAME" ]; then
        # For newer Kubernetes versions
        kubectl -n kubernetes-dashboard create token admin-user > /tmp/dashboard-token.txt
    else
        # For older Kubernetes versions
        kubectl -n kubernetes-dashboard get secret $SECRET_NAME -o jsonpath='{.data.token}' | base64 --decode > /tmp/dashboard-token.txt
    fi
    
    log_info "Dashboard token saved to /tmp/dashboard-token.txt"
    log_info "Access Dashboard at: https://<your-server-ip>:30000"
    
    # Create NodePort service to expose Dashboard
    log_info "Creating NodePort service for Dashboard..."
    cat > /tmp/dashboard-nodeport.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-dashboard-nodeport
  namespace: kubernetes-dashboard
spec:
  ports:
  - port: 443
    targetPort: 8443
    nodePort: 30000
  selector:
    k8s-app: kubernetes-dashboard
  type: NodePort
EOF
    
    kubectl apply -f /tmp/dashboard-nodeport.yaml
    rm /tmp/dashboard-nodeport.yaml
    
    log_success "Kubernetes Dashboard installed successfully"
}

# Install Prometheus monitoring stack
install_prometheus() {
    if [ "$INSTALL_PROMETHEUS" = false ]; then
        return
    fi
    
    # Skip if worker node
    if [ "$NODE_ROLE" = "worker" ]; then
        log_info "Skipping Prometheus installation on worker node"
        return
    fi
    
    print_section "Installing Prometheus Monitoring Stack"
    
    # Wait for cluster to be ready
    wait_for_cluster_ready
    
    # Check if Helm is installed
    if ! command -v helm &>/dev/null; then
        log_error "Helm is required for Prometheus installation"
        log_info "Please install Helm with --helm option"
        return
    fi
    
    # Add Prometheus repository
    log_info "Adding Prometheus Helm repository..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Install Prometheus stack
    log_info "Installing Prometheus stack..."
    helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
    
    # Create NodePort services to expose Prometheus and Grafana
    log_info "Creating NodePort services for Prometheus and Grafana..."
    cat > /tmp/prometheus-nodeport.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: prometheus-nodeport
  namespace: monitoring
spec:
  ports:
  - port: 9090
    targetPort: 9090
    nodePort: 30090
  selector:
    app.kubernetes.io/name: prometheus
  type: NodePort
---
apiVersion: v1
kind: Service
metadata:
  name: grafana-nodeport
  namespace: monitoring
spec:
  ports:
  - port: 80
    targetPort: 3000
    nodePort: 30300
  selector:
    app.kubernetes.io/name: grafana
  type: NodePort
EOF
    
    kubectl apply -f /tmp/prometheus-nodeport.yaml
    rm /tmp/prometheus-nodeport.yaml
    
    log_info "Prometheus available at: http://<your-server-ip>:30090"
    log_info "Grafana available at: http://<your-server-ip>:30300"
    log_info "Default Grafana credentials: admin/prom-operator"
    
    log_success "Prometheus monitoring stack installed successfully"
}

# Print cluster information
print_cluster_info() {
    if [ "$NODE_ROLE" = "worker" ]; then
        print_header "Kubernetes Worker Node Joined Successfully"
        log_info "The worker node has been successfully joined to the Kubernetes cluster."
        return
    fi
    
    print_header "Kubernetes Cluster Information"
    
    # Print node status
    log_info "Node status:"
    kubectl get nodes -o wide
    
    # Print pod status
    log_info "Pod status:"
    kubectl get pods --all-namespaces
    
    # Print service status
    log_info "Service status:"
    kubectl get services --all-namespaces
    
    # Print join command for worker nodes
    if [ -f /tmp/kubeadm_join_cmd.sh ]; then
        log_info "To join worker nodes to this cluster, run the following command on each worker node:"
        cat /tmp/kubeadm_join_cmd.sh
    fi
    
    # Print access information for additional components
    if [ "$INSTALL_DASHBOARD" = true ]; then
        log_info "Kubernetes Dashboard URL: https://<your-server-ip>:30000"
        log_info "Access token saved to: /tmp/dashboard-token.txt"
    fi
    
    if [ "$INSTALL_PROMETHEUS" = true ]; then
        log_info "Prometheus URL: http://<your-server-ip>:30090"
        log_info "Grafana URL: http://<your-server-ip>:30300"
        log_info "Default Grafana credentials: admin/prom-operator"
    fi
    
    # Print kubectl configuration
    log_info "Kubectl configuration:"
    log_info "export KUBECONFIG=$KUBECONFIG_PATH"
    
    # Print a note about scripts in /tmp
    if [ -f /tmp/kubeadm_join_cmd.sh ] || [ -f /tmp/dashboard-token.txt ]; then
        log_warning "Note: Files in /tmp will be lost on system reboot. Save them to a permanent location if needed."
    fi
}

# Main function
main() {
    print_header "Kubernetes Installation Script"
    
    # Check if running as root
    check_root
    
    # Detect Linux distribution
    detect_distribution
    
    # Check system requirements
    check_system_requirements
    
    # Detect primary IP address if not specified
    detect_primary_ip
    
    # Set up system prerequisites
    setup_prerequisites
    
    # Install container runtime
    install_container_runtime
    
    # Install Kubernetes components
    install_kubernetes
    
    # Initialize Kubernetes cluster
    initialize_kubernetes
    
    # Install CNI network plugin (for master and single node only)
    if [ "$NODE_ROLE" = "master" ] || [ "$NODE_ROLE" = "single" ]; then
        install_cni
    fi
    
    # Wait for cluster to be ready
    wait_for_cluster_ready
    
    # Install Helm package manager if requested (master and single node only)
    if [ "$INSTALL_HELM" = true ] && ([ "$NODE_ROLE" = "master" ] || [ "$NODE_ROLE" = "single" ]); then
        install_helm
    fi
    
    # Install additional components (master and single node only)
    if [ "$NODE_ROLE" = "master" ] || [ "$NODE_ROLE" = "single" ]; then
        # Install Ingress controller if requested
        if [ "$INGRESS_TYPE" != "none" ]; then
            install_ingress
        fi
        
        # Install MetalLB if requested
        if [ "$INSTALL_METALLB" = true ]; then
            install_metallb
        fi
        
        # Install storage solution if requested
        if [ "$STORAGE_TYPE" != "none" ]; then
            install_storage
        fi
        
        # Install Kubernetes Dashboard if requested
        if [ "$INSTALL_DASHBOARD" = true ]; then
            install_dashboard
        fi
        
        # Install Prometheus monitoring stack if requested
        if [ "$INSTALL_PROMETHEUS" = true ]; then
            install_prometheus
        fi
    fi
    
    # Print cluster information
    print_cluster_info
    
    print_header "Kubernetes Installation Complete"
    
    if [ "$NODE_ROLE" = "master" ] || [ "$NODE_ROLE" = "single" ]; then
        log_success "Kubernetes cluster has been successfully set up"
    else
        log_success "Worker node has been successfully joined to the cluster"
    fi
}

# Run the main function
main