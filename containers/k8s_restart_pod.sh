#!/bin/bash
#
# k8s_restart_pod.sh - Restart Kubernetes pods safely
#
# This script provides a safe way to restart Kubernetes pods without downtime,
# supporting multiple methods including rolling restart for deployments and
# individual pod deletion for stateful workloads.
#
# Usage:
#   ./k8s_restart_pod.sh [options]
#
# Options:
#   -p, --pod <name>          Specific pod name to restart
#   -d, --deployment <name>   Restart all pods in a deployment
#   -s, --statefulset <name>  Restart all pods in a statefulset
#   -l, --label <key=value>   Restart pods matching label selector
#   -n, --namespace <name>    Namespace (default: default)
#   -r, --rolling             Use rolling restart strategy (for deployments)
#   -t, --timeout <seconds>   Timeout waiting for pod to be ready (default: 300)
#   -w, --wait                Wait for pod to be ready before continuing
#   -f, --force               Force restart even for critical pods
#   --dry-run                 Show what would be done without actually doing it
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
DEPLOYMENT_NAME=""
STATEFULSET_NAME=""
LABEL_SELECTOR=""
NAMESPACE="default"
ROLLING_RESTART=false
TIMEOUT=300
WAIT_FOR_READY=false
FORCE_RESTART=false
DRY_RUN=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Restart Kubernetes pods safely."
    echo ""
    echo "Options:"
    echo "  -p, --pod <name>          Specific pod name to restart"
    echo "  -d, --deployment <name>   Restart all pods in a deployment"
    echo "  -s, --statefulset <name>  Restart all pods in a statefulset"
    echo "  -l, --label <key=value>   Restart pods matching label selector"
    echo "  -n, --namespace <name>    Namespace (default: default)"
    echo "  -r, --rolling             Use rolling restart strategy (for deployments)"
    echo "  -t, --timeout <seconds>   Timeout waiting for pod to be ready (default: 300)"
    echo "  -w, --wait                Wait for pod to be ready before continuing"
    echo "  -f, --force               Force restart even for critical pods"
    echo "  --dry-run                 Show what would be done without actually doing it"
    echo "  -h, --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") -p my-pod"
    echo "  $(basename "$0") -d my-deployment -n kube-system -r"
    echo "  $(basename "$0") -l app=nginx -w -n default"
    echo "  $(basename "$0") -s my-statefulset --dry-run"
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
            -d|--deployment)
                DEPLOYMENT_NAME="$2"
                shift 2
                ;;
            -s|--statefulset)
                STATEFULSET_NAME="$2"
                shift 2
                ;;
            -l|--label)
                LABEL_SELECTOR="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -r|--rolling)
                ROLLING_RESTART=true
                shift
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -lt 1 ]; then
                    log_error "Timeout must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -w|--wait)
                WAIT_FOR_READY=true
                shift
                ;;
            -f|--force)
                FORCE_RESTART=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
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
    local target_count=0
    if [ -n "$POD_NAME" ]; then target_count=$((target_count + 1)); fi
    if [ -n "$DEPLOYMENT_NAME" ]; then target_count=$((target_count + 1)); fi
    if [ -n "$STATEFULSET_NAME" ]; then target_count=$((target_count + 1)); fi
    if [ -n "$LABEL_SELECTOR" ]; then target_count=$((target_count + 1)); fi
    
    if [ $target_count -eq 0 ]; then
        log_error "At least one target (pod, deployment, statefulset, or label) is required"
        show_usage
        exit 1
    fi
    
    if [ $target_count -gt 1 ]; then
        log_error "Only one target (pod, deployment, statefulset, or label) can be specified"
        show_usage
        exit 1
    fi
    
    # Rolling restart is only valid for deployments
    if [ "$ROLLING_RESTART" = true ] && [ -z "$DEPLOYMENT_NAME" ]; then
        log_error "Rolling restart is only valid for deployments"
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

# Function to check if pod is critical
is_pod_critical() {
    local namespace="$1"
    local pod_name="$2"
    
    # Check if pod has critical annotations
    local critical
    critical=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.annotations.scheduler\.alpha\.kubernetes\.io/critical-pod}' 2>/dev/null)
    if [ "$critical" = "true" ]; then
        return 0
    fi
    
    # Check if pod is in kube-system namespace and doesn't have replicas
    if [ "$namespace" = "kube-system" ]; then
        # Get owner reference kind
        local owner_kind
        owner_kind=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)
        
        # Check if pod is a standalone pod or part of a DaemonSet
        if [ -z "$owner_kind" ] || [ "$owner_kind" = "Node" ]; then
            return 0
        fi
    fi
    
    return 1
}

# Function to wait for pod to be ready
wait_for_pod_ready() {
    local namespace="$1"
    local pod_name="$2"
    local timeout="$3"
    
    log_info "Waiting for pod $pod_name to be ready (timeout: ${timeout}s)"
    
    local end_time=$(($(date +%s) + timeout))
    
    while [ $(date +%s) -lt $end_time ]; do
        # Check if pod exists
        if ! kubectl get pod "$pod_name" -n "$namespace" &>/dev/null; then
            log_info "Pod $pod_name no longer exists, it may be recreating..."
            sleep 2
            continue
        fi
        
        # Check pod status
        local phase
        phase=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null)
        
        # Check if pod is running and ready
        if [ "$phase" = "Running" ]; then
            local ready
            ready=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
            
            if [ "$ready" = "true" ]; then
                log_success "Pod $pod_name is now ready"
                return 0
            fi
        fi
        
        log_info "Pod $pod_name status: $phase, waiting..."
        sleep 2
    done
    
    log_error "Timeout waiting for pod $pod_name to be ready"
    return 1
}

# Function to restart a pod
restart_pod() {
    local namespace="$1"
    local pod_name="$2"
    
    log_info "Restarting pod: $pod_name in namespace: $namespace"
    
    # Check if pod is critical and force restart is not enabled
    if is_pod_critical "$namespace" "$pod_name" && [ "$FORCE_RESTART" = false ]; then
        log_error "Pod $pod_name is critical. Use -f flag to force restart."
        return 1
    fi
    
    # Get pod's owner reference to determine recreation strategy
    local owner_kind
    local owner_name
    owner_kind=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)
    owner_name=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null)
    
    # Delete the pod
    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] Would delete pod: $pod_name in namespace: $namespace"
    else
        kubectl delete pod "$pod_name" -n "$namespace"
        if [ $? -ne 0 ]; then
            log_error "Failed to delete pod: $pod_name"
            return 1
        fi
        
        log_success "Pod deleted: $pod_name"
        
        # If the pod is managed by a controller, wait for it to be recreated
        if [ -n "$owner_kind" ] && [ "$WAIT_FOR_READY" = true ]; then
            # Allow some time for pod to be recreated
            sleep 2
            
            # Wait for the new pod with the same owner
            local new_pod
            local end_time=$(($(date +%s) + TIMEOUT))
            
            while [ $(date +%s) -lt $end_time ]; do
                # Try to find the new pod by owner reference
                if [ "$owner_kind" = "ReplicaSet" ]; then
                    new_pod=$(kubectl get pods -n "$namespace" -o jsonpath="{.items[?(@.metadata.ownerReferences[0].name=='$owner_name')].metadata.name}" 2>/dev/null | grep -v "$pod_name" | head -1)
                else
                    # For StatefulSets and DaemonSets, the pod name stays the same
                    new_pod="$pod_name"
                fi
                
                if [ -n "$new_pod" ] && kubectl get pod "$new_pod" -n "$namespace" &>/dev/null; then
                    wait_for_pod_ready "$namespace" "$new_pod" $((end_time - $(date +%s)))
                    return $?
                fi
                
                log_info "Waiting for pod to be recreated..."
                sleep 2
            done
            
            log_error "Timeout waiting for pod to be recreated"
            return 1
        fi
    fi
    
    return 0
}

# Function to restart all pods in a deployment
restart_deployment() {
    local namespace="$1"
    local deployment_name="$2"
    local rolling="$3"
    
    log_info "Restarting deployment: $deployment_name in namespace: $namespace"
    
    # Check if deployment exists
    if ! kubectl get deployment "$deployment_name" -n "$namespace" &>/dev/null; then
        log_error "Deployment not found: $deployment_name in namespace: $namespace"
        return 1
    fi
    
    if [ "$rolling" = true ]; then
        # Perform rolling restart
        if [ "$DRY_RUN" = true ]; then
            log_warning "[DRY RUN] Would perform rolling restart of deployment: $deployment_name"
        else
            log_info "Performing rolling restart of deployment: $deployment_name"
            
            # Using kubectl rollout restart if available (Kubernetes 1.15+)
            if kubectl rollout restart deployment "$deployment_name" -n "$namespace" 2>/dev/null; then
                log_success "Initiated rolling restart of deployment: $deployment_name"
                
                if [ "$WAIT_FOR_READY" = true ]; then
                    log_info "Waiting for rollout to complete"
                    kubectl rollout status deployment "$deployment_name" -n "$namespace" --timeout="${TIMEOUT}s"
                    if [ $? -eq 0 ]; then
                        log_success "Deployment rollout completed successfully"
                    else
                        log_error "Deployment rollout failed or timed out"
                        return 1
                    fi
                fi
            else
                # Fallback for older Kubernetes versions
                log_warning "kubectl rollout restart not available, using alternate method"
                
                # Patch deployment with a restart annotation
                kubectl patch deployment "$deployment_name" -n "$namespace" -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"kubectl.kubernetes.io/restartedAt\":\"$(date +%Y-%m-%dT%H:%M:%S%z)\"}}}}}"
                
                if [ $? -ne 0 ]; then
                    log_error "Failed to patch deployment: $deployment_name"
                    return 1
                fi
                
                log_success "Initiated rolling restart of deployment: $deployment_name"
                
                if [ "$WAIT_FOR_READY" = true ]; then
                    log_info "Waiting for rollout to complete"
                    kubectl rollout status deployment "$deployment_name" -n "$namespace" --timeout="${TIMEOUT}s"
                    if [ $? -eq 0 ]; then
                        log_success "Deployment rollout completed successfully"
                    else
                        log_error "Deployment rollout failed or timed out"
                        return 1
                    fi
                fi
            fi
        fi
    else
        # Restart by deleting pods
        log_info "Restarting deployment by deleting pods"
        
        # Get all pods in the deployment
        local pods
        pods=$(kubectl get pods -n "$namespace" -l "app=$deployment_name" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
        
        if [ -z "$pods" ]; then
            # Try to get pods by commonly used labels
            pods=$(kubectl get pods -n "$namespace" -o jsonpath="{.items[?(@.metadata.labels.app=='$deployment_name')].metadata.name}" 2>/dev/null)
        fi
        
        if [ -z "$pods" ]; then
            # Last resort: get pods owned by the deployment's replica sets
            rs_names=$(kubectl get rs -n "$namespace" -o jsonpath="{.items[?(@.metadata.ownerReferences[0].name=='$deployment_name')].metadata.name}" 2>/dev/null)
            
            for rs in $rs_names; do
                rs_pods=$(kubectl get pods -n "$namespace" -o jsonpath="{.items[?(@.metadata.ownerReferences[0].name=='$rs')].metadata.name}" 2>/dev/null)
                pods="$pods $rs_pods"
            done
        fi
        
        if [ -z "$pods" ]; then
            log_error "No pods found for deployment: $deployment_name"
            return 1
        fi
        
        local success_count=0
        local failure_count=0
        
        for pod in $pods; do
            if restart_pod "$namespace" "$pod"; then
                success_count=$((success_count + 1))
            else
                failure_count=$((failure_count + 1))
            fi
        done
        
        log_info "Deployment restart summary:"
        log_success "  Successful: $success_count"
        
        if [ $failure_count -gt 0 ]; then
            log_error "  Failed: $failure_count"
            return 1
        fi
    fi
    
    return 0
}

# Function to restart all pods in a statefulset
restart_statefulset() {
    local namespace="$1"
    local statefulset_name="$2"
    
    log_info "Restarting statefulset: $statefulset_name in namespace: $namespace"
    
    # Check if statefulset exists
    if ! kubectl get statefulset "$statefulset_name" -n "$namespace" &>/dev/null; then
        log_error "StatefulSet not found: $statefulset_name in namespace: $namespace"
        return 1
    fi
    
    # Get all pods in the statefulset
    local pods
    pods=$(kubectl get pods -n "$namespace" -l "app=$statefulset_name" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -z "$pods" ]; then
        # Try to get pods by commonly used labels
        pods=$(kubectl get pods -n "$namespace" -o jsonpath="{.items[?(@.metadata.labels.app=='$statefulset_name')].metadata.name}" 2>/dev/null)
    fi
    
    if [ -z "$pods" ]; then
        log_error "No pods found for statefulset: $statefulset_name"
        return 1
    fi
    
    # Sort pods to restart them in reverse order (from highest to lowest ordinal)
    pods=$(echo "$pods" | tr ' ' '\n' | sort -r)
    
    local success_count=0
    local failure_count=0
    
    for pod in $pods; do
        if restart_pod "$namespace" "$pod"; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi
    done
    
    log_info "StatefulSet restart summary:"
    log_success "  Successful: $success_count"
    
    if [ $failure_count -gt 0 ]; then
        log_error "  Failed: $failure_count"
        return 1
    fi
    
    return 0
}

# Function to restart pods by label selector
restart_pods_by_label() {
    local namespace="$1"
    local label_selector="$2"
    
    log_info "Restarting pods with label selector: $label_selector in namespace: $namespace"
    
    # Get all pods matching the label selector
    local pods
    pods=$(kubectl get pods -n "$namespace" -l "$label_selector" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -z "$pods" ]; then
        log_error "No pods found matching label selector: $label_selector"
        return 1
    fi
    
    local success_count=0
    local failure_count=0
    
    for pod in $pods; do
        if restart_pod "$namespace" "$pod"; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi
    done
    
    log_info "Label selector restart summary:"
    log_success "  Successful: $success_count"
    
    if [ $failure_count -gt 0 ]; then
        log_error "  Failed: $failure_count"
        return 1
    fi
    
    return 0
}

# Main execution
main() {
    parse_arguments "$@"
    check_kubectl
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE: No actual changes will be made"
    fi
    
    log_info "Kubernetes namespace: $NAMESPACE"
    
    # Execute appropriate restart function based on target
    if [ -n "$POD_NAME" ]; then
        restart_pod "$NAMESPACE" "$POD_NAME"
    elif [ -n "$DEPLOYMENT_NAME" ]; then
        restart_deployment "$NAMESPACE" "$DEPLOYMENT_NAME" "$ROLLING_RESTART"
    elif [ -n "$STATEFULSET_NAME" ]; then
        restart_statefulset "$NAMESPACE" "$STATEFULSET_NAME"
    elif [ -n "$LABEL_SELECTOR" ]; then
        restart_pods_by_label "$NAMESPACE" "$LABEL_SELECTOR"
    fi
    
    if [ $? -eq 0 ]; then
        log_success "Restart operation completed successfully"
    else
        log_error "Restart operation failed"
        exit 1
    fi
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
