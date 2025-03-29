#!/bin/bash
#
# service_manager.sh - Interactive service management script
# 
# This script provides a user-friendly interface for managing system services
# including enabling, disabling, starting, stopping, restarting services,
# and checking their status.

# Set strict error handling
set -e
trap 'echo "Error occurred at line $LINENO. Command: $BASH_COMMAND"' ERR

# Set text colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/service_manager.log"

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root!${NC}"
   exit 1
fi

# Function to log actions
log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to check if a service exists
service_exists() {
    if systemctl list-unit-files | grep -q "$1.service"; then
        return 0
    else
        return 1
    fi
}

# Function to display service status with formatted output
display_service_status() {
    local service=$1
    echo -e "${BLUE}=== Service: $service ===${NC}"
    
    if ! service_exists "$service"; then
        echo -e "${RED}Service $service does not exist${NC}"
        return 1
    fi
    
    local status
    status=$(systemctl is-active "$service")
    local enabled
    enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
    
    if [[ "$status" == "active" ]]; then
        echo -e "Status: ${GREEN}$status${NC}"
    else
        echo -e "Status: ${RED}$status${NC}"
    fi
    
    if [[ "$enabled" == "enabled" ]]; then
        echo -e "Boot status: ${GREEN}$enabled${NC}"
    else
        echo -e "Boot status: ${RED}$enabled${NC}"
    fi
    
    echo -e "${YELLOW}Service details:${NC}"
    systemctl status "$service" --no-pager | grep -E "Loaded:|Active:|Main PID:"
    
    echo -e "${YELLOW}Recent logs:${NC}"
    journalctl -u "$service" --no-pager -n 5 2>/dev/null || echo "No logs available"
}

# Function to start a service
start_service() {
    local service=$1
    
    if ! service_exists "$service"; then
        echo -e "${RED}Service $service does not exist${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Starting service $service...${NC}"
    if systemctl start "$service"; then
        echo -e "${GREEN}Service $service started successfully${NC}"
        log_action "Started service $service"
        return 0
    else
        echo -e "${RED}Failed to start service $service${NC}"
        log_action "Failed to start service $service"
        return 1
    fi
}

# Function to stop a service
stop_service() {
    local service=$1
    
    if ! service_exists "$service"; then
        echo -e "${RED}Service $service does not exist${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Stopping service $service...${NC}"
    if systemctl stop "$service"; then
        echo -e "${GREEN}Service $service stopped successfully${NC}"
        log_action "Stopped service $service"
        return 0
    else
        echo -e "${RED}Failed to stop service $service${NC}"
        log_action "Failed to stop service $service"
        return 1
    fi
}

# Function to restart a service
restart_service() {
    local service=$1
    
    if ! service_exists "$service"; then
        echo -e "${RED}Service $service does not exist${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Restarting service $service...${NC}"
    if systemctl restart "$service"; then
        echo -e "${GREEN}Service $service restarted successfully${NC}"
        log_action "Restarted service $service"
        return 0
    else
        echo -e "${RED}Failed to restart service $service${NC}"
        log_action "Failed to restart service $service"
        return 1
    fi
}

# Function to enable a service
enable_service() {
    local service=$1
    
    if ! service_exists "$service"; then
        echo -e "${RED}Service $service does not exist${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Enabling service $service to start at boot...${NC}"
    if systemctl enable "$service"; then
        echo -e "${GREEN}Service $service enabled successfully${NC}"
        log_action "Enabled service $service"
        return 0
    else
        echo -e "${RED}Failed to enable service $service${NC}"
        log_action "Failed to enable service $service"
        return 1
    fi
}

# Function to disable a service
disable_service() {
    local service=$1
    
    if ! service_exists "$service"; then
        echo -e "${RED}Service $service does not exist${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Disabling service $service from starting at boot...${NC}"
    if systemctl disable "$service"; then
        echo -e "${GREEN}Service $service disabled successfully${NC}"
        log_action "Disabled service $service"
        return 0
    else
        echo -e "${RED}Failed to disable service $service${NC}"
        log_action "Failed to disable service $service"
        return 1
    fi
}

# Function to list all services
list_services() {
    local filter=$1
    
    echo -e "${BLUE}=== Available Services ===${NC}"
    echo -e "${YELLOW}Showing services with filter: ${filter:-all}${NC}\n"
    
    if [[ -z "$filter" ]]; then
        systemctl list-unit-files --type=service --no-pager | grep -v "@."
    else
        systemctl list-unit-files --type=service --no-pager | grep -v "@." | grep -i "$filter"
    fi
}

# Function to search for and install a service package
install_service_package() {
    local package=$1
    
    echo -e "${YELLOW}Searching for package $package...${NC}"
    
    # Detect package manager
    if command -v apt &>/dev/null; then
        local PKG_MANAGER="apt"
        local SEARCH_CMD="apt search"
        local INSTALL_CMD="apt install -y"
    elif command -v yum &>/dev/null; then
        local PKG_MANAGER="yum"
        local SEARCH_CMD="yum search"
        local INSTALL_CMD="yum install -y"
    elif command -v dnf &>/dev/null; then
        local PKG_MANAGER="dnf"
        local SEARCH_CMD="dnf search"
        local INSTALL_CMD="dnf install -y"
    else
        echo -e "${RED}No supported package manager found (apt, yum, dnf)${NC}"
        return 1
    fi
    
    # Search for package
    local search_results
    search_results=$($SEARCH_CMD "$package" 2>/dev/null)
    
    if [[ -z "$search_results" ]]; then
        echo -e "${RED}No packages found matching '$package'${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Found packages matching '$package':${NC}"
    echo "$search_results"
    
    echo -e "${YELLOW}Would you like to install a package? (y/n)${NC}"
    read -r choice
    
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        echo -e "${YELLOW}Enter the exact package name to install:${NC}"
        read -r exact_package
        
        echo -e "${YELLOW}Installing $exact_package...${NC}"
        if $INSTALL_CMD "$exact_package"; then
            echo -e "${GREEN}Package $exact_package installed successfully${NC}"
            log_action "Installed package $exact_package using $PKG_MANAGER"
            return 0
        else
            echo -e "${RED}Failed to install package $exact_package${NC}"
            log_action "Failed to install package $exact_package using $PKG_MANAGER"
            return 1
        fi
    else
        echo -e "${YELLOW}Installation cancelled${NC}"
        return 0
    fi
}

# Function to analyze service dependencies
analyze_service_dependencies() {
    local service=$1
    
    if ! service_exists "$service"; then
        echo -e "${RED}Service $service does not exist${NC}"
        return 1
    fi
    
    echo -e "${BLUE}=== Service Dependencies for $service ===${NC}"
    
    echo -e "${YELLOW}Required by (services that depend on this service):${NC}"
    systemctl list-dependencies --reverse "$service" --no-pager
    
    echo -e "\n${YELLOW}Depends on (services this service requires):${NC}"
    systemctl list-dependencies "$service" --no-pager
}

# Function to check service performance
check_service_performance() {
    local service=$1
    
    if ! service_exists "$service"; then
        echo -e "${RED}Service $service does not exist${NC}"
        return 1
    fi
    
    echo -e "${BLUE}=== Performance Stats for $service ===${NC}"
    
    # Get main PID
    local pid
    pid=$(systemctl show -p MainPID "$service" | cut -d= -f2)
    
    if [[ "$pid" == "0" ]]; then
        echo -e "${RED}Service is not running (no PID)${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}CPU and Memory Usage:${NC}"
    ps -p "$pid" -o pid,ppid,cmd,%cpu,%mem,start,time --headers
    
    echo -e "\n${YELLOW}Open Files:${NC}"
    lsof -p "$pid" 2>/dev/null | head -10 || echo "No open files information available"
    
    echo -e "\n${YELLOW}Network Connections:${NC}"
    netstat -tunapl 2>/dev/null | grep "$pid/" || echo "No network connections found"
}

# Main menu function
show_menu() {
    echo -e "\n${BLUE}===== Service Management Tool =====${NC}"
    echo -e "1. ${GREEN}List available services${NC}"
    echo -e "2. ${GREEN}Check service status${NC}"
    echo -e "3. ${GREEN}Start a service${NC}"
    echo -e "4. ${GREEN}Stop a service${NC}"
    echo -e "5. ${GREEN}Restart a service${NC}"
    echo -e "6. ${GREEN}Enable a service${NC}"
    echo -e "7. ${GREEN}Disable a service${NC}"
    echo -e "8. ${GREEN}Search for and install a service package${NC}"
    echo -e "9. ${GREEN}Analyze service dependencies${NC}"
    echo -e "10. ${GREEN}Check service performance${NC}"
    echo -e "0. ${RED}Exit${NC}"
    echo -e "${YELLOW}Enter your choice:${NC} "
}

# Main function
main() {
    # Create log file if it doesn't exist
    touch "$LOG_FILE" 2>/dev/null || {
        LOG_FILE="./service_manager.log"
        touch "$LOG_FILE"
        echo "Created log file at $LOG_FILE"
    }
    
    log_action "Service Manager script started"
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                echo -e "${YELLOW}Enter filter term (leave empty for all services):${NC}"
                read -r filter
                list_services "$filter"
                ;;
            2)
                echo -e "${YELLOW}Enter service name:${NC}"
                read -r service
                display_service_status "$service"
                ;;
            3)
                echo -e "${YELLOW}Enter service name:${NC}"
                read -r service
                start_service "$service"
                ;;
            4)
                echo -e "${YELLOW}Enter service name:${NC}"
                read -r service
                stop_service "$service"
                ;;
            5)
                echo -e "${YELLOW}Enter service name:${NC}"
                read -r service
                restart_service "$service"
                ;;
            6)
                echo -e "${YELLOW}Enter service name:${NC}"
                read -r service
                enable_service "$service"
                ;;
            7)
                echo -e "${YELLOW}Enter service name:${NC}"
                read -r service
                disable_service "$service"
                ;;
            8)
                echo -e "${YELLOW}Enter package name to search:${NC}"
                read -r package
                install_service_package "$package"
                ;;
            9)
                echo -e "${YELLOW}Enter service name:${NC}"
                read -r service
                analyze_service_dependencies "$service"
                ;;
            10)
                echo -e "${YELLOW}Enter service name:${NC}"
                read -r service
                check_service_performance "$service"
                ;;
            0)
                log_action "Service Manager script ended"
                echo -e "${GREEN}Exiting. Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                ;;
        esac
        
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read -r
    done
}

# Start the script
main