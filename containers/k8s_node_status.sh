#!/bin/bash
#
# k8s_node_status.sh - Show status of Kubernetes nodes
#
# This script provides information about Kubernetes nodes, including
# status, capacity, allocatable resources, and taints.
#
# Usage:
#   ./k8s_node_status.sh [options]
#
# Options:
#   -n, --node <name>       Show details for a specific node
#   -l, --label <key=value> Filter nodes by label
#   -r, --role <role>       Filter nodes by role (master/control-plane/worker)
#   -d, --detailed          Show detailed information
#   -s, --sort <field>      Sort by field (name, status, cpu, memory)
#   -o, --output <format>   Output format (wide, json, yaml, default)
#   -w, --watch [seconds]   Watch nodes with optional refresh interval (default: 2s)
#   -c, --color             Enable colored output
#   -h, --help              Display this help message
#
# Author: BashScriptHub
# Date: 2023
# License: MIT

# Detect script directory for sourcing utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Source the color_echo utility if available
if [ -f "$ROOT_DIR/utils/color_echo.sh" ]; then
    source "$ROOT_DIR/utils/color_echo.sh"
else
    # Define minimal versions if color_echo.sh is not available
    log_info() { echo "INFO: $*"; }
    log_error() { echo "ERROR: $*" >&2; }
    log_success() { echo "SUCCESS: $*"; }
    log_warning() { echo "WARNING: $*"; }
    log_debug() { echo "DEBUG: $*"; }
fi

# Default values
NODE_NAME=""
LABEL_FILTER=""
ROLE_FILTER=""
DETAILED=false
SORT_FIELD="name"
OUTPUT_FORMAT="default"
WATCH_MODE=false
WATCH_INTERVAL=2
COLOR_OUTPUT=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Show status of Kubernetes nodes."
    echo ""
    echo "Options:"
    echo "  -n, --node <name>       Show details for a specific node"
    echo "  -l, --label <key=value> Filter nodes by label"
    echo "  -r, --role <role>       Filter nodes by role (master/control-plane/worker)"
    echo "  -d, --detailed          Show detailed information"
    echo "  -s, --sort <field>      Sort by field (name, status, cpu, memory)"
    echo "  -o, --output <format>   Output format (wide, json, yaml, default)"
    echo "  -w, --watch [seconds]   Watch nodes with optional refresh interval (default: 2s)"
    echo "  -c, --color             Enable colored output"
    echo "  -h, --help              Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")"
    echo "  $(basename "$0") -n node1 -d"
    echo "  $(basename "$0") -r master -o wide"
    echo "  $(basename "$0") -l node-role.kubernetes.io/worker= -w 5"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -n|--node)
                NODE_NAME="$2"
                shift 2
                ;;
            -l|--label)
                LABEL_FILTER="$2"
                shift 2
                ;;
            -r|--role)
                ROLE_FILTER="$2"
                case $ROLE_FILTER in
                    master|control-plane|worker)
                        # Valid roles
                        ;;
                    *)
                        log_error "Invalid role: $ROLE_FILTER"
                        log_error "Valid roles: master, control-plane, worker"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -d|--detailed)
                DETAILED=true
                shift
                ;;
            -s|--sort)
                SORT_FIELD="$2"
                case $SORT_FIELD in
                    name|status|cpu|memory)
                        # Valid sort fields
                        ;;
                    *)
                        log_error "Invalid sort field: $SORT_FIELD"
                        log_error "Valid fields: name, status, cpu, memory"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -o|--output)
                OUTPUT_FORMAT="$2"
                case $OUTPUT_FORMAT in
                    default|wide|json|yaml)
                        # Valid output formats
                        ;;
                    *)
                        log_error "Invalid output format: $OUTPUT_FORMAT"
                        log_error "Valid formats: default, wide, json, yaml"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -w|--watch)
                WATCH_MODE=true
                # Check if next argument is a number (seconds)
                if [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]]; then
                    WATCH_INTERVAL="$2"
                    shift
                fi
                shift
                ;;
            -c|--color)
                COLOR_OUTPUT=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to check if kubectl is installed and configured
check_kubectl() {
    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl is not installed or not in PATH"
        log_error "Please install kubectl:"
        log_error "  - Debian/Ubuntu: sudo apt-get install kubectl"
        log_error "  - RHEL/CentOS: sudo yum install kubectl"
        log_error "  - Fedora: sudo dnf install kubectl"
        log_error "  - Or follow: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
        exit 1
    fi
    
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        log_error "Make sure your kubeconfig is properly configured"
        log_error "Run 'kubectl cluster-info' to check cluster connectivity"
        exit 1
    fi
}

# Function to get node status
get_node_status() {
    local node_name="$1"
    local label_filter="$2"
    local role_filter="$3"
    local output_format="$4"
    local detailed="$5"
    
    local kubectl_cmd="kubectl get nodes"
    
    # Apply node name filter if specified
    if [ -n "$node_name" ]; then
        kubectl_cmd+=" $node_name"
    fi
    
    # Apply label filter if specified
    if [ -n "$label_filter" ]; then
        kubectl_cmd+=" -l $label_filter"
    fi
    
    # Apply role filter if specified
    if [ -n "$role_filter" ]; then
        if [ "$role_filter" = "master" ] || [ "$role_filter" = "control-plane" ]; then
            kubectl_cmd+=" -l node-role.kubernetes.io/control-plane="
        elif [ "$role_filter" = "worker" ]; then
            kubectl_cmd+=" -l node-role.kubernetes.io/worker="
        fi
    fi
    
    # Apply output format
    case $output_format in
        wide)
            kubectl_cmd+=" -o wide"
            ;;
        json)
            kubectl_cmd+=" -o json"
            ;;
        yaml)
            kubectl_cmd+=" -o yaml"
            ;;
        *)
            # Default format
            ;;
    esac
    
    # Execute kubectl command
    eval "$kubectl_cmd"
    
    # Show detailed information if requested and a specific node is specified
    if [ "$detailed" = true ] && [ -n "$node_name" ]; then
        echo ""
        echo "=== Detailed information for node: $node_name ==="
        echo ""
        
        # Show node description
        kubectl describe node "$node_name"
    fi
}

# Function to show node resource usage
show_node_resources() {
    local node_name="$1"
    local label_filter="$2"
    local role_filter="$3"
    
    echo "=== Node Resource Usage ==="
    echo ""
    
    local kubectl_cmd="kubectl top nodes"
    
    # Apply node name filter if specified
    if [ -n "$node_name" ]; then
        kubectl_cmd+=" $node_name"
    fi
    
    # Apply label filter if specified
    if [ -n "$label_filter" ]; then
        kubectl_cmd+=" -l $label_filter"
    fi
    
    # Apply role filter if specified
    if [ -n "$role_filter" ]; then
        if [ "$role_filter" = "master" ] || [ "$role_filter" = "control-plane" ]; then
            kubectl_cmd+=" -l node-role.kubernetes.io/control-plane="
        elif [ "$role_filter" = "worker" ]; then
            kubectl_cmd+=" -l node-role.kubernetes.io/worker="
        fi
    fi
    
    # Execute kubectl command
    eval "$kubectl_cmd"
}

# Function to get node count by status
get_node_counts() {
    local total_nodes
    local ready_nodes
    local not_ready_nodes
    
    total_nodes=$(kubectl get nodes -o name | wc -l)
    ready_nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.conditions[?(@.type=="Ready")]}{.status}{"\n"}{end}{end}' | grep -c "True")
    not_ready_nodes=$((total_nodes - ready_nodes))
    
    log_info "Node Summary:"
    log_info "  Total nodes: $total_nodes"
    log_success "  Ready: $ready_nodes"
    
    if [ "$not_ready_nodes" -gt 0 ]; then
        log_error "  Not Ready: $not_ready_nodes"
    else
        log_info "  Not Ready: $not_ready_nodes"
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    check_kubectl
    
    if [ "$WATCH_MODE" = true ]; then
        log_info "Watch mode enabled with $WATCH_INTERVAL second interval"
        log_info "Press Ctrl+C to exit"
        
        while true; do
            clear
            echo "=== Kubernetes Node Status - $(date '+%Y-%m-%d %H:%M:%S') ==="
            echo ""
            
            get_node_status "$NODE_NAME" "$LABEL_FILTER" "$ROLE_FILTER" "$OUTPUT_FORMAT" "$DETAILED"
            
            if [ "$DETAILED" = true ] && [ -z "$NODE_NAME" ]; then
                echo ""
                show_node_resources "$NODE_NAME" "$LABEL_FILTER" "$ROLE_FILTER"
            fi
            
            echo ""
            get_node_counts
            
            sleep "$WATCH_INTERVAL"
        done
    else
        echo "=== Kubernetes Node Status ==="
        echo ""
        
        get_node_status "$NODE_NAME" "$LABEL_FILTER" "$ROLE_FILTER" "$OUTPUT_FORMAT" "$DETAILED"
        
        if [ "$DETAILED" = true ] && [ -z "$NODE_NAME" ]; then
            echo ""
            show_node_resources "$NODE_NAME" "$LABEL_FILTER" "$ROLE_FILTER"
        fi
        
        echo ""
        get_node_counts
    fi
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Handle SIGINT (Ctrl+C) in watch mode
    trap 'echo -e "\nNode status monitoring stopped."; exit 0' INT
    
    main "$@"
fi
