#!/bin/bash
#
# ssl_expiry_checker.sh - Check SSL certificate expiry dates
#
# This script checks SSL/TLS certificate expiration dates for domains or certificate
# files and provides alerts when certificates are approaching expiration.
#
# Usage:
#   ./ssl_expiry_checker.sh [options] [domain|certificate_file]...
#
# Options:
#   -d, --domain <domain>       Domain to check (can be used multiple times)
#   -f, --file <cert_file>      Certificate file to check (can be used multiple times)
#   -p, --port <port>           Port to connect to for domain checks (default: 443)
#   -w, --warning <days>        Warning threshold in days (default: 30)
#   -c, --critical <days>       Critical threshold in days (default: 7)
#   -t, --timeout <seconds>     Connection timeout in seconds (default: 10)
#   -o, --output <file>         Write results to file
#   -a, --append                Append to output file instead of overwriting
#   -m, --mail <email>          Send email alerts for warnings and critical issues
#   -s, --slack <webhook>       Send Slack alerts via webhook URL
#   --format <format>           Output format (text, csv, json; default: text)
#   -q, --quiet                 Only output warnings and errors
#   -v, --verbose               Display detailed output
#   -h, --help                  Display this help message
#
# Requirements:
#   - OpenSSL for certificate checking
#   - curl for Slack notifications
#   - mail command for email notifications
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
DOMAINS=()
CERT_FILES=()
PORT=443
WARNING_DAYS=30
CRITICAL_DAYS=7
TIMEOUT=10
OUTPUT_FILE=""
APPEND=false
EMAIL=""
SLACK_WEBHOOK=""
FORMAT="text"
QUIET=false
VERBOSE=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options] [domain|certificate_file]..."
    echo ""
    echo "Check SSL certificate expiry dates."
    echo ""
    echo "Options:"
    echo "  -d, --domain <domain>       Domain to check (can be used multiple times)"
    echo "  -f, --file <cert_file>      Certificate file to check (can be used multiple times)"
    echo "  -p, --port <port>           Port to connect to for domain checks (default: 443)"
    echo "  -w, --warning <days>        Warning threshold in days (default: 30)"
    echo "  -c, --critical <days>       Critical threshold in days (default: 7)"
    echo "  -t, --timeout <seconds>     Connection timeout in seconds (default: 10)"
    echo "  -o, --output <file>         Write results to file"
    echo "  -a, --append                Append to output file instead of overwriting"
    echo "  -m, --mail <email>          Send email alerts for warnings and critical issues"
    echo "  -s, --slack <webhook>       Send Slack alerts via webhook URL"
    echo "  --format <format>           Output format (text, csv, json; default: text)"
    echo "  -q, --quiet                 Only output warnings and errors"
    echo "  -v, --verbose               Display detailed output"
    echo "  -h, --help                  Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") example.com github.com"
    echo "  $(basename "$0") -d example.com -d github.com -w 45 -c 14"
    echo "  $(basename "$0") -f /etc/ssl/certs/server.crt -m admin@example.com"
    echo "  $(basename "$0") -d example.com --format json -o ssl_report.json"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -d|--domain)
                DOMAINS+=("$2")
                shift 2
                ;;
            -f|--file)
                if [ ! -f "$2" ]; then
                    log_error "Certificate file not found: $2"
                    exit 1
                fi
                CERT_FILES+=("$2")
                shift 2
                ;;
            -p|--port)
                PORT="$2"
                if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
                    log_error "Port must be an integer between 1 and 65535"
                    exit 1
                fi
                shift 2
                ;;
            -w|--warning)
                WARNING_DAYS="$2"
                if ! [[ "$WARNING_DAYS" =~ ^[0-9]+$ ]] || [ "$WARNING_DAYS" -lt 1 ]; then
                    log_error "Warning threshold must be a positive integer"
                    exit 1
                fi
                shift 2
                ;;
            -c|--critical)
                CRITICAL_DAYS="$2"
                if ! [[ "$CRITICAL_DAYS" =~ ^[0-9]+$ ]] || [ "$CRITICAL_DAYS" -lt 1 ]; then
                    log_error "Critical threshold must be a positive integer"
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
                shift 2
                ;;
            -a|--append)
                APPEND=true
                shift
                ;;
            -m|--mail)
                EMAIL="$2"
                shift 2
                ;;
            -s|--slack)
                SLACK_WEBHOOK="$2"
                shift 2
                ;;
            --format)
                FORMAT="$2"
                # Validate format
                case "${FORMAT,,}" in
                    text|csv|json)
                        FORMAT="${FORMAT,,}"
                        ;;
                    *)
                        log_error "Invalid format: $FORMAT"
                        log_error "Valid formats: text, csv, json"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -q|--quiet)
                QUIET=true
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
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                # Assume argument is a domain
                DOMAINS+=("$1")
                shift
                ;;
        esac
    done
    
    # Validate that we have something to check
    if [ ${#DOMAINS[@]} -eq 0 ] && [ ${#CERT_FILES[@]} -eq 0 ]; then
        log_error "No domains or certificate files specified"
        show_usage
        exit 1
    fi
    
    # Make sure warning threshold is greater than critical threshold
    if [ "$WARNING_DAYS" -le "$CRITICAL_DAYS" ]; then
        log_warning "Warning threshold ($WARNING_DAYS days) is less than or equal to critical threshold ($CRITICAL_DAYS days)"
        log_warning "Setting warning threshold to $((CRITICAL_DAYS + 1)) days"
        WARNING_DAYS=$((CRITICAL_DAYS + 1))
    fi
    
    # Check for required utilities
    check_requirements
}

# Function to check for required commands
check_requirements() {
    # Check for OpenSSL
    if ! command -v openssl &>/dev/null; then
        log_error "OpenSSL is required but not installed"
        log_error "Please install OpenSSL for your distribution:"
        log_error "  - Debian/Ubuntu: sudo apt-get install openssl"
        log_error "  - RHEL/CentOS: sudo yum install openssl"
        log_error "  - Fedora: sudo dnf install openssl"
        exit 1
    fi
    
    # Check for curl if Slack webhook is specified
    if [ -n "$SLACK_WEBHOOK" ] && ! command -v curl &>/dev/null; then
        log_error "curl is required for Slack notifications but not installed"
        log_error "Please install curl for your distribution:"
        log_error "  - Debian/Ubuntu: sudo apt-get install curl"
        log_error "  - RHEL/CentOS: sudo yum install curl"
        log_error "  - Fedora: sudo dnf install curl"
        exit 1
    fi
    
    # Check for mail command if email is specified
    if [ -n "$EMAIL" ] && ! command -v mail &>/dev/null; then
        log_error "mail command is required for email notifications but not installed"
        log_error "Please install a mail client for your distribution:"
        log_error "  - Debian/Ubuntu: sudo apt-get install mailutils"
        log_error "  - RHEL/CentOS: sudo yum install mailx"
        log_error "  - Fedora: sudo dnf install mailx"
        exit 1
    fi
}

# Function to check domain certificate
check_domain_cert() {
    local domain="$1"
    local port="$2"
    local timeout="$3"
    
    log_info "Checking certificate for domain: $domain:$port"
    
    # Create a temporary file for the certificate
    local temp_file
    temp_file=$(mktemp)
    
    # Get certificate from domain
    if ! timeout "$timeout" openssl s_client -servername "$domain" -connect "$domain:$port" </dev/null 2>/dev/null | openssl x509 -outform PEM > "$temp_file"; then
        log_error "Failed to retrieve certificate for $domain:$port"
        rm -f "$temp_file"
        return 1
    fi
    
    # Check if certificate is valid
    if [ ! -s "$temp_file" ]; then
        log_error "Retrieved certificate for $domain:$port is empty or invalid"
        rm -f "$temp_file"
        return 1
    fi
    
    # Get certificate information
    get_cert_info "$temp_file" "$domain:$port"
    local result=$?
    
    # Clean up
    rm -f "$temp_file"
    
    return $result
}

# Function to check certificate file
check_cert_file() {
    local cert_file="$1"
    
    log_info "Checking certificate file: $cert_file"
    
    # Verify the certificate file is valid
    if ! openssl x509 -in "$cert_file" -noout &>/dev/null; then
        log_error "Invalid certificate file: $cert_file"
        return 1
    fi
    
    # Get certificate information
    get_cert_info "$cert_file" "$cert_file"
    return $?
}

# Function to get certificate information
get_cert_info() {
    local cert_file="$1"
    local identifier="$2"
    
    # Get certificate subject
    local subject
    subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed -e 's/^subject=//')
    
    if [ -z "$subject" ]; then
        log_error "Failed to get subject for $identifier"
        return 1
    fi
    
    # Get certificate issuer
    local issuer
    issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null | sed -e 's/^issuer=//')
    
    if [ -z "$issuer" ]; then
        log_error "Failed to get issuer for $identifier"
        return 1
    fi
    
    # Get certificate common name
    local common_name
    common_name=$(echo "$subject" | grep -o "CN=[^,/]\+" | sed -e 's/^CN=//')
    
    if [ -z "$common_name" ]; then
        common_name="Unknown"
    fi
    
    # Get alternative names (SANs)
    local sans
    sans=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -n1 | sed -e 's/^[[:space:]]*//' -e 's/DNS://g' -e 's/, /,/g')
    
    # Get expiry date
    local expiry_date
    expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | sed -e 's/^notAfter=//')
    
    if [ -z "$expiry_date" ]; then
        log_error "Failed to get expiry date for $identifier"
        return 1
    fi
    
    # Convert expiry date to seconds since epoch
    local expiry_date_epoch
    expiry_date_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        # Try alternative date format parsing for systems like macOS
        expiry_date_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            log_error "Failed to parse expiry date for $identifier"
            return 1
        fi
    fi
    
    # Get current date in seconds since epoch
    local current_date_epoch
    current_date_epoch=$(date +%s)
    
    # Calculate days until expiry
    local days_until_expiry
    days_until_expiry=$(( (expiry_date_epoch - current_date_epoch) / 86400 ))
    
    # Determine status
    local status="OK"
    if [ "$days_until_expiry" -le "$CRITICAL_DAYS" ]; then
        status="CRITICAL"
    elif [ "$days_until_expiry" -le "$WARNING_DAYS" ]; then
        status="WARNING"
    fi
    
    # Format output
    if [ "$VERBOSE" = true ]; then
        log_debug "Subject: $subject"
        log_debug "Issuer: $issuer"
        log_debug "Common Name: $common_name"
        log_debug "SANs: $sans"
        log_debug "Expiry Date: $expiry_date"
        log_debug "Days Until Expiry: $days_until_expiry"
    fi
    
    output_result "$identifier" "$common_name" "$sans" "$issuer" "$expiry_date" "$days_until_expiry" "$status"
    
    # Return non-zero if certificate is in warning or critical state
    if [ "$status" != "OK" ]; then
        return 1
    fi
    
    return 0
}

# Function to format and output result
output_result() {
    local identifier="$1"
    local common_name="$2"
    local sans="$3"
    local issuer="$4"
    local expiry_date="$5"
    local days_until_expiry="$6"
    local status="$7"
    
    # Get current timestamp
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Format output based on selected format
    local output
    case "$FORMAT" in
        text)
            output=$(printf "%-20s %-40s %-15s %-20s %-15s\n" \
                "$identifier" "$common_name" "$days_until_expiry days" "$expiry_date" "$status")
            ;;
        csv)
            output=$(printf "%s,%s,%s,%s,%s,%s,%s\n" \
                "$timestamp" "$identifier" "$common_name" "$sans" "$issuer" "$days_until_expiry" "$status")
            ;;
        json)
            output=$(printf '{"timestamp":"%s","identifier":"%s","common_name":"%s","sans":"%s","issuer":"%s","expiry_date":"%s","days_until_expiry":%d,"status":"%s"}\n' \
                "$timestamp" "$identifier" "$common_name" "$sans" "$issuer" "$expiry_date" "$days_until_expiry" "$status")
            ;;
    esac
    
    # Only output if not quiet or there's a warning/critical issue
    if [ "$QUIET" = false ] || [ "$status" != "OK" ]; then
        if [ -n "$OUTPUT_FILE" ]; then
            if [ "$APPEND" = true ]; then
                echo "$output" >> "$OUTPUT_FILE"
            else
                echo "$output" > "$OUTPUT_FILE"
                APPEND=true  # Set to true after first write to append subsequent lines
            fi
        else
            echo "$output"
        fi
    fi
    
    # Log appropriate message
    case "$status" in
        OK)
            log_success "Certificate for $identifier expires in $days_until_expiry days ($expiry_date)"
            ;;
        WARNING)
            log_warning "Certificate for $identifier expires in $days_until_expiry days ($expiry_date)"
            send_alerts "$identifier" "$common_name" "$days_until_expiry" "$expiry_date" "$status"
            ;;
        CRITICAL)
            log_error "Certificate for $identifier expires in $days_until_expiry days ($expiry_date)"
            send_alerts "$identifier" "$common_name" "$days_until_expiry" "$expiry_date" "$status"
            ;;
    esac
}

# Function to print header
print_header() {
    case "$FORMAT" in
        text)
            printf "%-20s %-40s %-15s %-20s %-15s\n" \
                "IDENTIFIER" "COMMON NAME" "EXPIRY" "EXPIRY DATE" "STATUS"
            printf "%-20s %-40s %-15s %-20s %-15s\n" \
                "--------------------" "----------------------------------------" "---------------" "--------------------" "---------------"
            ;;
        csv)
            printf "%s,%s,%s,%s,%s,%s,%s\n" \
                "timestamp" "identifier" "common_name" "sans" "issuer" "days_until_expiry" "status"
            ;;
        json)
            # For JSON, we'll start an array
            printf '[\n'
            ;;
    esac
}

# Function to print footer
print_footer() {
    if [ "$FORMAT" = "json" ]; then
        # Close the JSON array
        printf ']\n'
    fi
}

# Function to send alerts
send_alerts() {
    local identifier="$1"
    local common_name="$2"
    local days_until_expiry="$3"
    local expiry_date="$4"
    local status="$5"
    
    # Send email alert if configured
    if [ -n "$EMAIL" ]; then
        send_email_alert "$identifier" "$common_name" "$days_until_expiry" "$expiry_date" "$status"
    fi
    
    # Send Slack alert if configured
    if [ -n "$SLACK_WEBHOOK" ]; then
        send_slack_alert "$identifier" "$common_name" "$days_until_expiry" "$expiry_date" "$status"
    fi
}

# Function to send email alert
send_email_alert() {
    local identifier="$1"
    local common_name="$2"
    local days_until_expiry="$3"
    local expiry_date="$4"
    local status="$5"
    
    local subject="SSL Certificate $status: $identifier expires in $days_until_expiry days"
    local body="SSL Certificate Alert\n\n"
    body+="Status: $status\n"
    body+="Identifier: $identifier\n"
    body+="Common Name: $common_name\n"
    body+="Days Until Expiry: $days_until_expiry\n"
    body+="Expiry Date: $expiry_date\n\n"
    body+="This alert was generated by $(basename "$0") on $(hostname) at $(date)."
    
    log_info "Sending email alert to: $EMAIL"
    
    echo -e "$body" | mail -s "$subject" "$EMAIL"
    
    if [ $? -eq 0 ]; then
        log_success "Email alert sent successfully"
    else
        log_error "Failed to send email alert"
    fi
}

# Function to send Slack alert
send_slack_alert() {
    local identifier="$1"
    local common_name="$2"
    local days_until_expiry="$3"
    local expiry_date="$4"
    local status="$5"
    
    local color
    if [ "$status" = "CRITICAL" ]; then
        color="danger"
    else
        color="warning"
    fi
    
    local payload
    payload=$(cat <<EOF
{
    "attachments": [
        {
            "fallback": "SSL Certificate $status: $identifier expires in $days_until_expiry days",
            "color": "$color",
            "title": "SSL Certificate $status Alert",
            "fields": [
                {
                    "title": "Identifier",
                    "value": "$identifier",
                    "short": true
                },
                {
                    "title": "Common Name",
                    "value": "$common_name",
                    "short": true
                },
                {
                    "title": "Days Until Expiry",
                    "value": "$days_until_expiry",
                    "short": true
                },
                {
                    "title": "Expiry Date",
                    "value": "$expiry_date",
                    "short": true
                }
            ],
            "footer": "SSL Expiry Checker | $(hostname)",
            "ts": $(date +%s)
        }
    ]
}
EOF
    )
    
    log_info "Sending Slack alert"
    
    curl -s -X POST -H "Content-type: application/json" -d "$payload" "$SLACK_WEBHOOK" &>/dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Slack alert sent successfully"
    else
        log_error "Failed to send Slack alert"
    fi
}

# Main execution
main() {
    parse_arguments "$@"
    
    log_info "Starting SSL certificate expiry check"
    log_info "Warning threshold: $WARNING_DAYS days, Critical threshold: $CRITICAL_DAYS days"
    
    # Initialize counters
    local total_count=0
    local error_count=0
    local warning_count=0
    local critical_count=0
    
    # Print header if not quiet
    if [ "$QUIET" = false ]; then
        local header
        header=$(print_header)
        
        if [ -n "$OUTPUT_FILE" ]; then
            echo "$header" > "$OUTPUT_FILE"
        elif [ -n "$header" ]; then
            echo "$header"
        fi
    fi
    
    # Check domain certificates
    for domain in "${DOMAINS[@]}"; do
        total_count=$((total_count + 1))
        
        if ! check_domain_cert "$domain" "$PORT" "$TIMEOUT"; then
            if [ "$(check_domain_cert "$domain" "$PORT" "$TIMEOUT" | grep -c CRITICAL)" -gt 0 ]; then
                critical_count=$((critical_count + 1))
            elif [ "$(check_domain_cert "$domain" "$PORT" "$TIMEOUT" | grep -c WARNING)" -gt 0 ]; then
                warning_count=$((warning_count + 1))
            else
                error_count=$((error_count + 1))
            fi
        fi
    done
    
    # Check certificate files
    for cert_file in "${CERT_FILES[@]}"; do
        total_count=$((total_count + 1))
        
        if ! check_cert_file "$cert_file"; then
            if [ "$(check_cert_file "$cert_file" | grep -c CRITICAL)" -gt 0 ]; then
                critical_count=$((critical_count + 1))
            elif [ "$(check_cert_file "$cert_file" | grep -c WARNING)" -gt 0 ]; then
                warning_count=$((warning_count + 1))
            else
                error_count=$((error_count + 1))
            fi
        fi
    done
    
    # Print footer if using JSON format
    if [ "$FORMAT" = "json" ] && [ "$QUIET" = false ]; then
        local footer
        footer=$(print_footer)
        
        if [ -n "$OUTPUT_FILE" ]; then
            echo "$footer" >> "$OUTPUT_FILE"
        elif [ -n "$footer" ]; then
            echo "$footer"
        fi
    fi
    
    # Print summary
    log_info "SSL check summary:"
    log_info "  Total certificates checked: $total_count"
    
    if [ "$error_count" -gt 0 ]; then
        log_error "  Errors: $error_count"
    else
        log_info "  Errors: $error_count"
    fi
    
    if [ "$warning_count" -gt 0 ]; then
        log_warning "  Warnings: $warning_count (expires in $WARNING_DAYS days or less)"
    else
        log_info "  Warnings: $warning_count"
    fi
    
    if [ "$critical_count" -gt 0 ]; then
        log_error "  Critical: $critical_count (expires in $CRITICAL_DAYS days or less)"
    else
        log_info "  Critical: $critical_count"
    fi
    
    # Set exit code based on results
    if [ "$critical_count" -gt 0 ]; then
        exit 2
    elif [ "$warning_count" -gt 0 ]; then
        exit 1
    elif [ "$error_count" -gt 0 ]; then
        exit 3
    else
        exit 0
    fi
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi