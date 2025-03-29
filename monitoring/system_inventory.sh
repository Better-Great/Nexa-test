#!/bin/bash
#
# system_inventory.sh
# Gets basic system info and generates a report
#

# Set some paths and stuff
REPORT_DIR="/tmp/reports"
TODAY=$(date +"%Y-%m-%d")
REPORT_FILE="$REPORT_DIR/system_report_$TODAY.txt"
LOG_FILE="/var/log/sysinfo.log"

# Make sure we can write reports somewhere
mkdir -p "$REPORT_DIR" 2>/dev/null
if ! mkdir -p "$REPORT_DIR" 2>/dev/null; then
    echo "Can't create reports directory. Check permissions."
    exit 1
fi

# Basic logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null
}

# Check if we're root
if [ "$(id -u)" -ne 0 ]; then
    echo "Hey! Run this with sudo."
    exit 1
fi

# Start a new report file
create_report_header() {
    {
        echo "==========================="
        echo "  SYSTEM INVENTORY REPORT  "
        echo "  Created on: $TODAY"
        echo "==========================="
        echo ""
    } > "$REPORT_FILE"
}

# Add a section to the report
add_section() {
    {
        echo ""
        echo "##### $1 #####"
        echo ""
    } >> "$REPORT_FILE"
}

# Get basic system info
get_system_info() {
    log "Getting system info"
    
    add_section "SYSTEM INFO"
    
    {
        echo "Hostname: $(hostname)"
        echo "Kernel: $(uname -r)"
        
        # Get OS info
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            echo "OS: $PRETTY_NAME"
        else
            echo "OS: $(uname -s)"
        fi
        
        echo "Uptime: $(uptime -p)"
    } >> "$REPORT_FILE"
}

# Get CPU details
get_cpu_info() {
    log "Getting CPU info"
    
    add_section "CPU INFO"
    
    # Try lscpu first, fall back to /proc/cpuinfo
    if command -v lscpu >/dev/null; then
        lscpu | grep -E "Model name|Architecture|CPU\(s\)|Core|Thread" >> "$REPORT_FILE"
    else
        cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
        cpu_count=$(grep -c "processor" /proc/cpuinfo)
        {
            echo "Model: $cpu_model"
            echo "CPUs: $cpu_count"
        } >> "$REPORT_FILE"
    fi
}

# Get memory info
get_mem_info() {
    log "Getting memory info"
    
    add_section "MEMORY INFO"
    
    free -h >> "$REPORT_FILE"
}

# Get disk info
get_disk_info() {
    log "Getting disk info"
    
    add_section "DISK INFO"
    
    df -h | grep -v "tmpfs" >> "$REPORT_FILE"
    
    # Add extra detail if lsblk exists
    if command -v lsblk >/dev/null; then
        {
            echo ""
            echo "Block Devices:"
        } >> "$REPORT_FILE"
        lsblk -o NAME,SIZE,TYPE,MOUNTPOINT >> "$REPORT_FILE"
    fi
}

# Find what packages we have
get_package_info() {
    log "Getting package info"
    
    add_section "INSTALLED PACKAGES"
    
    # Find what package manager we're using and count packages
    if command -v dpkg >/dev/null; then
        # Debian/Ubuntu
        pkg_count=$(dpkg -l | grep -c "^ii")
        {
            echo "Debian packages installed: $pkg_count"
            echo ""
            echo "Top 10 largest packages:"
        } >> "$REPORT_FILE"
        dpkg-query -Wf '${Installed-Size}\t${Package}\n' | sort -nr | head -10 >> "$REPORT_FILE"
        
    elif command -v rpm >/dev/null; then
        # Red Hat/CentOS/Fedora
        pkg_count=$(rpm -qa | wc -l)
        {
            echo "RPM packages installed: $pkg_count"
            echo ""
            echo "Top 10 largest packages:"
        } >> "$REPORT_FILE"
        rpm -qa --queryformat '%{size} %{name}\n' | sort -nr | head -10 >> "$REPORT_FILE"
        
    elif command -v pacman >/dev/null; then
        # Arch
        pkg_count=$(pacman -Q | wc -l)
        echo "Arch packages installed: $pkg_count" >> "$REPORT_FILE"
        
    else
        echo "Couldn't figure out what package manager you're using." >> "$REPORT_FILE"
    fi
}

# Check running services
get_services() {
    log "Getting service info"
    
    add_section "RUNNING SERVICES"
    
    if command -v systemctl >/dev/null; then
        # systemd
        echo "Active systemd services:" >> "$REPORT_FILE"
        systemctl list-units --type=service --state=running | head -n -7 >> "$REPORT_FILE"
        
    elif [ -d /etc/init.d ]; then
        # SysV init - a bit hacky but works on most systems
        echo "SysV services:" >> "$REPORT_FILE"
        for svc in /etc/init.d/*; do
            if [ -x "$svc" ]; then
                svc_name=$(basename "$svc")
                status=$($svc status 2>/dev/null || echo "unknown")
                echo "$svc_name: $status" >> "$REPORT_FILE"
            fi
        done
    else
        # Fallback to just showing processes
        {
            echo "Top processes by CPU usage:"
        } >> "$REPORT_FILE"
        ps aux --sort=-%cpu | head -11 >> "$REPORT_FILE"
    fi
}

# Get network config
get_network_info() {
    log "Getting network info"
    
    add_section "NETWORK INFO"
    
    # Get interfaces
    if command -v ip >/dev/null; then
        echo "Network interfaces:" >> "$REPORT_FILE"
        ip addr | grep -E "^[0-9]:|inet " >> "$REPORT_FILE"
    elif command -v ifconfig >/dev/null; then
        echo "Network interfaces:" >> "$REPORT_FILE"
        ifconfig | grep -E "^[a-z]|inet " >> "$REPORT_FILE"
    fi
    
    # Get listening ports
    {
        echo ""
        echo "Listening ports:"
    } >> "$REPORT_FILE"
    if command -v ss >/dev/null; then
        ss -tuln | grep LISTEN >> "$REPORT_FILE"
    elif command -v netstat >/dev/null; then
        netstat -tuln | grep LISTEN >> "$REPORT_FILE"
    fi
}

# Main script
main() {
    # Let the user know we're working
    echo "Collecting system information..."
    
    # Start logging
    log "Starting system inventory"
    
    # Generate the report
    create_report_header
    get_system_info
    get_cpu_info
    get_mem_info
    get_disk_info
    get_package_info
    get_services
    get_network_info
    
    # All done
    log "Finished inventory, report at $REPORT_FILE"
    echo "Report saved to $REPORT_FILE"
    
    # Show the report if we're in a terminal
    if [ -t 1 ]; then
        less "$REPORT_FILE"
    fi
}

# Handle Ctrl+C
trap "echo 'Cancelled.'; exit 1" INT

# Run the script
main
exit 0