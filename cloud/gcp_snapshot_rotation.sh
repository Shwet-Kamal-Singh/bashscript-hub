#!/bin/bash
#
# gcp_snapshot_rotation.sh - Manage GCP disk snapshots with rotation policy
#
# This script creates and rotates disk snapshots in Google Cloud Platform,
# maintaining a specified number of backups and cleaning up old snapshots.
#
# Usage:
#   ./gcp_snapshot_rotation.sh [options]
#
# Options:
#   -p, --project <project-id>    GCP project ID
#   -d, --disk <disk-name>        Disk name to snapshot
#   -z, --zone <zone>             Zone where the disk is located
#   -r, --region <region>         Region for regional disks
#   -l, --label <key=value>       Label to apply to snapshot (can be used multiple times)
#   -k, --keep <number>           Number of snapshots to keep (default: 7)
#   -s, --schedule <cron>         Create schedule for snapshots (uses gcloud scheduler)
#   -f, --filter <filter>         Filter for identifying snapshots to manage
#   -n, --dry-run                 Show what would be done without making changes
#   -v, --verbose                 Display detailed output
#   -h, --help                    Display this help message
#
# Requirements:
#   - gcloud CLI installed and configured
#   - Valid GCP credentials with permissions to manage disks and snapshots
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
PROJECT_ID=""
DISK_NAME=""
ZONE=""
REGION=""
LABELS=()
KEEP_COUNT=7
SCHEDULE=""
FILTER=""
DRY_RUN=false
VERBOSE=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Manage GCP disk snapshots with rotation policy."
    echo ""
    echo "Options:"
    echo "  -p, --project <project-id>    GCP project ID"
    echo "  -d, --disk <disk-name>        Disk name to snapshot"
    echo "  -z, --zone <zone>             Zone where the disk is located"
    echo "  -r, --region <region>         Region for regional disks"
    echo "  -l, --label <key=value>       Label to apply to snapshot (can be used multiple times)"
    echo "  -k, --keep <number>           Number of snapshots to keep (default: 7)"
    echo "  -s, --schedule <cron>         Create schedule for snapshots (uses gcloud scheduler)"
    echo "  -f, --filter <filter>         Filter for identifying snapshots to manage"
    echo "  -n, --dry-run                 Show what would be done without making changes"
    echo "  -v, --verbose                 Display detailed output"
    echo "  -h, --help                    Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") -p my-project -d my-disk -z us-central1-a -k 5"
    echo "  $(basename "$0") -p my-project -d my-disk -z us-central1-a -l environment=prod -l backup=daily"
    echo "  $(basename "$0") -p my-project -f \"name=disk-1-backup AND labels.type=automated\" -k 10"
    echo "  $(basename "$0") -p my-project -d my-disk -z us-central1-a -s \"0 3 * * *\" -k 7"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -d|--disk)
                DISK_NAME="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -l|--label)
                LABELS+=("$2")
                shift 2
                ;;
            -k|--keep)
                KEEP_COUNT="$2"
                if ! [[ "$KEEP_COUNT" =~ ^[0-9]+$ ]] || [ "$KEEP_COUNT" -lt 1 ]; then
                    log_error "Keep count must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -s|--schedule)
                SCHEDULE="$2"
                shift 2
                ;;
            -f|--filter)
                FILTER="$2"
                shift 2
                ;;
            -n|--dry-run)
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
    if [ -z "$PROJECT_ID" ]; then
        log_error "Project ID is required"
        show_usage
        exit 1
    fi
    
    # Either disk with zone/region or filter is required
    if [ -z "$DISK_NAME" ] && [ -z "$FILTER" ]; then
        log_error "Either disk name or filter is required"
        show_usage
        exit 1
    fi
    
    # Zone or region is required if disk is specified
    if [ -n "$DISK_NAME" ] && [ -z "$ZONE" ] && [ -z "$REGION" ]; then
        log_error "Either zone or region is required when disk is specified"
        show_usage
        exit 1
    fi
    
    # Cannot specify both zone and region
    if [ -n "$ZONE" ] && [ -n "$REGION" ]; then
        log_error "Cannot specify both zone and region"
        show_usage
        exit 1
    fi
}

# Function to check if gcloud CLI is installed and configured
check_gcloud() {
    if ! command -v gcloud &>/dev/null; then
        log_error "gcloud CLI is not installed or not in PATH"
        log_error "Please install Google Cloud SDK:"
        log_error "  - Debian/Ubuntu: sudo apt-get install google-cloud-sdk"
        log_error "  - RHEL/CentOS: sudo tee -a /etc/yum.repos.d/google-cloud-sdk.repo << EOM"
        log_error "    [google-cloud-sdk]"
        log_error "    name=Google Cloud SDK"
        log_error "    baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el7-x86_64"
        log_error "    enabled=1"
        log_error "    gpgcheck=1"
        log_error "    repo_gpgcheck=1"
        log_error "    gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg"
        log_error "    EOM"
        log_error "    sudo yum install google-cloud-sdk"
        log_error "  - or follow: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated and has access to the project
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Cannot access project: $PROJECT_ID"
        log_error "Make sure you are authenticated with gcloud and have access to the project:"
        log_error "  gcloud auth login"
        log_error "  gcloud config set project $PROJECT_ID"
        exit 1
    fi
    
    # Set project
    if ! gcloud config set project "$PROJECT_ID" &>/dev/null; then
        log_error "Failed to set project: $PROJECT_ID"
        exit 1
    fi
}

# Function to check if disk exists
check_disk_exists() {
    local disk_name="$1"
    local zone="$2"
    local region="$3"
    
    log_info "Checking if disk exists: $disk_name"
    
    if [ -n "$zone" ]; then
        # Check zonal disk
        if ! gcloud compute disks describe "$disk_name" --zone "$zone" &>/dev/null; then
            log_error "Disk does not exist: $disk_name in zone $zone"
            exit 1
        fi
    elif [ -n "$region" ]; then
        # Check regional disk
        if ! gcloud compute disks describe "$disk_name" --region "$region" &>/dev/null; then
            log_error "Disk does not exist: $disk_name in region $region"
            exit 1
        fi
    fi
    
    log_success "Disk exists: $disk_name"
}

# Function to create snapshot
create_snapshot() {
    local disk_name="$1"
    local zone="$2"
    local region="$3"
    local labels=("${@:4}")
    
    # Generate snapshot name with timestamp
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local snapshot_name="${disk_name}-${timestamp}"
    
    log_info "Creating snapshot: $snapshot_name"
    
    # Build snapshot command
    local cmd="gcloud compute snapshots create $snapshot_name"
    
    if [ -n "$zone" ]; then
        cmd+=" --source-disk $disk_name --source-disk-zone $zone"
    elif [ -n "$region" ]; then
        cmd+=" --source-disk $disk_name --source-disk-region $region"
    fi
    
    # Add labels
    for label in "${labels[@]}"; do
        cmd+=" --labels $label"
    fi
    
    # Add standard labels for tracking
    cmd+=" --labels source-disk=$disk_name,created-by=snapshot-rotation-script,created-at=$timestamp"
    
    # Add description
    cmd+=" --description \"Automated snapshot created by snapshot-rotation script on $(date)\""
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] Would execute: $cmd"
        return 0
    fi
    
    if [ "$VERBOSE" = true ]; then
        log_debug "Executing: $cmd"
    fi
    
    # Execute command
    if eval "$cmd"; then
        log_success "Snapshot created: $snapshot_name"
        return 0
    else
        log_error "Failed to create snapshot: $snapshot_name"
        return 1
    fi
}

# Function to list snapshots
list_snapshots() {
    local disk_name="$1"
    local filter="$2"
    
    log_info "Listing snapshots for disk: $disk_name"
    
    local filter_expr
    if [ -n "$filter" ]; then
        filter_expr="$filter"
    else
        filter_expr="labels.source-disk=$disk_name"
    fi
    
    # List snapshots with creation timestamp
    local snapshots
    snapshots=$(gcloud compute snapshots list --filter="$filter_expr" --format="json(name,creationTimestamp,diskSizeGb,storageBytes,sourceDisk)")
    
    echo "$snapshots"
}

# Function to cleanup old snapshots
cleanup_snapshots() {
    local snapshots_json="$1"
    local keep_count="$2"
    
    log_info "Cleaning up old snapshots (keeping $keep_count most recent)"
    
    # Check if we have any snapshots
    local snapshot_count
    snapshot_count=$(echo "$snapshots_json" | jq '. | length')
    
    if [ "$snapshot_count" -eq 0 ]; then
        log_warning "No snapshots found to clean up"
        return 0
    fi
    
    # Sort snapshots by creation time (newest first)
    local sorted_snapshots
    sorted_snapshots=$(echo "$snapshots_json" | jq 'sort_by(.creationTimestamp) | reverse')
    
    # Identify snapshots to keep and delete
    local snapshots_to_delete
    if [ "$snapshot_count" -le "$keep_count" ]; then
        log_info "Found $snapshot_count snapshots, keeping all (threshold: $keep_count)"
        return 0
    else
        # Get the snapshots to delete (everything after the keep count)
        snapshots_to_delete=$(echo "$sorted_snapshots" | jq ".[${keep_count}:] | map(.name)")
        local delete_count
        delete_count=$(echo "$snapshots_to_delete" | jq '. | length')
        
        log_info "Found $snapshot_count snapshots, deleting $delete_count, keeping $keep_count"
    fi
    
    # Delete old snapshots
    local success_count=0
    local error_count=0
    
    for snapshot in $(echo "$snapshots_to_delete" | jq -r '.[]'); do
        log_info "Deleting snapshot: $snapshot"
        
        if [ "$DRY_RUN" = true ]; then
            log_warning "[DRY RUN] Would delete snapshot: $snapshot"
            success_count=$((success_count + 1))
            continue
        fi
        
        if gcloud compute snapshots delete "$snapshot" --quiet; then
            log_success "Deleted snapshot: $snapshot"
            success_count=$((success_count + 1))
        else
            log_error "Failed to delete snapshot: $snapshot"
            error_count=$((error_count + 1))
        fi
    done
    
    log_info "Snapshot cleanup summary:"
    log_success "  Successful: $success_count"
    
    if [ $error_count -gt 0 ]; then
        log_error "  Failed: $error_count"
        return 1
    else
        log_info "  Failed: $error_count"
        return 0
    fi
}

# Function to create a snapshot schedule
create_snapshot_schedule() {
    local disk_name="$1"
    local zone="$2"
    local region="$3"
    local schedule="$4"
    local labels=("${@:5}")
    
    log_info "Creating snapshot schedule for disk: $disk_name"
    
    # Check if Cloud Scheduler API is enabled
    if ! gcloud services list --enabled --filter="name:cloudscheduler.googleapis.com" | grep -q "cloudscheduler.googleapis.com"; then
        log_warning "Cloud Scheduler API is not enabled. Enabling..."
        
        if [ "$DRY_RUN" = true ]; then
            log_warning "[DRY RUN] Would enable Cloud Scheduler API"
        else
            if ! gcloud services enable cloudscheduler.googleapis.com; then
                log_error "Failed to enable Cloud Scheduler API"
                log_error "Please enable it manually: gcloud services enable cloudscheduler.googleapis.com"
                return 1
            fi
        fi
    fi
    
    # Generate job ID
    local job_id="snapshot-${disk_name//[^a-zA-Z0-9]/-}"
    
    # Build labels string for command
    local labels_str=""
    for label in "${labels[@]}"; do
        labels_str+=" --labels $label"
    done
    
    # Create command to run this script
    local script_path=$(realpath "$0")
    local command="bash $script_path -p $PROJECT_ID -d $disk_name"
    
    if [ -n "$zone" ]; then
        command+=" -z $zone"
    elif [ -n "$region" ]; then
        command+=" -r $region"
    fi
    
    for label in "${labels[@]}"; do
        command+=" -l $label"
    done
    
    command+=" -k $KEEP_COUNT"
    
    # Check if job already exists
    if gcloud scheduler jobs describe "$job_id" &>/dev/null; then
        log_warning "Scheduler job already exists: $job_id"
        
        if [ "$DRY_RUN" = true ]; then
            log_warning "[DRY RUN] Would update scheduler job: $job_id"
            return 0
        fi
        
        # Update existing job
        if gcloud scheduler jobs update http "$job_id" --schedule "$schedule" --uri "https://us-central1-run.googleapis.com/v1/jobs/$job_id" --http-method POST --message-body "{\"command\":\"$command\"}" --oauth-service-account-email "$PROJECT_ID@appspot.gserviceaccount.com"; then
            log_success "Updated scheduler job: $job_id"
            return 0
        else
            log_error "Failed to update scheduler job: $job_id"
            return 1
        fi
    else
        if [ "$DRY_RUN" = true ]; then
            log_warning "[DRY RUN] Would create scheduler job: $job_id"
            return 0
        fi
        
        # Create new job
        if gcloud scheduler jobs create http "$job_id" --schedule "$schedule" --uri "https://us-central1-run.googleapis.com/v1/jobs/$job_id" --http-method POST --message-body "{\"command\":\"$command\"}" --oauth-service-account-email "$PROJECT_ID@appspot.gserviceaccount.com"; then
            log_success "Created scheduler job: $job_id"
            return 0
        else
            log_error "Failed to create scheduler job: $job_id"
            log_warning "Note: This may fail if you don't have Cloud Run API enabled or proper permissions"
            log_warning "Consider creating a cron job instead: "
            log_warning "  $schedule $command"
            return 1
        fi
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    check_gcloud
    
    log_info "Starting GCP snapshot rotation process"
    log_info "Project: $PROJECT_ID"
    
    if [ -n "$DISK_NAME" ]; then
        if [ -n "$ZONE" ]; then
            log_info "Disk: $DISK_NAME (Zone: $ZONE)"
        else
            log_info "Disk: $DISK_NAME (Region: $REGION)"
        fi
        
        # Check if disk exists
        check_disk_exists "$DISK_NAME" "$ZONE" "$REGION"
        
        # Create snapshot schedule if requested
        if [ -n "$SCHEDULE" ]; then
            log_info "Setting up snapshot schedule: \"$SCHEDULE\""
            create_snapshot_schedule "$DISK_NAME" "$ZONE" "$REGION" "$SCHEDULE" "${LABELS[@]}"
            exit $?
        fi
        
        # Create snapshot
        create_snapshot "$DISK_NAME" "$ZONE" "$REGION" "${LABELS[@]}"
        
        # List snapshots
        snapshots_json=$(list_snapshots "$DISK_NAME" "$FILTER")
    else
        # Working with filter only (cleanup mode)
        log_info "Using filter: $FILTER"
        
        # List snapshots based on filter
        snapshots_json=$(list_snapshots "" "$FILTER")
    fi
    
    # Check if we got valid JSON
    if ! echo "$snapshots_json" | jq . &>/dev/null; then
        log_error "Failed to list snapshots or invalid response"
        exit 1
    fi
    
    # Clean up old snapshots
    cleanup_snapshots "$snapshots_json" "$KEEP_COUNT"
    
    log_success "GCP snapshot rotation process completed"
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
