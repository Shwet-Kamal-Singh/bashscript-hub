#!/bin/bash
#
# Script Name: create_users_bulk.sh
# Description: Create multiple user accounts from a CSV file
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./create_users_bulk.sh [options]
#
# Options:
#   -f, --file <csv_file>        CSV file with user information (required)
#   -c, --create-home            Create home directories (default)
#   -n, --no-home                Don't create home directories
#   -s, --shell <shell_path>     Default shell for new users (default: /bin/bash)
#   -g, --default-group <group>  Default primary group (default: users)
#   -G, --add-groups <groups>    Additional groups (comma-separated)
#   -p, --password-method <method>  Password method: random|predefined|none (default: random)
#   -l, --password-length <len>  Length for random passwords (default: 12)
#   -e, --password-expire        Force password change on first login
#   -E, --expire-days <days>     Password expiry days (default: system default)
#   -m, --mail-template <file>   Template file for welcome email
#   -M, --mail-command <cmd>     Mail command to use (default: mail)
#   -S, --ssh-key-dir <dir>      Directory with SSH keys for users
#   -d, --dry-run                Show what would be done without making changes
#   -o, --output <file>          Output results to file
#   -v, --verbose                Show detailed output
#   -h, --help                   Display this help message
#
# CSV File Format:
#   username,fullname,password,email,groups,shell,ssh_key
#
#   All fields except username are optional. If password is empty, it will be
#   generated based on password-method.
#
# Examples:
#   ./create_users_bulk.sh -f users.csv
#   ./create_users_bulk.sh -f users.csv -p predefined -e -G sudo,developers
#   ./create_users_bulk.sh -f users.csv -d -v
#
# Requirements:
#   - Root privileges (or sudo)
#   - Valid CSV file
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
CSV_FILE=""
CREATE_HOME=true
DEFAULT_SHELL="/bin/bash"
DEFAULT_GROUP="users"
ADDITIONAL_GROUPS=""
PASSWORD_METHOD="random"
PASSWORD_LENGTH=12
PASSWORD_EXPIRE=false
EXPIRE_DAYS=""
MAIL_TEMPLATE=""
MAIL_COMMAND="mail"
SSH_KEY_DIR=""
DRY_RUN=false
OUTPUT_FILE=""
VERBOSE=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            CSV_FILE="$2"
            shift 2
            ;;
        -c|--create-home)
            CREATE_HOME=true
            shift
            ;;
        -n|--no-home)
            CREATE_HOME=false
            shift
            ;;
        -s|--shell)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            DEFAULT_SHELL="$2"
            shift 2
            ;;
        -g|--default-group)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            DEFAULT_GROUP="$2"
            shift 2
            ;;
        -G|--add-groups)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            ADDITIONAL_GROUPS="$2"
            shift 2
            ;;
        -p|--password-method)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if [[ "$2" != "random" && "$2" != "predefined" && "$2" != "none" ]]; then
                log_error "Invalid password method: $2"
                log_error "Valid options: random, predefined, none"
                exit 1
            fi
            PASSWORD_METHOD="$2"
            shift 2
            ;;
        -l|--password-length)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid password length: $2"
                exit 1
            fi
            PASSWORD_LENGTH="$2"
            shift 2
            ;;
        -e|--password-expire)
            PASSWORD_EXPIRE=true
            shift
            ;;
        -E|--expire-days)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid expire days: $2"
                exit 1
            fi
            EXPIRE_DAYS="$2"
            shift 2
            ;;
        -m|--mail-template)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            MAIL_TEMPLATE="$2"
            shift 2
            ;;
        -M|--mail-command)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            MAIL_COMMAND="$2"
            shift 2
            ;;
        -S|--ssh-key-dir)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            SSH_KEY_DIR="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -o|--output)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            # Extract and display script header
            grep -E '^# (Script Name:|Description:|Usage:|Options:|CSV File Format:|Examples:|Requirements:)' "$0" | sed 's/^# //'
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
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root or with sudo"
    exit 1
fi

# Check if CSV file is provided
if [ -z "$CSV_FILE" ]; then
    log_error "CSV file is required"
    log_error "Use -f/--file option to specify the CSV file"
    exit 1
fi

# Check if CSV file exists
if [ ! -f "$CSV_FILE" ]; then
    log_error "CSV file not found: $CSV_FILE"
    exit 1
fi

# Initialize output file if specified
if [ -n "$OUTPUT_FILE" ]; then
    # Create or truncate the output file
    > "$OUTPUT_FILE"
    
    # Header for the output file
    if [ "$DRY_RUN" = true ]; then
        echo "# Bulk User Creation Dry Run - $(date)" >> "$OUTPUT_FILE"
    else
        echo "# Bulk User Creation Results - $(date)" >> "$OUTPUT_FILE"
    fi
    echo -e "Username\tFullname\tPassword\tEmail\tGroups\tShell\tStatus\tNotes" >> "$OUTPUT_FILE"
fi

# Function to log to output file
log_to_output() {
    local username="$1"
    local fullname="$2"
    local password="$3"
    local email="$4"
    local groups="$5"
    local shell="$6"
    local status="$7"
    local notes="$8"
    
    if [ -n "$OUTPUT_FILE" ]; then
        echo -e "$username\t$fullname\t$password\t$email\t$groups\t$shell\t$status\t$notes" >> "$OUTPUT_FILE"
    fi
}

# Function to generate a random password
generate_password() {
    local length="$1"
    local password=""
    
    # Check if we have openssl
    if command -v openssl >/dev/null 2>&1; then
        password=$(openssl rand -base64 "$((length * 3 / 4))" | tr -d '/+=' | cut -c1-"$length")
    else
        # Fallback to /dev/urandom
        password=$(tr -dc 'a-zA-Z0-9@#$%^&*()_+{}[]|:;<>,.?/~' < /dev/urandom | head -c "$length")
    fi
    
    echo "$password"
}

# Function to normalize username (convert to lowercase, replace spaces)
normalize_username() {
    local username="$1"
    
    # Convert to lowercase
    username=$(echo "$username" | tr '[:upper:]' '[:lower:]')
    
    # Replace spaces with underscores
    username=$(echo "$username" | tr ' ' '_')
    
    # Remove any special characters except underscore
    username=$(echo "$username" | tr -cd '[:alnum:]_')
    
    echo "$username"
}

# Function to validate username
validate_username() {
    local username="$1"
    
    # Check if username is valid
    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
        return 1
    fi
    
    # Check if username is too long
    if [ ${#username} -gt 32 ]; then
        return 2
    fi
    
    return 0
}

# Function to check if a user already exists
user_exists() {
    local username="$1"
    
    if id "$username" >/dev/null 2>&1; then
        return 0  # User exists
    else
        return 1  # User does not exist
    fi
}

# Function to check if a group exists, create if specified
ensure_group_exists() {
    local group="$1"
    local create="$2"  # true|false
    
    if getent group "$group" >/dev/null 2>&1; then
        return 0  # Group exists
    elif [ "$create" = true ]; then
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Would create group: $group"
        else
            if groupadd "$group"; then
                log_success "Created group: $group"
                return 0
            else
                log_error "Failed to create group: $group"
                return 1
            fi
        fi
    else
        log_warning "Group does not exist: $group"
        return 1
    fi
}

# Function to create a user
create_user() {
    local username="$1"
    local fullname="$2"
    local password="$3"
    local email="$4"
    local groups="$5"
    local shell="$6"
    local ssh_key="$7"
    
    local useradd_cmd="useradd"
    local status="FAILED"
    local notes=""
    
    # Normalize and validate username
    if [ -z "$username" ]; then
        log_error "Username cannot be empty"
        log_to_output "" "$fullname" "" "$email" "$groups" "$shell" "ERROR" "Empty username"
        return 1
    fi
    
    username=$(normalize_username "$username")
    validate_username "$username"
    local valid_result=$?
    
    if [ $valid_result -eq 1 ]; then
        log_error "Invalid username format: $username"
        log_to_output "$username" "$fullname" "" "$email" "$groups" "$shell" "ERROR" "Invalid username format"
        return 1
    elif [ $valid_result -eq 2 ]; then
        log_error "Username too long: $username"
        log_to_output "$username" "$fullname" "" "$email" "$groups" "$shell" "ERROR" "Username too long"
        return 1
    fi
    
    # Check if user already exists
    if user_exists "$username"; then
        log_warning "User already exists: $username"
        log_to_output "$username" "$fullname" "" "$email" "$groups" "$shell" "SKIPPED" "User already exists"
        return 0
    fi
    
    # Handle password
    local password_arg=""
    if [ "$PASSWORD_METHOD" = "random" ]; then
        if [ -z "$password" ]; then
            password=$(generate_password "$PASSWORD_LENGTH")
        fi
        password_arg="-p $(openssl passwd -6 "$password")"
    elif [ "$PASSWORD_METHOD" = "predefined" ]; then
        if [ -n "$password" ]; then
            password_arg="-p $(openssl passwd -6 "$password")"
        else
            log_warning "No password provided for user $username, using random password"
            password=$(generate_password "$PASSWORD_LENGTH")
            password_arg="-p $(openssl passwd -6 "$password")"
        fi
    elif [ "$PASSWORD_METHOD" = "none" ]; then
        password_arg="-p '!'"  # Lock the password
        password="[LOCKED]"
    fi
    
    # Handle home directory
    local home_arg=""
    if [ "$CREATE_HOME" = true ]; then
        home_arg="-m"
    else
        home_arg="-M"
    fi
    
    # Handle shell
    local shell_arg=""
    if [ -n "$shell" ]; then
        shell_arg="-s $shell"
    elif [ -n "$DEFAULT_SHELL" ]; then
        shell_arg="-s $DEFAULT_SHELL"
    fi
    
    # Handle full name (comment)
    local comment_arg=""
    if [ -n "$fullname" ]; then
        comment_arg="-c '$fullname'"
    fi
    
    # Handle default group
    local group_arg=""
    if [ -n "$DEFAULT_GROUP" ]; then
        # Check if the group exists, create if it doesn't
        if ensure_group_exists "$DEFAULT_GROUP" true; then
            group_arg="-g $DEFAULT_GROUP"
        fi
    fi
    
    # Handle additional groups
    local additional_groups="$groups"
    if [ -n "$ADDITIONAL_GROUPS" ]; then
        if [ -n "$additional_groups" ]; then
            additional_groups="$additional_groups,$ADDITIONAL_GROUPS"
        else
            additional_groups="$ADDITIONAL_GROUPS"
        fi
    fi
    
    local groups_arg=""
    if [ -n "$additional_groups" ]; then
        # Check if groups exist
        local all_groups_exist=true
        IFS=',' read -ra GROUP_ARRAY <<< "$additional_groups"
        for group in "${GROUP_ARRAY[@]}"; do
            if ! ensure_group_exists "$group" false; then
                all_groups_exist=false
                log_warning "Group does not exist and won't be added: $group"
            fi
        done
        
        if [ "$all_groups_exist" = true ]; then
            groups_arg="-G $additional_groups"
        else
            local existing_groups=""
            for group in "${GROUP_ARRAY[@]}"; do
                if ensure_group_exists "$group" false; then
                    if [ -n "$existing_groups" ]; then
                        existing_groups="$existing_groups,$group"
                    else
                        existing_groups="$group"
                    fi
                fi
            done
            
            if [ -n "$existing_groups" ]; then
                groups_arg="-G $existing_groups"
            fi
        fi
    fi
    
    # Build the complete useradd command
    useradd_cmd="useradd $home_arg $comment_arg $group_arg $groups_arg $shell_arg $password_arg $username"
    
    # Display the command in verbose mode
    if [ "$VERBOSE" = true ]; then
        # Hide the actual password in the displayed command
        local display_cmd
        if [ -n "$password_arg" ]; then
            display_cmd=$(echo "$useradd_cmd" | sed 's/-p [^ ]*/[-p PASSWORD]/g')
        else
            display_cmd="$useradd_cmd"
        fi
        log_info "Command: $display_cmd"
    fi
    
    # Execute the command (or simulate in dry run mode)
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would execute: useradd [options] $username"
        log_info "[DRY RUN] Would create user: $username ($fullname)"
        status="DRY_RUN"
    else
        # Replace single quotes in the command to make it work
        useradd_cmd=$(echo "$useradd_cmd" | sed "s/'//g")
        
        if eval "$useradd_cmd"; then
            log_success "Created user: $username"
            status="SUCCESS"
            
            # Handle password expiry if specified
            if [ "$PASSWORD_EXPIRE" = true ]; then
                if [ "$DRY_RUN" = true ]; then
                    log_info "[DRY RUN] Would force password change on first login for user: $username"
                else
                    passwd -e "$username" >/dev/null 2>&1
                    log_info "Enabled password expiry for user: $username"
                    notes="${notes}Password expires on first login. "
                fi
            fi
            
            # Handle custom expiry days if specified
            if [ -n "$EXPIRE_DAYS" ]; then
                if [ "$DRY_RUN" = true ]; then
                    log_info "[DRY RUN] Would set password expiry to $EXPIRE_DAYS days for user: $username"
                else
                    chage -M "$EXPIRE_DAYS" "$username" >/dev/null 2>&1
                    log_info "Set password expiry to $EXPIRE_DAYS days for user: $username"
                    notes="${notes}Password expires after $EXPIRE_DAYS days. "
                fi
            fi
            
            # Handle SSH key if provided in the CSV
            if [ -n "$ssh_key" ]; then
                if [ "$DRY_RUN" = true ]; then
                    log_info "[DRY RUN] Would add SSH key for user: $username"
                else
                    if [ -d "/home/$username" ]; then
                        mkdir -p "/home/$username/.ssh"
                        echo "$ssh_key" >> "/home/$username/.ssh/authorized_keys"
                        chmod 700 "/home/$username/.ssh"
                        chmod 600 "/home/$username/.ssh/authorized_keys"
                        chown -R "$username:$(id -gn "$username")" "/home/$username/.ssh"
                        log_info "Added SSH key for user: $username"
                        notes="${notes}SSH key added. "
                    else
                        log_warning "Home directory not found for user: $username, cannot add SSH key"
                        notes="${notes}Failed to add SSH key (no home directory). "
                    fi
                fi
            # Handle SSH key directory if specified
            elif [ -n "$SSH_KEY_DIR" ] && [ -d "$SSH_KEY_DIR" ]; then
                local key_file="$SSH_KEY_DIR/$username.pub"
                if [ -f "$key_file" ]; then
                    if [ "$DRY_RUN" = true ]; then
                        log_info "[DRY RUN] Would add SSH key from $key_file for user: $username"
                    else
                        if [ -d "/home/$username" ]; then
                            mkdir -p "/home/$username/.ssh"
                            cat "$key_file" >> "/home/$username/.ssh/authorized_keys"
                            chmod 700 "/home/$username/.ssh"
                            chmod 600 "/home/$username/.ssh/authorized_keys"
                            chown -R "$username:$(id -gn "$username")" "/home/$username/.ssh"
                            log_info "Added SSH key from $key_file for user: $username"
                            notes="${notes}SSH key added from file. "
                        else
                            log_warning "Home directory not found for user: $username, cannot add SSH key"
                            notes="${notes}Failed to add SSH key (no home directory). "
                        fi
                    fi
                fi
            fi
            
            # Send welcome email if template is provided
            if [ -n "$MAIL_TEMPLATE" ] && [ -n "$email" ]; then
                if [ -f "$MAIL_TEMPLATE" ]; then
                    if [ "$DRY_RUN" = true ]; then
                        log_info "[DRY RUN] Would send welcome email to: $email"
                    else
                        # Create a temporary file for the email
                        local temp_mail=$(mktemp)
                        
                        # Prepare the email body
                        cat "$MAIL_TEMPLATE" | \
                            sed "s/{{username}}/$username/g" | \
                            sed "s/{{fullname}}/$fullname/g" | \
                            sed "s/{{email}}/$email/g" | \
                            sed "s/{{password}}/$password/g" > "$temp_mail"
                        
                        # Send the email
                        if $MAIL_COMMAND -s "Welcome to the system, $username" "$email" < "$temp_mail" >/dev/null 2>&1; then
                            log_info "Sent welcome email to: $email"
                            notes="${notes}Welcome email sent. "
                        else
                            log_warning "Failed to send welcome email to: $email"
                            notes="${notes}Failed to send welcome email. "
                        fi
                        
                        # Remove the temporary file
                        rm -f "$temp_mail"
                    fi
                else
                    log_warning "Mail template not found: $MAIL_TEMPLATE"
                    notes="${notes}Mail template not found. "
                fi
            fi
        else
            log_error "Failed to create user: $username"
        fi
    fi
    
    # Log the result to the output file
    log_to_output "$username" "$fullname" "$password" "$email" "$additional_groups" "${shell:-$DEFAULT_SHELL}" "$status" "$notes"
    
    return 0
}

# Main function
main() {
    print_header "Bulk User Creation"
    
    # Check the CSV file format
    local header=$(head -n 1 "$CSV_FILE")
    if [ "$VERBOSE" = true ]; then
        log_info "CSV header: $header"
    fi
    
    # Count valid users in the CSV
    local user_count=$(grep -v "^#" "$CSV_FILE" | wc -l)
    if [ "$header" = "username,fullname,password,email,groups,shell,ssh_key" ]; then
        user_count=$((user_count - 1))  # Subtract the header line
    fi
    
    log_info "Processing $user_count users from $CSV_FILE"
    
    # Show execution mode
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No actual changes will be made"
    fi
    
    print_section "User Creation Process"
    
    # Process the CSV file line by line
    local line_number=0
    while IFS=, read -r username fullname password email groups shell ssh_key; do
        line_number=$((line_number + 1))
        
        # Skip comments and empty lines
        if [[ "$username" =~ ^#.*$ ]] || [ -z "$username" ]; then
            continue
        fi
        
        # Skip the header line if it matches our expected format
        if [ $line_number -eq 1 ] && [ "$username" = "username" ] && [ "$fullname" = "fullname" ]; then
            continue
        fi
        
        # Create the user
        if [ "$VERBOSE" = true ]; then
            log_info "Processing line $line_number: $username"
        fi
        
        create_user "$username" "$fullname" "$password" "$email" "$groups" "$shell" "$ssh_key"
    done < "$CSV_FILE"
    
    print_header "Bulk User Creation Complete"
    
    # Summary if an output file was specified
    if [ -n "$OUTPUT_FILE" ]; then
        log_success "Results saved to: $OUTPUT_FILE"
    fi
}

# Run the main function
main