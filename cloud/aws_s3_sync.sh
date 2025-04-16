#!/bin/bash
#
# aws_s3_sync.sh - Sync files to/from AWS S3 buckets
#
# This script facilitates syncing files between local directories and S3 buckets,
# with support for filtering, dry runs, and different sync directions.
#
# Usage:
#   ./aws_s3_sync.sh [options]
#
# Options:
#   -s, --source <path>         Source path (local path or s3://bucket/prefix)
#   -d, --destination <path>    Destination path (local path or s3://bucket/prefix)
#   -r, --region <region>       AWS region (default: region from AWS config)
#   -p, --profile <profile>     AWS profile to use
#   -e, --exclude <pattern>     Exclude files matching pattern (can be used multiple times)
#   -i, --include <pattern>     Include files matching pattern (can be used multiple times)
#   -a, --acl <acl>             S3 ACL to apply (e.g., private, public-read)
#   -c, --cache-control <val>   Cache-Control header to set
#   --delete                    Delete files in destination that don't exist in source
#   --dry-run                   Show what would be done without making changes
#   -v, --verbose               Display detailed output
#   -h, --help                  Display this help message
#
# Requirements:
#   - AWS CLI installed and configured
#   - Valid AWS credentials with S3 permissions
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
SOURCE_PATH=""
DESTINATION_PATH=""
REGION=""
PROFILE=""
EXCLUDE_PATTERNS=()
INCLUDE_PATTERNS=()
ACL=""
CACHE_CONTROL=""
DELETE=false
DRY_RUN=false
VERBOSE=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Sync files to/from AWS S3 buckets."
    echo ""
    echo "Options:"
    echo "  -s, --source <path>         Source path (local path or s3://bucket/prefix)"
    echo "  -d, --destination <path>    Destination path (local path or s3://bucket/prefix)"
    echo "  -r, --region <region>       AWS region (default: region from AWS config)"
    echo "  -p, --profile <profile>     AWS profile to use"
    echo "  -e, --exclude <pattern>     Exclude files matching pattern (can be used multiple times)"
    echo "  -i, --include <pattern>     Include files matching pattern (can be used multiple times)"
    echo "  -a, --acl <acl>             S3 ACL to apply (e.g., private, public-read)"
    echo "  -c, --cache-control <val>   Cache-Control header to set"
    echo "  --delete                    Delete files in destination that don't exist in source"
    echo "  --dry-run                   Show what would be done without making changes"
    echo "  -v, --verbose               Display detailed output"
    echo "  -h, --help                  Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") -s ./local/path -d s3://my-bucket/prefix"
    echo "  $(basename "$0") -s s3://my-bucket/prefix -d ./local/path"
    echo "  $(basename "$0") -s ./local/path -d s3://my-bucket/prefix -e \"*.log\" -e \"*.tmp\" --delete"
    echo "  $(basename "$0") -s ./local/path -d s3://my-bucket/prefix -a public-read --dry-run"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -s|--source)
                SOURCE_PATH="$2"
                shift 2
                ;;
            -d|--destination)
                DESTINATION_PATH="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -p|--profile)
                PROFILE="$2"
                shift 2
                ;;
            -e|--exclude)
                EXCLUDE_PATTERNS+=("$2")
                shift 2
                ;;
            -i|--include)
                INCLUDE_PATTERNS+=("$2")
                shift 2
                ;;
            -a|--acl)
                ACL="$2"
                shift 2
                ;;
            -c|--cache-control)
                CACHE_CONTROL="$2"
                shift 2
                ;;
            --delete)
                DELETE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
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
    
    # Validate required arguments
    if [ -z "$SOURCE_PATH" ]; then
        log_error "Source path is required"
        show_usage
        exit 1
    fi
    
    if [ -z "$DESTINATION_PATH" ]; then
        log_error "Destination path is required"
        show_usage
        exit 1
    fi
    
    # Validate S3 paths
    local is_source_s3=false
    local is_destination_s3=false
    
    if [[ "$SOURCE_PATH" == s3://* ]]; then
        is_source_s3=true
    fi
    
    if [[ "$DESTINATION_PATH" == s3://* ]]; then
        is_destination_s3=true
    fi
    
    # At least one path must be S3
    if ! $is_source_s3 && ! $is_destination_s3; then
        log_error "At least one of source or destination must be an S3 path (s3://bucket/prefix)"
        exit 1
    fi
    
    # Local paths must exist if they're the source
    if ! $is_source_s3 && [ ! -e "$SOURCE_PATH" ]; then
        log_error "Source path does not exist: $SOURCE_PATH"
        exit 1
    fi
    
    # Create local destination directory if it doesn't exist
    if ! $is_destination_s3 && [ ! -d "$DESTINATION_PATH" ]; then
        log_info "Creating destination directory: $DESTINATION_PATH"
        mkdir -p "$DESTINATION_PATH"
        if [ $? -ne 0 ]; then
            log_error "Failed to create destination directory: $DESTINATION_PATH"
            exit 1
        fi
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
    
    local aws_cmd="aws"
    if [ -n "$PROFILE" ]; then
        aws_cmd+=" --profile $PROFILE"
    fi
    
    if ! $aws_cmd sts get-caller-identity &>/dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        if [ -n "$PROFILE" ]; then
            log_error "Profile '$PROFILE' may not exist or have invalid credentials"
        else
            log_error "Please configure AWS CLI with valid credentials:"
            log_error "  aws configure"
        fi
        exit 1
    fi
}

# Function to build aws s3 sync command
build_sync_command() {
    local cmd="aws s3 sync"
    
    # Add profile if specified
    if [ -n "$PROFILE" ]; then
        cmd+=" --profile $PROFILE"
    fi
    
    # Add region if specified
    if [ -n "$REGION" ]; then
        cmd+=" --region $REGION"
    fi
    
    # Add exclude patterns
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        cmd+=" --exclude \"$pattern\""
    done
    
    # Add include patterns
    for pattern in "${INCLUDE_PATTERNS[@]}"; do
        cmd+=" --include \"$pattern\""
    done
    
    # Add ACL if specified
    if [ -n "$ACL" ]; then
        cmd+=" --acl $ACL"
    fi
    
    # Add Cache-Control if specified
    if [ -n "$CACHE_CONTROL" ]; then
        cmd+=" --cache-control \"$CACHE_CONTROL\""
    fi
    
    # Add delete flag if specified
    if [ "$DELETE" = true ]; then
        cmd+=" --delete"
    fi
    
    # Add dry run flag if specified
    if [ "$DRY_RUN" = true ]; then
        cmd+=" --dryrun"
    fi
    
    # Add source and destination
    cmd+=" \"$SOURCE_PATH\" \"$DESTINATION_PATH\""
    
    # Add quiet or verbose flag
    if [ "$VERBOSE" = true ]; then
        cmd+=" --debug"
    else
        # Default to quiet mode if not verbose
        cmd+=" --only-show-errors"
    fi
    
    echo "$cmd"
}

# Function to extract bucket name from S3 path
get_bucket_from_path() {
    local s3_path="$1"
    
    # Remove s3:// prefix
    local path_without_prefix="${s3_path#s3://}"
    
    # Extract bucket name (everything before the first /)
    local bucket_name="${path_without_prefix%%/*}"
    
    echo "$bucket_name"
}

# Function to check if bucket exists
check_bucket_exists() {
    local bucket_name="$1"
    local aws_cmd="aws"
    
    if [ -n "$PROFILE" ]; then
        aws_cmd+=" --profile $PROFILE"
    fi
    
    if [ -n "$REGION" ]; then
        aws_cmd+=" --region $REGION"
    fi
    
    if ! $aws_cmd s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        return 1
    fi
    
    return 0
}

# Main execution
main() {
    parse_arguments "$@"
    check_aws_cli
    
    log_info "Starting S3 sync operation"
    
    # Check if source is S3
    if [[ "$SOURCE_PATH" == s3://* ]]; then
        local bucket_name
        bucket_name=$(get_bucket_from_path "$SOURCE_PATH")
        
        log_info "Checking source bucket: $bucket_name"
        if ! check_bucket_exists "$bucket_name"; then
            log_error "Source bucket does not exist or you don't have access: $bucket_name"
            exit 1
        fi
    fi
    
    # Check if destination is S3
    if [[ "$DESTINATION_PATH" == s3://* ]]; then
        local bucket_name
        bucket_name=$(get_bucket_from_path "$DESTINATION_PATH")
        
        log_info "Checking destination bucket: $bucket_name"
        if ! check_bucket_exists "$bucket_name"; then
            log_error "Destination bucket does not exist or you don't have access: $bucket_name"
            exit 1
        fi
    fi
    
    # Build and execute sync command
    local sync_cmd
    sync_cmd=$(build_sync_command)
    
    log_info "Syncing from $SOURCE_PATH to $DESTINATION_PATH"
    
    if [ "$VERBOSE" = true ]; then
        log_debug "Executing command: $sync_cmd"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE: No actual changes will be made"
    fi
    
    # Execute the command
    eval "$sync_cmd"
    
    local result=$?
    if [ $result -eq 0 ]; then
        if [ "$DRY_RUN" = true ]; then
            log_success "Dry run completed successfully"
        else
            log_success "Sync operation completed successfully"
        fi
    else
        log_error "Sync operation failed with exit code: $result"
        exit $result
    fi
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
