#!/bin/bash
#
# docker_image_prune.sh - Prune Docker images based on age and tags
#
# This script helps manage Docker images by removing old or unused images
# based on criteria like age and tags, helping to recover disk space.
#
# Usage:
#   ./docker_image_prune.sh [options]
#
# Options:
#   -a, --age <days>          Remove images older than specified days
#   -t, --tag <pattern>       Remove images with tags matching the pattern
#   -e, --exclude <pattern>   Exclude images with tags matching the pattern
#   -r, --repo <name>         Only process images from specified repository
#   -d, --dangling            Remove dangling (untagged) images
#   -f, --force               Don't ask for confirmation
#   --dry-run                 Show what would be removed without removing anything
#   -v, --verbose             Show detailed output
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
MAX_AGE=""
TAG_PATTERN=""
EXCLUDE_PATTERN=""
REPOSITORY=""
REMOVE_DANGLING=false
FORCE=false
DRY_RUN=false
VERBOSE=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Prune Docker images based on age and tags."
    echo ""
    echo "Options:"
    echo "  -a, --age <days>          Remove images older than specified days"
    echo "  -t, --tag <pattern>       Remove images with tags matching the pattern"
    echo "  -e, --exclude <pattern>   Exclude images with tags matching the pattern"
    echo "  -r, --repo <name>         Only process images from specified repository"
    echo "  -d, --dangling            Remove dangling (untagged) images"
    echo "  -f, --force               Don't ask for confirmation"
    echo "  --dry-run                 Show what would be removed without removing anything"
    echo "  -v, --verbose             Show detailed output"
    echo "  -h, --help                Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") -a 30"
    echo "  $(basename "$0") -t '*-dev' -f"
    echo "  $(basename "$0") -r myapp -a 15 -e '*-stable'"
    echo "  $(basename "$0") -d --dry-run"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -a|--age)
                MAX_AGE="$2"
                if ! [[ "$MAX_AGE" =~ ^[0-9]+$ ]] || [ "$MAX_AGE" -lt 1 ]; then
                    log_error "Age must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -t|--tag)
                TAG_PATTERN="$2"
                shift 2
                ;;
            -e|--exclude)
                EXCLUDE_PATTERN="$2"
                shift 2
                ;;
            -r|--repo)
                REPOSITORY="$2"
                shift 2
                ;;
            -d|--dangling)
                REMOVE_DANGLING=true
                shift
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
    
    # Ensure at least one filter option is specified
    if [ -z "$MAX_AGE" ] && [ -z "$TAG_PATTERN" ] && [ -z "$REPOSITORY" ] && [ "$REMOVE_DANGLING" = false ]; then
        log_error "At least one filter option is required"
        show_usage
        exit 1
    fi
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

# Function to get image age in days
get_image_age_days() {
    local image_id="$1"
    local created_date
    local current_date
    local age_seconds
    
    # Get creation date in Unix timestamp
    created_date=$(docker inspect --format='{{.Created}}' "$image_id" | awk '{print $1}' | sed 's/T/ /' | sed 's/Z//')
    created_timestamp=$(date -d "$created_date" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$created_date" +%s 2>/dev/null)
    
    # Get current date in Unix timestamp
    current_timestamp=$(date +%s)
    
    # Calculate age in seconds
    age_seconds=$((current_timestamp - created_timestamp))
    
    # Convert to days
    echo $((age_seconds / 86400))
}

# Function to prune dangling images
prune_dangling_images() {
    log_info "Pruning dangling images..."
    
    if [ "$DRY_RUN" = true ]; then
        dangling_images=$(docker images -q -f "dangling=true")
        if [ -n "$dangling_images" ]; then
            log_info "[DRY RUN] Would remove these dangling images:"
            for image in $dangling_images; do
                echo "$image"
            done
        else
            log_info "No dangling images found"
        fi
    else
        if confirm_action "This will remove all dangling images."; then
            docker image prune -f
            log_success "Removed dangling images"
        else
            log_info "Dangling image cleanup cancelled"
        fi
    fi
}

# Function to prune images based on criteria
prune_images() {
    log_info "Searching for images to prune..."
    
    # Build docker images command
    local format="table {{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}\t{{.Size}}"
    local filter_cmd="docker images --format \"$format\""
    
    # Apply repository filter if specified
    if [ -n "$REPOSITORY" ]; then
        filter_cmd+=" | grep -E \"$REPOSITORY\""
    fi
    
    # Get images matching criteria
    images_table=$(eval "$filter_cmd")
    
    # Skip header line
    images_data=$(echo "$images_table" | tail -n +2)
    
    if [ -z "$images_data" ]; then
        log_info "No images found matching criteria"
        return
    fi
    
    # Track images to remove
    local images_to_remove=()
    
    # Process each image
    while IFS=$'\t' read -r id repo tag created_at size; do
        # Skip if tag is <none> and we're not removing dangling images
        if [ "$tag" = "<none>" ] && [ "$REMOVE_DANGLING" = false ]; then
            continue
        fi
        
        # Skip if tag matches exclude pattern
        if [ -n "$EXCLUDE_PATTERN" ] && [[ "$tag" == $EXCLUDE_PATTERN ]]; then
            [ "$VERBOSE" = true ] && log_debug "Skipping $repo:$tag (matches exclude pattern)"
            continue
        fi
        
        # Check if tag matches specified pattern
        if [ -n "$TAG_PATTERN" ] && [[ ! "$tag" == $TAG_PATTERN ]]; then
            [ "$VERBOSE" = true ] && log_debug "Skipping $repo:$tag (doesn't match tag pattern)"
            continue
        fi
        
        # Check image age if specified
        if [ -n "$MAX_AGE" ]; then
            image_age=$(get_image_age_days "$id")
            
            if [ "$image_age" -lt "$MAX_AGE" ]; then
                [ "$VERBOSE" = true ] && log_debug "Skipping $repo:$tag (age: $image_age days, younger than $MAX_AGE days)"
                continue
            else
                [ "$VERBOSE" = true ] && log_debug "Will remove $repo:$tag (age: $image_age days, older than $MAX_AGE days)"
            fi
        fi
        
        # Add image to removal list
        images_to_remove+=("$id $repo:$tag")
    done <<< "$images_data"
    
    # Check if any images should be removed
    if [ ${#images_to_remove[@]} -eq 0 ]; then
        log_info "No images found matching criteria for removal"
        return
    fi
    
    # Display images to be removed
    log_info "Found ${#images_to_remove[@]} images to remove:"
    for img in "${images_to_remove[@]}"; do
        echo "  $img"
    done
    
    # Remove images
    if [ "$DRY_RUN" = true ]; then
        log_warning "[DRY RUN] Would remove ${#images_to_remove[@]} images"
    else
        if confirm_action "This will remove ${#images_to_remove[@]} images."; then
            local removed=0
            local failed=0
            
            for img in "${images_to_remove[@]}"; do
                id=$(echo "$img" | awk '{print $1}')
                name=$(echo "$img" | awk '{print $2}')
                
                log_info "Removing image: $name ($id)"
                if docker rmi -f "$id" &>/dev/null; then
                    log_success "Removed $name"
                    removed=$((removed + 1))
                else
                    log_error "Failed to remove $name"
                    failed=$((failed + 1))
                fi
            done
            
            log_info "Image pruning completed:"
            log_success "  Removed: $removed"
            
            if [ $failed -gt 0 ]; then
                log_error "  Failed: $failed"
            fi
        else
            log_info "Image pruning cancelled"
        fi
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    check_docker
    
    log_info "Starting Docker image pruning"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE: No actual changes will be made"
    fi
    
    # Prune dangling images if requested
    if [ "$REMOVE_DANGLING" = true ] && [ -z "$TAG_PATTERN" ] && [ -z "$REPOSITORY" ] && [ -z "$MAX_AGE" ]; then
        prune_dangling_images
    else
        # Prune images based on criteria
        prune_images
    fi
    
    log_info "Docker image pruning completed"
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
