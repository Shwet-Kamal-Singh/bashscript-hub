#!/bin/bash
#
# deploy_app.sh - Automated deployment script for applications
#
# This script automates the deployment process for applications, supporting
# multiple deployment types (static websites, Node.js, Python, etc.) and
# environments (dev, staging, production).
#
# Usage:
#   ./deploy_app.sh [options]
#
# Options:
#   -s, --source <path>      Source code path (default: current directory)
#   -d, --destination <path> Deployment destination path
#   -t, --type <type>        Application type (static, nodejs, python, php)
#   -e, --env <environment>  Deployment environment (dev, staging, prod)
#   -b, --backup             Create backup before deployment
#   -n, --no-restart         Skip service restart after deployment
#   -c, --clean              Clean destination before deployment
#   -v, --verbose            Display detailed output
#   -h, --help               Display this help message
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
SOURCE_PATH="$(pwd)"
DESTINATION_PATH=""
APP_TYPE=""
ENVIRONMENT="dev"
BACKUP=false
NO_RESTART=false
CLEAN=false
VERBOSE=false

# Function to display usage information
show_usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Automated deployment script for applications."
    echo ""
    echo "Options:"
    echo "  -s, --source <path>      Source code path (default: current directory)"
    echo "  -d, --destination <path> Deployment destination path"
    echo "  -t, --type <type>        Application type (static, nodejs, python, php)"
    echo "  -e, --env <environment>  Deployment environment (dev, staging, prod)"
    echo "  -b, --backup             Create backup before deployment"
    echo "  -n, --no-restart         Skip service restart after deployment"
    echo "  -c, --clean              Clean destination before deployment"
    echo "  -v, --verbose            Display detailed output"
    echo "  -h, --help               Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") -s ./build -d /var/www/html -t static"
    echo "  $(basename "$0") -d /opt/myapp -t nodejs -e prod -b"
    echo "  $(basename "$0") -t python -d /srv/flask-app -e staging -c"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        key="$1"
        
        case $key in
            -s|--source)
                SOURCE_PATH="$2"
                shift 2
                ;;
            -d|--destination)
                DESTINATION_PATH="$2"
                shift 2
                ;;
            -t|--type)
                APP_TYPE="$2"
                shift 2
                ;;
            -e|--env)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -b|--backup)
                BACKUP=true
                shift
                ;;
            -n|--no-restart)
                NO_RESTART=true
                shift
                ;;
            -c|--clean)
                CLEAN=true
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
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [ -z "$DESTINATION_PATH" ]; then
        log_error "Destination path is required"
        show_usage
        exit 1
    fi
    
    if [ -z "$APP_TYPE" ]; then
        log_error "Application type is required"
        show_usage
        exit 1
    fi
    
    # Validate application type
    case $APP_TYPE in
        static|nodejs|python|php)
            # Valid types
            ;;
        *)
            log_error "Invalid application type: $APP_TYPE"
            log_error "Supported types: static, nodejs, python, php"
            exit 1
            ;;
    esac
    
    # Validate environment
    case $ENVIRONMENT in
        dev|staging|prod)
            # Valid environments
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT"
            log_error "Supported environments: dev, staging, prod"
            exit 1
            ;;
    esac
    
    # Check if source path exists
    if [ ! -e "$SOURCE_PATH" ]; then
        log_error "Source path does not exist: $SOURCE_PATH"
        exit 1
    fi
}

# Function to create backup
create_backup() {
    if [ ! -e "$DESTINATION_PATH" ]; then
        log_warning "Destination does not exist, skipping backup"
        return 0
    fi
    
    log_info "Creating backup of destination directory"
    
    local backup_dir
    backup_dir="$(dirname "$DESTINATION_PATH")/backup_$(basename "$DESTINATION_PATH")_$(date +%Y%m%d_%H%M%S)"
    
    cp -R "$DESTINATION_PATH" "$backup_dir"
    
    if [ $? -eq 0 ]; then
        log_success "Backup created at: $backup_dir"
        return 0
    else
        log_error "Failed to create backup"
        return 1
    fi
}

# Function to clean destination
clean_destination() {
    if [ ! -e "$DESTINATION_PATH" ]; then
        log_warning "Destination does not exist, nothing to clean"
        return 0
    fi
    
    log_info "Cleaning destination directory"
    
    if [ -d "$DESTINATION_PATH" ]; then
        # Remove all files but keep the directory
        rm -rf "$DESTINATION_PATH"/{*,.[!.]*,..?*} 2>/dev/null
        
        if [ $? -eq 0 ]; then
            log_success "Destination cleaned"
            return 0
        else
            log_error "Failed to clean destination"
            return 1
        fi
    else
        log_error "Destination is not a directory: $DESTINATION_PATH"
        return 1
    fi
}

# Function to deploy static website
deploy_static() {
    log_info "Deploying static website to: $DESTINATION_PATH"
    
    # Create destination directory if it doesn't exist
    mkdir -p "$DESTINATION_PATH"
    
    # Copy files
    if [ "$VERBOSE" = true ]; then
        cp -Rv "$SOURCE_PATH"/* "$DESTINATION_PATH"/
    else
        cp -R "$SOURCE_PATH"/* "$DESTINATION_PATH"/
    fi
    
    if [ $? -eq 0 ]; then
        log_success "Static files deployed successfully"
        return 0
    else
        log_error "Failed to deploy static files"
        return 1
    fi
}

# Function to deploy Node.js application
deploy_nodejs() {
    log_info "Deploying Node.js application to: $DESTINATION_PATH"
    
    # Create destination directory if it doesn't exist
    mkdir -p "$DESTINATION_PATH"
    
    # Copy files
    if [ "$VERBOSE" = true ]; then
        cp -Rv "$SOURCE_PATH"/* "$DESTINATION_PATH"/
    else
        cp -R "$SOURCE_PATH"/* "$DESTINATION_PATH"/
    fi
    
    if [ $? -ne 0 ]; then
        log_error "Failed to copy application files"
        return 1
    fi
    
    # Install dependencies if package.json exists
    if [ -f "$DESTINATION_PATH/package.json" ]; then
        log_info "Installing Node.js dependencies"
        
        if [ "$ENVIRONMENT" = "prod" ]; then
            # Production install (no dev dependencies)
            if [ "$VERBOSE" = true ]; then
                (cd "$DESTINATION_PATH" && npm install --production)
            else
                (cd "$DESTINATION_PATH" && npm install --production --silent)
            fi
        else
            # Development install (with dev dependencies)
            if [ "$VERBOSE" = true ]; then
                (cd "$DESTINATION_PATH" && npm install)
            else
                (cd "$DESTINATION_PATH" && npm install --silent)
            fi
        fi
        
        if [ $? -ne 0 ]; then
            log_error "Failed to install Node.js dependencies"
            return 1
        fi
    fi
    
    # Build application if needed
    if [ -f "$DESTINATION_PATH/package.json" ] && grep -q '"build"' "$DESTINATION_PATH/package.json"; then
        log_info "Building Node.js application"
        (cd "$DESTINATION_PATH" && npm run build)
        
        if [ $? -ne 0 ]; then
            log_error "Failed to build Node.js application"
            return 1
        fi
    fi
    
    # Restart service if needed
    if [ "$NO_RESTART" = false ]; then
        if command -v pm2 &>/dev/null; then
            log_info "Restarting application with PM2"
            
            # Get app name from package.json or use directory name
            if [ -f "$DESTINATION_PATH/package.json" ]; then
                app_name=$(grep -m 1 '"name":' "$DESTINATION_PATH/package.json" | awk -F'"' '{print $4}')
            else
                app_name=$(basename "$DESTINATION_PATH")
            fi
            
            # Check if app is already running in PM2
            if pm2 list | grep -q "$app_name"; then
                pm2 restart "$app_name"
            else
                # Start app with PM2
                (cd "$DESTINATION_PATH" && pm2 start npm --name "$app_name" -- start)
            fi
            
            if [ $? -ne 0 ]; then
                log_error "Failed to restart application with PM2"
                return 1
            fi
        else
            log_warning "PM2 not found, skipping application restart"
            log_warning "You may need to restart the application manually"
        fi
    fi
    
    log_success "Node.js application deployed successfully"
    return 0
}

# Function to deploy Python application
deploy_python() {
    log_info "Deploying Python application to: $DESTINATION_PATH"
    
    # Create destination directory if it doesn't exist
    mkdir -p "$DESTINATION_PATH"
    
    # Copy files
    if [ "$VERBOSE" = true ]; then
        cp -Rv "$SOURCE_PATH"/* "$DESTINATION_PATH"/
    else
        cp -R "$SOURCE_PATH"/* "$DESTINATION_PATH"/
    fi
    
    if [ $? -ne 0 ]; then
        log_error "Failed to copy application files"
        return 1
    fi
    
    # Check for virtual environment
    if [ -f "$DESTINATION_PATH/requirements.txt" ]; then
        log_info "Setting up Python virtual environment"
        
        # Create virtual environment if it doesn't exist
        if [ ! -d "$DESTINATION_PATH/venv" ]; then
            python3 -m venv "$DESTINATION_PATH/venv"
            
            if [ $? -ne 0 ]; then
                log_error "Failed to create Python virtual environment"
                return 1
            fi
        fi
        
        # Install dependencies
        log_info "Installing Python dependencies"
        if [ "$VERBOSE" = true ]; then
            "$DESTINATION_PATH/venv/bin/pip" install -r "$DESTINATION_PATH/requirements.txt"
        else
            "$DESTINATION_PATH/venv/bin/pip" install -q -r "$DESTINATION_PATH/requirements.txt"
        fi
        
        if [ $? -ne 0 ]; then
            log_error "Failed to install Python dependencies"
            return 1
        fi
    fi
    
    # Restart service if needed
    if [ "$NO_RESTART" = false ]; then
        # Check for uWSGI or Gunicorn
        if [ -f "$DESTINATION_PATH/wsgi.py" ] || [ -f "$DESTINATION_PATH/app.py" ]; then
            # Try standard locations for system services
            for service in uwsgi.service gunicorn.service; do
                if systemctl list-units --full -all | grep -q "$service"; then
                    log_info "Restarting $service"
                    systemctl restart "$service"
                    
                    if [ $? -eq 0 ]; then
                        log_success "Service restarted successfully"
                        break
                    else
                        log_error "Failed to restart $service"
                        log_warning "You may need to restart the service manually"
                    fi
                fi
            done
        else
            log_warning "No WSGI application found, skipping service restart"
            log_warning "You may need to restart the application manually"
        fi
    fi
    
    log_success "Python application deployed successfully"
    return 0
}

# Function to deploy PHP application
deploy_php() {
    log_info "Deploying PHP application to: $DESTINATION_PATH"
    
    # Create destination directory if it doesn't exist
    mkdir -p "$DESTINATION_PATH"
    
    # Copy files
    if [ "$VERBOSE" = true ]; then
        cp -Rv "$SOURCE_PATH"/* "$DESTINATION_PATH"/
    else
        cp -R "$SOURCE_PATH"/* "$DESTINATION_PATH"/
    fi
    
    if [ $? -ne 0 ]; then
        log_error "Failed to copy application files"
        return 1
    fi
    
    # Install Composer dependencies if composer.json exists
    if [ -f "$DESTINATION_PATH/composer.json" ]; then
        log_info "Installing Composer dependencies"
        
        if command -v composer &>/dev/null; then
            if [ "$ENVIRONMENT" = "prod" ]; then
                # Production install (no dev dependencies)
                if [ "$VERBOSE" = true ]; then
                    (cd "$DESTINATION_PATH" && composer install --no-dev)
                else
                    (cd "$DESTINATION_PATH" && composer install --no-dev --quiet)
                fi
            else
                # Development install (with dev dependencies)
                if [ "$VERBOSE" = true ]; then
                    (cd "$DESTINATION_PATH" && composer install)
                else
                    (cd "$DESTINATION_PATH" && composer install --quiet)
                fi
            fi
            
            if [ $? -ne 0 ]; then
                log_error "Failed to install Composer dependencies"
                return 1
            fi
        else
            log_warning "Composer not found, skipping dependency installation"
        fi
    fi
    
    # Restart service if needed
    if [ "$NO_RESTART" = false ]; then
        # Try to restart PHP-FPM service
        for service in php-fpm.service php7.0-fpm.service php7.4-fpm.service php8.0-fpm.service php8.1-fpm.service; do
            if systemctl list-units --full -all | grep -q "$service"; then
                log_info "Restarting $service"
                systemctl restart "$service"
                
                if [ $? -eq 0 ]; then
                    log_success "Service restarted successfully"
                    break
                else
                    log_error "Failed to restart $service"
                    log_warning "You may need to restart the service manually"
                fi
            fi
        done
    fi
    
    log_success "PHP application deployed successfully"
    return 0
}

# Main execution
main() {
    parse_arguments "$@"
    
    log_info "Starting deployment process"
    log_info "Source: $SOURCE_PATH"
    log_info "Destination: $DESTINATION_PATH"
    log_info "Application type: $APP_TYPE"
    log_info "Environment: $ENVIRONMENT"
    
    # Create backup if requested
    if [ "$BACKUP" = true ]; then
        create_backup || exit 1
    fi
    
    # Clean destination if requested
    if [ "$CLEAN" = true ]; then
        clean_destination || exit 1
    fi
    
    # Deploy application based on type
    case $APP_TYPE in
        static)
            deploy_static
            ;;
        nodejs)
            deploy_nodejs
            ;;
        python)
            deploy_python
            ;;
        php)
            deploy_php
            ;;
    esac
    
    # Check if deployment was successful
    if [ $? -eq 0 ]; then
        log_success "Deployment completed successfully"
    else
        log_error "Deployment failed"
        exit 1
    fi
}

# Execute main if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
