#!/bin/bash
#
# json_parser.sh - A simple JSON parser for Bash
#
# This script parses JSON files without requiring external dependencies like jq.
# It provides basic functionality for extracting values from JSON data.
#
# Usage:
#   ./json_parser.sh [options] <json_file> <query>
#   cat file.json | ./json_parser.sh [options] <query>
#
# Options:
#   -r, --raw     Output raw value without quotes or formatting
#   -h, --help    Display this help message
#
# Query syntax:
#   .key          Get value of key in object
#   .key1.key2    Get nested value
#   .[0]          Get array element by index
#   .key[0]       Get array element in object
#
# Author: BashScriptHub
# Date: 2023
# License: MIT

# Source the color_echo utility if it exists in the same directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/color_echo.sh" ]; then
    source "$SCRIPT_DIR/color_echo.sh"
else
    # Define minimal versions if color_echo.sh is not available
    log_info() { echo "INFO: $*"; }
    log_error() { echo "ERROR: $*" >&2; }
    log_success() { echo "SUCCESS: $*"; }
    log_warning() { echo "WARNING: $*"; }
    log_debug() { echo "DEBUG: $*"; }
fi

# Check if jq is installed and use it if available
check_jq() {
    if command -v jq &>/dev/null; then
        JQ_AVAILABLE=true
        log_debug "jq found, using it for JSON parsing"
    else
        JQ_AVAILABLE=false
        log_debug "jq not found, using fallback parser"
        log_warning "For better JSON parsing, consider installing jq:"
        log_warning "  - Debian/Ubuntu: sudo apt install jq"
        log_warning "  - RHEL/CentOS: sudo yum install jq"
        log_warning "  - Fedora: sudo dnf install jq"
    fi
}

# Default values
RAW_OUTPUT=false
JSON_FILE=""
QUERY=""

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options] <json_file> <query>"
    echo "       cat file.json | $(basename "$0") [options] <query>"
    echo ""
    echo "Parse JSON data and extract values."
    echo ""
    echo "Options:"
    echo "  -r, --raw     Output raw value without quotes or formatting"
    echo "  -h, --help    Display this help message"
    echo ""
    echo "Query syntax:"
    echo "  .key          Get value of key in object"
    echo "  .key1.key2    Get nested value"
    echo "  .[0]          Get array element by index"
    echo "  .key[0]       Get array element in object"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") file.json '.name'"
    echo "  $(basename "$0") file.json '.users[0].name'"
    echo "  cat file.json | $(basename "$0") '.config.settings'"
}

# Parse command line arguments
parse_arguments() {
    local positional=()
    
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -r|--raw)
                RAW_OUTPUT=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*) # Unknown option
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *) # Anything else is positional
                positional+=("$1")
                shift
                ;;
        esac
    done
    
    # Check if reading from stdin
    if [ -t 0 ]; then
        # Not reading from stdin, need file and query
        if [ ${#positional[@]} -lt 2 ]; then
            log_error "Missing required arguments"
            show_usage
            exit 1
        fi
        JSON_FILE="${positional[0]}"
        QUERY="${positional[1]}"
        
        # Check if file exists
        if [ ! -f "$JSON_FILE" ]; then
            log_error "File not found: $JSON_FILE"
            exit 1
        fi
    else
        # Reading from stdin, only need query
        if [ ${#positional[@]} -lt 1 ]; then
            log_error "Missing query argument"
            show_usage
            exit 1
        fi
        QUERY="${positional[0]}"
    fi
}

# Function to parse JSON using jq
parse_with_jq() {
    local json_data="$1"
    local query="$2"
    
    if [ "$RAW_OUTPUT" = true ]; then
        echo "$json_data" | jq -r "$query" 2>/dev/null
    else
        echo "$json_data" | jq "$query" 2>/dev/null
    fi
    
    return $?
}

# Function to extract value from key in JSON string (simple fallback parser)
# This is a basic parser and doesn't handle all JSON cases correctly
parse_fallback() {
    local json_data="$1"
    local query="$2"
    
    # Remove leading dot from query
    query="${query#.}"
    
    # Handle simple key
    if [[ ! "$query" =~ [\.\[] ]]; then
        # Extract key value with regex
        value=$(echo "$json_data" | grep -o "\"$query\"[[:space:]]*:[[:space:]]*[^,{}\[\]]*" | 
               sed -E 's/"'"$query"'"[[:space:]]*:[[:space:]]*//')
        
        # Remove surrounding quotes if string
        if [[ "$value" =~ ^\".*\"$ ]]; then
            value="${value#\"}"
            value="${value%\"}"
        fi
        
        echo "$value"
        return 0
    fi
    
    # Handle array index
    if [[ "$query" =~ ^\[([0-9]+)\]$ ]]; then
        index="${BASH_REMATCH[1]}"
        
        # Extract array elements
        elements=$(echo "$json_data" | grep -o '\[[^][]*\]' | sed -E 's/^\[|\]$//g' | tr ',' '\n')
        
        # Get element at index
        value=$(echo "$elements" | sed -n "$((index+1))p")
        
        # Remove surrounding quotes if string
        if [[ "$value" =~ ^\".*\"$ ]]; then
            value="${value#\"}"
            value="${value%\"}"
        fi
        
        echo "$value"
        return 0
    fi
    
    # Handle nested keys (simplified)
    if [[ "$query" =~ \. ]]; then
        first_key="${query%%.*}"
        rest_query=".${query#*.}"
        
        # Extract object for first key
        subobject=$(echo "$json_data" | grep -o "\"$first_key\"[[:space:]]*:[[:space:]]*{[^}]*}" | 
                   sed -E 's/"'"$first_key"'"[[:space:]]*:[[:space:]]*//')
        
        # Recursively parse rest of query
        parse_fallback "$subobject" "$rest_query"
        return $?
    fi
    
    # Handle key with array index (simplified)
    if [[ "$query" =~ (.*)\[([0-9]+)\]$ ]]; then
        key="${BASH_REMATCH[1]}"
        index="${BASH_REMATCH[2]}"
        
        # Extract array for key
        array=$(echo "$json_data" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\[[^]]*\]" | 
               sed -E 's/"'"$key"'"[[:space:]]*:[[:space:]]*//')
        
        # Extract elements
        elements=$(echo "$array" | sed -E 's/^\[|\]$//g' | tr ',' '\n')
        
        # Get element at index
        value=$(echo "$elements" | sed -n "$((index+1))p")
        
        # Remove surrounding quotes if string
        if [[ "$value" =~ ^\".*\"$ ]]; then
            value="${value#\"}"
            value="${value%\"}"
        fi
        
        echo "$value"
        return 0
    fi
    
    return 1
}

# Main execution
main() {
    parse_arguments "$@"
    check_jq
    
    # Get JSON data
    local json_data
    if [ -z "$JSON_FILE" ]; then
        # Read from stdin
        json_data=$(cat)
    else
        # Read from file
        json_data=$(cat "$JSON_FILE")
    fi
    
    # Parse JSON
    if [ "$JQ_AVAILABLE" = true ]; then
        # Use jq for parsing
        result=$(parse_with_jq "$json_data" "$QUERY")
        exit_code=$?
        
        if [ $exit_code -ne 0 ]; then
            log_error "Error parsing JSON with jq"
            exit $exit_code
        fi
        
        echo "$result"
    else
        # Use fallback parser
        result=$(parse_fallback "$json_data" "$QUERY")
        exit_code=$?
        
        if [ $exit_code -ne 0 ]; then
            log_error "Error parsing JSON with fallback parser"
            exit $exit_code
        fi
        
        echo "$result"
    fi
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
