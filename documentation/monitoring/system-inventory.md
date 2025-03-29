# System Inventory Script
This script collects important information about your Linux system and creates a detailed report. It gathers data about your hardware, installed software, and running services.

## Why is this useful?
- **Troubleshooting:** Quickly see all system information in one place
- **Documentation:** Keep records of system configurations
- **Monitoring:** Track changes in your system over time
- **Inventory:** Maintain records of multiple systems

## Requirements
- A Linux system
- Root/sudo privileges (needed to access certain system information)
- Basic command line tools (most come pre-installed on Linux)

## How to use the script
### Basic usage

1. Make the script executable:
```sh
chmod +x system-inventory.sh
```
2. Run with sudo to get complete information:
```sh
sudo ./system-inventory.sh
```
3. The script will create a report in /tmp/reports/ and automatically display it.

## Different ways to run
### Run silently (no display at end):
```sh
sudo ./system_inventory.sh > /dev/null
```
The report will still be saved, but not displayed.

### Save output to a custom location:
```sh
sudo REPORT_DIR="/home/username/reports" ./system_inventory.sh
```

### Run as a scheduled task (cron job):
```sh
# Add to crontab (sudo crontab -e)
0 8 * * 1 /path/to/system_inventory.sh
```
This runs the script every Monday at 8 AM.

### Run over SSH:
```sh
ssh user@server "sudo /path/to/system_inventory.sh"
```

## Understanding the script
### Main components
The script is organized into specialized functions that each collect different information:

1. **Report setup:** Creates directories and initializes the report file
2. **System info:** Collects basic system details (hostname, OS version, kernel)
3. **CPU info:** Gathers processor information
4. **Memory info:** Shows RAM usage and availability
5. **Disk info:** Lists storage devices and usage
6. **Package info:** Counts and lists installed software packages
7. **Services:** Identifies what programs are running
8. **Network info:** Shows network interfaces and active connections

### Step-by-step explanation
#### Setup and preparation
```sh
REPORT_DIR="/tmp/reports"
TODAY=$(date +"%Y-%m-%d")
REPORT_FILE="$REPORT_DIR/system_report_$TODAY.txt"
LOG_FILE="/var/log/sysinfo.log"
```
These lines set where reports will be saved and create filenames with today's date.

```sh
mkdir -p "$REPORT_DIR" 2>/dev/null
if ! mkdir -p "$REPORT_DIR" 2>/dev/null; then
    echo "Can't create reports directory. Check permissions."
    exit 1
fi
```
This creates the reports directory and exits with an error if it can't.
```sh
if [ "$(id -u)" -ne 0 ]; then
    echo "Hey! Run this with sudo."
    exit 1
fi
```

### Information gathering functions
Each function follows a similar pattern:
1. Adds a section header to the report
2. Runs appropriate system commands to gather information
3. Saves the output to the report file

For example, the disk information function:
```sh
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
```
This collects disk usage with df -h, then adds extra details using lsblk if available.

### Smart adaptability
The script is designed to work on different Linux distributions by checking which commands are available:
```sh
# Find what package manager we're using and count packages
if command -v dpkg >/dev/null; then
    # Debian/Ubuntu
    pkg_count=$(dpkg -l | grep -c "^ii")
    # ...more code...
elif command -v rpm >/dev/null; then
    # Red Hat/CentOS/Fedora
    # ...more code...
```
This makes the script work on Ubuntu, Fedora, CentOS, and other Linux systems.

### Main execution
```sh
main() {
    echo "Collecting system information..."
    log "Starting system inventory"
    
    create_report_header
    get_system_info
    get_cpu_info
    get_mem_info
    get_disk_info
    get_package_info
    get_services
    get_network_info
    
    log "Finished inventory, report at $REPORT_FILE"
    echo "Report saved to $REPORT_FILE"
    
    if [ -t 1 ]; then
        less "$REPORT_FILE"
    fi
}
```
This runs each function in sequence and displays the report at the end if you're running in a terminal.

### Output explained
The report is organized into clear sections:
1. **SYSTEM INFO:** Basic details about your system (OS, kernel version)
2. **CPU INFO:** Information about your processor(s)
3. **MEMORY INFO:** RAM usage and availability
4. **DISK INFO:** Storage devices and space usage
5. **INSTALLED PACKAGES:** Software package counts and largest packages
6. **RUNNING SERVICES:** Active system services
7. **NETWORK INFO:** Network interface configuration and listening ports

## Troubleshooting
### "Run this with sudo" error:

You need to run the script with root privileges: `sudo ./system_inventory.sh`

### Report not displaying:

- Check that the report was created in `/tmp/reports/`
You can open it manually with: less `/tmp/reports/system_report_YYYY-MM-DD.txt`

### Customization
You can easily modify the script to:

- Change the report location by editing **REPORT_DIR**
- Add new sections by creating additional functions
- Remove sections by commenting out function calls in the `main() function`