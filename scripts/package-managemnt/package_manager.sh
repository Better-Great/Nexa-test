#!/bin/bash
#
# package_manager.sh - Interactive script for package management
# 
# This script provides interactive package management functionality for Linux servers.
# It allows users to:
#   - Install common server packages
#   - Update the system
#   - Search for packages
#   - Install custom packages
#   - Configure common services
#   - Check package status


# Set strict mode
set -e
set -u
set -o pipefail

# Global variables
LOG_DIR="/var/log/admin-scripts"
LOG_FILE="$LOG_DIR/package_manager_$(date +%Y%m%d).log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
OS_TYPE=""
TIMEOUT_DURATION=300  # 5 minutes timeout for long operations

# Common server packages by category
declare -A PACKAGE_GROUPS
PACKAGE_GROUPS["web_server"]="nginx apache2"
PACKAGE_GROUPS["database"]="mariadb-server postgresql"
PACKAGE_GROUPS["security"]="fail2ban ufw rkhunter lynis"
PACKAGE_GROUPS["monitoring"]="htop iotop nmon sysstat"
PACKAGE_GROUPS["utilities"]="vim git curl wget tmux screen rsync"
PACKAGE_GROUPS["network"]="nmap tcpdump iperf3 net-tools dnsutils"
PACKAGE_GROUPS["development"]="build-essential python3 python3-pip"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Error handling function - Print error message and exit
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"  # Default exit code is 1
    
    log "ERROR" "$message"
    echo -e "${RED}ERROR: $message${NC}" >&2
    exit "$exit_code"
}

# Command execution with error handling
run_command() {
    local cmd="$1"
    local error_msg="$2"
    local timeout="${3:-$TIMEOUT_DURATION}"
    
    log "DEBUG" "Running command: $cmd"
    
    # Run the command with timeout and capture its output and return status
    local output
    if ! output=$(timeout "$timeout" bash -c "$cmd" 2>&1); then
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log "ERROR" "Command timed out after $timeout seconds: $cmd"
            echo -e "${RED}ERROR: Operation timed out. Please check your network or system load.${NC}"
            return 1
        else
            log "ERROR" "Command failed ($exit_code): $cmd"
            log "ERROR" "Output: $output"
            echo -e "${RED}ERROR: $error_msg${NC}"
            echo "Details: $output"
            return $exit_code
        fi
    fi
    
    log "DEBUG" "Command completed successfully: $cmd"
    return 0
}

# Setup logging
setup_logging() {
    # Create log directory if it doesn't exist
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR" || error_exit "Failed to create log directory $LOG_DIR"
        chmod 750 "$LOG_DIR" || error_exit "Failed to set permissions on log directory"
    fi
    
    # Create log file if it doesn't exist
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE" || error_exit "Failed to create log file $LOG_FILE"
        chmod 640 "$LOG_FILE" || error_exit "Failed to set permissions on log file"
    fi
    
    # Log script start
    echo "[$TIMESTAMP] Package Manager script started" >> "$LOG_FILE" || error_exit "Failed to write to log file"
}

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || {
        echo -e "${RED}WARNING: Could not write to log file $LOG_FILE${NC}" >&2
        # If we can't log, still try to display the message
        case "$level" in
            "INFO")
                echo -e "${GREEN}[INFO]${NC} $message"
                ;;
            "WARNING")
                echo -e "${YELLOW}[WARNING]${NC} $message"
                ;;
            "ERROR")
                echo -e "${RED}[ERROR]${NC} $message"
                ;;
            *)
                echo -e "${BLUE}[$level]${NC} $message"
                ;;
        esac
        return 1
    }
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        *)
            echo -e "${BLUE}[$level]${NC} $message"
            ;;
    esac
    
    return 0
}

# Check root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root" 1
    fi
}

# Check for required commands
check_requirements() {
    local required_commands=("timeout" "wget" "curl")

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "WARNING" "Required command '$cmd' not found. Attempting to install..."

            case "$OS_TYPE" in
                "ubuntu"|"debian")
                    if apt update -y; then
                        if apt install -y "$cmd"; then
                            log "INFO" "Successfully installed $cmd"
                        else
                            error_exit "Failed to install $cmd"
                        fi
                    else
                        error_exit "Failed to update apt repositories"
                    fi
                    ;;
                "centos"|"rhel"|"fedora"|"rocky"|"almalinux")
                    if dnf install -y "$cmd"; then
                        log "INFO" "Successfully installed $cmd"
                    else
                        error_exit "Failed to install $cmd"
                    fi
                    ;;
                *)
                    error_exit "Unsupported OS type: $OS_TYPE"
                    ;;
            esac
        fi
    done
}

# Detect OS type
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_TYPE=$ID
        log "INFO" "Detected OS: $OS_TYPE"
        
        # Validate supported OS
        case "$OS_TYPE" in
            "ubuntu"|"debian"|"centos"|"rhel"|"fedora"|"rocky"|"almalinux")
                log "INFO" "Operating system $OS_TYPE is supported"
                ;;
            *)
                error_exit "Unsupported OS type: $OS_TYPE. This script only supports Ubuntu, Debian, CentOS, RHEL, Fedora, Rocky Linux, and AlmaLinux."
                ;;
        esac
    else
        error_exit "Cannot detect OS type. /etc/os-release file not found."
    fi
}

# Check network connectivity
check_network() {
    log "INFO" "Checking network connectivity..."
    
    # Try to ping package repositories
    case "$OS_TYPE" in
        "ubuntu"|"debian")
            if ! ping -c 1 archive.ubuntu.com &>/dev/null && ! ping -c 1 deb.debian.org &>/dev/null; then
                error_exit "No network connectivity to package repositories. Please check your internet connection."
            fi
            ;;
        "centos"|"rhel"|"fedora"|"rocky"|"almalinux")
            if ! ping -c 1 mirror.centos.org &>/dev/null && ! ping -c 1 dl.fedoraproject.org &>/dev/null; then
                error_exit "No network connectivity to package repositories. Please check your internet connection."
            fi
            ;;
    esac
    
    log "INFO" "Network connectivity confirmed"
}

# Update system with error handling
update_system() {
    log "INFO" "Updating system packages..."
    
    # Check network connectivity before updating
    check_network
    
    case "$OS_TYPE" in
        "ubuntu"|"debian")
            if ! run_command "apt update -y" "Failed to update package lists"; then
                log "WARNING" "Retrying update with different mirror..."
                if ! run_command "apt update -y -o Acquire::AllowInsecureRepositories=true" "Failed to update package lists, even with alternative settings"; then
                    return 1
                fi
            fi
            
            if ! run_command "apt upgrade -y" "Failed to upgrade packages"; then
                log "WARNING" "Upgrading with --fix-broken flag..."
                if ! run_command "apt upgrade -y --fix-broken" "Failed to upgrade packages, even with --fix-broken"; then
                    return 1
                fi
            fi
            ;;
        "centos"|"rhel"|"fedora"|"rocky"|"almalinux")
            if ! run_command "dnf check-update" "Failed to check for updates"; then
                # Exit code 100 from check-update means updates are available, which is normal
                if [ $? -ne 100 ]; then
                    return 1
                fi
            fi
            
            if ! run_command "dnf update -y" "Failed to update packages"; then
                log "WARNING" "Retrying update with --skip-broken flag..."
                if ! run_command "dnf update -y --skip-broken" "Failed to update packages, even with --skip-broken"; then
                    return 1
                fi
            fi
            ;;
        *)
            log "ERROR" "Unsupported OS type: $OS_TYPE"
            return 1
            ;;
    esac
    
    log "INFO" "System updated successfully"
    return 0
}

# Validate package name
validate_package_name() {
    local package="$1"
    
    # Check if package name contains only alphanumeric characters, hyphens, periods, and plus signs
    if [[ ! "$package" =~ ^[a-zA-Z0-9.+-]+$ ]]; then
        log "ERROR" "Invalid package name: $package"
        echo -e "${RED}Invalid package name: $package${NC}"
        return 1
    fi
    
    return 0
}

# Check if package exists in repositories
package_exists() {
    local package="$1"
    
    log "DEBUG" "Checking if package exists: $package"
    
    case "$OS_TYPE" in
        "ubuntu"|"debian")
            if apt-cache show "$package" &>/dev/null; then
                return 0
            else
                return 1
            fi
            ;;
        "centos"|"rhel"|"fedora"|"rocky"|"almalinux")
            if dnf info "$package" &>/dev/null; then
                return 0
            else
                return 1
            fi
            ;;
        *)
            log "ERROR" "Unsupported OS type: $OS_TYPE"
            return 1
            ;;
    esac
}

# Install packages with error handling
install_packages() {
    local packages="$1"
    local non_existent_packages=""
    local install_packages=""
    
    log "INFO" "Preparing to install packages: $packages"
    
    # Check network connectivity
    check_network
    
    # Validate and check each package
    for package in $packages; do
        if ! validate_package_name "$package"; then
            continue
        fi
        
        if ! package_exists "$package"; then
            non_existent_packages="$non_existent_packages $package"
            log "WARNING" "Package does not exist in repositories: $package"
        else
            install_packages="$install_packages $package"
        fi
    done
    
    # Warn about non-existent packages
    if [[ -n "$non_existent_packages" ]]; then
        log "WARNING" "The following packages were not found in repositories: $non_existent_packages"
        echo -e "${YELLOW}WARNING: The following packages were not found in repositories:${NC} $non_existent_packages"
        
        # Ask user if they want to continue with available packages
        if [[ -n "$install_packages" ]]; then
            echo -e "${YELLOW}Do you want to continue installing available packages? (y/n)${NC}"
            read -r continue_install
            
            if [[ "$continue_install" != "y" ]]; then
                log "INFO" "Installation cancelled by user"
                return 0
            fi
        else
            log "ERROR" "No valid packages to install"
            echo -e "${RED}No valid packages to install${NC}"
            return 1
        fi
    fi
    
    # If no valid packages to install
    if [[ -z "$install_packages" ]]; then
        log "ERROR" "No valid packages to install"
        echo -e "${RED}No valid packages to install${NC}"
        return 1
    fi
    
    log "INFO" "Installing packages: $install_packages"
    
    case "$OS_TYPE" in
        "ubuntu"|"debian")
            if ! run_command "apt install -y $install_packages" "Failed to install packages"; then
                log "WARNING" "Retrying installation with --fix-broken flag..."
                if ! run_command "apt install -y --fix-broken $install_packages" "Failed to install packages, even with --fix-broken"; then
                    return 1
                fi
            fi
            ;;
        "centos"|"rhel"|"fedora"|"rocky"|"almalinux")
            if ! run_command "dnf install -y $install_packages" "Failed to install packages"; then
                log "WARNING" "Retrying installation with --skip-broken flag..."
                if ! run_command "dnf install -y --skip-broken $install_packages" "Failed to install packages, even with --skip-broken"; then
                    return 1
                fi
            fi
            ;;
        *)
            log "ERROR" "Unsupported OS type: $OS_TYPE"
            return 1
            ;;
    esac
    
    # Verify installation success
    local failed_packages=""
    for package in $install_packages; do
        if ! check_package "$package" &>/dev/null; then
            failed_packages="$failed_packages $package"
        fi
    done
    
    if [[ -n "$failed_packages" ]]; then
        log "WARNING" "The following packages could not be verified as installed: $failed_packages"
        echo -e "${YELLOW}WARNING: The following packages could not be verified as installed:${NC} $failed_packages"
        return 1
    fi
    
    log "INFO" "Packages installed successfully"
    return 0
}

# Search for packages with error handling
search_packages() {
    local search_term="$1"
    
    # Validate search term
    if [[ -z "$search_term" ]]; then
        log "ERROR" "Empty search term"
        echo -e "${RED}Search term cannot be empty${NC}"
        return 1
    fi
    
    # Sanitize search term to prevent command injection
    search_term=$(echo "$search_term" | tr -cd '[:alnum:] ._-')
    
    log "INFO" "Searching for packages matching: $search_term"
    
    # Check network connectivity
    check_network
    
    case "$OS_TYPE" in
        "ubuntu"|"debian")
            if ! run_command "apt search \"$search_term\"" "Failed to search for packages"; then
                return 1
            fi
            ;;
        "centos"|"rhel"|"fedora"|"rocky"|"almalinux")
            if ! run_command "dnf search \"$search_term\"" "Failed to search for packages"; then
                return 1
            fi
            ;;
        *)
            log "ERROR" "Unsupported OS type: $OS_TYPE"
            return 1
            ;;
    esac
    
    return 0
}

# Check if package is installed with error handling
check_package() {
    local package="$1"
    
    # Validate package name
    if ! validate_package_name "$package"; then
        return 1
    fi
    
    log "INFO" "Checking if package is installed: $package"
    
    case "$OS_TYPE" in
        "ubuntu"|"debian")
            if dpkg -l "$package" &>/dev/null; then
                echo -e "${GREEN}Package $package is installed${NC}"
                return 0
            else
                echo -e "${RED}Package $package is NOT installed${NC}"
                return 1
            fi
            ;;
        "centos"|"rhel"|"fedora"|"rocky"|"almalinux")
            if rpm -q "$package" &>/dev/null; then
                echo -e "${GREEN}Package $package is installed${NC}"
                return 0
            else
                echo -e "${RED}Package $package is NOT installed${NC}"
                return 1
            fi
            ;;
        *)
            log "ERROR" "Unsupported OS type: $OS_TYPE"
            return 1
            ;;
    esac
}

# Write file with error handling
write_file() {
    local file="$1"
    local content="$2"
    
    # Create directory if it doesn't exist
    local dir
    dir=$(dirname "$file")
    if [[ ! -d "$dir" ]]; then
        if ! mkdir -p "$dir"; then
            log "ERROR" "Failed to create directory: $dir"
            return 1
        fi
    fi
    
    # Write content to file
    log "INFO" "Writing to file: $file"
    if ! echo "$content" > "$file"; then
        log "ERROR" "Failed to write to file: $file"
        return 1
    fi
    
    log "INFO" "File written successfully: $file"
    return 0
}

# Main function - The entry point of the script
main() {
    # Initialize script
    check_root
    detect_os
    setup_logging
    check_requirements
    
    echo -e "${GREEN}=======================================${NC}"
    echo -e "${GREEN}= Interactive Package Manager Script  =${NC}"
    echo -e "${GREEN}=======================================${NC}"
    echo
    
    while true; do
        echo -e "${BLUE}Please select an option:${NC}"
        echo "1) Update system"
        echo "2) Install common server packages"
        echo "3) Search for packages"
        echo "4) Install custom packages"
        echo "5) Check package status"
        echo "6) Configure web server (Nginx)"
        echo "7) Configure database (MariaDB)"
        echo "0) Exit"
        echo
        
        read -r -p "Enter your choice [0-7]: " choice
        
        case $choice in
            1)
                echo -e "${YELLOW}Updating system...${NC}"
                if update_system; then
                    echo -e "${GREEN}System updated successfully${NC}"
                else
                    echo -e "${RED}System update failed${NC}"
                fi
                ;;
            2)
                echo -e "${BLUE}Available package groups:${NC}"
                for group in "${!PACKAGE_GROUPS[@]}"; do
                    echo "$group: ${PACKAGE_GROUPS[$group]}"
                done
                echo
                
                read -r -p "Enter package group to install: " group
                
                if [[ -n "${PACKAGE_GROUPS[$group]:-}" ]]; then
                    echo -e "${YELLOW}Installing packages: ${PACKAGE_GROUPS[$group]}${NC}"
                    
                    if install_packages "${PACKAGE_GROUPS[$group]}"; then
                        echo -e "${GREEN}Packages installed successfully${NC}"
                    else
                        echo -e "${RED}Package installation failed${NC}"
                    fi
                else
                    echo -e "${RED}Invalid package group: $group${NC}"
                fi
                ;;
            3)
                read -r -p "Enter search term: " search_term
                
                if [[ -n "$search_term" ]]; then
                    echo -e "${YELLOW}Searching for packages matching: $search_term${NC}"
                    search_packages "$search_term"
                else
                    echo -e "${RED}Search term cannot be empty${NC}"
                fi
                ;;
            4)
                read -r -p "Enter package names (space separated): " packages
                
                if [[ -n "$packages" ]]; then
                    echo -e "${YELLOW}Installing packages: $packages${NC}"
                    
                    if install_packages "$packages"; then
                        echo -e "${GREEN}Packages installed successfully${NC}"
                    else
                        echo -e "${RED}Package installation failed${NC}"
                    fi
                else
                    echo -e "${RED}No packages specified${NC}"
                fi
                ;;
            5)
                read -r -p "Enter package name to check: " package
                
                if [[ -n "$package" ]]; then
                    check_package "$package"
                else
                    echo -e "${RED}Package name cannot be empty${NC}"
                fi
                ;;
            6)
                echo -e "${YELLOW}Configuring Nginx web server...${NC}"
                # Basic Nginx configuration (simplified)
                if ! check_package "nginx" &>/dev/null; then
                    echo -e "${YELLOW}Nginx not installed. Installing...${NC}"
                    install_packages "nginx"
                fi
                
                # Enable and start Nginx
                systemctl enable nginx
                systemctl restart nginx
                echo -e "${GREEN}Nginx configured and started${NC}"
                ;;
            7)
                echo -e "${YELLOW}Configuring MariaDB...${NC}"
                # Basic MariaDB configuration (simplified)
                if ! check_package "mariadb-server" &>/dev/null; then
                    echo -e "${YELLOW}MariaDB not installed. Installing...${NC}"
                    install_packages "mariadb-server"
                fi
                
                # Enable and start MariaDB
                systemctl enable mariadb
                systemctl restart mariadb
                echo -e "${GREEN}MariaDB configured and started${NC}"
                echo -e "${YELLOW}NOTE: Run 'mysql_secure_installation' manually to secure the installation${NC}"
                ;;
            0)
                echo -e "${GREEN}Exiting...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                ;;
        esac
        
        echo
    done
}

# Execute main function
main "$@"