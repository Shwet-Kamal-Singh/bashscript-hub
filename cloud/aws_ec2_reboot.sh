#!/bin/bash
#
# aws_ec2_reboot.sh - Safely reboot AWS EC2 instances
#
# This script safely reboots AWS EC2 instances with options to filter by
# region, tags, or instance IDs. It includes checks to ensure instances
# come back online after reboot and can perform rolling reboots for multiple
# instances to minimize service disruption.
#
# Usage:
#   ./aws_ec2_reboot.sh [options]
#
# Options:
#   -i, --instance <id>       Instance ID to reboot (can be used multiple times)
#   -r, --region <region>     AWS region (default: region from AWS config)
#   -t, --tag <key=value>     Filter instances by tag (can be used multiple times)
#   -g, --group <name>        Auto Scaling Group name
#   -w, --wait                Wait for instances to return to running state
#   -l, --rolling             Perform rolling reboot (one instance at a time)
#   -d, --delay <seconds>     Delay between reboots in rolling mode (default: 300)
#   -f, --force               Skip confirmation prompt
#   --dry-run                 Show what would be done without making changes
#   -h, --help                Display this help message
#
# Requirements:
#   - AWS CLI installed and configured
#   - Valid AWS credentials with EC2 permissions
#
# Author: BashScriptHub
# Date: 2023
# License: MIT

# Detect script directory for sourcing utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

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
INSTANCE_IDS=()
REGION=""
TAGS=()
ASG_NAME=""
WAIT_FOR_STATE=false
ROLLING_REBOOT=false
REBOOT_DELAY=300
FORCE=false
DRY_RUN=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Safely reboot AWS EC2 instances."
    echo ""
    echo "Options:"
    echo "  -i, --instance <id>       Instance ID to reboot (can be used multiple times)"
    echo "  -r, --region <region>     AWS region (default: region from AWS config)"
    echo "  -t, --tag <key=value>     Filter instances by tag (can be used multiple times)"
    echo "  -g, --group <name>        Auto Scaling Group name"
    echo "  -w, --wait                Wait for instances to return to running state"
    echo "  -l, --rolling             Perform rolling reboot (one instance at a time)"
    echo "  -d, --delay <seconds>     Delay between reboots in rolling mode (default: 300)"
    echo "  -f, --force               Skip confirmation prompt"
    echo "  --dry-run                 Show what would be done without making changes"
    echo "  -h, --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") -i i-0abc123def456 -w"
    echo "  $(basename "$0") -r us-west-2 -t Name=webserver -l"
    echo "  $(basename "$0") -g my-auto-scaling-group -w -l -d 600"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -i|--instance)
                INSTANCE_IDS+=("$2")
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -t|--tag)
                TAGS+=("$2")
                shift 2
                ;;
            -g|--group)
                ASG_NAME="$2"
                shift 2
                ;;
            -w|--wait)
                WAIT_FOR_STATE=true
                shift
                ;;
            -l|--rolling)
                ROLLING_REBOOT=true
                shift
                ;;
            -d|--delay)
                REBOOT_DELAY="$2"
                if ! [[ "$REBOOT_DELAY" =~ ^[0-9]+$ ]] || [ "$REBOOT_DELAY" -lt 0 ]; then
                    log_error "Delay must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -f|--force)
                FORCE=true
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
    if [ ${#INSTANCE_IDS[@]} -eq 0 ] && [ ${#TAGS[@]} -eq 0 ] && [ -z "$ASG_NAME" ]; then
        log_error "At least one of --instance, --tag, or --group is required"
        show_usage
        exit 1
    fi
    
    # Add region parameter if specified
    if [ -n "$REGION" ]; then
        REGION_PARAM="--region $REGION"
    else
        REGION_PARAM=""
    fi
}

# Function to check if AWS CLI is installed and configured
check_aws_cli() {
    if ! command -v aws &>/dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        log_error "Please install AWS CLI:"
        log_error "  - Debian/Ubuntu: sudo apt-get install awscli"
        log_error "  - RHEL/CentOS: sudo yum install awscli"
        log_error "  - Fedora: sudo dnf install awscli"
        log_error "  - or follow: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        log_error "Please configure AWS CLI with valid credentials:"
        log_error "  aws configure"
        exit 1
    fi
}

# Function to get instances from Auto Scaling Group
get_asg_instances() {
    local asg_name="$1"
    
    log_info "Getting instances in Auto Scaling Group: $asg_name"
    
    local instances
    instances=$(aws autoscaling describe-auto-scaling-groups $REGION_PARAM \
        --auto-scaling-group-names "$asg_name" \
        --query "AutoScalingGroups[].Instances[].InstanceId" \
        --output text)
    
    if [ -z "$instances" ]; then
        log_error "No instances found in Auto Scaling Group: $asg_name"
        exit 1
    fi
    
    echo "$instances"
}

# Function to get instances by tags
get_instances_by_tags() {
    local tags=("$@")
    local filter_params=""
    
    log_info "Getting instances by tags"
    
    for tag in "${tags[@]}"; do
        # Split tag into key and value
        IFS='=' read -r key value <<< "$tag"
        
        if [ -n "$key" ] && [ -n "$value" ]; then
            filter_params+="Name=tag:$key,Values=$value "
        else
            log_warning "Ignoring invalid tag format: $tag (expected key=value)"
        fi
    done
    
    if [ -z "$filter_params" ]; then
        log_error "No valid tags provided"
        exit 1
    fi
    
    local instances
    instances=$(aws ec2 describe-instances $REGION_PARAM \
        --filters $filter_params "Name=instance-state-name,Values=running" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text)
    
    if [ -z "$instances" ]; then
        log_error "No running instances found matching the specified tags"
        exit 1
    fi
    
    echo "$instances"
}

# Function to get instance info
get_instance_info() {
    local instance_id="$1"
    
    aws ec2 describe-instances $REGION_PARAM \
        --instance-ids "$instance_id" \
        --query "Reservations[].Instances[].{InstanceId:InstanceId, State:State.Name, Name:Tags[?Key=='Name'].Value | [0], Type:InstanceType, PrivateIP:PrivateIpAddress}" \
        --output json
}

# Function to check if instance exists and is in a valid state for reboot
check_instance() {
    local instance_id="$1"
    
    log_info "Checking instance: $instance_id"
    
    local instance_info
    instance_info=$(get_instance_info "$instance_id")
    
    if [ -z "$instance_info" ] || [ "$instance_info" = "null" ]; then
        log_error "Instance not found: $instance_id"
        return 1
    fi
    
    local state
    state=$(echo "$instance_info" | grep -o '"State": *"[^"]*"' | cut -d'"' -f4)
    
    if [ "$state" != "running" ]; then
        log_warning "Instance $instance_id is not in 'running' state (current state: $state)"
        return 1
    fi
    
    return 0
}

# Function to reboot an instance
reboot_instance() {
    local instance_id="$1"
    
    # Get instance name for better logging
    local instance_name
    instance_name=$(aws ec2 describe-tags $REGION_PARAM \
        --filters "Name=resource-id,Values=$instance_id" "Name=key,Values=Name" \
        --query "Tags[0].Value" \
        --output text)
    
    if [ "$instance_name" = "None" ]; then
        instance_name="(unnamed)"
    fi
    
    log_info "Rebooting instance: $instance_id ($instance_name)"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] Would reboot instance: $instance_id ($instance_name)"
        return 0
    fi
    
    aws ec2 reboot-instances $REGION_PARAM --instance-ids "$instance_id"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to reboot instance: $instance_id"
        return 1
    fi
    
    log_success "Reboot command sent to instance: $instance_id"
    return 0
}

# Function to wait for instance to return to running state
wait_for_instance() {
    local instance_id="$1"
    local timeout=600  # 10 minutes
    local interval=10  # 10 seconds
    local elapsed=0
    
    log_info "Waiting for instance $instance_id to return to 'running' state..."
    
    while [ $elapsed -lt $timeout ]; do
        local state
        state=$(aws ec2 describe-instances $REGION_PARAM \
            --instance-ids "$instance_id" \
            --query "Reservations[].Instances[].State.Name" \
            --output text)
        
        if [ "$state" = "running" ]; then
            # Even though instance state is 'running', the system might not be fully booted
            # Wait a bit more to allow services to start
            log_info "Instance $instance_id is now in 'running' state. Waiting for system to stabilize..."
            sleep 30
            
            # Try to check instance status
            local status
            status=$(aws ec2 describe-instance-status $REGION_PARAM \
                --instance-ids "$instance_id" \
                --query "InstanceStatuses[].InstanceStatus.Status" \
                --output text)
            
            if [ "$status" = "ok" ]; then
                log_success "Instance $instance_id is now fully operational"
                return 0
            else
                log_info "Instance $instance_id status: $status. Continuing to wait..."
            fi
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        log_info "Still waiting for instance $instance_id... (${elapsed}s elapsed)"
    done
    
    log_error "Timeout waiting for instance $instance_id to return to 'running' state"
    return 1
}

# Function to confirm action with user
confirm_action() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    local instances=("$@")
    local count=${#instances[@]}
    
    echo "You are about to reboot the following $count instance(s):"
    
    for instance in "${instances[@]}"; do
        local instance_info
        instance_info=$(get_instance_info "$instance")
        local name
        name=$(echo "$instance_info" | grep -o '"Name": *"[^"]*"' | cut -d'"' -f4)
        
        if [ -z "$name" ]; then
            name="(unnamed)"
        fi
        
        echo "  - $instance ($name)"
    done
    
    if [ "$ROLLING_REBOOT" = true ]; then
        echo "Instances will be rebooted one at a time with a ${REBOOT_DELAY}s delay between each reboot."
    fi
    
    echo ""
    read -p "Do you want to continue? (y/N): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    check_aws_cli
    
    log_info "Starting EC2 instance reboot process"
    
    # Collect all instances to reboot
    ALL_INSTANCES=()
    
    # Add instances from direct IDs
    for id in "${INSTANCE_IDS[@]}"; do
        if check_instance "$id"; then
            ALL_INSTANCES+=("$id")
        fi
    done
    
    # Add instances from Auto Scaling Group
    if [ -n "$ASG_NAME" ]; then
        IFS=$'\t' read -ra asg_instances <<< "$(get_asg_instances "$ASG_NAME")"
        for id in "${asg_instances[@]}"; do
            if check_instance "$id"; then
                ALL_INSTANCES+=("$id")
            fi
        done
    fi
    
    # Add instances from tags
    if [ ${#TAGS[@]} -gt 0 ]; then
        IFS=$'\t' read -ra tagged_instances <<< "$(get_instances_by_tags "${TAGS[@]}")"
        for id in "${tagged_instances[@]}"; do
            if check_instance "$id"; then
                # Check if instance is already in the list
                if [[ ! " ${ALL_INSTANCES[*]} " =~ " ${id} " ]]; then
                    ALL_INSTANCES+=("$id")
                fi
            fi
        done
    fi
    
    # Check if we have any instances to reboot
    if [ ${#ALL_INSTANCES[@]} -eq 0 ]; then
        log_error "No valid instances found to reboot"
        exit 1
    fi
    
    # Confirm reboot operation
    confirm_action "${ALL_INSTANCES[@]}"
    
    # Perform reboot operations
    REBOOT_SUCCESS=0
    REBOOT_FAILED=0
    
    if [ "$ROLLING_REBOOT" = true ]; then
        log_info "Performing rolling reboot of ${#ALL_INSTANCES[@]} instances"
        
        for id in "${ALL_INSTANCES[@]}"; do
            if reboot_instance "$id"; then
                if [ "$WAIT_FOR_STATE" = true ]; then
                    wait_for_instance "$id"
                fi
                REBOOT_SUCCESS=$((REBOOT_SUCCESS + 1))
            else
                REBOOT_FAILED=$((REBOOT_FAILED + 1))
            fi
            
            # Skip delay after the last instance
            if [ "$id" != "${ALL_INSTANCES[-1]}" ]; then
                log_info "Waiting ${REBOOT_DELAY}s before rebooting the next instance..."
                sleep "$REBOOT_DELAY"
            fi
        done
    else
        log_info "Rebooting all ${#ALL_INSTANCES[@]} instances simultaneously"
        
        for id in "${ALL_INSTANCES[@]}"; do
            if reboot_instance "$id"; then
                REBOOT_SUCCESS=$((REBOOT_SUCCESS + 1))
            else
                REBOOT_FAILED=$((REBOOT_FAILED + 1))
            fi
        done
        
        if [ "$WAIT_FOR_STATE" = true ]; then
            for id in "${ALL_INSTANCES[@]}"; do
                wait_for_instance "$id"
            done
        fi
    fi
    
    # Display summary
    log_info "EC2 instance reboot summary:"
    log_success "  Successful: $REBOOT_SUCCESS"
    
    if [ $REBOOT_FAILED -gt 0 ]; then
        log_error "  Failed: $REBOOT_FAILED"
        exit 1
    fi
    
    log_success "All reboot operations completed successfully"
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
