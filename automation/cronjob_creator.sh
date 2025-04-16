#!/bin/bash
#
# cronjob_creator.sh - Create and manage cron jobs easily
#
# This script simplifies the creation and management of cron jobs by providing
# a user-friendly interface for adding, removing, and listing scheduled tasks.
#
# Usage:
#   ./cronjob_creator.sh [command] [options]
#
# Commands:
#   add        Add a new cron job
#   remove     Remove an existing cron job
#   list       List all cron jobs
#   help       Display this help message
#
# Options for 'add' command:
#   -c, --command <cmd>      Command to execute
#   -s, --schedule <sched>   Cron schedule expression (e.g., "0 0 * * *" for daily at midnight)
#   -u, --user <user>        User to run the job as (requires root, default: current user)
#   -l, --label <label>      Add a label comment to identify the job
#   -o, --output <file>      Redirect command output to file
#
# Options for 'remove' command:
#   -l, --label <label>      Remove jobs with this label
#   -c, --command <cmd>      Remove jobs with this command
#   -u, --user <user>        User whose crontab to modify (requires root)
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
COMMAND=""
SCHEDULE=""
USERNAME="$USER"
LABEL=""
OUTPUT_FILE=""
ACTION=""

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [command] [options]"
    echo ""
    echo "Create and manage cron jobs easily."
    echo ""
    echo "Commands:"
    echo "  add        Add a new cron job"
    echo "  remove     Remove an existing cron job"
    echo "  list       List all cron jobs"
    echo "  help       Display this help message"
    echo ""
    echo "Options for 'add' command:"
    echo "  -c, --command <cmd>      Command to execute"
    echo "  -s, --schedule <sched>   Cron schedule expression (e.g., \"0 0 * * *\" for daily at midnight)"
    echo "  -u, --user <user>        User to run the job as (requires root, default: current user)"
    echo "  -l, --label <label>      Add a label comment to identify the job"
    echo "  -o, --output <file>      Redirect command output to file"
    echo ""
    echo "Options for 'remove' command:"
    echo "  -l, --label <label>      Remove jobs with this label"
    echo "  -c, --command <cmd>      Remove jobs with this command"
    echo "  -u, --user <user>        User whose crontab to modify (requires root)"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") add -c \"/path/to/script.sh\" -s \"0 0 * * *\" -l \"nightly-backup\""
    echo "  $(basename "$0") add -c \"/path/to/script.sh\" -s \"*/5 * * * *\" -o \"/var/log/script.log\""
    echo "  $(basename "$0") remove -l \"nightly-backup\""
    echo "  $(basename "$0") list"
    echo "  $(basename "$0") list -u otheruser"
}

# Function to show help for schedule format
show_schedule_help() {
    echo "Cron Schedule Format:"
    echo ""
    echo "    ┌───────────── minute (0 - 59)"
    echo "    │ ┌───────────── hour (0 - 23)"
    echo "    │ │ ┌───────────── day of the month (1 - 31)"
    echo "    │ │ │ ┌───────────── month (1 - 12)"
    echo "    │ │ │ │ ┌───────────── day of the week (0 - 6) (Sunday to Saturday)"
    echo "    │ │ │ │ │"
    echo "    * * * * *  command to execute"
    echo ""
    echo "Examples:"
    echo "  \"0 0 * * *\"      = Daily at midnight"
    echo "  \"*/15 * * * *\"   = Every 15 minutes"
    echo "  \"0 9-17 * * 1-5\" = Every hour from 9 AM to 5 PM, Monday to Friday"
    echo "  \"0 0 1 * *\"      = At midnight on the first day of each month"
    echo "  \"0 0 * * 0\"      = At midnight on Sunday"
}

# Function to parse command line arguments
parse_arguments() {
    # Check if no arguments were provided
    if [ $# -eq 0 ]; then
        show_usage
        exit 0
    fi
    
    # Parse action
    ACTION="$1"
    shift
    
    case $ACTION in
        add|remove|list)
            # Valid actions
            ;;
        help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown command: $ACTION"
            show_usage
            exit 1
            ;;
    esac
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -c|--command)
                COMMAND="$2"
                shift 2
                ;;
            -s|--schedule)
                SCHEDULE="$2"
                shift 2
                ;;
            -u|--user)
                USERNAME="$2"
                shift 2
                ;;
            -l|--label)
                LABEL="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --help-schedule)
                show_schedule_help
                exit 0
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
    
    # Validate options based on action
    case $ACTION in
        add)
            if [ -z "$COMMAND" ]; then
                log_error "Command is required for add action"
                show_usage
                exit 1
            fi
            
            if [ -z "$SCHEDULE" ]; then
                log_error "Schedule is required for add action"
                show_usage
                exit 1
            fi
            ;;
        remove)
            if [ -z "$LABEL" ] && [ -z "$COMMAND" ]; then
                log_error "Either label or command is required for remove action"
                show_usage
                exit 1
            fi
            ;;
    esac
    
    # Check if requesting to modify another user's crontab
    if [ "$USERNAME" != "$USER" ]; then
        if [ "$(id -u)" -ne 0 ]; then
            log_error "Root privileges required to modify another user's crontab"
            exit 1
        fi
    fi
}

# Function to validate cron schedule
validate_schedule() {
    local schedule="$1"
    
    # Check format (5 fields separated by spaces)
    if ! [[ "$schedule" =~ ^[0-9*,/-]+([ \t]+[0-9*,/-]+){4}$ ]]; then
        log_error "Invalid cron schedule format: $schedule"
        show_schedule_help
        return 1
    fi
    
    return 0
}

# Function to add a cron job
add_cronjob() {
    log_info "Adding cron job for user: $USERNAME"
    
    # Validate schedule
    validate_schedule "$SCHEDULE" || return 1
    
    # Build cron entry
    local cron_entry="$SCHEDULE $COMMAND"
    
    # Add output redirection if specified
    if [ -n "$OUTPUT_FILE" ]; then
        cron_entry="$cron_entry > $OUTPUT_FILE 2>&1"
    fi
    
    # Create temporary file
    local temp_file
    temp_file=$(mktemp)
    
    # Get current crontab
    crontab -u "$USERNAME" -l 2>/dev/null > "$temp_file" || echo "" > "$temp_file"
    
    # Add label as comment if specified
    if [ -n "$LABEL" ]; then
        echo "# BEGIN: $LABEL" >> "$temp_file"
    fi
    
    # Add cron entry
    echo "$cron_entry" >> "$temp_file"
    
    # Add end label if specified
    if [ -n "$LABEL" ]; then
        echo "# END: $LABEL" >> "$temp_file"
    fi
    
    # Install new crontab
    if crontab -u "$USERNAME" "$temp_file"; then
        log_success "Cron job added successfully"
    else
        log_error "Failed to add cron job"
        rm -f "$temp_file"
        return 1
    fi
    
    # Clean up
    rm -f "$temp_file"
    return 0
}

# Function to remove a cron job
remove_cronjob() {
    log_info "Removing cron job for user: $USERNAME"
    
    # Create temporary file
    local temp_file
    temp_file=$(mktemp)
    
    # Get current crontab
    if ! crontab -u "$USERNAME" -l 2>/dev/null > "$temp_file"; then
        log_error "Failed to retrieve crontab for user: $USERNAME"
        rm -f "$temp_file"
        return 1
    fi
    
    # Create another temporary file for the new crontab
    local new_crontab
    new_crontab=$(mktemp)
    
    if [ -n "$LABEL" ]; then
        # Remove jobs with specified label
        local in_labeled_section=false
        
        while IFS= read -r line; do
            if [[ "$line" == "# BEGIN: $LABEL" ]]; then
                in_labeled_section=true
            elif [[ "$line" == "# END: $LABEL" ]]; then
                in_labeled_section=false
            elif [ "$in_labeled_section" = false ]; then
                echo "$line" >> "$new_crontab"
            fi
        done < "$temp_file"
    elif [ -n "$COMMAND" ]; then
        # Remove jobs with specified command
        while IFS= read -r line; do
            if ! [[ "$line" =~ $COMMAND ]]; then
                echo "$line" >> "$new_crontab"
            fi
        done < "$temp_file"
    fi
    
    # Install new crontab
    if crontab -u "$USERNAME" "$new_crontab"; then
        log_success "Cron job(s) removed successfully"
    else
        log_error "Failed to update crontab"
        rm -f "$temp_file" "$new_crontab"
        return 1
    fi
    
    # Clean up
    rm -f "$temp_file" "$new_crontab"
    return 0
}

# Function to list cron jobs
list_cronjobs() {
    log_info "Listing cron jobs for user: $USERNAME"
    
    # Get current crontab
    if ! crontab -u "$USERNAME" -l 2>/dev/null; then
        log_warning "No crontab for user: $USERNAME"
        return 1
    fi
    
    return 0
}

# Main execution
main() {
    parse_arguments "$@"
    
    case $ACTION in
        add)
            add_cronjob
            ;;
        remove)
            remove_cronjob
            ;;
        list)
            list_cronjobs
            ;;
    esac
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
