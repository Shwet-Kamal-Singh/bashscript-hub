#!/bin/bash
#
# docker_cleanup.sh - Clean up Docker containers, volumes, and networks
#
# This script helps manage Docker resources by cleaning up stopped containers,
# dangling images, unused volumes, and unused networks. It can be run regularly
# to prevent resource accumulation.
#
# Usage:
#   ./docker_cleanup.sh [options]
#
# Options:
#   -a, --all               Remove all unused containers, not just stopped ones
#   -f, --force             Don't ask for confirmation
#   -i, --images            Remove dangling images
#   -I, --all-images        Remove all unused images, not just dangling ones
#   -v, --volumes           Remove unused volumes
#   -n, --networks          Remove unused networks
#   -s, --system            Run docker system prune (implies -i -v -n)
#   --dry-run               Show what would be removed without removing anything
#   -h, --help              Display this help message
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
REMOVE_ALL=false
FORCE=false
REMOVE_IMAGES=false
REMOVE_ALL_IMAGES=false
REMOVE_VOLUMES=false
REMOVE_NETWORKS=false
SYSTEM_PRUNE=false
DRY_RUN=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Clean up Docker containers, volumes, and networks."
    echo ""
    echo "Options:"
    echo "  -a, --all               Remove all unused containers, not just stopped ones"
    echo "  -f, --force             Don't ask for confirmation"
    echo "  -i, --images            Remove dangling images"
    echo "  -I, --all-images        Remove all unused images, not just dangling ones"
    echo "  -v, --volumes           Remove unused volumes"
    echo "  -n, --networks          Remove unused networks"
    echo "  -s, --system            Run docker system prune (implies -i -v -n)"
    echo "  --dry-run               Show what would be removed without removing anything"
    echo "  -h, --help              Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0")"
    echo "  $(basename "$0") -a -f"
    echo "  $(basename "$0") -i -v -n"
    echo "  $(basename "$0") -s"
    echo "  $(basename "$0") --dry-run -a -i -v"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -a|--all)
                REMOVE_ALL=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -i|--images)
                REMOVE_IMAGES=true
                shift
                ;;
            -I|--all-images)
                REMOVE_ALL_IMAGES=true
                REMOVE_IMAGES=true
                shift
                ;;
            -v|--volumes)
                REMOVE_VOLUMES=true
                shift
                ;;
            -n|--networks)
                REMOVE_NETWORKS=true
                shift
                ;;
            -s|--system)
                SYSTEM_PRUNE=true
                REMOVE_IMAGES=true
                REMOVE_VOLUMES=true
                REMOVE_NETWORKS=true
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

# Function to confirm action with user
confirm_action() {
    local message="$1"
    
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    echo "$message"
    read -r -p "Continue? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to clean up containers
cleanup_containers() {
    local cmd
    local dry_run_flag=""
    
    if [ "$DRY_RUN" = true ]; then
        dry_run_flag="--dry-run"
    fi
    
    if [ "$REMOVE_ALL" = true ]; then
        log_info "Removing all unused containers..."
        cmd="docker container prune $dry_run_flag -f"
    else
        log_info "Removing stopped containers..."
        cmd="docker container ls -a -q -f status=exited | xargs -r docker rm $dry_run_flag"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would execute: $cmd"
        if [ "$REMOVE_ALL" = true ]; then
            docker container prune --dry-run -f
        else
            containers=$(docker container ls -a -q -f status=exited)
            if [ -n "$containers" ]; then
                log_info "[DRY RUN] Would remove these containers:"
                for container in $containers; do
                    docker container ls -a --format "{{.ID}} - {{.Names}} ({{.Status}})" | grep "$container"
                done
            else
                log_info "[DRY RUN] No stopped containers to remove"
            fi
        fi
    else
        if [ "$REMOVE_ALL" = true ]; then
            docker container prune -f
        else
            containers=$(docker container ls -a -q -f status=exited)
            if [ -n "$containers" ]; then
                docker rm $containers
                log_success "Removed stopped containers"
            else
                log_info "No stopped containers to remove"
            fi
        fi
    fi
}

# Function to clean up images
cleanup_images() {
    local dry_run_flag=""
    
    if [ "$DRY_RUN" = true ]; then
        dry_run_flag="--dry-run"
    fi
    
    if [ "$REMOVE_ALL_IMAGES" = true ]; then
        log_info "Removing all unused images..."
        
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Would execute: docker image prune -a -f"
            docker image prune -a -f --dry-run
        else
            if confirm_action "This will remove ALL unused images. This could be a lot of data."; then
                docker image prune -a -f
                log_success "Removed all unused images"
            else
                log_info "Image cleanup cancelled"
            fi
        fi
    elif [ "$REMOVE_IMAGES" = true ]; then
        log_info "Removing dangling images..."
        
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Would execute: docker image prune -f"
            docker image prune -f --dry-run
        else
            docker image prune -f
            log_success "Removed dangling images"
        fi
    fi
}

# Function to clean up volumes
cleanup_volumes() {
    local dry_run_flag=""
    
    if [ "$DRY_RUN" = true ]; then
        dry_run_flag="--dry-run"
    fi
    
    log_info "Removing unused volumes..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would execute: docker volume prune -f"
        docker volume prune -f --dry-run
    else
        if confirm_action "This will remove all unused volumes. Any data in these volumes will be lost."; then
            docker volume prune -f
            log_success "Removed unused volumes"
        else
            log_info "Volume cleanup cancelled"
        fi
    fi
}

# Function to clean up networks
cleanup_networks() {
    local dry_run_flag=""
    
    if [ "$DRY_RUN" = true ]; then
        dry_run_flag="--dry-run"
    fi
    
    log_info "Removing unused networks..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would execute: docker network prune -f"
        docker network prune -f --dry-run
    else
        docker network prune -f
        log_success "Removed unused networks"
    fi
}

# Function to run system prune
run_system_prune() {
    local prune_cmd="docker system prune"
    
    if [ "$REMOVE_VOLUMES" = true ]; then
        prune_cmd+=" --volumes"
    fi
    
    if [ "$REMOVE_ALL_IMAGES" = true ]; then
        prune_cmd+=" -a"
    fi
    
    if [ "$FORCE" = true ]; then
        prune_cmd+=" -f"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        prune_cmd+=" --dry-run"
    fi
    
    log_info "Running system prune..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would execute: $prune_cmd"
    fi
    
    eval "$prune_cmd"
    
    if [ $? -eq 0 ] && [ "$DRY_RUN" = false ]; then
        log_success "System prune completed successfully"
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    check_docker
    
    log_info "Starting Docker cleanup"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE: No actual changes will be made"
    fi
    
    # Run system prune if requested
    if [ "$SYSTEM_PRUNE" = true ]; then
        run_system_prune
    else
        # Otherwise run individual cleanup functions
        cleanup_containers
        
        if [ "$REMOVE_IMAGES" = true ]; then
            cleanup_images
        fi
        
        if [ "$REMOVE_VOLUMES" = true ]; then
            cleanup_volumes
        fi
        
        if [ "$REMOVE_NETWORKS" = true ]; then
            cleanup_networks
        fi
    fi
    
    log_info "Docker cleanup completed"
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
