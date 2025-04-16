#!/bin/bash
#
# azure_vm_stats.sh - Collect and display Azure VM statistics
#
# This script collects statistics about Azure Virtual Machines, including
# resource usage, status, and configuration details.
#
# Usage:
#   ./azure_vm_stats.sh [options]
#
# Options:
#   -r, --resource-group <name>  Resource group name (default: all resource groups)
#   -n, --name <vm-name>         Specific VM name (default: all VMs)
#   -s, --subscription <id>      Subscription ID (default: current subscription)
#   -t, --time-range <range>     Time range for metrics (default: 1h, format: 1h, 1d, 7d)
#   -m, --metrics <metrics>      Metrics to display (comma-separated, default: CPU,Memory,Disk,Network)
#   -o, --output <format>        Output format (table, json, csv, default: table)
#   -f, --output-file <file>     Save output to file
#   --sort <column>              Sort by column (name, group, size, state, CPU, default: name)
#   -v, --verbose                Display detailed output
#   -h, --help                   Display this help message
#
# Requirements:
#   - Azure CLI installed and configured
#   - Valid Azure credentials with VM permissions
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
RESOURCE_GROUP=""
VM_NAME=""
SUBSCRIPTION_ID=""
TIME_RANGE="1h"
METRICS="CPU,Memory,Disk,Network"
OUTPUT_FORMAT="table"
OUTPUT_FILE=""
SORT_COLUMN="name"
VERBOSE=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Collect and display Azure VM statistics."
    echo ""
    echo "Options:"
    echo "  -r, --resource-group <name>  Resource group name (default: all resource groups)"
    echo "  -n, --name <vm-name>         Specific VM name (default: all VMs)"
    echo "  -s, --subscription <id>      Subscription ID (default: current subscription)"
    echo "  -t, --time-range <range>     Time range for metrics (default: 1h, format: 1h, 1d, 7d)"
    echo "  -m, --metrics <metrics>      Metrics to display (comma-separated, default: CPU,Memory,Disk,Network)"
    echo "  -o, --output <format>        Output format (table, json, csv, default: table)"
    echo "  -f, --output-file <file>     Save output to file"
    echo "  --sort <column>              Sort by column (name, group, size, state, CPU, default: name)"
    echo "  -v, --verbose                Display detailed output"
    echo "  -h, --help                   Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")"
    echo "  $(basename "$0") -r myresourcegroup -t 24h"
    echo "  $(basename "$0") -n myvm -m CPU,Memory -o json"
    echo "  $(basename "$0") --sort CPU -f vm-stats.txt"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -r|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -n|--name)
                VM_NAME="$2"
                shift 2
                ;;
            -s|--subscription)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            -t|--time-range)
                TIME_RANGE="$2"
                # Validate time range format
                if ! [[ "$TIME_RANGE" =~ ^[0-9]+[hd]$ ]]; then
                    log_error "Invalid time range format: $TIME_RANGE"
                    log_error "Valid formats: 1h, 12h, 1d, 7d"
                    exit 1
                fi
                shift 2
                ;;
            -m|--metrics)
                METRICS="$2"
                # Convert to uppercase for consistency
                METRICS="${METRICS^^}"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FORMAT="$2"
                # Validate output format
                case "$OUTPUT_FORMAT" in
                    table|json|csv)
                        # Valid formats
                        ;;
                    *)
                        log_error "Invalid output format: $OUTPUT_FORMAT"
                        log_error "Valid formats: table, json, csv"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -f|--output-file)
                OUTPUT_FILE="$2"
                # Check if file is writable
                touch "$OUTPUT_FILE" 2>/dev/null
                if [ $? -ne 0 ]; then
                    log_error "Cannot write to output file: $OUTPUT_FILE"
                    exit 1
                fi
                shift 2
                ;;
            --sort)
                SORT_COLUMN="$2"
                # Validate sort column
                case "${SORT_COLUMN,,}" in
                    name|group|size|state|cpu)
                        # Valid columns, convert to lowercase
                        SORT_COLUMN="${SORT_COLUMN,,}"
                        ;;
                    *)
                        log_error "Invalid sort column: $SORT_COLUMN"
                        log_error "Valid columns: name, group, size, state, CPU"
                        exit 1
                        ;;
                esac
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
    
    # Get current subscription ID for reference
    CURRENT_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    CURRENT_SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    
    log_info "Using subscription: $CURRENT_SUBSCRIPTION_NAME ($CURRENT_SUBSCRIPTION_ID)"
}

# Function to get VMs to analyze
get_vms() {
    local resource_group="$1"
    local vm_name="$2"
    
    log_info "Getting virtual machines"
    
    local query_cmd="az vm list"
    
    # Apply resource group filter if specified
    if [ -n "$resource_group" ]; then
        query_cmd+=" --resource-group $resource_group"
    else
        query_cmd+=" --all"
    fi
    
    # Apply VM name filter if specified
    if [ -n "$vm_name" ]; then
        query_cmd+=" --query \"[?name=='$vm_name']\""
    fi
    
    # Add output format
    query_cmd+=" --query \"[].{name:name, resourceGroup:resourceGroup, size:hardwareProfile.vmSize, location:location, osType:storageProfile.osDisk.osType, id:id, powerState: powerState}\""
    query_cmd+=" -o json"
    
    if [ "$VERBOSE" = true ]; then
        log_debug "Executing: $query_cmd"
    fi
    
    # Execute query
    local vms
    vms=$(eval "$query_cmd")
    
    if [ -z "$vms" ] || [ "$vms" = "[]" ]; then
        log_error "No VMs found matching the criteria"
        exit 1
    fi
    
    echo "$vms"
}

# Function to get VM metrics
get_vm_metrics() {
    local vm_id="$1"
    local time_range="$2"
    local metrics="$3"
    
    # Set time interval based on time range
    local time_interval="PT5M"  # 5 minutes by default
    
    if [[ "$time_range" =~ ^[0-9]+d$ ]]; then
        # For days, use hourly intervals
        time_interval="PT1H"
    elif [[ "$time_range" =~ ^[0-9]+h$ ]]; then
        # For hours > 6, use 15-minute intervals
        if [ "${time_range%h}" -gt 6 ]; then
            time_interval="PT15M"
        fi
    fi
    
    # Parse time range to ISO8601 format for Azure CLI
    local time_value="${time_range%[hd]}"
    local time_unit="${time_range: -1}"
    local time_string
    
    if [ "$time_unit" = "h" ]; then
        time_string="PT${time_value}H"
    else
        time_string="P${time_value}D"
    fi
    
    # Prepare metrics to collect
    local metric_names=""
    
    # Check each requested metric
    if [[ "$metrics" == *"CPU"* ]]; then
        metric_names+="Percentage CPU,"
    fi
    
    if [[ "$metrics" == *"MEMORY"* ]]; then
        metric_names+="Available Memory Bytes,"
    fi
    
    if [[ "$metrics" == *"DISK"* ]]; then
        metric_names+="Disk Read Operations/Sec,Disk Write Operations/Sec,"
    fi
    
    if [[ "$metrics" == *"NETWORK"* ]]; then
        metric_names+="Network In Total,Network Out Total,"
    fi
    
    # Remove trailing comma
    metric_names="${metric_names%,}"
    
    if [ -z "$metric_names" ]; then
        log_error "No valid metrics specified"
        exit 1
    fi
    
    if [ "$VERBOSE" = true ]; then
        log_debug "Getting metrics for VM: $vm_id"
        log_debug "Time range: $time_string, Interval: $time_interval"
        log_debug "Metrics: $metric_names"
    fi
    
    # Get metrics
    local metrics_data
    metrics_data=$(az monitor metrics list --resource "$vm_id" --metric "$metric_names" --interval "$time_interval" --time-grain "$time_interval" --start-time "-$time_string" -o json)
    
    echo "$metrics_data"
}

# Function to process VM metrics data
process_vm_metrics() {
    local vm_data="$1"
    local metrics_data="$2"
    
    # Extract basic VM info
    local vm_name=$(echo "$vm_data" | jq -r '.name')
    local resource_group=$(echo "$vm_data" | jq -r '.resourceGroup')
    local vm_size=$(echo "$vm_data" | jq -r '.size')
    local location=$(echo "$vm_data" | jq -r '.location')
    local os_type=$(echo "$vm_data" | jq -r '.osType')
    local power_state=$(echo "$vm_data" | jq -r '.powerState')
    
    # Extract metrics
    local cpu_avg="N/A"
    local memory_avg="N/A"
    local disk_read_avg="N/A"
    local disk_write_avg="N/A"
    local network_in_avg="N/A"
    local network_out_avg="N/A"
    
    # Process each metric
    while read -r metric_name; do
        # Skip if no metric name
        if [ -z "$metric_name" ]; then
            continue
        fi
        
        # Get average value for the metric
        local avg_value
        avg_value=$(echo "$metrics_data" | jq --arg name "$metric_name" '.value[] | select(.name.value == $name) | .timeseries[0].data | map(select(.average != null)) | if length > 0 then (map(.average) | add / length) else null end')
        
        # Check if we got a valid average value
        if [ "$avg_value" = "null" ] || [ -z "$avg_value" ]; then
            avg_value="N/A"
        else
            # Round to 2 decimal places
            avg_value=$(printf "%.2f" "$avg_value")
        fi
        
        # Assign to appropriate variable
        case "$metric_name" in
            "Percentage CPU")
                cpu_avg="$avg_value"
                ;;
            "Available Memory Bytes")
                # Convert to GB if it's a number
                if [ "$avg_value" != "N/A" ]; then
                    memory_avg=$(echo "scale=2; $avg_value / 1024 / 1024 / 1024" | bc)
                    memory_avg="${memory_avg}GB"
                else
                    memory_avg="N/A"
                fi
                ;;
            "Disk Read Operations/Sec")
                disk_read_avg="$avg_value"
                ;;
            "Disk Write Operations/Sec")
                disk_write_avg="$avg_value"
                ;;
            "Network In Total")
                # Convert to MB if it's a number
                if [ "$avg_value" != "N/A" ]; then
                    network_in_avg=$(echo "scale=2; $avg_value / 1024 / 1024" | bc)
                    network_in_avg="${network_in_avg}MB"
                else
                    network_in_avg="N/A"
                fi
                ;;
            "Network Out Total")
                # Convert to MB if it's a number
                if [ "$avg_value" != "N/A" ]; then
                    network_out_avg=$(echo "scale=2; $avg_value / 1024 / 1024" | bc)
                    network_out_avg="${network_out_avg}MB"
                else
                    network_out_avg="N/A"
                fi
                ;;
        esac
    done < <(echo "$metrics_data" | jq -r '.value[].name.value')
    
    # Combine disk metrics
    local disk_avg
    if [ "$disk_read_avg" != "N/A" ] && [ "$disk_write_avg" != "N/A" ]; then
        disk_avg="R:${disk_read_avg} W:${disk_write_avg}"
    else
        disk_avg="N/A"
    fi
    
    # Combine network metrics
    local network_avg
    if [ "$network_in_avg" != "N/A" ] && [ "$network_out_avg" != "N/A" ]; then
        network_avg="In:${network_in_avg} Out:${network_out_avg}"
    else
        network_avg="N/A"
    fi
    
    # Create result object
    local result
    result=$(jq -n \
        --arg name "$vm_name" \
        --arg group "$resource_group" \
        --arg size "$vm_size" \
        --arg location "$location" \
        --arg os_type "$os_type" \
        --arg state "$power_state" \
        --arg cpu "$cpu_avg" \
        --arg memory "$memory_avg" \
        --arg disk "$disk_avg" \
        --arg network "$network_avg" \
        '{name: $name, group: $group, size: $size, location: $location, osType: $os_type, state: $state, cpu: $cpu, memory: $memory, disk: $disk, network: $network}')
    
    echo "$result"
}

# Function to format output
format_output() {
    local data="$1"
    local format="$2"
    local sort_by="$3"
    
    # Convert sort column to jq field name
    local sort_field
    case "$sort_by" in
        name) sort_field=".name" ;;
        group) sort_field=".group" ;;
        size) sort_field=".size" ;;
        state) sort_field=".state" ;;
        cpu) 
            # Sort by CPU numerically if possible
            sort_field='(if .cpu == "N/A" then 0 else (.cpu | tonumber) end)'
            ;;
        *) sort_field=".name" ;;
    esac
    
    # Sort the data
    local sorted_data
    sorted_data=$(echo "$data" | jq -s "sort_by($sort_field)")
    
    # Format according to requested output format
    case "$format" in
        json)
            echo "$sorted_data"
            ;;
        csv)
            # Create CSV header
            echo "Name,Resource Group,Size,Location,OS Type,State,CPU %,Memory,Disk IOPS,Network"
            
            # Create CSV rows
            echo "$sorted_data" | jq -r '.[] | [.name, .group, .size, .location, .osType, .state, .cpu, .memory, .disk, .network] | @csv'
            ;;
        table|*)
            # Create table header
            printf "%-20s %-20s %-15s %-10s %-10s %-10s %-10s %-15s %-20s %-25s\n" \
                "NAME" "RESOURCE GROUP" "SIZE" "LOCATION" "OS TYPE" "STATE" "CPU %" "MEMORY" "DISK IOPS" "NETWORK"
            
            # Create separator line
            printf "%.s-" {1..150}
            printf "\n"
            
            # Create table rows
            while read -r vm; do
                local name=$(echo "$vm" | jq -r '.name')
                local group=$(echo "$vm" | jq -r '.group')
                local size=$(echo "$vm" | jq -r '.size')
                local location=$(echo "$vm" | jq -r '.location')
                local os_type=$(echo "$vm" | jq -r '.osType')
                local state=$(echo "$vm" | jq -r '.state')
                local cpu=$(echo "$vm" | jq -r '.cpu')
                local memory=$(echo "$vm" | jq -r '.memory')
                local disk=$(echo "$vm" | jq -r '.disk')
                local network=$(echo "$vm" | jq -r '.network')
                
                printf "%-20s %-20s %-15s %-10s %-10s %-10s %-10s %-15s %-20s %-25s\n" \
                    "$name" "$group" "$size" "$location" "$os_type" "$state" "$cpu" "$memory" "$disk" "$network"
            done < <(echo "$sorted_data" | jq -c '.[]')
            ;;
    esac
}

# Main execution
main() {
    parse_arguments "$@"
    check_azure_cli
    
    log_info "Starting Azure VM statistics collection"
    
    # Get VMs to analyze
    vms_json=$(get_vms "$RESOURCE_GROUP" "$VM_NAME")
    vm_count=$(echo "$vms_json" | jq '. | length')
    
    log_info "Found $vm_count VM(s) to analyze"
    
    # Process each VM
    all_results=()
    
    for i in $(seq 0 $((vm_count-1))); do
        vm_data=$(echo "$vms_json" | jq ".[$i]")
        vm_id=$(echo "$vm_data" | jq -r '.id')
        vm_name=$(echo "$vm_data" | jq -r '.name')
        
        log_info "Analyzing VM $((i+1))/$vm_count: $vm_name"
        
        # Get metrics for the VM
        metrics_data=$(get_vm_metrics "$vm_id" "$TIME_RANGE" "$METRICS")
        
        # Process metrics
        result=$(process_vm_metrics "$vm_data" "$metrics_data")
        
        all_results+=("$result")
    done
    
    # Combine all results
    combined_results=$(printf "%s\n" "${all_results[@]}" | jq -s '.')
    
    # Format output
    formatted_output=$(format_output "$combined_results" "$OUTPUT_FORMAT" "$SORT_COLUMN")
    
    # Output results
    if [ -n "$OUTPUT_FILE" ]; then
        echo "$formatted_output" > "$OUTPUT_FILE"
        log_success "Results saved to: $OUTPUT_FILE"
    else
        echo "$formatted_output"
    fi
    
    log_success "Azure VM statistics collection completed successfully"
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
