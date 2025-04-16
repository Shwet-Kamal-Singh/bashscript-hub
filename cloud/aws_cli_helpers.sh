#!/bin/bash
#
# aws_cli_helpers.sh - Helper functions for AWS CLI operations
#
# This script provides a collection of helper functions to simplify common 
# AWS CLI operations, making them more user-friendly and convenient.
#
# Usage:
#   source aws_cli_helpers.sh
#   aws_list_regions
#   aws_list_instances [region]
#   aws_list_s3_buckets
#
# Requirements:
#   - AWS CLI installed and configured
#   - Valid AWS credentials
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

# Check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &>/dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        log_error "Please install AWS CLI:"
        log_error "  - Debian/Ubuntu: sudo apt-get install awscli"
        log_error "  - RHEL/CentOS: sudo yum install awscli"
        log_error "  - Fedora: sudo dnf install awscli"
        log_error "  - or follow: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        return 1
    fi
    
    return 0
}

# Check if AWS CLI is configured
check_aws_config() {
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        log_error "Please configure AWS CLI with valid credentials:"
        log_error "  aws configure"
        return 1
    fi
    
    return 0
}

# List all AWS regions
aws_list_regions() {
    if ! check_aws_cli; then
        return 1
    fi
    
    log_info "Listing all AWS regions"
    aws ec2 describe-regions --query "Regions[].RegionName" --output table
    
    return $?
}

# List EC2 instances in a region
aws_list_instances() {
    if ! check_aws_cli; then
        return 1
    fi
    
    local region="$1"
    local region_param=""
    
    if [ -n "$region" ]; then
        region_param="--region $region"
    fi
    
    log_info "Listing EC2 instances${region:+ in region $region}"
    aws ec2 describe-instances $region_param \
        --query "Reservations[].Instances[].[InstanceId, State.Name, InstanceType, PublicIpAddress, Tags[?Key=='Name'].Value | [0]]" \
        --output table
    
    return $?
}

# List all S3 buckets
aws_list_s3_buckets() {
    if ! check_aws_cli; then
        return 1
    fi
    
    log_info "Listing all S3 buckets"
    aws s3 ls
    
    return $?
}

# Get S3 bucket size
aws_get_s3_bucket_size() {
    if ! check_aws_cli; then
        return 1
    fi
    
    local bucket="$1"
    
    if [ -z "$bucket" ]; then
        log_error "Bucket name is required"
        echo "Usage: aws_get_s3_bucket_size <bucket-name>"
        return 1
    fi
    
    log_info "Getting size of S3 bucket: $bucket"
    
    # Check if bucket exists
    if ! aws s3 ls "s3://$bucket" &>/dev/null; then
        log_error "Bucket does not exist: $bucket"
        return 1
    fi
    
    # Get bucket size
    aws s3 ls "s3://$bucket" --recursive --human-readable --summarize | grep "Total Size"
    
    return $?
}

# List snapshot for a volume
aws_list_snapshots_for_volume() {
    if ! check_aws_cli; then
        return 1
    fi
    
    local volume_id="$1"
    local region="$2"
    local region_param=""
    
    if [ -z "$volume_id" ]; then
        log_error "Volume ID is required"
        echo "Usage: aws_list_snapshots_for_volume <volume-id> [region]"
        return 1
    fi
    
    if [ -n "$region" ]; then
        region_param="--region $region"
    fi
    
    log_info "Listing snapshots for volume: $volume_id${region:+ in region $region}"
    aws ec2 describe-snapshots $region_param \
        --filters "Name=volume-id,Values=$volume_id" \
        --query "Snapshots[].{ID:SnapshotId,VolumeID:VolumeId,Size:VolumeSize,State:State,Progress:Progress,StartTime:StartTime}" \
        --output table
    
    return $?
}

# Get public IP of EC2 instance
aws_get_instance_public_ip() {
    if ! check_aws_cli; then
        return 1
    fi
    
    local instance_id="$1"
    local region="$2"
    local region_param=""
    
    if [ -z "$instance_id" ]; then
        log_error "Instance ID is required"
        echo "Usage: aws_get_instance_public_ip <instance-id> [region]"
        return 1
    fi
    
    if [ -n "$region" ]; then
        region_param="--region $region"
    fi
    
    log_info "Getting public IP for instance: $instance_id${region:+ in region $region}"
    aws ec2 describe-instances $region_param \
        --instance-ids "$instance_id" \
        --query "Reservations[].Instances[].PublicIpAddress" \
        --output text
    
    return $?
}

# List CloudWatch log groups
aws_list_log_groups() {
    if ! check_aws_cli; then
        return 1
    fi
    
    local region="$1"
    local region_param=""
    
    if [ -n "$region" ]; then
        region_param="--region $region"
    fi
    
    log_info "Listing CloudWatch log groups${region:+ in region $region}"
    aws logs describe-log-groups $region_param \
        --query "logGroups[].{Name:logGroupName,Size:storedBytes,RetentionDays:retentionInDays}" \
        --output table
    
    return $?
}

# List Lambda functions
aws_list_lambda_functions() {
    if ! check_aws_cli; then
        return 1
    fi
    
    local region="$1"
    local region_param=""
    
    if [ -n "$region" ]; then
        region_param="--region $region"
    fi
    
    log_info "Listing Lambda functions${region:+ in region $region}"
    aws lambda list-functions $region_param \
        --query "Functions[].{Name:FunctionName,Runtime:Runtime,Memory:MemorySize,Timeout:Timeout,LastModified:LastModified}" \
        --output table
    
    return $?
}

# List IAM users
aws_list_iam_users() {
    if ! check_aws_cli; then
        return 1
    fi
    
    log_info "Listing IAM users"
    aws iam list-users \
        --query "Users[].{Name:UserName,ID:UserId,Created:CreateDate,PasswordLastUsed:PasswordLastUsed}" \
        --output table
    
    return $?
}

# Get instance types available in a region
aws_get_instance_types() {
    if ! check_aws_cli; then
        return 1
    fi
    
    local region="$1"
    local region_param=""
    
    if [ -z "$region" ]; then
        log_error "Region is required"
        echo "Usage: aws_get_instance_types <region>"
        return 1
    fi
    
    region_param="--region $region"
    
    log_info "Getting available instance types in region: $region"
    aws ec2 describe-instance-type-offerings $region_param \
        --location-type availability-zone \
        --query "InstanceTypeOfferings[].InstanceType" \
        --output table
    
    return $?
}

# Main execution
main() {
    if [ "$#" -eq 0 ]; then
        # Display available functions if no arguments are provided
        log_info "Available AWS CLI helper functions:"
        log_info "  aws_list_regions"
        log_info "  aws_list_instances [region]"
        log_info "  aws_list_s3_buckets"
        log_info "  aws_get_s3_bucket_size <bucket-name>"
        log_info "  aws_list_snapshots_for_volume <volume-id> [region]"
        log_info "  aws_get_instance_public_ip <instance-id> [region]"
        log_info "  aws_list_log_groups [region]"
        log_info "  aws_list_lambda_functions [region]"
        log_info "  aws_list_iam_users"
        log_info "  aws_get_instance_types <region>"
        return 0
    fi
    
    # Check AWS CLI and configuration
    if ! check_aws_cli || ! check_aws_config; then
        return 1
    fi
    
    # Execute the specified function
    local function_name="$1"
    shift
    
    case "$function_name" in
        aws_list_regions)
            aws_list_regions "$@"
            ;;
        aws_list_instances)
            aws_list_instances "$@"
            ;;
        aws_list_s3_buckets)
            aws_list_s3_buckets "$@"
            ;;
        aws_get_s3_bucket_size)
            aws_get_s3_bucket_size "$@"
            ;;
        aws_list_snapshots_for_volume)
            aws_list_snapshots_for_volume "$@"
            ;;
        aws_get_instance_public_ip)
            aws_get_instance_public_ip "$@"
            ;;
        aws_list_log_groups)
            aws_list_log_groups "$@"
            ;;
        aws_list_lambda_functions)
            aws_list_lambda_functions "$@"
            ;;
        aws_list_iam_users)
            aws_list_iam_users "$@"
            ;;
        aws_get_instance_types)
            aws_get_instance_types "$@"
            ;;
        *)
            log_error "Unknown function: $function_name"
            return 1
            ;;
    esac
    
    return $?
}

# Check if the script is being sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # If executed directly, run main with all arguments
    main "$@"
fi
