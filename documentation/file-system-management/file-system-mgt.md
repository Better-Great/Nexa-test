# Linux File System Management Script
## Introduction
As part of the **Nexascale mentorship program's first mini-project**, the focus once narrows on file system management. This `README` explains my approach to creating an interactive bash script that simplifies complex file system operations.

## Project Context
The mini-project required demonstrating skills in Linux administration, including file system management (partitioning, mounting, and storage management). Instead of implementing these tasks manually, I created a comprehensive script that automates and simplifies these operations while following best practices for error handling, logging, and user interaction.

## Why I Chose This Approach
I developed this interactive bash script to address several challenges in Linux file system management:
1. **Simplification of complex tasks:** Commands like fdisk, parted, and lvm have complex syntax that's difficult to remember and error-prone when typed manually.
2. **Standardization:** The script ensures operations follow a consistent approach with proper error handling and logging.
3. **Reduced learning curve:** Team members with less Linux experience can perform advanced file system operations through the guided menu system.
4. **Audit trail:** All operations are logged for accountability and troubleshooting.
Safety: The script includes verification steps and error handling to prevent data loss or system damage.

## Usage Instructions

### 1. Run with root privileges
```sh
sudo ./file-system-manager.sh
```

### 2. Navigate the menu to perform various operations:
1. **Options 1-2:** View disk and partition information
2. **Options 3-4:** Create and format partitions
3. **Options 5-7:** Mount operations
4. **Option 8:** LVM management
5. **Options 9-10:** Monitoring tools
6. **Option 11:** Quota configuration


Follow the prompts for each operation, providing the requested information.

## Script Functionality Breakdown
## Core Components
### 1. Environment Setup and Error Handling
```sh
set -e # Exit on error
set -u # Treat unset variables as errors
```
I implemented strict error handling to ensure the script fails safely rather than continuing after errors. The color-coded output helps users quickly distinguish between different message types (errors, warnings, info).
The script creates backup files before modifying critical system files like `/etc/fstab`, providing recovery options if something goes wrong.

### 2. Logging System
```sh
log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${message}" >> "$LOG_FILE"
    
    # Display messages with appropriate colors
    case $level in
        "INFO") echo -e "${GREEN}[INFO]${NC} $message" ;;
        # ...
    esac
}
```
I implemented a comprehensive logging system that:
- Records all operations with timestamps and severity levels
- Saves logs to `/var/log/admin-scripts/file-system-manager.log`
- Displays color-coded messages to the console
- Makes troubleshooting easier by capturing exactly what happened and when

### 3. Prerequisite Checks
```sh
check_root()
check_dependencies()
```
These functions verify:
- The script is running with root privileges (essential for disk operations)
- All required tools are installed (fdisk, parted, etc.)
- Missing dependencies can be automatically installed

This prevents the script from failing unexpectedly due to missing prerequisites.

## Main Functionality
### 1. Disk and Partition Management
```sh
list_disks()
list_partitions()
create_partition()
format_partition()
```
These functions provide user-friendly interfaces for:

- Viewing available storage devices
- Creating partitions with specific sizes and types
- Formatting partitions with various filesystems (ext4, xfs, swap)
- Handling error conditions gracefully

I used `parted` instead of `fdisk` for greater flexibility with different partition table types and automation capabilities.

### 2. Mount Operations
```sh
mount_partition()
unmount_partition()
add_to_fstab()
```
These functions:

- Handle temporary and permanent mounting of partitions
- Create mount points automatically if they don't exist
- Add entries to `/etc/fstab` with proper UUID-based identification
- Validate operations to prevent common mistakes

I chose to use UUIDs rather than device names in `/etc/fstab` to ensure reliability even if disk device names change.

### 3. LVM Management
```sh
setup_lvm()
```
This function provides a complete workflow for Logical Volume Management:

- Creating physical volumes from partitions
- Creating volume groups from physical volumes
- Creating and formatting logical volumes
- Mounting logical volumes and adding them to `/etc/fstab`

LVM provides flexibility for storage management, allowing volumes to be resized or moved between physical disks as needed.

### 4. Monitoring and Management
```sh
check_disk_usage()
check_disk_health()
configure_quotas()
```
These utilities help maintain system health by:

- Monitoring disk space usage and identifying large directories
- Checking disk health using SMART data
- Configuring and managing disk quotas for users

### 5. Interactive Menu System
```sh
main_menu()
```
I implemented a user-friendly menu system that:

- Guides users through complex operations step-by-step
- Provides clear prompts for required information
- Returns to the main menu after each operation
- Offers a clean and organized interface

## Technical Implementation Details
### Error Recovery Mechanism
The script uses a trap to catch errors:
```sh
trap 'handle_error $LINENO' ERR
```
This ensures that if any command fails, the `handle_error function` captures the failure point, logs it, and exits gracefully instead of continuing with potentially damaging operations.

### Partition Management Strategy
For partition creation, I used the non-interactive mode of `parted` with specific start and end positions, which allows for flexible partition sizing using percentages or absolute values:
```sh
parted -s "/dev/$disk" mkpart "$part_type" "$start" "$end"
```

### Backup Before Modification
Before modifying critical system files:
```sh
cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d%H%M%S)
```
This creates timestamped backups that can be restored if changes cause problems.

### LVM Implementation
The LVM workflow follows best practices:

1. First creating physical volumes (PVs)
2. Then creating volume groups (VGs) from those PVs
3. Finally creating logical volumes (LVs) within those VGs

This modular approach allows for maximum flexibility in storage management.

### Quota Management
The quota implementation:
1. Modifies mount options in /etc/fstab
2. Properly initializes quota databases
3. Allows setting soft and hard limits for both blocks and inodes
4. Shows current quota usage for verification

## How This Addresses Project Requirements
This script directly aligns with the "File system management" requirement from Part 2 of the Linux Server Administration challenge by providing a comprehensive tool that can:

- Partition disks (`create_partition()`)
- Format partitions with various filesystems (`format_partition()`)
- Mount storage devices (`mount_partition()`, `add_to_fstab()`)
- Manage LVM for flexible storage allocation (`setup_lvm()`)
- Monitor disk usage and health (`check_disk_usage()`, `check_disk_health()`)
- Configure quotas to control resource usage (`configure_quotas()`)