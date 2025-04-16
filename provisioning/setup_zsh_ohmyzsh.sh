#!/bin/bash
#
# Script Name: setup_zsh_ohmyzsh.sh
# Description: Install Zsh and Oh My Zsh with sensible default configuration and plugins
# Author: BashScriptHub
# Date: April 15, 2025
# Version: 1.0
#
# Usage: ./setup_zsh_ohmyzsh.sh [options]
#
# Options:
#   -u, --user <username>     Install for specific user (default: current user)
#   -a, --all-users           Install for all users
#   -t, --theme <theme>       Set Oh My Zsh theme (default: robbyrussell)
#   -p, --plugins <plugins>   Comma-separated list of plugins to enable (default: git,docker,kubectl)
#   -f, --fonts               Install Powerline fonts
#   -P, --powerlevel10k       Install Powerlevel10k theme
#   -s, --syntax-highlight    Install syntax highlighting plugin
#   -A, --autosuggestions     Install autosuggestions plugin
#   -c, --custom-aliases      Add custom aliases
#   -d, --default-shell       Set Zsh as default shell for user(s)
#   -C, --copy-config <file>  Copy custom .zshrc from specified file
#   -F, --force               Force reinstallation if already installed
#   -y, --yes                 Answer yes to all prompts
#   -h, --help                Display this help message
#
# Examples:
#   ./setup_zsh_ohmyzsh.sh
#   ./setup_zsh_ohmyzsh.sh -u john -t agnoster -p "git,docker,kubectl,composer"
#   ./setup_zsh_ohmyzsh.sh -a -f -P -s -A -d
#   ./setup_zsh_ohmyzsh.sh -C /path/to/custom/.zshrc
#
# Requirements:
#   - Root privileges (or sudo) if installing for other users or all users
#   - Internet connection for downloading Oh My Zsh and plugins
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
TARGET_USER="$USER"
ALL_USERS=false
THEME="robbyrussell"
PLUGINS="git,docker,kubectl"
INSTALL_FONTS=false
INSTALL_POWERLEVEL10K=false
INSTALL_SYNTAX_HIGHLIGHT=false
INSTALL_AUTOSUGGESTIONS=false
ADD_CUSTOM_ALIASES=false
SET_DEFAULT_SHELL=false
CUSTOM_CONFIG_FILE=""
FORCE_INSTALL=false
ASSUME_YES=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            TARGET_USER="$2"
            shift 2
            ;;
        -a|--all-users)
            ALL_USERS=true
            shift
            ;;
        -t|--theme)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            THEME="$2"
            shift 2
            ;;
        -p|--plugins)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            PLUGINS="$2"
            shift 2
            ;;
        -f|--fonts)
            INSTALL_FONTS=true
            shift
            ;;
        -P|--powerlevel10k)
            INSTALL_POWERLEVEL10K=true
            shift
            ;;
        -s|--syntax-highlight)
            INSTALL_SYNTAX_HIGHLIGHT=true
            shift
            ;;
        -A|--autosuggestions)
            INSTALL_AUTOSUGGESTIONS=true
            shift
            ;;
        -c|--custom-aliases)
            ADD_CUSTOM_ALIASES=true
            shift
            ;;
        -d|--default-shell)
            SET_DEFAULT_SHELL=true
            shift
            ;;
        -C|--copy-config)
            if [[ -z "$2" || "$2" == -* ]]; then
                log_error "Missing argument for $1 option"
                exit 1
            fi
            CUSTOM_CONFIG_FILE="$2"
            shift 2
            ;;
        -F|--force)
            FORCE_INSTALL=true
            shift
            ;;
        -y|--yes)
            ASSUME_YES=true
            shift
            ;;
        --help)
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

# Detect Linux distribution
detect_distribution() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        DISTRO="$ID"
        VERSION="$VERSION_ID"
    elif [ -f /etc/lsb-release ]; then
        # shellcheck disable=SC1091
        source /etc/lsb-release
        DISTRO="$DISTRIB_ID"
        VERSION="$DISTRIB_RELEASE"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
        VERSION=$(cat /etc/debian_version)
    elif [ -f /etc/redhat-release ]; then
        DISTRO=$(grep -oP '(?<=^)[^[:space:]]+' /etc/redhat-release | tr '[:upper:]' '[:lower:]')
        VERSION=$(grep -oP '(?<=release )[[:digit:]]+' /etc/redhat-release)
    else
        DISTRO="unknown"
        VERSION="unknown"
    fi

    # Normalize distro names
    case "$DISTRO" in
        "ubuntu"|"debian"|"linuxmint")
            DISTRO_FAMILY="debian"
            ;;
        "rhel"|"centos"|"fedora"|"rocky"|"almalinux"|"ol")
            DISTRO_FAMILY="redhat"
            ;;
        "opensuse"*|"sles")
            DISTRO_FAMILY="suse"
            ;;
        "arch"|"manjaro")
            DISTRO_FAMILY="arch"
            ;;
        *)
            DISTRO_FAMILY="unknown"
            ;;
    esac

    log_info "Detected distribution: $DISTRO $VERSION (family: $DISTRO_FAMILY)"
}

# Check if running with root/sudo
check_permissions() {
    if [ "$ALL_USERS" = true ] || [ "$TARGET_USER" != "$USER" ]; then
        if [ $EUID -ne 0 ]; then
            log_error "Root privileges required for installing for other users"
            log_error "Please run this script with sudo or as root"
            exit 1
        fi
    fi
}

# Check if user exists
check_user_exists() {
    local user="$1"
    if ! id "$user" &>/dev/null; then
        log_error "User $user does not exist"
        exit 1
    fi
}

# Install Zsh
install_zsh() {
    print_section "Installing Zsh"
    
    # Check if Zsh is already installed
    if command -v zsh &>/dev/null; then
        log_info "Zsh is already installed"
        zsh --version
        if [ "$FORCE_INSTALL" != true ]; then
            return
        else
            log_info "Force reinstallation enabled"
        fi
    fi
    
    # Install Zsh based on the distribution
    case "$DISTRO_FAMILY" in
        "debian")
            log_info "Installing Zsh for Debian-based distribution..."
            apt-get update
            apt-get install -y zsh
            ;;
        "redhat")
            log_info "Installing Zsh for Red Hat-based distribution..."
            if [ "$DISTRO" = "fedora" ]; then
                dnf install -y zsh
            else
                yum install -y zsh
            fi
            ;;
        "suse")
            log_info "Installing Zsh for SUSE-based distribution..."
            zypper install -y zsh
            ;;
        "arch")
            log_info "Installing Zsh for Arch-based distribution..."
            pacman -Sy --noconfirm zsh
            ;;
        *)
            log_error "Unsupported distribution: $DISTRO_FAMILY"
            log_error "Please install Zsh manually and try again"
            exit 1
            ;;
    esac
    
    # Verify Zsh installation
    if ! command -v zsh &>/dev/null; then
        log_error "Failed to install Zsh"
        exit 1
    fi
    
    log_success "Zsh installed successfully"
    zsh --version
}

# Install Oh My Zsh
install_oh_my_zsh() {
    local user="$1"
    local user_home
    
    # Get user's home directory
    if [ "$user" = "root" ]; then
        user_home="/root"
    else
        user_home=$(eval echo ~"$user")
    fi
    
    print_section "Installing Oh My Zsh for user: $user"
    
    # Check if Oh My Zsh is already installed
    if [ -d "$user_home/.oh-my-zsh" ]; then
        log_info "Oh My Zsh is already installed for user: $user"
        if [ "$FORCE_INSTALL" != true ]; then
            return
        else
            log_info "Force reinstallation enabled, backing up existing installation"
            local backup_dir="$user_home/.oh-my-zsh.backup.$(date +%Y%m%d%H%M%S)"
            mv "$user_home/.oh-my-zsh" "$backup_dir"
            log_info "Backed up to: $backup_dir"
        fi
    fi
    
    # Create a temporary install script
    local install_script="/tmp/install_ohmyzsh_$user.sh"
    
    log_info "Downloading Oh My Zsh installer..."
    curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh > "$install_script"
    
    # Modify the install script to not run zsh at the end
    sed -i 's/exec zsh -l/echo "Oh My Zsh installed"/' "$install_script"
    
    # Make it executable
    chmod +x "$install_script"
    
    # Run the installer as the target user
    log_info "Installing Oh My Zsh for user: $user"
    if [ "$user" = "$USER" ] && [ $EUID -ne 0 ]; then
        # Running as self, not root
        RUNZSH=no sh "$install_script"
    else
        # Running as a different user or as root
        su - "$user" -c "RUNZSH=no sh $install_script"
    fi
    
    # Clean up the install script
    rm "$install_script"
    
    # Check if installation was successful
    if [ ! -d "$user_home/.oh-my-zsh" ]; then
        log_error "Failed to install Oh My Zsh for user: $user"
        return
    fi
    
    log_success "Oh My Zsh installed successfully for user: $user"
}

# Configure Oh My Zsh
configure_oh_my_zsh() {
    local user="$1"
    local user_home
    
    # Get user's home directory
    if [ "$user" = "root" ]; then
        user_home="/root"
    else
        user_home=$(eval echo ~"$user")
    fi
    
    print_section "Configuring Oh My Zsh for user: $user"
    
    # Check if custom config file is provided
    if [ -n "$CUSTOM_CONFIG_FILE" ]; then
        if [ -f "$CUSTOM_CONFIG_FILE" ]; then
            log_info "Using custom .zshrc file: $CUSTOM_CONFIG_FILE"
            cp "$CUSTOM_CONFIG_FILE" "$user_home/.zshrc"
            chown "$user:$(id -gn "$user")" "$user_home/.zshrc"
            return
        else
            log_error "Custom config file not found: $CUSTOM_CONFIG_FILE"
            log_info "Proceeding with default configuration..."
        fi
    fi
    
    # Make a backup of the original .zshrc if it exists
    if [ -f "$user_home/.zshrc" ]; then
        local backup_file="$user_home/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
        cp "$user_home/.zshrc" "$backup_file"
        log_info "Backed up original .zshrc to: $backup_file"
    fi
    
    # Configure theme
    log_info "Setting theme to: $THEME"
    sed -i "s/ZSH_THEME=\"robbyrussell\"/ZSH_THEME=\"$THEME\"/" "$user_home/.zshrc"
    
    # Configure plugins
    log_info "Setting plugins: $PLUGINS"
    # Convert comma-separated list to space-separated for zsh
    local plugins_list
    plugins_list=$(echo "$PLUGINS" | tr ',' ' ')
    sed -i "s/plugins=(git)/plugins=($plugins_list)/" "$user_home/.zshrc"
    
    # Set ownership
    chown "$user:$(id -gn "$user")" "$user_home/.zshrc"
    
    log_success "Oh My Zsh configured successfully for user: $user"
}

# Install Powerline fonts
install_powerline_fonts() {
    if [ "$INSTALL_FONTS" != true ]; then
        return
    fi
    
    print_section "Installing Powerline Fonts"
    
    # Install required packages for font installation
    case "$DISTRO_FAMILY" in
        "debian")
            apt-get update
            apt-get install -y git fontconfig
            ;;
        "redhat")
            if [ "$DISTRO" = "fedora" ]; then
                dnf install -y git fontconfig
            else
                yum install -y git fontconfig
            fi
            ;;
        "suse")
            zypper install -y git fontconfig
            ;;
        "arch")
            pacman -Sy --noconfirm git fontconfig
            ;;
        *)
            log_warning "Unsupported distribution for font installation: $DISTRO_FAMILY"
            log_warning "Skipping Powerline fonts installation"
            return
            ;;
    esac
    
    # Clone and install Powerline fonts
    log_info "Downloading and installing Powerline fonts..."
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Clone the repository
    git clone --depth=1 https://github.com/powerline/fonts.git "$temp_dir"
    
    # Run the install script
    cd "$temp_dir" || exit
    ./install.sh
    
    # Clean up
    cd - || exit
    rm -rf "$temp_dir"
    
    log_success "Powerline fonts installed successfully"
}

# Install Powerlevel10k theme
install_powerlevel10k() {
    if [ "$INSTALL_POWERLEVEL10K" != true ]; then
        return
    fi
    
    print_section "Installing Powerlevel10k Theme"
    
    # Process each user
    if [ "$ALL_USERS" = true ]; then
        # Get all users with home directories
        for user_home in /home/*; do
            if [ -d "$user_home" ]; then
                local user
                user=$(basename "$user_home")
                install_powerlevel10k_for_user "$user"
            fi
        done
        
        # Also for root if needed
        if [ "$INCLUDE_ROOT" = true ]; then
            install_powerlevel10k_for_user "root"
        fi
    else
        install_powerlevel10k_for_user "$TARGET_USER"
    fi
}

# Install Powerlevel10k for a specific user
install_powerlevel10k_for_user() {
    local user="$1"
    local user_home
    
    # Get user's home directory
    if [ "$user" = "root" ]; then
        user_home="/root"
    else
        user_home=$(eval echo ~"$user")
    fi
    
    log_info "Installing Powerlevel10k theme for user: $user"
    
    # Check if Oh My Zsh is installed
    if [ ! -d "$user_home/.oh-my-zsh" ]; then
        log_warning "Oh My Zsh not installed for user: $user, skipping Powerlevel10k"
        return
    fi
    
    # Clone Powerlevel10k repository
    local themes_dir="$user_home/.oh-my-zsh/custom/themes"
    
    # Create directory if it doesn't exist
    mkdir -p "$themes_dir"
    
    # Clone the repository
    if [ -d "$themes_dir/powerlevel10k" ]; then
        log_info "Powerlevel10k already installed for user: $user"
        if [ "$FORCE_INSTALL" = true ]; then
            log_info "Force reinstallation enabled, updating Powerlevel10k"
            cd "$themes_dir/powerlevel10k" || return
            git pull
            cd - || return
        fi
    else
        # Clone as the user to avoid permission issues
        if [ "$user" = "$USER" ] && [ $EUID -ne 0 ]; then
            # Running as self, not root
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$themes_dir/powerlevel10k"
        else
            # Running as a different user
            su - "$user" -c "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $themes_dir/powerlevel10k"
        fi
    fi
    
    # Update .zshrc to use Powerlevel10k
    log_info "Configuring Powerlevel10k as default theme for user: $user"
    sed -i "s/ZSH_THEME=\".*\"/ZSH_THEME=\"powerlevel10k\/powerlevel10k\"/" "$user_home/.zshrc"
    
    # Create a basic p10k configuration file if it doesn't exist
    if [ ! -f "$user_home/.p10k.zsh" ]; then
        log_info "Creating default p10k.zsh configuration for user: $user"
        cat > "$user_home/.p10k.zsh" << 'EOF'
# Generated by Powerlevel10k configuration wizard on 2023-05-01 at 12:00 UTC.
# For more information, see: https://github.com/romkatv/powerlevel10k#configuration
# Config created via setup_zsh_ohmyzsh.sh

# Temporarily change options.
'builtin' 'local' '-a' 'p10k_config_opts'
[[ ! -o 'aliases'         ]] || p10k_config_opts+=('aliases')
[[ ! -o 'sh_glob'         ]] || p10k_config_opts+=('sh_glob')
[[ ! -o 'no_brace_expand' ]] || p10k_config_opts+=('no_brace_expand')
'builtin' 'setopt' 'no_aliases' 'no_sh_glob' 'brace_expand'

() {
  emulate -L zsh -o extended_glob

  # Unset all configuration options.
  unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'

  # Zsh >= 5.1 is required.
  [[ $ZSH_VERSION == (5.<1->*|<6->.*) ]] || return

  # Basic settings
  POWERLEVEL9K_MODE='nerdfont-complete'
  POWERLEVEL9K_ICON_PADDING=none
  POWERLEVEL9K_BACKGROUND=transparent
  POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    dir                     # current directory
    vcs                     # git status
    newline                 # prompt on new line
    prompt_char             # prompt symbol
  )
  POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    status                  # exit code of the last command
    command_execution_time  # duration of the last command
    background_jobs         # presence of background jobs
    newline                 # prompt on new line
    time                    # current time
  )
  POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
  POWERLEVEL9K_PROMPT_CHAR_OK_VIINS='❯'
  POWERLEVEL9K_PROMPT_CHAR_ERROR_VIINS='❯'
  POWERLEVEL9K_PROMPT_CHAR_OK_VICMD='❮'
  POWERLEVEL9K_PROMPT_CHAR_ERROR_VICMD='❮'
  POWERLEVEL9K_PROMPT_CHAR_OK_VIVIS='❮'
  POWERLEVEL9K_PROMPT_CHAR_ERROR_VIVIS='❮'
  POWERLEVEL9K_PROMPT_CHAR_OK_VIOWR='❮'
  POWERLEVEL9K_PROMPT_CHAR_ERROR_VIOWR='❮'
  POWERLEVEL9K_DIR_FOREGROUND=blue
  POWERLEVEL9K_VCS_FOREGROUND=green
  POWERLEVEL9K_STATUS_ERROR_FOREGROUND=red
  POWERLEVEL9K_TIME_FOREGROUND=yellow
  POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
  POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=1
  POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=yellow
}

# Restore previous options.
(( ${#p10k_config_opts} )) && setopt ${p10k_config_opts[@]}
'builtin' 'unset' 'p10k_config_opts'
EOF
        
        # Append source of p10k.zsh to .zshrc if not already present
        if ! grep -q "source.*\.p10k\.zsh" "$user_home/.zshrc"; then
            echo "" >> "$user_home/.zshrc"
            echo "# To customize prompt, run 'p10k configure' or edit ~/.p10k.zsh." >> "$user_home/.zshrc"
            echo "[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh" >> "$user_home/.zshrc"
        fi
        
        # Set ownership
        chown "$user:$(id -gn "$user")" "$user_home/.p10k.zsh"
    fi
    
    # Set ownership for theme directory
    chown -R "$user:$(id -gn "$user")" "$themes_dir/powerlevel10k"
    
    log_success "Powerlevel10k theme installed and configured for user: $user"
}

# Install Zsh Syntax Highlighting
install_syntax_highlighting() {
    if [ "$INSTALL_SYNTAX_HIGHLIGHT" != true ]; then
        return
    fi
    
    print_section "Installing Zsh Syntax Highlighting"
    
    # Process each user
    if [ "$ALL_USERS" = true ]; then
        # Get all users with home directories
        for user_home in /home/*; do
            if [ -d "$user_home" ]; then
                local user
                user=$(basename "$user_home")
                install_syntax_highlighting_for_user "$user"
            fi
        done
        
        # Also for root if needed
        if [ "$INCLUDE_ROOT" = true ]; then
            install_syntax_highlighting_for_user "root"
        fi
    else
        install_syntax_highlighting_for_user "$TARGET_USER"
    fi
}

# Install Syntax Highlighting for a specific user
install_syntax_highlighting_for_user() {
    local user="$1"
    local user_home
    
    # Get user's home directory
    if [ "$user" = "root" ]; then
        user_home="/root"
    else
        user_home=$(eval echo ~"$user")
    fi
    
    log_info "Installing Zsh Syntax Highlighting for user: $user"
    
    # Check if Oh My Zsh is installed
    if [ ! -d "$user_home/.oh-my-zsh" ]; then
        log_warning "Oh My Zsh not installed for user: $user, skipping Syntax Highlighting"
        return
    fi
    
    # Clone Syntax Highlighting repository
    local plugins_dir="$user_home/.oh-my-zsh/custom/plugins"
    
    # Create directory if it doesn't exist
    mkdir -p "$plugins_dir"
    
    # Clone the repository
    if [ -d "$plugins_dir/zsh-syntax-highlighting" ]; then
        log_info "Syntax Highlighting already installed for user: $user"
        if [ "$FORCE_INSTALL" = true ]; then
            log_info "Force reinstallation enabled, updating Syntax Highlighting"
            cd "$plugins_dir/zsh-syntax-highlighting" || return
            git pull
            cd - || return
        fi
    else
        # Clone as the user to avoid permission issues
        if [ "$user" = "$USER" ] && [ $EUID -ne 0 ]; then
            # Running as self, not root
            git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$plugins_dir/zsh-syntax-highlighting"
        else
            # Running as a different user
            su - "$user" -c "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $plugins_dir/zsh-syntax-highlighting"
        fi
    fi
    
    # Update .zshrc to use Syntax Highlighting
    if ! grep -q "zsh-syntax-highlighting" "$user_home/.zshrc"; then
        log_info "Adding Syntax Highlighting to plugins for user: $user"
        # Get current plugins
        local current_plugins
        current_plugins=$(grep "^plugins=" "$user_home/.zshrc" | sed 's/^plugins=(//' | sed 's/)$//')
        
        # Append Syntax Highlighting to plugins
        if [ -n "$current_plugins" ]; then
            sed -i "s/^plugins=(/plugins=($current_plugins zsh-syntax-highlighting /" "$user_home/.zshrc"
        else
            sed -i "s/^plugins=(/plugins=(zsh-syntax-highlighting /" "$user_home/.zshrc"
        fi
    fi
    
    # Set ownership for plugin directory
    chown -R "$user:$(id -gn "$user")" "$plugins_dir/zsh-syntax-highlighting"
    
    log_success "Zsh Syntax Highlighting installed and configured for user: $user"
}

# Install Zsh Autosuggestions
install_autosuggestions() {
    if [ "$INSTALL_AUTOSUGGESTIONS" != true ]; then
        return
    fi
    
    print_section "Installing Zsh Autosuggestions"
    
    # Process each user
    if [ "$ALL_USERS" = true ]; then
        # Get all users with home directories
        for user_home in /home/*; do
            if [ -d "$user_home" ]; then
                local user
                user=$(basename "$user_home")
                install_autosuggestions_for_user "$user"
            fi
        done
        
        # Also for root if needed
        if [ "$INCLUDE_ROOT" = true ]; then
            install_autosuggestions_for_user "root"
        fi
    else
        install_autosuggestions_for_user "$TARGET_USER"
    fi
}

# Install Autosuggestions for a specific user
install_autosuggestions_for_user() {
    local user="$1"
    local user_home
    
    # Get user's home directory
    if [ "$user" = "root" ]; then
        user_home="/root"
    else
        user_home=$(eval echo ~"$user")
    fi
    
    log_info "Installing Zsh Autosuggestions for user: $user"
    
    # Check if Oh My Zsh is installed
    if [ ! -d "$user_home/.oh-my-zsh" ]; then
        log_warning "Oh My Zsh not installed for user: $user, skipping Autosuggestions"
        return
    fi
    
    # Clone Autosuggestions repository
    local plugins_dir="$user_home/.oh-my-zsh/custom/plugins"
    
    # Create directory if it doesn't exist
    mkdir -p "$plugins_dir"
    
    # Clone the repository
    if [ -d "$plugins_dir/zsh-autosuggestions" ]; then
        log_info "Autosuggestions already installed for user: $user"
        if [ "$FORCE_INSTALL" = true ]; then
            log_info "Force reinstallation enabled, updating Autosuggestions"
            cd "$plugins_dir/zsh-autosuggestions" || return
            git pull
            cd - || return
        fi
    else
        # Clone as the user to avoid permission issues
        if [ "$user" = "$USER" ] && [ $EUID -ne 0 ]; then
            # Running as self, not root
            git clone https://github.com/zsh-users/zsh-autosuggestions.git "$plugins_dir/zsh-autosuggestions"
        else
            # Running as a different user
            su - "$user" -c "git clone https://github.com/zsh-users/zsh-autosuggestions.git $plugins_dir/zsh-autosuggestions"
        fi
    fi
    
    # Update .zshrc to use Autosuggestions
    if ! grep -q "zsh-autosuggestions" "$user_home/.zshrc"; then
        log_info "Adding Autosuggestions to plugins for user: $user"
        # Get current plugins
        local current_plugins
        current_plugins=$(grep "^plugins=" "$user_home/.zshrc" | sed 's/^plugins=(//' | sed 's/)$//')
        
        # Append Autosuggestions to plugins
        if [ -n "$current_plugins" ]; then
            sed -i "s/^plugins=(/plugins=($current_plugins zsh-autosuggestions /" "$user_home/.zshrc"
        else
            sed -i "s/^plugins=(/plugins=(zsh-autosuggestions /" "$user_home/.zshrc"
        fi
    fi
    
    # Set ownership for plugin directory
    chown -R "$user:$(id -gn "$user")" "$plugins_dir/zsh-autosuggestions"
    
    log_success "Zsh Autosuggestions installed and configured for user: $user"
}

# Add custom aliases
add_custom_aliases() {
    if [ "$ADD_CUSTOM_ALIASES" != true ]; then
        return
    fi
    
    print_section "Adding Custom Aliases"
    
    # Process each user
    if [ "$ALL_USERS" = true ]; then
        # Get all users with home directories
        for user_home in /home/*; do
            if [ -d "$user_home" ]; then
                local user
                user=$(basename "$user_home")
                add_custom_aliases_for_user "$user"
            fi
        done
        
        # Also for root if needed
        if [ "$INCLUDE_ROOT" = true ]; then
            add_custom_aliases_for_user "root"
        fi
    else
        add_custom_aliases_for_user "$TARGET_USER"
    fi
}

# Add custom aliases for a specific user
add_custom_aliases_for_user() {
    local user="$1"
    local user_home
    
    # Get user's home directory
    if [ "$user" = "root" ]; then
        user_home="/root"
    else
        user_home=$(eval echo ~"$user")
    fi
    
    log_info "Adding custom aliases for user: $user"
    
    # Check if .zshrc exists
    if [ ! -f "$user_home/.zshrc" ]; then
        log_warning "No .zshrc found for user: $user, skipping aliases"
        return
    fi
    
    # Check if aliases already exist
    if grep -q "# Custom aliases" "$user_home/.zshrc"; then
        log_info "Custom aliases section already exists for user: $user"
        if [ "$FORCE_INSTALL" != true ]; then
            return
        else
            log_info "Force enabled, adding custom aliases anyway"
        fi
    fi
    
    # Add custom aliases section
    log_info "Adding custom aliases to .zshrc for user: $user"
    
    cat >> "$user_home/.zshrc" << 'EOF'

# Custom aliases
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'
alias c='clear'
alias h='history'
alias j='jobs -l'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit -m'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
alias glg='git log --graph --oneline --decorate'

# Docker aliases
alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dl='docker logs'

# System aliases
alias mem='free -m'
alias cpu='top -bn1 | grep "Cpu(s)"'
alias disk='df -h'
alias myip='curl -s ipinfo.io/ip'
alias ports='netstat -tulanp'
alias update-sys='sudo apt update && sudo apt upgrade -y'
EOF
    
    # Set ownership
    chown "$user:$(id -gn "$user")" "$user_home/.zshrc"
    
    log_success "Custom aliases added for user: $user"
}

# Set Zsh as default shell
set_default_shell() {
    if [ "$SET_DEFAULT_SHELL" != true ]; then
        return
    fi
    
    print_section "Setting Zsh as Default Shell"
    
    # Check if zsh is in /etc/shells
    if ! grep -q "$(command -v zsh)" /etc/shells; then
        log_info "Adding Zsh to /etc/shells"
        echo "$(command -v zsh)" >> /etc/shells
    fi
    
    # Process each user
    if [ "$ALL_USERS" = true ]; then
        # Get all users with home directories
        for user_home in /home/*; do
            if [ -d "$user_home" ]; then
                local user
                user=$(basename "$user_home")
                set_default_shell_for_user "$user"
            fi
        done
        
        # Also for root if needed
        if [ "$INCLUDE_ROOT" = true ]; then
            set_default_shell_for_user "root"
        fi
    else
        set_default_shell_for_user "$TARGET_USER"
    fi
}

# Set Zsh as default shell for a specific user
set_default_shell_for_user() {
    local user="$1"
    
    log_info "Setting Zsh as default shell for user: $user"
    
    # Get current shell
    local current_shell
    current_shell=$(getent passwd "$user" | cut -d: -f7)
    
    # Check if Zsh is already the default shell
    if [ "$current_shell" = "$(command -v zsh)" ]; then
        log_info "Zsh is already the default shell for user: $user"
        return
    fi
    
    # Change shell
    chsh -s "$(command -v zsh)" "$user"
    
    # Verify the change
    current_shell=$(getent passwd "$user" | cut -d: -f7)
    if [ "$current_shell" = "$(command -v zsh)" ]; then
        log_success "Default shell changed to Zsh for user: $user"
    else
        log_error "Failed to set Zsh as default shell for user: $user"
    fi
}

# Process all users
process_all_users() {
    # Process all users with home directories
    for user_home in /home/*; do
        if [ -d "$user_home" ]; then
            local user
            user=$(basename "$user_home")
            
            # Skip system users
            if id -u "$user" >/dev/null 2>&1; then
                if [ "$(id -u "$user")" -ge 1000 ]; then
                    log_info "Processing user: $user"
                    install_oh_my_zsh "$user"
                    configure_oh_my_zsh "$user"
                fi
            fi
        fi
    done
    
    # Also process root if needed
    if [ "$INCLUDE_ROOT" = true ]; then
        log_info "Processing root user"
        install_oh_my_zsh "root"
        configure_oh_my_zsh "root"
    fi
}

# Main function
main() {
    print_header "Zsh and Oh My Zsh Installation Script"
    
    # Detect Linux distribution
    detect_distribution
    
    # Check permissions
    check_permissions
    
    # Install Zsh
    install_zsh
    
    # Install and configure for specific user or all users
    if [ "$ALL_USERS" = true ]; then
        log_info "Installing for all users"
        
        # Prompt for including root user
        INCLUDE_ROOT=false
        if [ "$ASSUME_YES" = true ]; then
            INCLUDE_ROOT=true
        else
            read -p "Include root user? [y/N]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                INCLUDE_ROOT=true
            fi
        fi
        
        process_all_users
    else
        # Check if target user exists
        check_user_exists "$TARGET_USER"
        
        # Install and configure for target user
        install_oh_my_zsh "$TARGET_USER"
        configure_oh_my_zsh "$TARGET_USER"
    fi
    
    # Install additional components
    install_powerline_fonts
    install_powerlevel10k
    install_syntax_highlighting
    install_autosuggestions
    add_custom_aliases
    set_default_shell
    
    print_header "Installation Complete"
    
    log_success "Zsh and Oh My Zsh have been successfully installed and configured"
    log_info "To start using Zsh, log out and log back in, or run: exec zsh"
    
    if [ "$INSTALL_POWERLEVEL10K" = true ]; then
        log_info "To customize Powerlevel10k theme, run: p10k configure"
    fi
}

# Run the main function
main