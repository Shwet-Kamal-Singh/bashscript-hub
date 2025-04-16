#!/bin/bash
#
# azure_blob_cleanup.sh - Clean up old blobs in Azure Storage containers
#
# This script helps manage Azure Storage by removing or archiving old blobs
# based on age, prefix, and other criteria.
#
# Usage:
#   ./azure_blob_cleanup.sh [options]
#
# Options:
#   -a, --account <name>       Storage account name
#   -c, --container <name>     Container name
#   -d, --days <number>        Delete blobs older than specified days
#   -p, --prefix <prefix>      Only process blobs with this prefix
#   -t, --tier <tier>          Move to specified access tier instead of deleting (Hot, Cool, Archive)
#   -k, --keep <number>        Keep the most recent N blobs matching criteria
#   -r, --resource-group <name> Resource group name (for authentication with Azure CLI)
#   -s, --subscription <id>    Subscription ID (for authentication with Azure CLI)
#   -f, --force                Skip confirmation prompt
#   --dry-run                  Show what would be done without making changes
#   -v, --verbose              Display detailed output
#   -h, --help                 Display this help message
#
# Requirements:
#   - Azure CLI installed and configured
#   - Valid Azure credentials with Storage permissions
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
STORAGE_ACCOUNT=""
CONTAINER_NAME=""
OLDER_THAN_DAYS=0
BLOB_PREFIX=""
ACCESS_TIER=""
KEEP_LATEST=0
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
FORCE=false
DRY_RUN=false
VERBOSE=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Clean up old blobs in Azure Storage containers."
    echo ""
    echo "Options:"
    echo "  -a, --account <name>       Storage account name"
    echo "  -c, --container <name>     Container name"
    echo "  -d, --days <number>        Delete blobs older than specified days"
    echo "  -p, --prefix <prefix>      Only process blobs with this prefix"
    echo "  -t, --tier <tier>          Move to specified access tier instead of deleting (Hot, Cool, Archive)"
    echo "  -k, --keep <number>        Keep the most recent N blobs matching criteria"
    echo "  -r, --resource-group <name> Resource group name (for authentication with Azure CLI)"
    echo "  -s, --subscription <id>    Subscription ID (for authentication with Azure CLI)"
    echo "  -f, --force                Skip confirmation prompt"
    echo "  --dry-run                  Show what would be done without making changes"
    echo "  -v, --verbose              Display detailed output"
    echo "  -h, --help                 Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") -a mystorageaccount -c mycontainer -d 30"
    echo "  $(basename "$0") -a mystorageaccount -c backups -p \"backup-\" -d 90 -k 5"
    echo "  $(basename "$0") -a mystorageaccount -c logs -d 60 -t Archive -r myresourcegroup"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -a|--account)
                STORAGE_ACCOUNT="$2"
                shift 2
                ;;
            -c|--container)
                CONTAINER_NAME="$2"
                shift 2
                ;;
            -d|--days)
                OLDER_THAN_DAYS="$2"
                if ! [[ "$OLDER_THAN_DAYS" =~ ^[0-9]+$ ]] || [ "$OLDER_THAN_DAYS" -lt 1 ]; then
                    log_error "Days must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -p|--prefix)
                BLOB_PREFIX="$2"
                shift 2
                ;;
            -t|--tier)
                ACCESS_TIER="$2"
                # Validate access tier
                case "${ACCESS_TIER,,}" in
                    hot|cool|archive)
                        # Capitalize first letter for Azure CLI
                        ACCESS_TIER="${ACCESS_TIER^}"
                        ;;
                    *)
                        log_error "Invalid access tier: $ACCESS_TIER"
                        log_error "Valid tiers: Hot, Cool, Archive"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -k|--keep)
                KEEP_LATEST="$2"
                if ! [[ "$KEEP_LATEST" =~ ^[0-9]+$ ]]; then
                    log_error "Keep count must be a non-negative integer"
                    exit 1
                fi
                shift 2
                ;;
            -r|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -s|--subscription)
                SUBSCRIPTION_ID="$2"
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
    if [ -z "$STORAGE_ACCOUNT" ]; then
        log_error "Storage account name is required"
        show_usage
        exit 1
    fi
    
    if [ -z "$CONTAINER_NAME" ]; then
        log_error "Container name is required"
        show_usage
        exit 1
    fi
    
    if [ "$OLDER_THAN_DAYS" -eq 0 ] && [ "$KEEP_LATEST" -eq 0 ]; then
        log_error "Either days (-d) or keep count (-k) must be specified"
        show_usage
        exit 1
    fi
}

# Function to check if Azure CLI is installed and configured
check_azure_cli() {
    if ! command -v az &>/dev/null; then
        log_error "Azure CLI is not installed or not in PATH"
        log_error "Please install Azure CLI:"
        log_error "  - Debian/Ubuntu: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
        log_error "  - RHEL/CentOS: sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc && sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm && sudo dnf install -y azure-cli"
        log_error "  - Fedora: sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc && sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm && sudo dnf install -y azure-cli"
        log_error "  - or follow: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &>/dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Set subscription if specified
    if [ -n "$SUBSCRIPTION_ID" ]; then
        log_info "Setting Azure subscription to: $SUBSCRIPTION_ID"
        if ! az account set --subscription "$SUBSCRIPTION_ID"; then
            log_error "Failed to set subscription: $SUBSCRIPTION_ID"
            exit 1
        fi
    fi
}

# Function to check if storage account and container exist
check_storage_container() {
    local account="$1"
    local container="$2"
    local resource_group="$3"
    
    log_info "Checking storage account and container"
    
    local account_exists=false
    
    # Check if resource group is provided
    if [ -n "$resource_group" ]; then
        if az storage account show --name "$account" --resource-group "$resource_group" &>/dev/null; then
            account_exists=true
        fi
    else
        # Try to find the storage account without resource group
        if az storage account show --name "$account" &>/dev/null; then
            account_exists=true
        fi
    fi
    
    if [ "$account_exists" = false ]; then
        log_error "Storage account does not exist or you don't have access: $account"
        exit 1
    fi
    
    # Get storage account key
    local account_key=""
    if [ -n "$resource_group" ]; then
        account_key=$(az storage account keys list --account-name "$account" --resource-group "$resource_group" --query "[0].value" -o tsv)
    else
        account_key=$(az storage account keys list --account-name "$account" --query "[0].value" -o tsv)
    fi
    
    if [ -z "$account_key" ]; then
        log_error "Failed to retrieve storage account key"
        exit 1
    fi
    
    # Check if container exists
    if ! az storage container show --name "$container" --account-name "$account" --account-key "$account_key" &>/dev/null; then
        log_error "Container does not exist or you don't have access: $container"
        exit 1
    fi
    
    log_success "Storage account and container verified"
    echo "$account_key"
}

# Function to list blobs to process
list_blobs() {
    local account="$1"
    local container="$2"
    local account_key="$3"
    local prefix="$4"
    local days="$5"
    
    log_info "Listing blobs in container: $container"
    
    local cutoff_date=""
    if [ "$days" -gt 0 ]; then
        # Calculate cutoff date
        if command -v gdate &>/dev/null; then
            # macOS with GNU date installed as gdate
            cutoff_date=$(gdate -d "$days days ago" +%Y-%m-%dT%H:%M:%SZ)
        else
            # Linux
            cutoff_date=$(date -d "$days days ago" +%Y-%m-%dT%H:%M:%SZ)
        fi
        
        log_info "Cutoff date: $cutoff_date (older than $days days)"
    fi
    
    # List all blobs with prefix
    local all_blobs=""
    if [ -n "$prefix" ]; then
        all_blobs=$(az storage blob list --container-name "$container" --account-name "$account" --account-key "$account_key" --prefix "$prefix" --query "[].{name:name, lastModified:properties.lastModified}" -o json)
    else
        all_blobs=$(az storage blob list --container-name "$container" --account-name "$account" --account-key "$account_key" --query "[].{name:name, lastModified:properties.lastModified}" -o json)
    fi
    
    if [ -z "$all_blobs" ] || [ "$all_blobs" = "[]" ]; then
        log_warning "No blobs found in container: $container"
        echo "[]"
        return
    fi
    
    # Filter by date if days is specified
    if [ "$days" -gt 0 ]; then
        log_info "Filtering blobs older than $days days"
        
        # Use jq to filter by date if available
        if command -v jq &>/dev/null; then
            filtered_blobs=$(echo "$all_blobs" | jq --arg date "$cutoff_date" '[.[] | select(.lastModified < $date)]')
        else
            # Fallback without jq - this will work but is less reliable
            filtered_blobs="["
            filtered_count=0
            
            # Process each blob
            while read -r name last_modified; do
                # Remove quotes from name and lastModified
                name="${name%\"}"
                name="${name#\"}"
                last_modified="${last_modified%\"}"
                last_modified="${last_modified#\"}"
                
                # Compare dates
                if [[ "$last_modified" < "$cutoff_date" ]]; then
                    if [ "$filtered_count" -gt 0 ]; then
                        filtered_blobs+=","
                    fi
                    filtered_blobs+="{\"name\":\"$name\",\"lastModified\":\"$last_modified\"}"
                    filtered_count=$((filtered_count + 1))
                fi
            done < <(echo "$all_blobs" | grep -o '"name": "[^"]*"' | awk -F': ' '{print $2}' | paste -d' ' - <(echo "$all_blobs" | grep -o '"lastModified": "[^"]*"' | awk -F': ' '{print $2}'))
            
            filtered_blobs+="]"
        fi
    else
        filtered_blobs="$all_blobs"
    fi
    
    echo "$filtered_blobs"
}

# Function to exclude the most recent N blobs
exclude_recent_blobs() {
    local blobs_json="$1"
    local keep_count="$2"
    
    if [ "$keep_count" -eq 0 ]; then
        # No need to exclude any blobs
        echo "$blobs_json"
        return
    fi
    
    log_info "Keeping $keep_count most recent blobs"
    
    # Use jq to sort by date and exclude most recent if available
    if command -v jq &>/dev/null; then
        excluded_blobs=$(echo "$blobs_json" | jq --arg keep "$keep_count" 'sort_by(.lastModified) | .[0:-(($keep|tonumber))]')
    else
        # Fallback without jq - this is very basic and may not work for all cases
        # Convert to lines, sort by date, and remove most recent N
        all_lines=""
        while read -r name last_modified; do
            # Remove quotes from name and lastModified
            name="${name%\"}"
            name="${name#\"}"
            last_modified="${last_modified%\"}"
            last_modified="${last_modified#\"}"
            
            all_lines+="$last_modified $name\n"
        done < <(echo "$blobs_json" | grep -o '"name": "[^"]*"' | awk -F': ' '{print $2}' | paste -d' ' - <(echo "$blobs_json" | grep -o '"lastModified": "[^"]*"' | awk -F': ' '{print $2}'))
        
        # Sort by date (oldest first) and exclude most recent
        sorted_lines=$(echo -e "$all_lines" | sort)
        total_lines=$(echo -e "$sorted_lines" | wc -l)
        keep_lines=$((total_lines - keep_count))
        
        if [ "$keep_lines" -le 0 ]; then
            # If keep count is >= total, return empty array
            echo "[]"
            return
        fi
        
        # Build JSON array from lines
        excluded_blobs="["
        excluded_count=0
        
        while read -r line; do
            if [ "$excluded_count" -ge "$keep_lines" ]; then
                break
            fi
            
            last_modified=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
            
            if [ "$excluded_count" -gt 0 ]; then
                excluded_blobs+=","
            fi
            excluded_blobs+="{\"name\":\"$name\",\"lastModified\":\"$last_modified\"}"
            excluded_count=$((excluded_count + 1))
        done < <(echo -e "$sorted_lines")
        
        excluded_blobs+="]"
    fi
    
    echo "$excluded_blobs"
}

# Function to confirm action with user
confirm_action() {
    local blobs_json="$1"
    local action="$2"
    
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    local blob_count=$(echo "$blobs_json" | grep -o '"name"' | wc -l)
    
    echo "You are about to $action $blob_count blob(s) from container: $CONTAINER_NAME"
    echo ""
    
    # Show a preview of blobs (limited to 10)
    echo "Preview of blobs to $action:"
    count=0
    while read -r name; do
        if [ "$count" -ge 10 ]; then
            echo "... and $((blob_count - 10)) more"
            break
        fi
        
        # Remove quotes from name
        name="${name%\"}"
        name="${name#\"}"
        echo "  - $name"
        count=$((count + 1))
    done < <(echo "$blobs_json" | grep -o '"name": "[^"]*"' | awk -F': ' '{print $2}')
    
    echo ""
    read -p "Do you want to continue? (y/N): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
}

# Function to process blobs (delete or change tier)
process_blobs() {
    local account="$1"
    local container="$2"
    local account_key="$3"
    local blobs_json="$4"
    local tier="$5"
    
    local action="deleting"
    if [ -n "$tier" ]; then
        action="moving to $tier tier"
    fi
    
    log_info "Processing blobs: $action"
    
    local success_count=0
    local error_count=0
    
    while read -r name; do
        # Remove quotes from name
        name="${name%\"}"
        name="${name#\"}"
        
        if [ "$DRY_RUN" = true ]; then
            log_warning "[DRY RUN] Would $action blob: $name"
            success_count=$((success_count + 1))
            continue
        fi
        
        if [ -n "$tier" ]; then
            # Change access tier
            if [ "$VERBOSE" = true ]; then
                log_debug "Changing tier of blob: $name to $tier"
            fi
            
            if az storage blob set-tier --container-name "$container" --name "$name" --tier "$tier" --account-name "$account" --account-key "$account_key" &>/dev/null; then
                success_count=$((success_count + 1))
                
                if [ "$VERBOSE" = true ]; then
                    log_success "Changed tier of blob: $name to $tier"
                fi
            else
                error_count=$((error_count + 1))
                log_error "Failed to change tier of blob: $name"
            fi
        else
            # Delete blob
            if [ "$VERBOSE" = true ]; then
                log_debug "Deleting blob: $name"
            fi
            
            if az storage blob delete --container-name "$container" --name "$name" --account-name "$account" --account-key "$account_key" &>/dev/null; then
                success_count=$((success_count + 1))
                
                if [ "$VERBOSE" = true ]; then
                    log_success "Deleted blob: $name"
                fi
            else
                error_count=$((error_count + 1))
                log_error "Failed to delete blob: $name"
            fi
        fi
    done < <(echo "$blobs_json" | grep -o '"name": "[^"]*"' | awk -F': ' '{print $2}')
    
    log_info "Blob processing summary:"
    log_success "  Successful: $success_count"
    
    if [ $error_count -gt 0 ]; then
        log_error "  Failed: $error_count"
    else
        log_info "  Failed: $error_count"
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    check_azure_cli
    
    log_info "Starting Azure blob cleanup process"
    log_info "Storage account: $STORAGE_ACCOUNT"
    log_info "Container: $CONTAINER_NAME"
    
    if [ -n "$RESOURCE_GROUP" ]; then
        log_info "Resource group: $RESOURCE_GROUP"
    fi
    
    if [ -n "$BLOB_PREFIX" ]; then
        log_info "Blob prefix: $BLOB_PREFIX"
    fi
    
    # Check if storage account and container exist
    local account_key
    account_key=$(check_storage_container "$STORAGE_ACCOUNT" "$CONTAINER_NAME" "$RESOURCE_GROUP")
    
    # List blobs to process
    blobs_json=$(list_blobs "$STORAGE_ACCOUNT" "$CONTAINER_NAME" "$account_key" "$BLOB_PREFIX" "$OLDER_THAN_DAYS")
    
    # Exclude most recent blobs if requested
    if [ "$KEEP_LATEST" -gt 0 ]; then
        blobs_json=$(exclude_recent_blobs "$blobs_json" "$KEEP_LATEST")
    fi
    
    # Check if there are any blobs to process
    if [ "$blobs_json" = "[]" ] || [ -z "$blobs_json" ]; then
        log_info "No blobs found matching the criteria"
        exit 0
    fi
    
    # Count blobs to process
    local blob_count
    blob_count=$(echo "$blobs_json" | grep -o '"name"' | wc -l)
    
    log_info "Found $blob_count blob(s) to process"
    
    # Determine action
    local action="delete"
    if [ -n "$ACCESS_TIER" ]; then
        action="move to $ACCESS_TIER tier"
    fi
    
    # Confirm with user
    confirm_action "$blobs_json" "$action"
    
    # Process blobs
    process_blobs "$STORAGE_ACCOUNT" "$CONTAINER_NAME" "$account_key" "$blobs_json" "$ACCESS_TIER"
    
    if [ "$DRY_RUN" = true ]; then
        log_success "Dry run completed successfully"
    else
        log_success "Blob cleanup process completed successfully"
    fi
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
