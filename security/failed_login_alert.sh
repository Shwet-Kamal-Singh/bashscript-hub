#!/bin/bash
#
# Script Name: failed_login_alert.sh
# Description: Monitor and alert on failed login attempts
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./failed_login_alert.sh [options]
#
# Options:
#   -l, --log-file <file>         Specify custom auth log file (default: auto-detect)
#   -t, --threshold <num>         Set threshold for alerts (default: 5)
#   -i, --interval <seconds>      Check interval in seconds (default: 300)
#   -p, --period <minutes>        Time period to check in minutes (default: 10)
#   -f, --filter <regex>          Custom regex filter (default: "Failed|Failure|Invalid")
#   -e, --email <address>         Email for alerts (comma-separated for multiple)
#   -s, --smtp-server <server>    SMTP server for email alerts (default: localhost)
#   -P, --smtp-port <port>        SMTP port (default: 25)
#   -u, --smtp-user <username>    SMTP username if required
#   -w, --smtp-pass <password>    SMTP password if required
#   -S, --slack-webhook <url>     Slack webhook URL for notifications
#   -T, --telegram-token <token>  Telegram bot token
#   -C, --telegram-chat-id <id>   Telegram chat ID
#   -W, --webhook-url <url>       Generic webhook URL
#   -b, --block-ip                Automatically block IPs (requires iptables/firewalld)
#   -B, --block-threshold <num>   Threshold for blocking IPs (default: 10)
#   -w, --whitelist <file>        IP whitelist file
#   -r, --report <file>           Output report to file
#   -d, --daemon                  Run as a daemon in the background
#   -D, --debug                   Enable debug mode
#   -h, --help                    Display this help message
#
# Examples:
#   ./failed_login_alert.sh -t 3 -e admin@example.com
#   ./failed_login_alert.sh -p 60 -S https://hooks.slack.com/services/TXXXX/BXXXX/XXXXXXXX
#   ./failed_login_alert.sh -b -B 5 -w /etc/whitelist.txt -d
#
# Requirements:
#   - Root privileges (or sudo) for some features
#   - System with auth.log or secure log file
#   - mail command for email alerts (optional)
#   - curl for webhook notifications (optional)
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
LOG_FILE=""
THRESHOLD=5
INTERVAL=300
PERIOD=10
FILTER="Failed|Failure|Invalid"
EMAIL_ADDRESSES=""
SMTP_SERVER="localhost"
SMTP_PORT=25
SMTP_USER=""
SMTP_PASS=""
SLACK_WEBHOOK=""
TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""
WEBHOOK_URL=""
BLOCK_IP=false
BLOCK_THRESHOLD=10
WHITELIST_FILE=""
REPORT_FILE=""
RUN_AS_DAEMON=false
DEBUG=false

# Temporary files
TEMP_DIR="/tmp/failed_login_alert"
IP_LIST_FILE="$TEMP_DIR/ip_list.txt"
BLOCKED_IP_FILE="$TEMP_DIR/blocked_ips.txt"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--log-file)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            LOG_FILE="$2"
            shift 2
            ;;
        -t|--threshold)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid threshold: $2"
                exit 1
            fi
            THRESHOLD="$2"
            shift 2
            ;;
        -i|--interval)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid interval: $2"
                exit 1
            fi
            INTERVAL="$2"
            shift 2
            ;;
        -p|--period)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid period: $2"
                exit 1
            fi
            PERIOD="$2"
            shift 2
            ;;
        -f|--filter)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            FILTER="$2"
            shift 2
            ;;
        -e|--email)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            EMAIL_ADDRESSES="$2"
            shift 2
            ;;
        -s|--smtp-server)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            SMTP_SERVER="$2"
            shift 2
            ;;
        -P|--smtp-port)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid SMTP port: $2"
                exit 1
            fi
            SMTP_PORT="$2"
            shift 2
            ;;
        -u|--smtp-user)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            SMTP_USER="$2"
            shift 2
            ;;
        -w|--smtp-pass)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            SMTP_PASS="$2"
            shift 2
            ;;
        -S|--slack-webhook)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            SLACK_WEBHOOK="$2"
            shift 2
            ;;
        -T|--telegram-token)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            TELEGRAM_TOKEN="$2"
            shift 2
            ;;
        -C|--telegram-chat-id)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            TELEGRAM_CHAT_ID="$2"
            shift 2
            ;;
        -W|--webhook-url)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            WEBHOOK_URL="$2"
            shift 2
            ;;
        -b|--block-ip)
            BLOCK_IP=true
            shift
            ;;
        -B|--block-threshold)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                log_error "Invalid block threshold: $2"
                exit 1
            fi
            BLOCK_THRESHOLD="$2"
            shift 2
            ;;
        -w|--whitelist)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            WHITELIST_FILE="$2"
            shift 2
            ;;
        -r|--report)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            REPORT_FILE="$2"
            shift 2
            ;;
        -d|--daemon)
            RUN_AS_DAEMON=true
            shift
            ;;
        -D|--debug)
            DEBUG=true
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

# Enable debug mode if requested
if [ "$DEBUG" = true ]; then
    set -x
fi

# Create temporary directory
mkdir -p "$TEMP_DIR"

# Initialize blocked IP file if it doesn't exist
if [ ! -f "$BLOCKED_IP_FILE" ]; then
    touch "$BLOCKED_IP_FILE"
fi

# Function to detect the auth log file
detect_auth_log() {
    if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
        return
    fi
    
    # Common locations for auth log files
    local log_files=(
        "/var/log/auth.log"       # Debian/Ubuntu
        "/var/log/secure"         # RHEL/CentOS
        "/var/log/messages"       # Fallback
        "/var/log/syslog"         # Fallback
    )
    
    for file in "${log_files[@]}"; do
        if [ -f "$file" ]; then
            LOG_FILE="$file"
            log_info "Detected auth log file: $LOG_FILE"
            return
        fi
    done
    
    log_error "Could not detect auth log file. Please specify with --log-file option."
    exit 1
}

# Function to check system prerequisites
check_prerequisites() {
    # Check if we have grep
    if ! command -v grep &>/dev/null; then
        log_error "grep command not found. This is required for log parsing."
        exit 1
    fi
    
    # Check if we have curl for webhook notifications
    if [ -n "$SLACK_WEBHOOK" ] || [ -n "$TELEGRAM_TOKEN" ] || [ -n "$WEBHOOK_URL" ]; then
        if ! command -v curl &>/dev/null; then
            log_warning "curl command not found. This is required for webhook notifications."
            log_warning "Disabling webhook notifications."
            SLACK_WEBHOOK=""
            TELEGRAM_TOKEN=""
            WEBHOOK_URL=""
        fi
    fi
    
    # Check if we have mail for email alerts
    if [ -n "$EMAIL_ADDRESSES" ]; then
        if ! command -v mail &>/dev/null; then
            log_warning "mail command not found. This is required for email alerts."
            log_warning "Disabling email alerts."
            EMAIL_ADDRESSES=""
        fi
    fi
    
    # Check if we have iptables or firewalld for IP blocking
    if [ "$BLOCK_IP" = true ]; then
        if ! command -v iptables &>/dev/null && ! command -v firewall-cmd &>/dev/null; then
            log_warning "Neither iptables nor firewalld found. IP blocking will be disabled."
            BLOCK_IP=false
        fi
        
        # Check if running as root for IP blocking
        if [ $EUID -ne 0 ]; then
            log_warning "Not running as root. IP blocking will be disabled."
            BLOCK_IP=false
        fi
    fi
}

# Function to parse log files for failed login attempts
parse_logs() {
    local period_seconds=$((PERIOD * 60))
    local start_time=$(date -d "@$(($(date +%s) - period_seconds))" +"%Y-%m-%d %H:%M:%S")
    
    log_info "Checking failed login attempts since $start_time..."
    
    # Use the appropriate date command format for Linux
    local filter_cmd="grep -E \"$FILTER\" \"$LOG_FILE\" | grep -v \"Failed\""
    
    # Clear the IP list file
    > "$IP_LIST_FILE"
    
    # Extract IP addresses from failed login attempts
    grep -E "$FILTER" "$LOG_FILE" | grep -a -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | sort | uniq -c | sort -nr > "$IP_LIST_FILE"
    
    # Check if we found any failed login attempts
    if [ ! -s "$IP_LIST_FILE" ]; then
        log_info "No failed login attempts found."
        return
    fi
    
    # Parse the IP list
    local high_attempts=false
    local ips_to_block=()
    local alert_message="Failed Login Attempts Detected:\n\n"
    
    while read -r count ip; do
        # Check if IP is in the whitelist
        if [ -n "$WHITELIST_FILE" ] && [ -f "$WHITELIST_FILE" ] && grep -q "^$ip$" "$WHITELIST_FILE"; then
            log_info "IP $ip is whitelisted. Ignoring $count failed attempts."
            continue
        fi
        
        # Add to the alert message
        alert_message+="$count failed attempts from IP: $ip\n"
        
        # Check if we should alert
        if [ "$count" -ge "$THRESHOLD" ]; then
            high_attempts=true
            
            # Check if we should block this IP
            if [ "$BLOCK_IP" = true ] && [ "$count" -ge "$BLOCK_THRESHOLD" ]; then
                # Check if IP is already blocked
                if ! grep -q "^$ip$" "$BLOCKED_IP_FILE"; then
                    ips_to_block+=("$ip")
                fi
            fi
        fi
    done < "$IP_LIST_FILE"
    
    # Send alert if threshold exceeded
    if [ "$high_attempts" = true ]; then
        log_warning "Failed login attempts exceed threshold!"
        
        # Block IPs if needed
        if [ ${#ips_to_block[@]} -gt 0 ]; then
            block_ips "${ips_to_block[@]}"
            
            # Update the alert message with blocking information
            alert_message+="\nThe following IPs have been blocked:\n"
            for ip in "${ips_to_block[@]}"; do
                alert_message+="$ip\n"
            done
        fi
        
        # Send alerts
        send_alerts "$alert_message"
        
        # Generate report if requested
        if [ -n "$REPORT_FILE" ]; then
            generate_report "$alert_message"
        fi
    else
        log_info "Failed login attempts below threshold."
    fi
}

# Function to block IPs using iptables or firewalld
block_ips() {
    local ips=("$@")
    
    print_section "Blocking IPs"
    
    for ip in "${ips[@]}"; do
        log_info "Blocking IP: $ip"
        
        # Check if we should use iptables or firewalld
        if command -v firewall-cmd &>/dev/null; then
            # Using firewalld
            firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='$ip' reject" >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                firewall-cmd --reload >/dev/null 2>&1
                log_success "Blocked IP $ip using firewalld"
                echo "$ip" >> "$BLOCKED_IP_FILE"
            else
                log_error "Failed to block IP $ip using firewalld"
            fi
        elif command -v iptables &>/dev/null; then
            # Using iptables
            iptables -A INPUT -s "$ip" -j DROP >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                log_success "Blocked IP $ip using iptables"
                echo "$ip" >> "$BLOCKED_IP_FILE"
            else
                log_error "Failed to block IP $ip using iptables"
            fi
        fi
    done
}

# Function to send email alerts
send_email_alert() {
    local message="$1"
    local hostname=$(hostname)
    local subject="[Security Alert] Failed Login Attempts on $hostname"
    
    log_info "Sending email alert..."
    
    IFS=',' read -ra EMAIL_LIST <<< "$EMAIL_ADDRESSES"
    for email in "${EMAIL_LIST[@]}"; do
        if [ -n "$SMTP_USER" ] && [ -n "$SMTP_PASS" ]; then
            # Using authentication with mail command (this is very basic and may not work with all mail configurations)
            echo -e "$message" | mail -s "$subject" -S smtp="$SMTP_SERVER:$SMTP_PORT" -S smtp-auth=login -S smtp-auth-user="$SMTP_USER" -S smtp-auth-password="$SMTP_PASS" "$email"
        else
            # Simple mail command
            echo -e "$message" | mail -s "$subject" "$email"
        fi
        
        if [ $? -eq 0 ]; then
            log_success "Email alert sent to $email"
        else
            log_error "Failed to send email alert to $email"
        fi
    done
}

# Function to send Slack alerts
send_slack_alert() {
    local message="$1"
    local hostname=$(hostname)
    local json_payload="{\"text\":\"*Security Alert: Failed Login Attempts on $hostname*\n\n$message\"}"
    
    log_info "Sending Slack alert..."
    
    curl -s -X POST -H 'Content-type: application/json' --data "$json_payload" "$SLACK_WEBHOOK" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Slack alert sent"
    else
        log_error "Failed to send Slack alert"
    fi
}

# Function to send Telegram alerts
send_telegram_alert() {
    local message="$1"
    local hostname=$(hostname)
    local formatted_message="Security Alert: Failed Login Attempts on $hostname\n\n$message"
    
    log_info "Sending Telegram alert..."
    
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d "chat_id=$TELEGRAM_CHAT_ID&text=$formatted_message&parse_mode=Markdown" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Telegram alert sent"
    else
        log_error "Failed to send Telegram alert"
    fi
}

# Function to send webhook alerts
send_webhook_alert() {
    local message="$1"
    local hostname=$(hostname)
    local json_payload="{\"hostname\":\"$hostname\",\"message\":\"$message\",\"timestamp\":\"$(date -Iseconds)\"}"
    
    log_info "Sending webhook alert..."
    
    curl -s -X POST -H 'Content-type: application/json' --data "$json_payload" "$WEBHOOK_URL" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Webhook alert sent"
    else
        log_error "Failed to send webhook alert"
    fi
}

# Function to send all configured alerts
send_alerts() {
    local message="$1"
    
    print_section "Sending Alerts"
    
    if [ -n "$EMAIL_ADDRESSES" ]; then
        send_email_alert "$message"
    fi
    
    if [ -n "$SLACK_WEBHOOK" ]; then
        send_slack_alert "$message"
    fi
    
    if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        send_telegram_alert "$message"
    fi
    
    if [ -n "$WEBHOOK_URL" ]; then
        send_webhook_alert "$message"
    fi
}

# Function to generate a report file
generate_report() {
    local message="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    print_section "Generating Report"
    
    log_info "Writing report to $REPORT_FILE..."
    
    # Create the report file
    echo -e "Failed Login Attempts Report\n" > "$REPORT_FILE"
    echo -e "Generated: $timestamp\n" >> "$REPORT_FILE"
    echo -e "$message\n" >> "$REPORT_FILE"
    
    # Add currently blocked IPs
    if [ -s "$BLOCKED_IP_FILE" ]; then
        echo -e "Currently Blocked IPs:" >> "$REPORT_FILE"
        cat "$BLOCKED_IP_FILE" >> "$REPORT_FILE"
    fi
    
    log_success "Report generated: $REPORT_FILE"
}

# Function to run the script as a daemon
run_as_daemon() {
    print_header "Running as daemon"
    
    log_info "Starting monitor with interval of $INTERVAL seconds..."
    
    # Write PID to file
    echo $$ > "$TEMP_DIR/failed_login_alert.pid"
    
    # Create a trap to catch signals
    trap cleanup SIGINT SIGTERM
    
    # Run the monitor loop
    while true; do
        parse_logs
        sleep "$INTERVAL"
    done
}

# Function to clean up on exit
cleanup() {
    log_info "Cleaning up..."
    rm -f "$TEMP_DIR/failed_login_alert.pid"
    exit 0
}

# Main function
main() {
    print_header "Failed Login Alert Monitor"
    
    # Detect the auth log file
    detect_auth_log
    
    # Check prerequisites
    check_prerequisites
    
    # Print configuration summary
    print_section "Configuration"
    log_info "Log file: $LOG_FILE"
    log_info "Alert threshold: $THRESHOLD failed attempts"
    log_info "Check interval: $INTERVAL seconds"
    log_info "Check period: $PERIOD minutes"
    log_info "Failure filter: $FILTER"
    
    if [ -n "$EMAIL_ADDRESSES" ]; then
        log_info "Email alerts: enabled (to: $EMAIL_ADDRESSES)"
    else
        log_info "Email alerts: disabled"
    fi
    
    if [ -n "$SLACK_WEBHOOK" ]; then
        log_info "Slack alerts: enabled"
    else
        log_info "Slack alerts: disabled"
    fi
    
    if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        log_info "Telegram alerts: enabled"
    else
        log_info "Telegram alerts: disabled"
    fi
    
    if [ -n "$WEBHOOK_URL" ]; then
        log_info "Webhook alerts: enabled"
    else
        log_info "Webhook alerts: disabled"
    fi
    
    if [ "$BLOCK_IP" = true ]; then
        log_info "IP blocking: enabled (threshold: $BLOCK_THRESHOLD)"
    else
        log_info "IP blocking: disabled"
    fi
    
    if [ -n "$WHITELIST_FILE" ]; then
        log_info "IP whitelist: $WHITELIST_FILE"
    else
        log_info "IP whitelist: none"
    fi
    
    if [ -n "$REPORT_FILE" ]; then
        log_info "Report file: $REPORT_FILE"
    else
        log_info "Report file: none"
    fi
    
    # Run as daemon or one-time check
    if [ "$RUN_AS_DAEMON" = true ]; then
        run_as_daemon
    else
        parse_logs
    fi
    
    print_header "Failed Login Alert Monitor Complete"
}

# Run the main function
main