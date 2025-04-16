#!/bin/bash
#
# mass_ssh_command_runner.sh - Execute commands on multiple remote servers via SSH
#
# This script allows executing the same command(s) on multiple remote servers
# using SSH. It supports authentication via password or SSH key, and can run
# commands in parallel for faster execution.
#
# Usage:
#   ./mass_ssh_command_runner.sh [options]
#
# Options:
#   -h, --hosts <file>       File containing list of hosts, one per line
#   -H, --host <host>        Individual host to connect to (can be used multiple times)
#   -c, --command <cmd>      Command to execute (can be used multiple times)
#   -f, --file <file>        File containing commands to execute
#   -u, --user <user>        SSH username (default: current user)
#   -i, --identity <file>    SSH private key file
#   -p, --parallel <num>     Max number of parallel connections (default: 5)
#   -t, --timeout <seconds>  SSH connection timeout (default: 10)
#   -o, --output <file>      Save output to file
#   --help                   Display this help message
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
HOSTS_FILE=""
HOSTS=()
COMMANDS=()
COMMANDS_FILE=""
SSH_USER="$(whoami)"
SSH_KEY=""
PARALLEL=5
TIMEOUT=10
OUTPUT_FILE=""

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Execute commands on multiple remote servers via SSH."
    echo ""
    echo "Options:"
    echo "  -h, --hosts <file>       File containing list of hosts, one per line"
    echo "  -H, --host <host>        Individual host to connect to (can be used multiple times)"
    echo "  -c, --command <cmd>      Command to execute (can be used multiple times)"
    echo "  -f, --file <file>        File containing commands to execute"
    echo "  -u, --user <user>        SSH username (default: current user)"
    echo "  -i, --identity <file>    SSH private key file"
    echo "  -p, --parallel <num>     Max number of parallel connections (default: $PARALLEL)"
    echo "  -t, --timeout <seconds>  SSH connection timeout (default: $TIMEOUT)"
    echo "  -o, --output <file>      Save output to file"
    echo "  --help                   Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") -h hosts.txt -c 'uptime'"
    echo "  $(basename "$0") -H server1 -H server2 -c 'df -h' -c 'free -m'"
    echo "  $(basename "$0") -h hosts.txt -f commands.txt -p 10"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -h|--hosts)
                HOSTS_FILE="$2"
                if [ ! -f "$HOSTS_FILE" ]; then
                    log_error "Hosts file not found: $HOSTS_FILE"
                    exit 1
                fi
                shift 2
                ;;
            -H|--host)
                HOSTS+=("$2")
                shift 2
                ;;
            -c|--command)
                COMMANDS+=("$2")
                shift 2
                ;;
            -f|--file)
                COMMANDS_FILE="$2"
                if [ ! -f "$COMMANDS_FILE" ]; then
                    log_error "Commands file not found: $COMMANDS_FILE"
                    exit 1
                fi
                shift 2
                ;;
            -u|--user)
                SSH_USER="$2"
                shift 2
                ;;
            -i|--identity)
                SSH_KEY="$2"
                if [ ! -f "$SSH_KEY" ]; then
                    log_error "SSH key file not found: $SSH_KEY"
                    exit 1
                fi
                shift 2
                ;;
            -p|--parallel)
                PARALLEL="$2"
                if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || [ "$PARALLEL" -lt 1 ]; then
                    log_error "Parallel connections must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -lt 1 ]; then
                    log_error "Timeout must be a positive integer"
                    exit 1
                fi
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
            --help)
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
    
    # Load hosts from file if specified
    if [ -n "$HOSTS_FILE" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip empty lines and comments
            if [ -n "$line" ] && [[ ! "$line" =~ ^[[:space:]]*# ]]; then
                HOSTS+=("$line")
            fi
        done < "$HOSTS_FILE"
    fi
    
    # Load commands from file if specified
    if [ -n "$COMMANDS_FILE" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip empty lines and comments
            if [ -n "$line" ] && [[ ! "$line" =~ ^[[:space:]]*# ]]; then
                COMMANDS+=("$line")
            fi
        done < "$COMMANDS_FILE"
    fi
    
    # Validate hosts and commands
    if [ ${#HOSTS[@]} -eq 0 ]; then
        log_error "No hosts specified"
        show_usage
        exit 1
    fi
    
    if [ ${#COMMANDS[@]} -eq 0 ]; then
        log_error "No commands specified"
        show_usage
        exit 1
    fi
}

# Function to execute command on a single host
execute_command_on_host() {
    local host="$1"
    local cmd="$2"
    local output_file="$3"
    
    # Build SSH options
    local ssh_opts="-o ConnectTimeout=$TIMEOUT -o BatchMode=yes -o StrictHostKeyChecking=no"
    
    if [ -n "$SSH_KEY" ]; then
        ssh_opts+=" -i $SSH_KEY"
    fi
    
    # Execute command via SSH
    local result
    result=$(ssh $ssh_opts "$SSH_USER@$host" "$cmd" 2>&1)
    local status=$?
    
    # Output result
    if [ "$status" -eq 0 ]; then
        log_success "[$host] Command executed successfully"
        if [ -n "$output_file" ]; then
            echo "=== Host: $host, Command: $cmd ===" >> "$output_file"
            echo "$result" >> "$output_file"
            echo "" >> "$output_file"
        else
            echo "=== Host: $host, Command: $cmd ==="
            echo "$result"
            echo ""
        fi
    else
        log_error "[$host] Command failed with status $status"
        if [ -n "$output_file" ]; then
            echo "=== Host: $host, Command: $cmd (FAILED) ===" >> "$output_file"
            echo "$result" >> "$output_file"
            echo "" >> "$output_file"
        else
            echo "=== Host: $host, Command: $cmd (FAILED) ==="
            echo "$result"
            echo ""
        fi
    fi
    
    return $status
}

# Function to execute commands on all hosts
execute_commands() {
    local hosts=("$@")
    local num_hosts=${#hosts[@]}
    local num_commands=${#COMMANDS[@]}
    local total_tasks=$((num_hosts * num_commands))
    local completed=0
    local successful=0
    local failed=0
    
    log_info "Executing $num_commands command(s) on $num_hosts host(s) with max $PARALLEL parallel connections"
    
    # Create temporary directory for process control
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Initialize counter for parallel execution
    local running=0
    
    # Loop through each host
    for host in "${hosts[@]}"; do
        # Loop through each command
        for cmd in "${COMMANDS[@]}"; do
            # Wait if max parallel processes reached
            while [ $running -ge $PARALLEL ]; do
                # Count running processes
                running=0
                for pid_file in "$temp_dir"/*.pid; do
                    if [ -f "$pid_file" ]; then
                        pid=$(cat "$pid_file")
                        if kill -0 $pid 2>/dev/null; then
                            running=$((running + 1))
                        else
                            # Process has finished, remove pid file
                            rm -f "$pid_file"
                        fi
                    fi
                done
                sleep 0.1
            done
            
            # Execute command in background
            (
                local task_id="$RANDOM$RANDOM"
                echo $$ > "$temp_dir/$task_id.pid"
                
                if execute_command_on_host "$host" "$cmd" "$OUTPUT_FILE"; then
                    echo "success" > "$temp_dir/$task_id.result"
                else
                    echo "failure" > "$temp_dir/$task_id.result"
                fi
                
                rm -f "$temp_dir/$task_id.pid"
            ) &
            
            running=$((running + 1))
        done
    done
    
    # Wait for all processes to finish
    wait
    
    # Count results
    for result_file in "$temp_dir"/*.result; do
        if [ -f "$result_file" ]; then
            completed=$((completed + 1))
            if [ "$(cat "$result_file")" = "success" ]; then
                successful=$((successful + 1))
            else
                failed=$((failed + 1))
            fi
        fi
    done
    
    # Clean up
    rm -rf "$temp_dir"
    
    # Display summary
    log_info "Execution summary:"
    log_info "  Total tasks:      $total_tasks"
    log_info "  Completed:        $completed"
    log_success "  Successful:       $successful"
    
    if [ $failed -gt 0 ]; then
        log_error "  Failed:           $failed"
    else
        log_info "  Failed:           $failed"
    fi
    
    if [ -n "$OUTPUT_FILE" ]; then
        log_info "Output saved to: $OUTPUT_FILE"
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    execute_commands "${HOSTS[@]}"
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
