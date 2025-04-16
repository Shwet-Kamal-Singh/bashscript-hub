#!/bin/bash
#
# docker_monitor.sh - Monitor Docker containers and system resources
#
# This script monitors Docker containers and system resources, providing
# information about container status, resource usage, and system health.
#
# Usage:
#   ./docker_monitor.sh [options]
#
# Options:
#   -c, --containers         Show container information (default)
#   -i, --images             Show image information
#   -v, --volumes            Show volume information
#   -n, --networks           Show network information
#   -s, --system             Show system-wide Docker information
#   -r, --resources          Show system resource usage by containers
#   -a, --all                Show all information
#   -l, --logs <container>   Show logs for specific container
#   -m, --metrics            Show container metrics (requires stats API)
#   -f, --format <format>    Output format (table, json, csv)
#   -o, --output <file>      Write output to file
#   -w, --watch [seconds]    Watch mode with optional refresh interval (default: 2s)
#   -h, --help               Display this help message
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
SHOW_CONTAINERS=false
SHOW_IMAGES=false
SHOW_VOLUMES=false
SHOW_NETWORKS=false
SHOW_SYSTEM=false
SHOW_RESOURCES=false
SHOW_ALL=false
CONTAINER_LOGS=""
SHOW_METRICS=false
OUTPUT_FORMAT="table"
OUTPUT_FILE=""
WATCH_MODE=false
WATCH_INTERVAL=2

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Monitor Docker containers and system resources."
    echo ""
    echo "Options:"
    echo "  -c, --containers         Show container information (default)"
    echo "  -i, --images             Show image information"
    echo "  -v, --volumes            Show volume information"
    echo "  -n, --networks           Show network information"
    echo "  -s, --system             Show system-wide Docker information"
    echo "  -r, --resources          Show system resource usage by containers"
    echo "  -a, --all                Show all information"
    echo "  -l, --logs <container>   Show logs for specific container"
    echo "  -m, --metrics            Show container metrics (requires stats API)"
    echo "  -f, --format <format>    Output format (table, json, csv)"
    echo "  -o, --output <file>      Write output to file"
    echo "  -w, --watch [seconds]    Watch mode with optional refresh interval (default: 2s)"
    echo "  -h, --help               Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")"
    echo "  $(basename "$0") -a"
    echo "  $(basename "$0") -c -r -w 5"
    echo "  $(basename "$0") -l my-container"
    echo "  $(basename "$0") -m -f json -o metrics.json"
}

# Function to parse command line arguments
parse_arguments() {
    # Set defaults if no options provided
    if [ $# -eq 0 ]; then
        SHOW_CONTAINERS=true
    fi
    
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -c|--containers)
                SHOW_CONTAINERS=true
                shift
                ;;
            -i|--images)
                SHOW_IMAGES=true
                shift
                ;;
            -v|--volumes)
                SHOW_VOLUMES=true
                shift
                ;;
            -n|--networks)
                SHOW_NETWORKS=true
                shift
                ;;
            -s|--system)
                SHOW_SYSTEM=true
                shift
                ;;
            -r|--resources)
                SHOW_RESOURCES=true
                shift
                ;;
            -a|--all)
                SHOW_ALL=true
                SHOW_CONTAINERS=true
                SHOW_IMAGES=true
                SHOW_VOLUMES=true
                SHOW_NETWORKS=true
                SHOW_SYSTEM=true
                SHOW_RESOURCES=true
                shift
                ;;
            -l|--logs)
                CONTAINER_LOGS="$2"
                shift 2
                ;;
            -m|--metrics)
                SHOW_METRICS=true
                shift
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                case $OUTPUT_FORMAT in
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
            -o|--output)
                OUTPUT_FILE="$2"
                touch "$OUTPUT_FILE" 2>/dev/null
                if [ $? -ne 0 ]; then
                    log_error "Cannot write to output file: $OUTPUT_FILE"
                    exit 1
                fi
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

# Function to check if Docker is installed and running
check_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed or not in PATH"
        log_error "Please install Docker before running this script:"
        log_error "  - Debian/Ubuntu: https://docs.docker.com/engine/install/debian/"
        log_error "  - RHEL/CentOS: https://docs.docker.com/engine/install/centos/"
        log_error "  - Fedora: https://docs.docker.com/engine/install/fedora/"
        exit 1
    fi
    
    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running or current user doesn't have permission"
        log_error "Make sure Docker is running and you have proper permissions"
        log_error "You might need to add your user to the docker group:"
        log_error "  sudo usermod -aG docker $USER"
        log_error "Then log out and log back in to apply the changes"
        exit 1
    fi
}

# Function to show container information
show_container_info() {
    print_header "Container Information"
    
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        docker ps -a --format '{{json .}}' | jq -s '.'
    elif [ "$OUTPUT_FORMAT" = "csv" ]; then
        echo "ID,Name,Image,Status,Ports"
        docker ps -a --format '{{.ID}},{{.Names}},{{.Image}},{{.Status}},{{.Ports}}'
    else
        docker ps -a
    fi
    
    # Count containers by status
    local running
    local stopped
    local total
    
    running=$(docker ps -q | wc -l)
    total=$(docker ps -a -q | wc -l)
    stopped=$((total - running))
    
    echo ""
    log_info "Container Summary:"
    log_success "  Running: $running"
    log_warning "  Stopped: $stopped"
    log_info "  Total:   $total"
}

# Function to show image information
show_image_info() {
    print_header "Image Information"
    
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        docker images --format '{{json .}}' | jq -s '.'
    elif [ "$OUTPUT_FORMAT" = "csv" ]; then
        echo "Repository,Tag,ID,Size"
        docker images --format '{{.Repository}},{{.Tag}},{{.ID}},{{.Size}}'
    else
        docker images
    fi
    
    # Count images
    local total
    local dangling
    
    total=$(docker images -q | wc -l)
    dangling=$(docker images -f "dangling=true" -q | wc -l)
    
    echo ""
    log_info "Image Summary:"
    log_info "  Total:     $total"
    log_warning "  Dangling:  $dangling"
}

# Function to show volume information
show_volume_info() {
    print_header "Volume Information"
    
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        docker volume ls --format '{{json .}}' | jq -s '.'
    elif [ "$OUTPUT_FORMAT" = "csv" ]; then
        echo "Driver,Name"
        docker volume ls --format '{{.Driver}},{{.Name}}'
    else
        docker volume ls
    fi
    
    # Count volumes
    local total
    
    total=$(docker volume ls -q | wc -l)
    
    echo ""
    log_info "Volume Summary:"
    log_info "  Total: $total"
}

# Function to show network information
show_network_info() {
    print_header "Network Information"
    
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        docker network ls --format '{{json .}}' | jq -s '.'
    elif [ "$OUTPUT_FORMAT" = "csv" ]; then
        echo "ID,Name,Driver,Scope"
        docker network ls --format '{{.ID}},{{.Name}},{{.Driver}},{{.Scope}}'
    else
        docker network ls
    fi
    
    # Count networks
    local total
    
    total=$(docker network ls -q | wc -l)
    
    echo ""
    log_info "Network Summary:"
    log_info "  Total: $total"
}

# Function to show system-wide Docker information
show_system_info() {
    print_header "Docker System Information"
    
    docker info
    
    echo ""
    docker system df
}

# Function to show resource usage by containers
show_resource_usage() {
    print_header "Container Resource Usage"
    
    docker stats --no-stream
}

# Function to show logs for specific container
show_container_logs() {
    local container="$1"
    
    print_header "Logs for Container: $container"
    
    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        log_error "Container not found: $container"
        log_error "Available containers:"
        docker ps -a --format '{{.Names}}'
        return 1
    fi
    
    # Get last 50 log lines
    docker logs --tail 50 "$container"
}

# Function to show container metrics
show_container_metrics() {
    print_header "Container Metrics"
    
    # Get metrics for all running containers
    local containers
    containers=$(docker ps -q)
    
    if [ -z "$containers" ]; then
        log_warning "No running containers found"
        return
    fi
    
    # Collect metrics for each container
    local metrics=()
    
    for container in $containers; do
        local name
        local cpu
        local mem
        local net_in
        local net_out
        local disk_read
        local disk_write
        
        name=$(docker inspect --format '{{.Name}}' "$container" | sed 's/^\///')
        
        # Get CPU and memory usage
        stats=$(docker stats --no-stream "$container" --format "{{.CPUPerc}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}")
        
        cpu=$(echo "$stats" | cut -d '|' -f1)
        mem=$(echo "$stats" | cut -d '|' -f2)
        net_io=$(echo "$stats" | cut -d '|' -f3)
        block_io=$(echo "$stats" | cut -d '|' -f4)
        
        net_in=$(echo "$net_io" | awk '{print $1}')
        net_out=$(echo "$net_io" | awk '{print $3}')
        disk_read=$(echo "$block_io" | awk '{print $1}')
        disk_write=$(echo "$block_io" | awk '{print $3}')
        
        if [ "$OUTPUT_FORMAT" = "json" ]; then
            metrics+=("{\"container\":\"$name\",\"cpu\":\"$cpu\",\"memory\":\"$mem\",\"network_in\":\"$net_in\",\"network_out\":\"$net_out\",\"disk_read\":\"$disk_read\",\"disk_write\":\"$disk_write\"}")
        elif [ "$OUTPUT_FORMAT" = "csv" ]; then
            metrics+=("$name,$cpu,$mem,$net_in,$net_out,$disk_read,$disk_write")
        else
            metrics+=("$name|$cpu|$mem|$net_in|$net_out|$disk_read|$disk_write")
        fi
    done
    
    # Output metrics
    if [ "$OUTPUT_FORMAT" = "json" ]; then
        (
            echo "["
            for ((i=0; i<${#metrics[@]}; i++)); do
                echo "${metrics[$i]}"
                if [ $i -lt $((${#metrics[@]} - 1)) ]; then
                    echo ","
                fi
            done
            echo "]"
        ) | jq '.'
    elif [ "$OUTPUT_FORMAT" = "csv" ]; then
        echo "Container,CPU,Memory,Network In,Network Out,Disk Read,Disk Write"
        for metric in "${metrics[@]}"; do
            echo "$metric"
        done
    else
        printf "%-20s | %-8s | %-8s | %-10s | %-10s | %-10s | %-10s\n" "CONTAINER" "CPU" "MEMORY" "NET IN" "NET OUT" "DISK READ" "DISK WRITE"
        printf "%.s-" {1..90}
        echo ""
        
        for metric in "${metrics[@]}"; do
            IFS='|' read -r name cpu mem net_in net_out disk_read disk_write <<< "$metric"
            printf "%-20s | %-8s | %-8s | %-10s | %-10s | %-10s | %-10s\n" "$name" "$cpu" "$mem" "$net_in" "$net_out" "$disk_read" "$disk_write"
        done
    fi
}

# Function to clear screen in watch mode
clear_screen() {
    if [ "$WATCH_MODE" = true ]; then
        clear
    fi
}

# Function to run monitor once
run_monitor() {
    # Clear output file if specified
    if [ -n "$OUTPUT_FILE" ]; then
        > "$OUTPUT_FILE"
    fi
    
    # Redirect output to file if specified
    if [ -n "$OUTPUT_FILE" ]; then
        exec > >(tee "$OUTPUT_FILE") 2>&1
    fi
    
    # Display timestamp in watch mode
    if [ "$WATCH_MODE" = true ]; then
        print_header "Docker Monitor - $(date '+%Y-%m-%d %H:%M:%S')"
    fi
    
    # Show requested information
    if [ -n "$CONTAINER_LOGS" ]; then
        show_container_logs "$CONTAINER_LOGS"
    else
        if [ "$SHOW_SYSTEM" = true ]; then
            show_system_info
            echo ""
        fi
        
        if [ "$SHOW_CONTAINERS" = true ]; then
            show_container_info
            echo ""
        fi
        
        if [ "$SHOW_IMAGES" = true ]; then
            show_image_info
            echo ""
        fi
        
        if [ "$SHOW_VOLUMES" = true ]; then
            show_volume_info
            echo ""
        fi
        
        if [ "$SHOW_NETWORKS" = true ]; then
            show_network_info
            echo ""
        fi
        
        if [ "$SHOW_RESOURCES" = true ]; then
            show_resource_usage
            echo ""
        fi
        
        if [ "$SHOW_METRICS" = true ]; then
            show_container_metrics
            echo ""
        fi
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    check_docker
    
    if [ "$WATCH_MODE" = true ]; then
        log_info "Watch mode enabled with $WATCH_INTERVAL second interval"
        log_info "Press Ctrl+C to exit"
        
        while true; do
            clear_screen
            run_monitor
            sleep "$WATCH_INTERVAL"
        done
    else
        run_monitor
    fi
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Use color_echo's print_header function if available, otherwise define it
    if ! command -v print_header &>/dev/null; then
        print_header() {
            echo -e "\n=== $* ===\n"
        }
    fi
    
    # Handle SIGINT (Ctrl+C) in watch mode
    trap 'echo -e "\nDocker monitor stopped."; exit 0' INT
    
    main "$@"
fi
