#!/bin/bash
#
# Script Name: reset_user_password.sh
# Description: Reset user passwords safely across Linux systems
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./reset_user_password.sh [options]
#
# Options:
#   -u, --user <username>        Username to reset password (required if not using -f)
#   -p, --password <password>    New password (if not provided, will generate random)
#   -f, --file <csv_file>        CSV file with username,password for bulk reset
#   -l, --length <length>        Length for generated passwords (default: 12)
#   -c, --complexity <level>     Password complexity: low|medium|high (default: medium)
#   -e, --expire                 Force password change on next login
#   -E, --expiry-days <days>     Set password expiry days (default: system default)
#   -n, --no-digits              Don't include digits in generated passwords
#   -s, --no-special             Don't include special characters in generated passwords
#   -m, --mail                   Send email with new password
#   -M, --mail-command <cmd>     Mail command to use (default: mail)
#   -t, --mail-template <file>   Email template file
#   -o, --output <file>          Output results to file
#   -d, --dry-run                Show what would be done without making changes
#   -v, --verbose                Show detailed output
#   -h, --help                   Display this help message
#
# Examples:
#   ./reset_user_password.sh -u john -p "NewP@ssw0rd"
#   ./reset_user_password.sh -u jane -e
#   ./reset_user_password.sh -f users.csv -e -o results.txt
#
# CSV File Format:
#   username,password
#
# Requirements:
#   - Root privileges (or sudo)
#
# License: MIT
# Repository: https://github.com/bashscript-hub

# Source the color_echo utility if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$ROOT_DIR/utils/color_echo.sh" ]; then
    source "$ROOT_DIR/utils/color_echo.sh"
else
    # Define minimal versions if color_echo.sh is not available
    log_info() { echo "INFO: $*"; }
    log_error() { echo "ERROR: $*" >&2; }
    log_success() { echo "SUCCESS: $*"; }
    log_warning() { echo "WARNING: $*"; }
    print_header() { echo -e "\n=== $* ===\n"; }
    print_section() { echo -e "\n--- $* ---\n"; }
fi

# Set default values
USERNAME=""
PASSWORD=""
CSV_FILE=""
PASSWORD_LENGTH=12
PASSWORD_COMPLEXITY="medium"
FORCE_EXPIRE=false
EXPIRY_DAYS=""
INCLUDE_DIGITS=true
INCLUDE_SPECIAL=true
SEND_EMAIL=false
MAIL_COMMAND="mail"
MAIL_TEMPLATE=""
OUTPUT_FILE=""
DRY_RUN=false
VERBOSE=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            USERNAME="$2"
            shift 2
            ;;
        -p|--password)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            PASSWORD="$2"
            shift 2
            ;;
        -f|--file)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            CSV_FILE="$2"
            shift 2
            ;;
        -l|--length)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid length: $2"
                exit 1
            fi
            PASSWORD_LENGTH="$2"
            shift 2
            ;;
        -c|--complexity)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "low" && "$2" != "medium" && "$2" != "high" ]]; then
                log_error "Invalid complexity level: $2"
                log_error "Valid options: low, medium, high"
                exit 1
            fi
            PASSWORD_COMPLEXITY="$2"
            shift 2
            ;;
        -e|--expire)
            FORCE_EXPIRE=true
            shift
            ;;
        -E|--expiry-days)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid expiry days: $2"
                exit 1
            fi
            EXPIRY_DAYS="$2"
            shift 2
            ;;
        -n|--no-digits)
            INCLUDE_DIGITS=false
            shift
            ;;
        -s|--no-special)
            INCLUDE_SPECIAL=false
            shift
            ;;
        -m|--mail)
            SEND_EMAIL=true
            shift
            ;;
        -M|--mail-command)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            MAIL_COMMAND="$2"
            shift 2
            ;;
        -t|--mail-template)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            MAIL_TEMPLATE="$2"
            shift 2
            ;;
        -o|--output)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            # Extract and display script header
            grep -E '^# (Script Name:|Description:|Usage:|Options:|Examples:|CSV File Format:|Requirements:)' "$0" | sed 's/^# //'
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            log_error "Use --help to see available options"
            exit 1
            ;;
    esac
done

# Check if running with root/sudo
check_root() {
    if [ $EUID -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Validate input parameters
validate_input() {
    # Check if we have a username or CSV file
    if [ -z "$USERNAME" ] && [ -z "$CSV_FILE" ]; then
        log_error "No username or CSV file specified"
        log_error "Use -u/--user option to specify a username or -f/--file for bulk reset"
        exit 1
    fi
    
    # If CSV file is specified, check if it exists
    if [ -n "$CSV_FILE" ] && [ ! -f "$CSV_FILE" ]; then
        log_error "CSV file not found: $CSV_FILE"
        exit 1
    fi
    
    # If email is enabled, check if mail command is available
    if [ "$SEND_EMAIL" = true ]; then
        # Extract the base command from MAIL_COMMAND
        local base_cmd
        base_cmd=$(echo "$MAIL_COMMAND" | awk '{print $1}')
        
        if ! command -v "$base_cmd" &>/dev/null; then
            log_warning "$base_cmd command not found, email notifications will be disabled"
            SEND_EMAIL=false
        fi
        
        # Check if template file exists
        if [ -n "$MAIL_TEMPLATE" ] && [ ! -f "$MAIL_TEMPLATE" ]; then
            log_warning "Email template file not found: $MAIL_TEMPLATE"
            MAIL_TEMPLATE=""
        fi
    fi
}

# Generate a random password
generate_password() {
    local length="$1"
    local complexity="$2"
    local include_digits="$3"
    local include_special="$4"
    
    local chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local digits="0123456789"
    local special="!@#$%^&*()-_=+[]{}|;:,.<>?"
    
    # Add digits if requested
    if [ "$include_digits" = true ]; then
        chars+="$digits"
    fi
    
    # Add special characters based on complexity
    if [ "$include_special" = true ]; then
        case "$complexity" in
            "low")
                chars+="!@#$%"
                ;;
            "medium")
                chars+="!@#$%^&*()-_=+"
                ;;
            "high")
                chars+="$special"
                ;;
        esac
    fi
    
    # Generate password
    local password=""
    
    # Use OpenSSL if available, otherwise fallback to /dev/urandom
    if command -v openssl &>/dev/null; then
        password=$(openssl rand -base64 "$((length * 3 / 4))" | tr -dc "$chars" | head -c "$length")
    else
        password=$(< /dev/urandom tr -dc "$chars" | head -c "$length")
    fi
    
    # Ensure the password has at least one character from each required category
    local has_upper=false
    local has_lower=false
    local has_digit=false
    local has_special=false
    
    for (( i=0; i<${#password}; i++ )); do
        char="${password:$i:1}"
        
        if [[ "$char" =~ [A-Z] ]]; then
            has_upper=true
        elif [[ "$char" =~ [a-z] ]]; then
            has_lower=true
        elif [[ "$char" =~ [0-9] ]]; then
            has_digit=true
        else
            has_special=true
        fi
    done
    
    # If we're missing a category, regenerate the password
    if [ "$has_upper" = false ] || [ "$has_lower" = false ] || \
       ([ "$include_digits" = true ] && [ "$has_digit" = false ]) || \
       ([ "$include_special" = true ] && [ "$has_special" = false ]); then
        generate_password "$length" "$complexity" "$include_digits" "$include_special"
    else
        echo "$password"
    fi
}

# Check if a user exists
user_exists() {
    local user="$1"
    id "$user" &>/dev/null
    return $?
}

# Reset password for a single user
reset_password() {
    local username="$1"
    local password="$2"
    
    # Check if user exists
    if ! user_exists "$username"; then
        log_error "User does not exist: $username"
        return 1
    fi
    
    # Generate a password if not provided
    if [ -z "$password" ]; then
        password=$(generate_password "$PASSWORD_LENGTH" "$PASSWORD_COMPLEXITY" "$INCLUDE_DIGITS" "$INCLUDE_SPECIAL")
    fi
    
    # Reset the password
    if [ "$DRY_RUN" = false ]; then
        if ! echo "$username:$password" | chpasswd; then
            log_error "Failed to reset password for user: $username"
            return 1
        fi
        
        # Force password expiry if requested
        if [ "$FORCE_EXPIRE" = true ]; then
            if ! passwd -e "$username"; then
                log_warning "Failed to set password expiry for user: $username"
            fi
        fi
        
        # Set password expiry days if specified
        if [ -n "$EXPIRY_DAYS" ]; then
            if ! chage -M "$EXPIRY_DAYS" "$username"; then
                log_warning "Failed to set password expiry days for user: $username"
            fi
        fi
    fi
    
    log_success "Password reset for user: $username"
    
    # Send email if requested
    if [ "$SEND_EMAIL" = true ]; then
        send_password_email "$username" "$password"
    fi
    
    # Write to output file if specified
    if [ -n "$OUTPUT_FILE" ]; then
        echo "$username,$password" >> "$OUTPUT_FILE"
    fi
    
    # Display the password only if requested or in dry run mode
    if [ "$VERBOSE" = true ] || [ "$DRY_RUN" = true ]; then
        log_info "New password for $username: $password"
    fi
    
    return 0
}

# Send email with new password
send_password_email() {
    local username="$1"
    local password="$2"
    
    # Get user's full name
    local fullname
    fullname=$(getent passwd "$username" | cut -d: -f5 | cut -d, -f1)
    
    # Get user's email
    local email
    email="$username@$(hostname -f)"
    
    # If we have a mail template, use it
    if [ -n "$MAIL_TEMPLATE" ]; then
        # Create a temporary file for the email
        local temp_mail
        temp_mail=$(mktemp)
        
        # Prepare the email body
        cat "$MAIL_TEMPLATE" | \
            sed "s/{{username}}/$username/g" | \
            sed "s/{{fullname}}/$fullname/g" | \
            sed "s/{{email}}/$email/g" | \
            sed "s/{{password}}/$password/g" > "$temp_mail"
        
        if [ "$DRY_RUN" = false ]; then
            # Send the email
            if $MAIL_COMMAND -s "Your Password Has Been Reset" "$email" < "$temp_mail"; then
                log_success "Password notification email sent to: $email"
            else
                log_warning "Failed to send password notification email to: $email"
            fi
        else
            log_info "[DRY RUN] Would send password notification email to: $email"
        fi
        
        # Remove the temporary file
        rm -f "$temp_mail"
    else
        # Create a simple email message
        local message="Hello $fullname,

Your account password has been reset.

Username: $username
New Password: $password

Please change your password immediately after logging in.

This is an automated message. Please do not reply."
        
        if [ "$DRY_RUN" = false ]; then
            # Send the email
            if echo "$message" | $MAIL_COMMAND -s "Your Password Has Been Reset" "$email"; then
                log_success "Password notification email sent to: $email"
            else
                log_warning "Failed to send password notification email to: $email"
            fi
        else
            log_info "[DRY RUN] Would send password notification email to: $email"
        fi
    fi
}

# Process CSV file for bulk password reset
process_csv_file() {
    local csv_file="$1"
    local line_number=0
    local success_count=0
    local failure_count=0
    
    # Create or truncate the output file if specified
    if [ -n "$OUTPUT_FILE" ]; then
        > "$OUTPUT_FILE"
        echo "# Password Reset Results" >> "$OUTPUT_FILE"
        echo "# Generated: $(date)" >> "$OUTPUT_FILE"
        echo "# Format: username,password" >> "$OUTPUT_FILE"
    fi
    
    # Process each line in the CSV file
    while IFS=, read -r username password; do
        ((line_number++))
        
        # Skip comments and empty lines
        if [[ "$username" =~ ^#.*$ ]] || [ -z "$username" ]; then
            continue
        fi
        
        # Skip the header line if it exists (username,password)
        if [ $line_number -eq 1 ] && [ "$username" = "username" ] && [ "$password" = "password" ]; then
            continue
        fi
        
        # Reset the password
        if reset_password "$username" "$password"; then
            ((success_count++))
        else
            ((failure_count++))
        fi
    done < "$csv_file"
    
    log_info "Processed $((success_count + failure_count)) users from CSV file"
    log_success "Successful password resets: $success_count"
    
    if [ $failure_count -gt 0 ]; then
        log_warning "Failed password resets: $failure_count"
    fi
}

# Main function
main() {
    print_header "User Password Reset"
    
    # Check if running as root
    check_root
    
    # Validate input parameters
    validate_input
    
    # Print configuration
    print_section "Configuration"
    
    if [ -n "$USERNAME" ]; then
        log_info "Target user: $USERNAME"
    elif [ -n "$CSV_FILE" ]; then
        log_info "Target users from CSV file: $CSV_FILE"
    fi
    
    if [ -n "$PASSWORD" ]; then
        log_info "Using specified password"
    else
        log_info "Will generate random passwords (length: $PASSWORD_LENGTH, complexity: $PASSWORD_COMPLEXITY)"
        log_info "Include digits: $([ "$INCLUDE_DIGITS" = true ] && echo "Yes" || echo "No")"
        log_info "Include special chars: $([ "$INCLUDE_SPECIAL" = true ] && echo "Yes" || echo "No")"
    fi
    
    log_info "Force password expiry: $([ "$FORCE_EXPIRE" = true ] && echo "Yes" || echo "No")"
    
    if [ -n "$EXPIRY_DAYS" ]; then
        log_info "Password expiry days: $EXPIRY_DAYS"
    fi
    
    log_info "Send email notification: $([ "$SEND_EMAIL" = true ] && echo "Yes" || echo "No")"
    
    if [ -n "$OUTPUT_FILE" ]; then
        log_info "Output file: $OUTPUT_FILE"
    fi
    
    log_info "Dry run mode: $([ "$DRY_RUN" = true ] && echo "Yes" || echo "No")"
    
    # Process users
    print_section "Resetting Passwords"
    
    if [ -n "$USERNAME" ]; then
        # Single user mode
        reset_password "$USERNAME" "$PASSWORD"
    elif [ -n "$CSV_FILE" ]; then
        # Bulk mode
        process_csv_file "$CSV_FILE"
    fi
    
    print_header "Password Reset Complete"
}

# Run the main function
main