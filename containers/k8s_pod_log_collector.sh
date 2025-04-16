#!/bin/bash
#
# k8s_pod_log_collector.sh - Collect logs from Kubernetes pods
#
# This script collects logs from Kubernetes pods, with options to filter
# by namespace, label, container, and time range. Logs can be saved to files
# or displayed in the terminal.
#
# Usage:
#   ./k8s_pod_log_collector.sh [options]
#
# Options:
#   -p, --pod <name>          Specific pod name
#   -n, --namespace <name>    Namespace (default: default)
#   -l, --label <key=value>   Filter pods by label
#   -c, --container <name>    Specific container in pod
#   -t, --tail <num>          Number of lines to show (default: all)
#   -s, --since <time>        Show logs since time (e.g. 1h, 10m, 2d)
#   -u, --until <time>        Show logs until time
#   -f, --follow              Follow logs in real-time
#   -o, --output <dir>        Output directory for log files
#   -z, --compress            Compress log files
#   -a, --all-containers      Get logs from all containers in pods
#   -m, --merge               Merge all logs into a single file
#   -h, --help                Display this help message
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
POD_NAME=""
NAMESPACE="default"
LABEL_FILTER=""
CONTAINER_NAME=""
TAIL_LINES=""
SINCE_TIME=""
UNTIL_TIME=""
FOLLOW=false
OUTPUT_DIR=""
COMPRESS=false
ALL_CONTAINERS=false
MERGE_LOGS=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Collect logs from Kubernetes pods."
    echo ""
    echo "Options:"
    echo "  -p, --pod <name>          Specific pod name"
    echo "  -n, --namespace <name>    Namespace (default: default)"
    echo "  -l, --label <key=value>   Filter pods by label"
    echo "  -c, --container <name>    Specific container in pod"
    echo "  -t, --tail <num>          Number of lines to show (default: all)"
    echo "  -s, --since <time>        Show logs since time (e.g. 1h, 10m, 2d)"
    echo "  -u, --until <time>        Show logs until time"
    echo "  -f, --follow              Follow logs in real-time"
    echo "  -o, --output <dir>        Output directory for log files"
    echo "  -z, --compress            Compress log files"
    echo "  -a, --all-containers      Get logs from all containers in pods"
    echo "  -m, --merge               Merge all logs into a single file"
    echo "  -h, --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") -p my-pod"
    echo "  $(basename "$0") -n kube-system -l app=metrics-server"
    echo "  $(basename "$0") -n default -l app=nginx -o /tmp/logs -z"
    echo "  $(basename "$0") -n monitoring -a -m -o /tmp/logs"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -p|--pod)
                POD_NAME="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -l|--label)
                LABEL_FILTER="$2"
                shift 2
                ;;
            -c|--container)
                CONTAINER_NAME="$2"
                shift 2
                ;;
            -t|--tail)
                TAIL_LINES="$2"
                if ! [[ "$TAIL_LINES" =~ ^[0-9]+$ ]]; then
                    log_error "Tail lines must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -s|--since)
                SINCE_TIME="$2"
                shift 2
                ;;
            -u|--until)
                UNTIL_TIME="$2"
                shift 2
                ;;
            -f|--follow)
                FOLLOW=true
                shift
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                if [ ! -d "$OUTPUT_DIR" ]; then
                    log_info "Output directory does not exist, creating: $OUTPUT_DIR"
                    mkdir -p "$OUTPUT_DIR"
                    if [ $? -ne 0 ]; then
                        log_error "Failed to create output directory: $OUTPUT_DIR"
                        exit 1
                    fi
                fi
                shift 2
                ;;
            -z|--compress)
                COMPRESS=true
                shift
                ;;
            -a|--all-containers)
                ALL_CONTAINERS=true
                shift
                ;;
            -m|--merge)
                MERGE_LOGS=true
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
    
    # Validate arguments
    if [ -z "$POD_NAME" ] && [ -z "$LABEL_FILTER" ]; then
        log_error "Either pod name (-p) or label filter (-l) is required"
        show_usage
        exit 1
    fi
    
    # Cannot follow logs and output to file at the same time
    if [ "$FOLLOW" = true ] && [ -n "$OUTPUT_DIR" ]; then
        log_error "Cannot follow logs (-f) and output to file (-o) at the same time"
        exit 1
    fi
    
    # Merge logs requires output directory
    if [ "$MERGE_LOGS" = true ] && [ -z "$OUTPUT_DIR" ]; then
        log_error "Merge logs (-m) requires output directory (-o)"
        exit 1
    fi
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

# Function to get pods based on filters
get_pods() {
    local namespace="$1"
    local pod_name="$2"
    local label_filter="$3"
    
    local kubectl_cmd="kubectl get pods -n $namespace"
    
    # Apply pod name filter if specified
    if [ -n "$pod_name" ]; then
        kubectl_cmd+=" $pod_name"
    fi
    
    # Apply label filter if specified
    if [ -n "$label_filter" ]; then
        kubectl_cmd+=" -l $label_filter"
    fi
    
    # Get pod names
    kubectl_cmd+=" -o jsonpath='{.items[*].metadata.name}'"
    
    # Execute kubectl command
    pods=$(eval "$kubectl_cmd")
    
    if [ -z "$pods" ]; then
        log_error "No pods found matching the criteria"
        exit 1
    fi
    
    echo "$pods"
}

# Function to get containers for a pod
get_containers() {
    local namespace="$1"
    local pod_name="$2"
    local container_name="$3"
    local all_containers="$4"
    
    if [ -n "$container_name" ]; then
        # Return specified container
        echo "$container_name"
    elif [ "$all_containers" = true ]; then
        # Get all containers (including init containers)
        containers=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.spec.containers[*].name} {.spec.initContainers[*].name}')
        echo "$containers"
    else
        # Get the first container
        container=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.spec.containers[0].name}')
        echo "$container"
    fi
}

# Function to collect logs for a pod
collect_pod_logs() {
    local namespace="$1"
    local pod_name="$2"
    local container_name="$3"
    local tail_lines="$4"
    local since_time="$5"
    local until_time="$6"
    local follow="$7"
    local output_dir="$8"
    local compress="$9"
    
    local kubectl_cmd="kubectl logs"
    
    # Apply namespace
    kubectl_cmd+=" -n $namespace $pod_name"
    
    # Apply container name if specified
    if [ -n "$container_name" ]; then
        kubectl_cmd+=" -c $container_name"
    fi
    
    # Apply tail lines if specified
    if [ -n "$tail_lines" ]; then
        kubectl_cmd+=" --tail=$tail_lines"
    fi
    
    # Apply since time if specified
    if [ -n "$since_time" ]; then
        kubectl_cmd+=" --since=$since_time"
    fi
    
    # Apply until time if specified
    if [ -n "$until_time" ]; then
        kubectl_cmd+=" --until=$until_time"
    fi
    
    # Apply follow flag if specified
    if [ "$follow" = true ]; then
        kubectl_cmd+=" -f"
    fi
    
    # Execute kubectl command
    if [ -n "$output_dir" ]; then
        # Output to file
        local log_file
        if [ -n "$container_name" ]; then
            log_file="$output_dir/${pod_name}_${container_name}.log"
        else
            log_file="$output_dir/${pod_name}.log"
        fi
        
        log_info "Collecting logs for $pod_name${container_name:+ (container: $container_name)}"
        eval "$kubectl_cmd > \"$log_file\""
        
        if [ $? -eq 0 ]; then
            # Compress if requested
            if [ "$compress" = true ]; then
                gzip "$log_file"
                log_success "Logs saved and compressed: ${log_file}.gz"
            else
                log_success "Logs saved: $log_file"
            fi
        else
            log_error "Failed to collect logs for $pod_name${container_name:+ (container: $container_name)}"
            return 1
        fi
    else
        # Output to stdout
        log_info "Displaying logs for $pod_name${container_name:+ (container: $container_name)}"
        eval "$kubectl_cmd"
        
        if [ $? -ne 0 ]; then
            log_error "Failed to display logs for $pod_name${container_name:+ (container: $container_name)}"
            return 1
        fi
    fi
    
    return 0
}

# Function to merge logs from multiple files
merge_logs() {
    local output_dir="$1"
    local compress="$2"
    local merged_file="${output_dir}/merged_logs.log"
    
    log_info "Merging logs into a single file"
    
    # Add a separator and file name before each log file content
    for log_file in "$output_dir"/*.log; do
        if [ -f "$log_file" ] && [ "$log_file" != "$merged_file" ]; then
            echo -e "\n\n=== $(basename "$log_file") ===" >> "$merged_file"
            cat "$log_file" >> "$merged_file"
        fi
    done
    
    # Compress if requested
    if [ "$compress" = true ]; then
        gzip "$merged_file"
        log_success "Merged logs saved and compressed: ${merged_file}.gz"
    else
        log_success "Merged logs saved: $merged_file"
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    check_kubectl
    
    log_info "Starting log collection from Kubernetes pods"
    log_info "Namespace: $NAMESPACE"
    
    if [ -n "$POD_NAME" ]; then
        log_info "Pod: $POD_NAME"
    fi
    
    if [ -n "$LABEL_FILTER" ]; then
        log_info "Label filter: $LABEL_FILTER"
    fi
    
    # Get list of pods
    pods=$(get_pods "$NAMESPACE" "$POD_NAME" "$LABEL_FILTER")
    
    # Track success and failure counts
    local success_count=0
    local failure_count=0
    
    # Process each pod
    for pod in $pods; do
        # Get containers for pod
        containers=$(get_containers "$NAMESPACE" "$pod" "$CONTAINER_NAME" "$ALL_CONTAINERS")
        
        # Process each container
        for container in $containers; do
            if collect_pod_logs "$NAMESPACE" "$pod" "$container" "$TAIL_LINES" "$SINCE_TIME" "$UNTIL_TIME" "$FOLLOW" "$OUTPUT_DIR" "$COMPRESS"; then
                success_count=$((success_count + 1))
            else
                failure_count=$((failure_count + 1))
            fi
        done
    done
    
    # Merge logs if requested
    if [ "$MERGE_LOGS" = true ] && [ -n "$OUTPUT_DIR" ]; then
        merge_logs "$OUTPUT_DIR" "$COMPRESS"
    fi
    
    # Show summary
    log_info "Log collection completed"
    log_success "Successful: $success_count"
    
    if [ $failure_count -gt 0 ]; then
        log_error "Failed: $failure_count"
    fi
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
