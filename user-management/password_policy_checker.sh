#!/bin/bash
#
# Script Name: password_policy_checker.sh
# Description: Check password policy compliance for user accounts
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./password_policy_checker.sh [options]
#
# Options:
#   -u, --users <userlist>       Check specific users (comma-separated)
#   -g, --groups <grouplist>     Check users in specific groups (comma-separated)
#   -a, --all-users              Check all users in /etc/passwd (default: non-system only)
#   -s, --system-users           Include system users (UID < 1000)
#   -e, --min-days <days>        Minimum password age (default: 1)
#   -E, --max-days <days>        Maximum password age (default: 90)
#   -w, --warn-days <days>       Password expiry warning period (default: 7)
#   -i, --inactive-days <days>   Account inactivity lock period (default: 30)
#   -p, --policy <file>          Custom password policy file
#   -c, --check-only             Only check, don't show recommendations
#   -f, --fix                    Fix non-compliant settings
#   -r, --report <file>          Output report to file
#   -j, --json                   Output in JSON format
#   -v, --verbose                Show detailed output
#   -h, --help                   Display this help message
#
# Examples:
#   ./password_policy_checker.sh -a
#   ./password_policy_checker.sh -u john,alice -E 60 -w 5
#   ./password_policy_checker.sh -g sudo,admin -f
#
# Requirements:
#   - Root privileges (or sudo) for checking all users
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
USER_LIST=""
GROUP_LIST=""
CHECK_ALL_USERS=false
INCLUDE_SYSTEM_USERS=false
MIN_PASS_DAYS=1
MAX_PASS_DAYS=90
PASS_WARN_DAYS=7
PASS_INACTIVE_DAYS=30
POLICY_FILE=""
CHECK_ONLY=false
FIX_NONCOMPLIANT=false
REPORT_FILE=""
OUTPUT_JSON=false
VERBOSE=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--users)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            USER_LIST="$2"
            shift 2
            ;;
        -g|--groups)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            GROUP_LIST="$2"
            shift 2
            ;;
        -a|--all-users)
            CHECK_ALL_USERS=true
            shift
            ;;
        -s|--system-users)
            INCLUDE_SYSTEM_USERS=true
            shift
            ;;
        -e|--min-days)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid min days: $2"
                exit 1
            fi
            MIN_PASS_DAYS="$2"
            shift 2
            ;;
        -E|--max-days)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid max days: $2"
                exit 1
            fi
            MAX_PASS_DAYS="$2"
            shift 2
            ;;
        -w|--warn-days)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid warn days: $2"
                exit 1
            fi
            PASS_WARN_DAYS="$2"
            shift 2
            ;;
        -i|--inactive-days)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid inactive days: $2"
                exit 1
            fi
            PASS_INACTIVE_DAYS="$2"
            shift 2
            ;;
        -p|--policy)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            POLICY_FILE="$2"
            shift 2
            ;;
        -c|--check-only)
            CHECK_ONLY=true
            shift
            ;;
        -f|--fix)
            FIX_NONCOMPLIANT=true
            shift
            ;;
        -r|--report)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            REPORT_FILE="$2"
            shift 2
            ;;
        -j|--json)
            OUTPUT_JSON=true
            shift
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
        *)
            log_error "Unknown option: $1"
            log_error "Use --help to see available options"
            exit 1
            ;;
    esac
done

# Check if running with root/sudo
check_root() {
    if [ $EUID -ne 0 ] && [ "$FIX_NONCOMPLIANT" = true ]; then
        log_error "This script must be run as root or with sudo to fix non-compliant settings"
        exit 1
    fi
    
    if [ $EUID -ne 0 ] && [ "$CHECK_ALL_USERS" = true ]; then
        log_warning "Not running as root. May not be able to check all users."
    fi
}

# Load custom policy file if provided
load_policy_file() {
    if [ -n "$POLICY_FILE" ] && [ -f "$POLICY_FILE" ]; then
        log_info "Loading custom policy file: $POLICY_FILE"
        
        # Source the policy file to override default values
        source "$POLICY_FILE"
        
        log_info "Loaded custom policy settings:"
        log_info "  Minimum password age: $MIN_PASS_DAYS days"
        log_info "  Maximum password age: $MAX_PASS_DAYS days"
        log_info "  Password warning period: $PASS_WARN_DAYS days"
        log_info "  Account inactivity lock: $PASS_INACTIVE_DAYS days"
    fi
}

# Build a list of users to check
build_user_list() {
    local users_to_check=()
    
    # Add users specified directly
    if [ -n "$USER_LIST" ]; then
        IFS=',' read -ra SPECIFIED_USERS <<< "$USER_LIST"
        for user in "${SPECIFIED_USERS[@]}"; do
            if id "$user" &>/dev/null; then
                users_to_check+=("$user")
            else
                log_warning "User does not exist: $user"
            fi
        done
    fi
    
    # Add users from specified groups
    if [ -n "$GROUP_LIST" ]; then
        IFS=',' read -ra SPECIFIED_GROUPS <<< "$GROUP_LIST"
        for group in "${SPECIFIED_GROUPS[@]}"; do
            if getent group "$group" &>/dev/null; then
                local group_members=$(getent group "$group" | cut -d: -f4 | tr ',' ' ')
                for user in $group_members; do
                    if ! [[ " ${users_to_check[*]} " =~ " $user " ]]; then
                        users_to_check+=("$user")
                    fi
                done
            else
                log_warning "Group does not exist: $group"
            fi
        done
    fi
    
    # If check all users or no specific users/groups provided, get all users
    if [ ${#users_to_check[@]} -eq 0 ] || [ "$CHECK_ALL_USERS" = true ]; then
        while IFS=: read -r user pass uid gid gecos home shell; do
            # Skip system users unless explicitly included
            if [ "$INCLUDE_SYSTEM_USERS" = false ] && [ "$uid" -lt 1000 ]; then
                continue
            fi
            
            # Skip users with nologin/false shells unless explicitly specified
            if [[ "$shell" == *nologin ]] || [[ "$shell" == *false ]]; then
                # Only include if explicitly specified in USER_LIST
                if [ -n "$USER_LIST" ] && [[ " ${SPECIFIED_USERS[*]} " =~ " $user " ]]; then
                    users_to_check+=("$user")
                fi
                continue
            fi
            
            # Add regular users
            if ! [[ " ${users_to_check[*]} " =~ " $user " ]]; then
                users_to_check+=("$user")
            fi
        done < /etc/passwd
    fi
    
    echo "${users_to_check[@]}"
}

# Check a single user's password policy compliance
check_user_password_policy() {
    local user="$1"
    local compliant=true
    local issues=()
    local user_data=""
    
    # Get user's password aging information
    local chage_output=$(chage -l "$user" 2>/dev/null)
    if [ $? -ne 0 ]; then
        log_warning "Could not get password aging info for user: $user"
        return 1
    fi
    
    # Extract password aging information
    local last_change=$(echo "$chage_output" | grep "Last password change" | cut -d: -f2- | xargs)
    local password_expires=$(echo "$chage_output" | grep "Password expires" | cut -d: -f2- | xargs)
    local password_inactive=$(echo "$chage_output" | grep "Password inactive" | cut -d: -f2- | xargs)
    local account_expires=$(echo "$chage_output" | grep "Account expires" | cut -d: -f2- | xargs)
    local min_days=$(echo "$chage_output" | grep "Minimum number of days" | cut -d: -f2- | xargs)
    local max_days=$(echo "$chage_output" | grep "Maximum number of days" | cut -d: -f2- | xargs)
    local warn_days=$(echo "$chage_output" | grep "Number of days of warning" | cut -d: -f2- | xargs)
    
    # Check if values are "never"
    [ "$password_expires" = "never" ] && password_expires=-1
    [ "$password_inactive" = "never" ] && password_inactive=-1
    [ "$account_expires" = "never" ] && account_expires=-1
    
    # Check if numeric values are actually numeric
    if ! [[ "$min_days" =~ ^-?[0-9]+$ ]]; then min_days=0; fi
    if ! [[ "$max_days" =~ ^-?[0-9]+$ ]]; then max_days=99999; fi
    if ! [[ "$warn_days" =~ ^-?[0-9]+$ ]]; then warn_days=7; fi
    
    # Check minimum password age
    if [ "$min_days" -lt "$MIN_PASS_DAYS" ]; then
        compliant=false
        issues+=("Minimum password age ($min_days days) is less than required ($MIN_PASS_DAYS days)")
    fi
    
    # Check maximum password age
    if [ "$max_days" -eq -1 ] || [ "$max_days" -gt "$MAX_PASS_DAYS" ]; then
        compliant=false
        issues+=("Maximum password age ($max_days days) is greater than allowed ($MAX_PASS_DAYS days)")
    fi
    
    # Check password warning period
    if [ "$warn_days" -lt "$PASS_WARN_DAYS" ]; then
        compliant=false
        issues+=("Password warning period ($warn_days days) is less than recommended ($PASS_WARN_DAYS days)")
    fi
    
    # Check account inactivity period
    if [ "$password_inactive" -eq -1 ] || [ "$password_inactive" -gt "$PASS_INACTIVE_DAYS" ]; then
        compliant=false
        issues+=("Password inactivity period ($password_inactive days) exceeds policy ($PASS_INACTIVE_DAYS days)")
    fi
    
    # Additional checks for locked accounts
    local passwd_status=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')
    if [ "$passwd_status" = "L" ] || [ "$passwd_status" = "LK" ]; then
        issues+=("Account is locked")
    fi
    
    # Check for password set
    local shadow_entry=$(grep "^$user:" /etc/shadow 2>/dev/null)
    local password_field=$(echo "$shadow_entry" | cut -d: -f2)
    if [ "$password_field" = "!" ] || [ "$password_field" = "*" ] || [ -z "$password_field" ]; then
        issues+=("No password set")
    fi
    
    # Build user data structure based on output format
    if [ "$OUTPUT_JSON" = true ]; then
        user_data="{\"user\":\"$user\",\"compliant\":$compliant,\"min_days\":$min_days,\"max_days\":$max_days,\"warn_days\":$warn_days,\"inactive_days\":\"$password_inactive\",\"last_change\":\"$last_change\",\"issues\":["
        
        for i in "${!issues[@]}"; do
            if [ $i -gt 0 ]; then
                user_data+=","
            fi
            user_data+="\"${issues[$i]}\""
        done
        
        user_data+="]}"
    else
        user_data="User: $user\n"
        user_data+="  Compliant: $([ "$compliant" = true ] && echo "Yes" || echo "No")\n"
        user_data+="  Last password change: $last_change\n"
        user_data+="  Minimum password age: $min_days days (Policy: $MIN_PASS_DAYS days)\n"
        user_data+="  Maximum password age: $max_days days (Policy: $MAX_PASS_DAYS days)\n"
        user_data+="  Password warning period: $warn_days days (Policy: $PASS_WARN_DAYS days)\n"
        user_data+="  Password inactivity period: $password_inactive days (Policy: $PASS_INACTIVE_DAYS days)\n"
        
        if [ ${#issues[@]} -gt 0 ]; then
            user_data+="  Issues:\n"
            for issue in "${issues[@]}"; do
                user_data+="    - $issue\n"
            done
        fi
    fi
    
    # Fix issues if requested
    if [ "$FIX_NONCOMPLIANT" = true ] && [ "$compliant" = false ]; then
        if [ $EUID -eq 0 ]; then
            fix_user_password_policy "$user" "$min_days" "$max_days" "$warn_days" "$password_inactive"
        else
            log_warning "Cannot fix issues for user $user - not running as root"
        fi
    fi
    
    echo -e "$user_data"
    return $([ "$compliant" = true ] && echo 0 || echo 1)
}

# Fix a user's password policy settings
fix_user_password_policy() {
    local user="$1"
    local current_min_days="$2"
    local current_max_days="$3"
    local current_warn_days="$4"
    local current_inactive_days="$5"
    
    log_info "Fixing password policy for user: $user"
    
    # Build chage command to fix issues
    local chage_cmd="chage"
    
    # Fix minimum password age
    if [ "$current_min_days" -lt "$MIN_PASS_DAYS" ]; then
        chage_cmd+=" -m $MIN_PASS_DAYS"
    fi
    
    # Fix maximum password age
    if [ "$current_max_days" -eq -1 ] || [ "$current_max_days" -gt "$MAX_PASS_DAYS" ]; then
        chage_cmd+=" -M $MAX_PASS_DAYS"
    fi
    
    # Fix password warning period
    if [ "$current_warn_days" -lt "$PASS_WARN_DAYS" ]; then
        chage_cmd+=" -W $PASS_WARN_DAYS"
    fi
    
    # Fix account inactivity period
    if [ "$current_inactive_days" -eq -1 ] || [ "$current_inactive_days" -gt "$PASS_INACTIVE_DAYS" ]; then
        chage_cmd+=" -I $PASS_INACTIVE_DAYS"
    fi
    
    # Execute the chage command if needed
    if [ "$chage_cmd" != "chage" ]; then
        chage_cmd+=" $user"
        if $chage_cmd; then
            log_success "Fixed password policy for user: $user"
        else
            log_error "Failed to fix password policy for user: $user"
        fi
    else
        log_info "No changes needed for user: $user"
    fi
}

# Generate a report file
generate_report() {
    local users_data="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    log_info "Generating report file: $REPORT_FILE"
    
    if [ "$OUTPUT_JSON" = true ]; then
        # Create JSON report
        echo "{" > "$REPORT_FILE"
        echo "  \"report_time\": \"$timestamp\"," >> "$REPORT_FILE"
        echo "  \"policy\": {" >> "$REPORT_FILE"
        echo "    \"min_days\": $MIN_PASS_DAYS," >> "$REPORT_FILE"
        echo "    \"max_days\": $MAX_PASS_DAYS," >> "$REPORT_FILE"
        echo "    \"warn_days\": $PASS_WARN_DAYS," >> "$REPORT_FILE"
        echo "    \"inactive_days\": $PASS_INACTIVE_DAYS" >> "$REPORT_FILE"
        echo "  }," >> "$REPORT_FILE"
        echo "  \"users\": [" >> "$REPORT_FILE"
        
        # Add users data
        echo "$users_data" | sed '$s/,$//' >> "$REPORT_FILE"
        
        echo "  ]" >> "$REPORT_FILE"
        echo "}" >> "$REPORT_FILE"
    else
        # Create text report
        echo "Password Policy Compliance Report" > "$REPORT_FILE"
        echo "Generated: $timestamp" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "Policy Settings:" >> "$REPORT_FILE"
        echo "  Minimum password age: $MIN_PASS_DAYS days" >> "$REPORT_FILE"
        echo "  Maximum password age: $MAX_PASS_DAYS days" >> "$REPORT_FILE"
        echo "  Password warning period: $PASS_WARN_DAYS days" >> "$REPORT_FILE"
        echo "  Account inactivity lock: $PASS_INACTIVE_DAYS days" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "User Compliance:" >> "$REPORT_FILE"
        echo "$users_data" >> "$REPORT_FILE"
    fi
    
    log_success "Report generated: $REPORT_FILE"
}

# Main function
main() {
    print_header "Password Policy Checker"
    
    # Check if running as root
    check_root
    
    # Load custom policy if provided
    load_policy_file
    
    # Print configuration summary
    print_section "Configuration"
    log_info "Minimum password age: $MIN_PASS_DAYS days"
    log_info "Maximum password age: $MAX_PASS_DAYS days"
    log_info "Password warning period: $PASS_WARN_DAYS days"
    log_info "Account inactivity lock: $PASS_INACTIVE_DAYS days"
    
    if [ "$FIX_NONCOMPLIANT" = true ]; then
        log_info "Fix non-compliant settings: Yes"
    else
        log_info "Fix non-compliant settings: No"
    fi
    
    if [ -n "$REPORT_FILE" ]; then
        log_info "Report file: $REPORT_FILE"
    fi
    
    if [ "$OUTPUT_JSON" = true ]; then
        log_info "Output format: JSON"
    else
        log_info "Output format: Text"
    fi
    
    # Build list of users to check
    print_section "Building User List"
    users_to_check=($(build_user_list))
    
    log_info "Checking ${#users_to_check[@]} users"
    
    if [ ${#users_to_check[@]} -eq 0 ]; then
        log_warning "No users to check"
        exit 0
    fi
    
    # Check each user's password policy
    print_section "Checking Password Policies"
    
    local all_compliant=true
    local users_data=""
    local non_compliant_count=0
    
    for user in "${users_to_check[@]}"; do
        if [ "$VERBOSE" = true ]; then
            log_info "Checking user: $user"
        fi
        
        local user_data=$(check_user_password_policy "$user")
        local user_compliant=$?
        
        if [ $user_compliant -ne 0 ]; then
            all_compliant=false
            ((non_compliant_count++))
        fi
        
        if [ "$OUTPUT_JSON" = true ]; then
            if [ -n "$users_data" ]; then
                users_data+=",\n"
            fi
            users_data+="    $user_data"
        else
            # For text output, print details
            if [ "$VERBOSE" = true ] || [ $user_compliant -ne 0 ]; then
                echo -e "$user_data"
            else
                log_info "User $user is compliant with password policy"
            fi
            
            if [ -n "$REPORT_FILE" ]; then
                users_data+="$user_data\n"
            fi
        fi
    done
    
    # Generate report if requested
    if [ -n "$REPORT_FILE" ]; then
        generate_report "$users_data"
    fi
    
    # Print summary
    print_header "Password Policy Check Summary"
    if [ "$all_compliant" = true ]; then
        log_success "All users are compliant with password policy"
    else
        log_warning "$non_compliant_count out of ${#users_to_check[@]} users are not compliant with password policy"
        
        if [ "$FIX_NONCOMPLIANT" = true ]; then
            log_info "Non-compliant settings have been fixed"
        elif [ "$CHECK_ONLY" = false ]; then
            log_info "To fix non-compliant settings, run with --fix option"
        fi
    fi
}

# Run the main function
main