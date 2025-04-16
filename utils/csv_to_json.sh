#!/bin/bash
#
# Script Name: csv_to_json.sh
# Description: Convert CSV files to JSON format
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./csv_to_json.sh [options] <csv_file>
#
# Options:
#   -o, --output <file>         Output file (default: stdout)
#   -d, --delimiter <char>      CSV delimiter (default: comma)
#   -a, --array                 Output as JSON array (default: array of objects)
#   -n, --no-header             CSV has no header row (auto-generate field names)
#   -f, --fields <fields>       Specify field names (comma-separated, for use with --no-header)
#   -p, --pretty                Pretty-print JSON output
#   -t, --types                 Try to detect and convert field types (number, boolean, null)
#   -N, --null <string>         String to interpret as null (default: empty string)
#   -T, --true <string>         String to interpret as true (default: "true")
#   -F, --false <string>        String to interpret as false (default: "false")
#   -D, --date-fields <fields>  Comma-separated list of fields to treat as dates
#   -i, --ignore-errors         Ignore parsing errors and continue processing
#   -j, --jq-filter <filter>    Apply jq filter to output (requires jq)
#   -v, --verbose               Show detailed output
#   -h, --help                  Display this help message
#
# Examples:
#   ./csv_to_json.sh data.csv
#   ./csv_to_json.sh -o data.json -d ";" -p data.csv
#   ./csv_to_json.sh -n -f "id,name,value" -t data.csv
#   ./csv_to_json.sh -d "|" -t -N "NULL" -j '.[] | select(.active==true)' data.csv
#
# Requirements:
#   - Bash 4.0+ for associative arrays
#   - jq (optional, for filtering and pretty printing)
#
# License: MIT
# Repository: https://github.com/bashscript-hub

# Source the color_echo utility if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$SCRIPT_DIR/color_echo.sh" ]; then
    source "$SCRIPT_DIR/color_echo.sh"
else
    # Define minimal versions if color_echo.sh is not available
    log_info() { echo "INFO: $*"; }
    log_error() { echo "ERROR: $*" >&2; }
    log_success() { echo "SUCCESS: $*"; }
    log_warning() { echo "WARNING: $*"; }
    print_header() { echo -e "\n=== $* ===\n"; }
    print_section() { echo -e "\n--- $* ---\n"; }
fi

# Check Bash version for associative arrays (4.0+)
if ((BASH_VERSINFO[0] < 4)); then
    log_error "This script requires Bash 4.0 or higher for associative arrays"
    exit 1
fi

# Set default values
OUTPUT_FILE=""
DELIMITER=","
OUTPUT_AS_ARRAY=false
HAS_HEADER=true
FIELD_NAMES=""
PRETTY_PRINT=false
DETECT_TYPES=false
NULL_STRING=""
TRUE_STRING="true"
FALSE_STRING="false"
DATE_FIELDS=""
IGNORE_ERRORS=false
JQ_FILTER=""
VERBOSE=false
CSV_FILE=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -d|--delimiter)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            DELIMITER="$2"
            shift 2
            ;;
        -a|--array)
            OUTPUT_AS_ARRAY=true
            shift
            ;;
        -n|--no-header)
            HAS_HEADER=false
            shift
            ;;
        -f|--fields)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            FIELD_NAMES="$2"
            shift 2
            ;;
        -p|--pretty)
            PRETTY_PRINT=true
            shift
            ;;
        -t|--types)
            DETECT_TYPES=true
            shift
            ;;
        -N|--null)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            NULL_STRING="$2"
            shift 2
            ;;
        -T|--true)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            TRUE_STRING="$2"
            shift 2
            ;;
        -F|--false)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            FALSE_STRING="$2"
            shift 2
            ;;
        -D|--date-fields)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            DATE_FIELDS="$2"
            shift 2
            ;;
        -i|--ignore-errors)
            IGNORE_ERRORS=true
            shift
            ;;
        -j|--jq-filter)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            JQ_FILTER="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            # Extract and display script header
            grep -E '^# (Script Name:|Description:|Usage:|Options:|Examples:|Requirements:)' "$0" | sed 's/^# //'
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            log_error "Use --help to see available options"
            exit 1
            ;;
        *)
            # Assume it's the CSV file
            if [ -z "$CSV_FILE" ]; then
                CSV_FILE="$1"
            else
                log_error "Extra argument: $1"
                log_error "Use --help to see available options"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if CSV file is provided
if [ -z "$CSV_FILE" ]; then
    log_error "No CSV file specified"
    log_error "Usage: $0 [options] <csv_file>"
    exit 1
fi

# Check if CSV file exists
if [ ! -f "$CSV_FILE" ]; then
    log_error "CSV file not found: $CSV_FILE"
    exit 1
fi

# Check if jq is available if needed
if [ -n "$JQ_FILTER" ] || [ "$PRETTY_PRINT" = true ]; then
    if ! command -v jq &>/dev/null; then
        log_error "jq is required for filtering or pretty printing."
        log_error "Please install jq and try again."
        exit 1
    fi
fi

# Function to sanitize a string for JSON
json_escape() {
    local s="$1"
    # Escape backslashes, double quotes, and control characters
    s="${s//\\/\\\\}"    # Escape backslashes
    s="${s//\"/\\\"}"    # Escape double quotes
    s="${s//	/\\t}"      # Escape tabs
    s="${s//
/\\n}"      # Escape newlines
    s="${s//\r/\\r}"     # Escape carriage returns
    echo "$s"
}

# Function to detect data type
detect_type() {
    local value="$1"
    local field="$2"
    
    # Check if field is in date fields list
    if [[ ",$DATE_FIELDS," == *",$field,"* ]]; then
        # Simple ISO date validation (YYYY-MM-DD)
        if [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
           [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:[0-9]{2})?$ ]]; then
            echo "\"$value\""
            return
        fi
    fi
    
    # Check if it's null
    if [ "$value" = "$NULL_STRING" ]; then
        echo "null"
        return
    fi
    
    # Check if it's boolean
    if [ "$value" = "$TRUE_STRING" ]; then
        echo "true"
        return
    fi
    
    if [ "$value" = "$FALSE_STRING" ]; then
        echo "false"
        return
    fi
    
    # Check if it's a number
    if [[ "$value" =~ ^-?[0-9]+$ ]] || [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]]; then
        echo "$value"
        return
    fi
    
    # If it's not a recognized type, treat as string
    local escaped_value=$(json_escape "$value")
    echo "\"$escaped_value\""
}

# Function to process the CSV file
process_csv() {
    local csv_file="$1"
    local header_line=""
    local header=()
    local line_number=0
    local output=""
    local objects=()
    
    # Read file line by line
    while IFS= read -r line; do
        ((line_number++))
        
        # Skip empty lines
        if [ -z "$line" ]; then
            continue
        fi
        
        # Handle header line
        if [ $line_number -eq 1 ] && [ "$HAS_HEADER" = true ]; then
            header_line="$line"
            IFS="$DELIMITER" read -ra header <<< "$header_line"
            
            # Clean up header field names
            for i in "${!header[@]}"; do
                # Remove quotes if present
                header[$i]=${header[$i]#\"}
                header[$i]=${header[$i]%\"}
                
                # Replace spaces with underscores and remove special characters
                header[$i]=$(echo "${header[$i]}" | tr ' ' '_' | tr -cd 'a-zA-Z0-9_')
                
                # Ensure the field name is not empty
                if [ -z "${header[$i]}" ]; then
                    header[$i]="field_$i"
                fi
            done
            
            if [ "$VERBOSE" = true ]; then
                log_info "Detected fields: ${header[*]}"
            fi
            continue
        fi
        
        # If no header, use provided field names or generate them
        if [ "$HAS_HEADER" = false ] && [ $line_number -eq 1 ]; then
            if [ -n "$FIELD_NAMES" ]; then
                IFS="$DELIMITER" read -ra header <<< "$FIELD_NAMES"
            else
                # Count the number of fields in the first line
                local field_count
                IFS="$DELIMITER" read -ra tmp_fields <<< "$line"
                field_count=${#tmp_fields[@]}
                
                # Generate field names
                for ((i=0; i<field_count; i++)); do
                    header[$i]="field_$i"
                done
            fi
            
            if [ "$VERBOSE" = true ]; then
                log_info "Using fields: ${header[*]}"
            fi
        fi
        
        # Process data line
        local fields
        IFS="$DELIMITER" read -ra fields <<< "$line"
        
        # Create JSON object for this row
        local obj="{"
        local first=true
        
        for i in "${!fields[@]}"; do
            if [ $i -ge ${#header[@]} ]; then
                if [ "$IGNORE_ERRORS" = true ]; then
                    log_warning "Line $line_number: More fields than headers, ignoring extra field"
                    break
                else
                    log_error "Line $line_number: More fields than headers"
                    exit 1
                fi
            fi
            
            local field_name="${header[$i]}"
            local field_value="${fields[$i]}"
            
            # Remove quotes if present
            field_value=${field_value#\"}
            field_value=${field_value%\"}
            
            # Process value based on type detection
            local json_value
            if [ "$DETECT_TYPES" = true ]; then
                json_value=$(detect_type "$field_value" "$field_name")
            else
                # Always treat as string
                local escaped_value=$(json_escape "$field_value")
                json_value="\"$escaped_value\""
            fi
            
            # Add field to object
            if [ "$first" = true ]; then
                first=false
            else
                obj+=","
            fi
            obj+="\"$field_name\":$json_value"
        done
        
        # Add any missing fields (if there are fewer fields than headers)
        for ((i=${#fields[@]}; i<${#header[@]}; i++)); do
            if [ "$first" = true ]; then
                first=false
            else
                obj+=","
            fi
            
            local field_name="${header[$i]}"
            obj+="\"$field_name\":null"
        done
        
        obj+="}"
        objects+=("$obj")
        
    done < "$csv_file"
    
    # Construct the final JSON output
    if [ "$OUTPUT_AS_ARRAY" = true ]; then
        # Output as simple array of values
        output="["
        local first=true
        for obj in "${objects[@]}"; do
            if [ "$first" = true ]; then
                first=false
            else
                output+=","
            fi
            output+="$obj"
        done
        output+="]"
    else
        # Output as array of objects
        output="["
        local first=true
        for obj in "${objects[@]}"; do
            if [ "$first" = true ]; then
                first=false
            else
                output+=","
            fi
            output+="$obj"
        done
        output+="]"
    fi
    
    echo "$output"
}

# Main function
main() {
    # Process CSV file
    local json_output
    
    if [ "$VERBOSE" = true ]; then
        log_info "Processing CSV file: $CSV_FILE"
        log_info "Delimiter: $(if [ "$DELIMITER" = "," ]; then echo "comma"; else echo "'$DELIMITER'"; fi)"
        log_info "Has header: $HAS_HEADER"
        log_info "Output as array: $OUTPUT_AS_ARRAY"
        log_info "Type detection: $DETECT_TYPES"
    fi
    
    json_output=$(process_csv "$CSV_FILE")
    
    # Apply jq filter if specified
    if [ -n "$JQ_FILTER" ]; then
        if [ "$VERBOSE" = true ]; then
            log_info "Applying jq filter: $JQ_FILTER"
        fi
        json_output=$(echo "$json_output" | jq "$JQ_FILTER")
    # Pretty print if requested
    elif [ "$PRETTY_PRINT" = true ] && command -v jq &>/dev/null; then
        if [ "$VERBOSE" = true ]; then
            log_info "Pretty-printing JSON output"
        fi
        json_output=$(echo "$json_output" | jq .)
    fi
    
    # Output the result
    if [ -n "$OUTPUT_FILE" ]; then
        if [ "$VERBOSE" = true ]; then
            log_info "Writing output to file: $OUTPUT_FILE"
        fi
        echo "$json_output" > "$OUTPUT_FILE"
        log_success "JSON output written to $OUTPUT_FILE"
    else
        # Output to stdout
        echo "$json_output"
    fi
}

# Run the main function
main