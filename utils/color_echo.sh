#!/bin/bash
#
# Script Name: color_echo.sh
# Description: Colored logging functions for bash scripts
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: source color_echo.sh
#
# Functions:
#   log_info "Message"      - Print information message (blue)
#   log_success "Message"   - Print success message (green)
#   log_warning "Message"   - Print warning message (yellow)
#   log_error "Message"     - Print error message (red)
#   log_debug "Message"     - Print debug message (cyan)
#   print_header "Message"  - Print header message (bold white with separators)
#   print_section "Message" - Print section message (underlined white with smaller separators)
#   status_ok "Message"     - Print OK status message (green with [OK] prefix)
#   status_failed "Message" - Print FAILED status message (red with [FAILED] prefix)
#   status_warn "Message"   - Print WARNING status message (yellow with [WARNING] prefix)
#   show_spinner "Message"  - Show spinner with message while a command runs
#   progress_bar           - Show progress bar for long-running operations
#
# Examples:
#   source color_echo.sh
#   log_info "Starting installation..."
#   log_success "Installation complete!"
#   log_warning "Disk space is low"
#   log_error "Failed to connect to server"
#   print_header "System Configuration"
#   print_section "Network Settings"
#   status_ok "Service started"
#   status_failed "Service failed to start"
#   
#   # With spinner
#   show_spinner "Installing dependencies" sleep 5
#   
#   # With progress bar
#   for i in {1..100}; do
#     progress_bar $i 100 "Processing files"
#     sleep 0.1
#   done
#
# Requirements:
#   - Bash shell
#
# License: MIT
# Repository: https://github.com/bashscript-hub

# Check if the terminal supports colors
if [ -t 1 ] && [ -n "$TERM" ] && [ "$TERM" != "dumb" ]; then
    COLOR_SUPPORT=true
    
    # ANSI color codes
    COLOR_RESET='\033[0m'
    COLOR_BLACK='\033[0;30m'
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_PURPLE='\033[0;35m'
    COLOR_CYAN='\033[0;36m'
    COLOR_WHITE='\033[0;37m'
    
    # ANSI style codes
    STYLE_BOLD='\033[1m'
    STYLE_DIM='\033[2m'
    STYLE_UNDERLINE='\033[4m'
    STYLE_BLINK='\033[5m'
    STYLE_INVERTED='\033[7m'
    STYLE_HIDDEN='\033[8m'
else
    COLOR_SUPPORT=false
fi

# Check if output is being redirected
if [ -t 1 ]; then
    STDOUT_TERMINAL=true
else
    STDOUT_TERMINAL=false
    COLOR_SUPPORT=false
fi

# Enable or disable colors (can be set by the parent script)
COLOR_ENABLED=${COLOR_ENABLED:-$COLOR_SUPPORT}

# Debug mode flag (can be set by the parent script)
DEBUG_MODE=${DEBUG_MODE:-false}

# Default log level
LOG_LEVEL=${LOG_LEVEL:-"INFO"}  # DEBUG, INFO, WARNING, ERROR

# Convert log level to numeric value for comparison
get_log_level_value() {
    case "$1" in
        "DEBUG") echo 0 ;;
        "INFO") echo 1 ;;
        "WARNING") echo 2 ;;
        "ERROR") echo 3 ;;
        *) echo 1 ;; # Default to INFO
    esac
}

# Check if a log should be displayed based on current log level
should_log() {
    local msg_level="$1"
    local current_value
    local msg_value
    
    current_value=$(get_log_level_value "$LOG_LEVEL")
    msg_value=$(get_log_level_value "$msg_level")
    
    [ "$msg_value" -ge "$current_value" ]
}

# Get current timestamp
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Print a message with color
print_color() {
    local color="$1"
    local message="$2"
    local newline="${3:-true}"
    
    if [ "$COLOR_ENABLED" = true ]; then
        if [ "$newline" = true ]; then
            echo -e "${color}${message}${COLOR_RESET}"
        else
            echo -n -e "${color}${message}${COLOR_RESET}"
        fi
    else
        if [ "$newline" = true ]; then
            echo "$message"
        else
            echo -n "$message"
        fi
    fi
}

# Information message (blue)
log_info() {
    if should_log "INFO"; then
        local timestamp=$(get_timestamp)
        if [ "$COLOR_ENABLED" = true ]; then
            echo -e "${STYLE_DIM}${timestamp}${COLOR_RESET} ${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
        else
            echo "${timestamp} [INFO] $*"
        fi
    fi
}

# Success message (green)
log_success() {
    if should_log "INFO"; then
        local timestamp=$(get_timestamp)
        if [ "$COLOR_ENABLED" = true ]; then
            echo -e "${STYLE_DIM}${timestamp}${COLOR_RESET} ${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*"
        else
            echo "${timestamp} [SUCCESS] $*"
        fi
    fi
}

# Warning message (yellow)
log_warning() {
    if should_log "WARNING"; then
        local timestamp=$(get_timestamp)
        if [ "$COLOR_ENABLED" = true ]; then
            echo -e "${STYLE_DIM}${timestamp}${COLOR_RESET} ${COLOR_YELLOW}[WARNING]${COLOR_RESET} $*" >&2
        else
            echo "${timestamp} [WARNING] $*" >&2
        fi
    fi
}

# Error message (red)
log_error() {
    if should_log "ERROR"; then
        local timestamp=$(get_timestamp)
        if [ "$COLOR_ENABLED" = true ]; then
            echo -e "${STYLE_DIM}${timestamp}${COLOR_RESET} ${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
        else
            echo "${timestamp} [ERROR] $*" >&2
        fi
    fi
}

# Debug message (cyan)
log_debug() {
    if [ "$DEBUG_MODE" = true ] && should_log "DEBUG"; then
        local timestamp=$(get_timestamp)
        if [ "$COLOR_ENABLED" = true ]; then
            echo -e "${STYLE_DIM}${timestamp}${COLOR_RESET} ${COLOR_CYAN}[DEBUG]${COLOR_RESET} $*"
        else
            echo "${timestamp} [DEBUG] $*"
        fi
    fi
}

# Print a header
print_header() {
    if [ "$COLOR_ENABLED" = true ]; then
        echo -e "\n${STYLE_BOLD}${COLOR_WHITE}===== $* =====${COLOR_RESET}\n"
    else
        echo -e "\n===== $* =====\n"
    fi
}

# Print a section
print_section() {
    if [ "$COLOR_ENABLED" = true ]; then
        echo -e "\n${STYLE_UNDERLINE}${COLOR_WHITE}--- $* ---${COLOR_RESET}\n"
    else
        echo -e "\n--- $* ---\n"
    fi
}

# Status: OK
status_ok() {
    if [ "$COLOR_ENABLED" = true ]; then
        echo -e "${COLOR_GREEN}[  OK  ]${COLOR_RESET} $*"
    else
        echo "[  OK  ] $*"
    fi
}

# Status: FAILED
status_failed() {
    if [ "$COLOR_ENABLED" = true ]; then
        echo -e "${COLOR_RED}[FAILED]${COLOR_RESET} $*" >&2
    else
        echo "[FAILED] $*" >&2
    fi
}

# Status: WARNING
status_warn() {
    if [ "$COLOR_ENABLED" = true ]; then
        echo -e "${COLOR_YELLOW}[ WARN ]${COLOR_RESET} $*" >&2
    else
        echo "[ WARN ] $*" >&2
    fi
}

# Show spinner while a command runs
show_spinner() {
    local message="$1"
    local cmd="$2"
    local cmd_args="${@:3}"
    local spinner_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local pid
    local exit_status
    
    # Only use spinner if output is to a terminal
    if [ "$STDOUT_TERMINAL" = true ]; then
        # Run the command in the background
        eval "$cmd $cmd_args" &
        pid=$!
        
        # Show spinner
        echo -n -e "\r                                                  \r"
        echo -n "$message "
        while kill -0 $pid 2>/dev/null; do
            for char in "${spinner_chars[@]}"; do
                echo -n -e "\b$char"
                sleep 0.1
            done
        done
        
        # Get the exit status of the command
        wait $pid
        exit_status=$?
        
        # Print success or failure
        if [ $exit_status -eq 0 ]; then
            echo -e "\r                                                  \r"
            status_ok "$message"
        else
            echo -e "\r                                                  \r"
            status_failed "$message (exit code: $exit_status)"
        fi
        
        return $exit_status
    else
        # If not in a terminal, just run the command normally
        eval "$cmd $cmd_args"
        return $?
    fi
}

# Show progress bar
progress_bar() {
    local current="$1"
    local total="$2"
    local message="${3:-"Processing"}"
    local width=40
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    # Only show progress bar if output is to a terminal
    if [ "$STDOUT_TERMINAL" = true ]; then
        # Create the progress bar
        local progress="["
        for ((i=0; i<completed; i++)); do progress+="="; done
        if [ $completed -lt $width ]; then progress+=">"; fi
        for ((i=0; i<remaining-1; i++)); do progress+=" "; done
        progress+="]"
        
        # Print the progress bar
        echo -n -e "\r                                                                                \r"
        if [ "$COLOR_ENABLED" = true ]; then
            echo -n -e "${message}: ${COLOR_GREEN}${progress}${COLOR_RESET} ${percentage}%"
        else
            echo -n -e "${message}: ${progress} ${percentage}%"
        fi
        
        # Clear the line when complete
        if [ $current -eq $total ]; then
            echo -e "\r                                                                                \r"
            status_ok "$message: Complete"
        fi
    fi
}

# Clear the current line
clear_line() {
    if [ "$STDOUT_TERMINAL" = true ]; then
        echo -n -e "\r                                                  \r"
    fi
}

# Function to set log level
set_log_level() {
    local level="$1"
    case "$level" in
        "DEBUG"|"INFO"|"WARNING"|"ERROR")
            LOG_LEVEL="$level"
            ;;
        *)
            log_warning "Invalid log level: $level. Using default: INFO"
            LOG_LEVEL="INFO"
            ;;
    esac
}

# Function to enable/disable debug mode
set_debug_mode() {
    local mode="$1"
    if [ "$mode" = true ] || [ "$mode" = "true" ] || [ "$mode" = "1" ]; then
        DEBUG_MODE=true
        log_debug "Debug mode enabled"
    else
        DEBUG_MODE=false
    fi
}

# Function to enable/disable color output
set_color_output() {
    local mode="$1"
    if [ "$mode" = true ] || [ "$mode" = "true" ] || [ "$mode" = "1" ]; then
        COLOR_ENABLED=true
        log_debug "Color output enabled"
    else
        COLOR_ENABLED=false
        log_debug "Color output disabled"
    fi
}

# Print script invocation message if debugging is enabled
if [ "$DEBUG_MODE" = true ]; then
    log_debug "Color output utility loaded"
fi