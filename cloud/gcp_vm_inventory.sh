#!/bin/bash
#
# gcp_vm_inventory.sh - Create detailed inventory of GCP virtual machines
#
# This script generates an inventory of Google Cloud Platform virtual machines
# with detailed information about machine types, zones, networks, and tags.
# It supports filtering by project, zone, and labels, with multiple output formats.
#
# Usage:
#   ./gcp_vm_inventory.sh [options]
#
# Options:
#   -p, --project <project-id>    GCP project ID
#   -z, --zone <zone>             Filter by zone
#   -r, --region <region>         Filter by region
#   -l, --label <key=value>       Filter by label (can be used multiple times)
#   -s, --status <status>         Filter by status (RUNNING, TERMINATED, etc.)
#   -o, --output <format>         Output format (table, csv, json, yaml; default: table)
#   -f, --file <filename>         Write output to file
#   --include-disks               Include disk information
#   --include-network             Include detailed network information
#   --include-metadata            Include VM metadata
#   --sort-by <field>             Sort results by field (name, zone, status, etc.)
#   -v, --verbose                 Display detailed output
#   -h, --help                    Display this help message
#
# Requirements:
#   - gcloud CLI installed and configured
#   - Valid GCP credentials with permissions to list compute instances
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
ZONE=""
REGION=""
LABELS=()
STATUS=""
OUTPUT_FORMAT="table"
OUTPUT_FILE=""
INCLUDE_DISKS=false
INCLUDE_NETWORK=false
INCLUDE_METADATA=false
SORT_BY="name"
VERBOSE=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Create detailed inventory of GCP virtual machines."
    echo ""
    echo "Options:"
    echo "  -p, --project <project-id>    GCP project ID"
    echo "  -z, --zone <zone>             Filter by zone"
    echo "  -r, --region <region>         Filter by region"
    echo "  -l, --label <key=value>       Filter by label (can be used multiple times)"
    echo "  -s, --status <status>         Filter by status (RUNNING, TERMINATED, etc.)"
    echo "  -o, --output <format>         Output format (table, csv, json, yaml; default: table)"
    echo "  -f, --file <filename>         Write output to file"
    echo "  --include-disks               Include disk information"
    echo "  --include-network             Include detailed network information"
    echo "  --include-metadata            Include VM metadata"
    echo "  --sort-by <field>             Sort results by field (name, zone, status, etc.)"
    echo "  -v, --verbose                 Display detailed output"
    echo "  -h, --help                    Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") -p my-project"
    echo "  $(basename "$0") -p my-project -z us-central1-a -o json"
    echo "  $(basename "$0") -p my-project -l environment=production -s RUNNING"
    echo "  $(basename "$0") -p my-project --include-disks --include-network -f inventory.csv -o csv"
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
            -s|--status)
                STATUS="$2"
                # Validate status
                case "${STATUS^^}" in
                    RUNNING|TERMINATED|STOPPING|PROVISIONING|REPAIRING|SUSPENDING|SUSPENDED)
                        STATUS="${STATUS^^}"
                        ;;
                    *)
                        log_error "Invalid status: $STATUS"
                        log_error "Valid statuses: RUNNING, TERMINATED, STOPPING, PROVISIONING, REPAIRING, SUSPENDING, SUSPENDED"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -o|--output)
                OUTPUT_FORMAT="$2"
                # Validate output format
                case "${OUTPUT_FORMAT,,}" in
                    table|csv|json|yaml)
                        OUTPUT_FORMAT="${OUTPUT_FORMAT,,}"
                        ;;
                    *)
                        log_error "Invalid output format: $OUTPUT_FORMAT"
                        log_error "Valid formats: table, csv, json, yaml"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -f|--file)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --include-disks)
                INCLUDE_DISKS=true
                shift
                ;;
            --include-network)
                INCLUDE_NETWORK=true
                shift
                ;;
            --include-metadata)
                INCLUDE_METADATA=true
                shift
                ;;
            --sort-by)
                SORT_BY="$2"
                shift 2
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
        log_error "  - Debian/Ubuntu: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
        log_error "  - RHEL/CentOS: sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc && sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm && sudo dnf install -y azure-cli"
        log_error "  - Fedora: sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc && sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm && sudo dnf install -y azure-cli"
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
    
    log_success "Successfully connected to project: $PROJECT_ID"
}

# Function to build filter string for gcloud command
build_filter() {
    local filter=""
    
    # Add status filter
    if [ -n "$STATUS" ]; then
        filter="status=${STATUS}"
    fi
    
    # Add label filters
    for label in "${LABELS[@]}"; do
        # Split label into key and value
        IFS='=' read -r key value <<< "$label"
        
        if [ -n "$key" ] && [ -n "$value" ]; then
            if [ -n "$filter" ]; then
                filter+=" AND "
            fi
            filter+="labels.${key}=${value}"
        fi
    done
    
    echo "$filter"
}

# Function to get VM instances
get_instances() {
    local project="$1"
    local zone="$2"
    local region="$3"
    local filter_str="$4"
    
    log_info "Retrieving VM instances"
    
    local cmd="gcloud compute instances list"
    cmd+=" --project=${project}"
    
    # Add zone or region filter
    if [ -n "$zone" ]; then
        cmd+=" --zones=${zone}"
    elif [ -n "$region" ]; then
        cmd+=" --filter=zone~^${region}"
    fi
    
    # Add custom filter
    if [ -n "$filter_str" ]; then
        if [[ "$cmd" == *"--filter"* ]]; then
            # Already has a filter, append with AND
            cmd="${cmd} AND ${filter_str}"
        else
            cmd+=" --filter=\"${filter_str}\""
        fi
    fi
    
    # Add format based on required fields
    local format_fields="NAME,ZONE,MACHINE_TYPE,INTERNAL_IP,EXTERNAL_IP,STATUS"
    
    if [ "$INCLUDE_DISKS" = true ]; then
        format_fields+=",DISK_SIZE_GB,DISK_TYPE"
    fi
    
    if [ "$INCLUDE_NETWORK" = true ]; then
        format_fields+=",NETWORK,SUBNET,NETWORK_TIER"
    fi
    
    # Add output format
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        cmd+=" --format=json"
    elif [ "$OUTPUT_FORMAT" = "yaml" ]; then
        cmd+=" --format=yaml"
    elif [ "$OUTPUT_FORMAT" = "csv" ]; then
        cmd+=" --format=csv[$format_fields]"
    else
        # Default to table
        cmd+=" --format=table[$format_fields]"
    fi
    
    # Add sorting
    if [ -n "$SORT_BY" ]; then
        if [ "$OUTPUT_FORMAT" = "json" ] || [ "$OUTPUT_FORMAT" = "yaml" ]; then
            # Sorting will be done later for JSON/YAML
            :
        else
            cmd+=" --sort-by=${SORT_BY}"
        fi
    fi
    
    if [ "$VERBOSE" = true ]; then
        log_debug "Executing command: $cmd"
    fi
    
    # Execute command
    local result
    result=$(eval "$cmd")
    
    echo "$result"
}

# Function to get instance metadata
get_instance_metadata() {
    local project="$1"
    local zone="$2"
    local instance="$3"
    
    log_info "Retrieving metadata for instance: $instance"
    
    local metadata
    metadata=$(gcloud compute instances describe "$instance" \
        --project="$project" \
        --zone="$zone" \
        --format=json)
    
    echo "$metadata"
}

# Function to process and format output
format_output() {
    local data="$1"
    local format="$2"
    local output_file="$3"
    
    # If output file is specified, write to file
    if [ -n "$output_file" ]; then
        log_info "Writing output to file: $output_file"
        echo "$data" > "$output_file"
        
        if [ $? -eq 0 ]; then
            log_success "Output written to file: $output_file"
        else
            log_error "Failed to write output to file: $output_file"
            return 1
        fi
    else
        # Otherwise, print to standard output
        echo "$data"
    fi
    
    return 0
}

# Function to enrich JSON output with additional metadata
enrich_json_output() {
    local instances_json="$1"
    local project="$2"
    
    if [ "$INCLUDE_METADATA" != true ]; then
        echo "$instances_json"
        return
    fi
    
    log_info "Enriching output with metadata"
    
    # Initialize array for enriched data
    local enriched_data="["
    local first_item=true
    
    # Process each instance
    while IFS= read -r instance_json; do
        local name=$(echo "$instance_json" | jq -r '.name')
        local zone=$(echo "$instance_json" | jq -r '.zone' | awk -F'/' '{print $NF}')
        
        log_info "Processing metadata for instance: $name in zone: $zone"
        
        # Get metadata
        local metadata
        metadata=$(get_instance_metadata "$project" "$zone" "$name")
        
        # Merge instance data with metadata
        local merged
        if [ "$first_item" = true ]; then
            first_item=false
        else
            enriched_data+=","
        fi
        
        enriched_data+="$metadata"
    done < <(echo "$instances_json" | jq -c '.[]')
    
    # Close the array
    enriched_data+="]"
    
    echo "$enriched_data"
}

# Main execution
main() {
    parse_arguments "$@"
    check_gcloud
    
    log_info "Starting GCP VM inventory for project: $PROJECT_ID"
    
    # Build filter string
    local filter_str
    filter_str=$(build_filter)
    
    # Get instances
    local instances_data
    instances_data=$(get_instances "$PROJECT_ID" "$ZONE" "$REGION" "$filter_str")
    
    # Handle JSON and YAML formats with metadata
    if [ "$OUTPUT_FORMAT" = "json" ] && [ "$INCLUDE_METADATA" = true ]; then
        instances_data=$(enrich_json_output "$instances_data" "$PROJECT_ID")
    fi
    
    # Format and output the data
    format_output "$instances_data" "$OUTPUT_FORMAT" "$OUTPUT_FILE"
    
    log_success "VM inventory completed successfully"
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi