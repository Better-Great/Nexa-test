#!/bin/bash

# -----------------------------------------------
# 
# Description: Interactive script for Linux file system management
# - Partitions disks
# - Creates file systems
# - Mounts/unmounts partitions
# - Manages storage (LVM, quotas, etc.)
# - Checks disk usage and health
#
# -----------------------------------------------

set -e # Exit on error
set -u # Treat unset variables as errors

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_DIR="/var/log/admin-scripts"
LOG_FILE="$LOG_DIR/file-system-manager.log"

# Create log directory if it doesn't exist
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    chmod 750 "$LOG_DIR"
fi

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${message}" >> "$LOG_FILE"
    
    case $level in
        "INFO") echo -e "${GREEN}[INFO]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" ;;
        *) echo -e "$message" ;;
    esac
}

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    log "ERROR" "Script failed at line $line_number with exit code $exit_code"
    echo -e "${RED}Error occurred at line $line_number. Check log at $LOG_FILE for details.${NC}"
    exit $exit_code
}

# Set up trap for error handling
trap 'handle_error $LINENO' ERR

# Check if user is root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "This script must be run as root"
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
}

# Check if required tools are installed
check_dependencies() {
    local dependencies=("fdisk" "parted" "mkfs.ext4" "mkfs.xfs" "lvm" "mount" "df" "smartctl")
    local missing=()
    
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        log "WARNING" "Missing dependencies: ${missing[*]}"
        echo -e "${YELLOW}Missing dependencies: ${missing[*]}${NC}"
        echo "Would you like to install them now? (y/n)"
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            log "INFO" "Installing missing dependencies"
            apt-get update
            apt-get install -y fdisk parted e2fsprogs xfsprogs lvm2 mount smartmontools
        else
            log "ERROR" "Required dependencies not installed. Exiting."
            echo -e "${RED}Required dependencies not installed. Exiting.${NC}"
            exit 1
        fi
    fi
}

# List available disks
list_disks() {
    echo -e "${BLUE}Available disks:${NC}"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
    echo ""
}

# List partitions on a disk
list_partitions() {
    local disk=$1
    echo -e "${BLUE}Partitions on $disk:${NC}"
    parted -s "/dev/$disk" print || true
}

# Create a new partition
create_partition() {
    local disk=$1
    local part_type=$2
    local start=$3
    local end=$4
    
    log "INFO" "Creating $part_type partition on /dev/$disk from $start to $end"
    echo -e "${BLUE}Creating new partition on /dev/$disk from $start to $end${NC}"
    
    # Create partition
    parted -s "/dev/$disk" mkpart "$part_type" "$start" "$end"
    
    # Wait for partition to be recognized by the system
    sleep 2
    partprobe "/dev/$disk"
    sleep 1
    
    # Get the newly created partition
    local new_part
    new_part=$(lsblk -o NAME -n -l "/dev/$disk" | grep -v "$disk" | tail -1)
    
    echo -e "${GREEN}Successfully created partition /dev/$new_part${NC}"
    log "INFO" "Successfully created partition /dev/$new_part"
    
    return 0
}

# Format a partition with specified filesystem
format_partition() {
    local partition=$1
    local fs_type=$2
    local label=$3
    
    log "INFO" "Formatting /dev/$partition with $fs_type filesystem and label $label"
    echo -e "${BLUE}Formatting /dev/$partition with $fs_type filesystem${NC}"
    
    case $fs_type in
        ext4)
            mkfs.ext4 -L "$label" "/dev/$partition"
            ;;
        xfs)
            mkfs.xfs -L "$label" "/dev/$partition"
            ;;
        swap)
            mkswap -L "$label" "/dev/$partition"
            ;;
        *)
            log "ERROR" "Unsupported filesystem type: $fs_type"
            echo -e "${RED}Unsupported filesystem type: $fs_type${NC}"
            return 1
            ;;
    esac
    
    sync
    log "INFO" "Successfully formatted /dev/$partition with $fs_type filesystem"
    echo -e "${GREEN}Successfully formatted /dev/$partition${NC}"
    
    return 0
}

# Mount a partition
mount_partition() {
    local partition=$1
    local mount_point=$2
    
    # Check if mount point exists
    if [ ! -d "$mount_point" ]; then
        log "INFO" "Creating mount point directory: $mount_point"
        mkdir -p "$mount_point"
    fi
    
    # Check if already mounted
    if mount | grep -q "/dev/$partition"; then
        log "WARNING" "Partition /dev/$partition is already mounted"
        echo -e "${YELLOW}Partition /dev/$partition is already mounted${NC}"
        return 1
    fi
    
    log "INFO" "Mounting /dev/$partition to $mount_point"
    mount "/dev/$partition" "$mount_point"
    
    # Verify mount
    if mount | grep -q "/dev/$partition"; then
        log "INFO" "Successfully mounted /dev/$partition to $mount_point"
        echo -e "${GREEN}Successfully mounted /dev/$partition to $mount_point${NC}"
    else
        log "ERROR" "Failed to mount /dev/$partition to $mount_point"
        echo -e "${RED}Failed to mount /dev/$partition to $mount_point${NC}"
        return 1
    fi
    
    return 0
}

# Unmount a partition
unmount_partition() {
    local partition=$1
    
    # Check if mounted
    if ! mount | grep -q "/dev/$partition"; then
        log "WARNING" "Partition /dev/$partition is not mounted"
        echo -e "${YELLOW}Partition /dev/$partition is not mounted${NC}"
        return 1
    fi
    
    log "INFO" "Unmounting /dev/$partition"
    umount "/dev/$partition"
    
    # Verify unmount
    if ! mount | grep -q "/dev/$partition"; then
        log "INFO" "Successfully unmounted /dev/$partition"
        echo -e "${GREEN}Successfully unmounted /dev/$partition${NC}"
    else
        log "ERROR" "Failed to unmount /dev/$partition"
        echo -e "${RED}Failed to unmount /dev/$partition${NC}"
        return 1
    fi
    
    return 0
}

# Add entry to /etc/fstab
add_to_fstab() {
    local partition=$1
    local mount_point=$2
    local fs_type=$3
    local options=$4
    local dump=$5
    local pass=$6
    
    # Check if already in fstab
    if grep -q "/dev/$partition" /etc/fstab; then
        log "WARNING" "Entry for /dev/$partition already exists in fstab"
        echo -e "${YELLOW}Entry for /dev/$partition already exists in fstab${NC}"
        return 1
    fi
    
    # Get UUID for more reliable mounting
    local uuid
    uuid=$(blkid -s UUID -o value "/dev/$partition")
    
    log "INFO" "Adding /dev/$partition (UUID=$uuid) to /etc/fstab"
    echo -e "${BLUE}Adding mount entry to /etc/fstab${NC}"
    
    # Create backup of fstab
    cp /etc/fstab "/etc/fstab.backup.$(date +%Y%m%d%H%M%S)"
    
    # Add to fstab
    echo "UUID=$uuid    $mount_point    $fs_type    $options    $dump    $pass" >> /etc/fstab
    
    log "INFO" "Successfully added /dev/$partition to /etc/fstab"
    echo -e "${GREEN}Successfully added mount entry to /etc/fstab${NC}"
    
    return 0
}

# Setup LVM volume
setup_lvm() {
    local operation=$1
    
    case $operation in
        "pvcreate")
            echo -e "${BLUE}Select a partition to create a physical volume:${NC}"
            list_disks
            read -r partition
            
            if [ -z "$partition" ]; then
                log "ERROR" "No partition selected"
                echo -e "${RED}No partition selected${NC}"
                return 1
            fi
            
            log "INFO" "Creating physical volume on /dev/$partition"
            pvcreate "/dev/$partition"
            echo -e "${GREEN}Successfully created physical volume on /dev/$partition${NC}"
            pvdisplay
            ;;
            
        "vgcreate")
            echo -e "${BLUE}Enter volume group name:${NC}"
            read -r vg_name
            
            echo -e "${BLUE}Select physical volumes (space-separated):${NC}"
            pvs
            read -r physical_volumes
            
            if [ -z "$vg_name" ] || [ -z "$physical_volumes" ]; then
                log "ERROR" "Missing volume group name or physical volumes"
                echo -e "${RED}Missing volume group name or physical volumes${NC}"
                return 1
            fi

            read -ra pv_array <<< "$physical_volumes"
            for i in "${!pv_array[@]}"; do
                if [[ ! "${pv_array[$i]}" =~ ^/dev/ ]]; then
                    pv_array[i]="/dev/${pv_array[i]}" 
                fi
            done
            
            log "INFO" "Creating volume group $vg_name with ${pv_array[*]}"
            vgcreate "$vg_name" "${pv_array[@]}"
            echo -e "${GREEN}Successfully created volume group $vg_name${NC}"
            vgdisplay "$vg_name"
            ;;
            
        "lvcreate")
            echo -e "${BLUE}Available volume groups:${NC}"
            vgs
            
            echo -e "${BLUE}Enter volume group name:${NC}"
            read -r vg_name
            
            echo -e "${BLUE}Enter logical volume name:${NC}"
            read -r lv_name
            
            echo -e "${BLUE}Enter size (e.g., 10G, 500M):${NC}"
            read -r lv_size
            
            if [ -z "$vg_name" ] || [ -z "$lv_name" ] || [ -z "$lv_size" ]; then
                log "ERROR" "Missing required parameters for logical volume creation"
                echo -e "${RED}Missing required parameters for logical volume creation${NC}"
                return 1
            fi
            
            log "INFO" "Creating logical volume $lv_name of size $lv_size in volume group $vg_name"
            lvcreate -n "$lv_name" -L "$lv_size" "$vg_name"
            echo -e "${GREEN}Successfully created logical volume $lv_name${NC}"
            lvdisplay "$vg_name/$lv_name"
            
            echo -e "${BLUE}Would you like to format this logical volume? (y/n)${NC}"
            read -r format_answer
            if [[ "$format_answer" =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}Select filesystem type (ext4/xfs):${NC}"
                read -r fs_type
                
                echo -e "${BLUE}Enter filesystem label:${NC}"
                read -r fs_label
                
                if [ -z "$fs_type" ] || [ -z "$fs_label" ]; then
                    log "ERROR" "Missing filesystem type or label"
                    echo -e "${RED}Missing filesystem type or label${NC}"
                    return 1
                fi
                
                format_partition "${vg_name}/${lv_name}" "$fs_type" "$fs_label"
                
                echo -e "${BLUE}Would you like to mount this logical volume? (y/n)${NC}"
                read -r mount_answer
                if [[ "$mount_answer" =~ ^[Yy]$ ]]; then
                    echo -e "${BLUE}Enter mount point:${NC}"
                    read -r mount_point
                    
                    if [ -z "$mount_point" ]; then
                        log "ERROR" "No mount point specified"
                        echo -e "${RED}No mount point specified${NC}"
                        return 1
                    fi
                    
                    mount_partition "${vg_name}/${lv_name}" "$mount_point"
                    
                    echo -e "${BLUE}Add to /etc/fstab? (y/n)${NC}"
                    read -r fstab_answer
                    if [[ "$fstab_answer" =~ ^[Yy]$ ]]; then
                        add_to_fstab "${vg_name}/${lv_name}" "$mount_point" "$fs_type" "defaults" "0" "2"
                    fi
                fi
            fi
            ;;
            
        *)
            log "ERROR" "Unknown LVM operation: $operation"
            echo -e "${RED}Unknown LVM operation: $operation${NC}"
            return 1
            ;;
    esac
    
    return 0
}

# Display disk usage
check_disk_usage() {
    echo -e "${BLUE}Disk usage:${NC}"
    df -h
    
    echo -e "\n${BLUE}Inodes usage:${NC}"
    df -i
    
    echo -e "\n${BLUE}Largest directories:${NC}"
    echo "Path                                 Size"
    echo "----                                 ----"
    du -h --max-depth=2 / 2>/dev/null | sort -rh | head -10
    
    return 0
}

# Check disk health
check_disk_health() {
    echo -e "${BLUE}Select disk to check (e.g., sda):${NC}"
    list_disks
    read -r disk
    
    if [ -z "$disk" ]; then
        log "ERROR" "No disk selected"
        echo -e "${RED}No disk selected${NC}"
        return 1
    fi
    
    log "INFO" "Checking health of disk /dev/$disk"
    echo -e "${BLUE}Checking disk health for /dev/$disk...${NC}"
    
    # Only run if smartctl is available
    if command -v smartctl &> /dev/null; then
        echo -e "\n${BLUE}SMART information:${NC}"
        smartctl -a "/dev/$disk"
        
        echo -e "\n${BLUE}SMART overall health:${NC}"
        smartctl -H "/dev/$disk"
    else
        echo -e "${YELLOW}smartctl not available. Installing smartmontools package is recommended for disk health monitoring.${NC}"
    fi
    
    echo -e "\n${BLUE}Checking for bad blocks (read-only test):${NC}"
    echo "This could take a long time. Press Ctrl+C to cancel."
    read -p "Continue? (y/n): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        badblocks -sv -c 10240 "/dev/$disk"
    fi
    
    return 0
}

# Configure disk quotas
configure_quotas() {
    echo -e "${BLUE}Select filesystem for quota configuration:${NC}"
    df -h
    echo -e "${BLUE}Enter filesystem (e.g., /dev/sda1 or /home):${NC}"
    read -r quota_fs
    
    if [ -z "$quota_fs" ]; then
        log "ERROR" "No filesystem selected for quota configuration"
        echo -e "${RED}No filesystem selected${NC}"
        return 1
    fi
    
    # Check if quota tools are installed
    if ! command -v quotacheck &> /dev/null; then
        log "WARNING" "Quota tools not installed"
        echo -e "${YELLOW}Quota tools not installed. Install quota package?${NC} (y/n)"
        read -r install_quota
        if [[ "$install_quota" =~ ^[Yy]$ ]]; then
            apt-get update
            apt-get install -y quota
        else
            log "ERROR" "Cannot configure quotas without quota tools"
            echo -e "${RED}Cannot configure quotas without quota tools${NC}"
            return 1
        fi
    fi
    
    # Get mount point
    local mount_point
    mount_point=$(findmnt -n -o TARGET --source "$quota_fs")
    if [ -z "$mount_point" ]; then
        mount_point="$quota_fs"
    fi
    
    log "INFO" "Configuring quotas on $mount_point"
    echo -e "${BLUE}Configuring quotas on $mount_point${NC}"
    
    # Backup fstab
    cp /etc/fstab "/etc/fstab.backup.$(date +%Y%m%d%H%M%S)"
    
    # Add usrquota,grpquota to mount options
    sed -i "s|\( $mount_point [^ ]*\) \([^ ]*\)|\1 \2,usrquota,grpquota|" /etc/fstab
    
    echo "Remounting filesystem with quota options"
    mount -o remount "$mount_point"
    
    echo "Creating quota files"
    quotacheck -cugm "$mount_point"
    
    echo "Enabling quotas"
    quotaon "$mount_point"
    
    echo -e "${GREEN}Quota system initialized on $mount_point${NC}"
    log "INFO" "Quota system initialized on $mount_point"
    
    # Ask for user quota configuration
    echo -e "${BLUE}Configure quota for a user? (y/n)${NC}"
    read -r config_user_quota
    if [[ "$config_user_quota" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Enter username:${NC}"
        read -r quota_user
        
        if ! id "$quota_user" &>/dev/null; then
            log "ERROR" "User $quota_user does not exist"
            echo -e "${RED}User $quota_user does not exist${NC}"
            return 1
        fi
        
        echo -e "${BLUE}Enter soft block limit (e.g., 1000000 for ~1GB):${NC}"
        read -r soft_block
        
        echo -e "${BLUE}Enter hard block limit (e.g., 1200000 for ~1.2GB):${NC}"
        read -r hard_block
        
        echo -e "${BLUE}Enter soft inode limit (e.g., 10000):${NC}"
        read -r soft_inode
        
        echo -e "${BLUE}Enter hard inode limit (e.g., 12000):${NC}"
        read -r hard_inode
        
        setquota -u "$quota_user" "$soft_block" "$hard_block" "$soft_inode" "$hard_inode" "$mount_point"
        
        echo -e "${GREEN}Quota set for user $quota_user on $mount_point${NC}"
        log "INFO" "Quota set for user $quota_user on $mount_point"
        
        # Display quota
        echo -e "${BLUE}Current quota settings:${NC}"
        quota -v "$quota_user"
    fi
    
    return 0
}

# Main menu
main_menu() {
    clear
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}      File System Manager Tool       ${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo ""
    echo "1. List available disks"
    echo "2. List partitions on a disk"
    echo "3. Create a new partition"
    echo "4. Format a partition"
    echo "5. Mount a partition"
    echo "6. Unmount a partition"
    echo "7. Add entry to /etc/fstab"
    echo "8. LVM Management"
    echo "9. Check disk usage"
    echo "10. Check disk health"
    echo "11. Configure disk quotas"
    echo "12. Exit"
    echo ""
    echo -e "${BLUE}Enter your choice [1-12]:${NC}"
    read -r choice
    
    case $choice in
        1)
            list_disks
            ;;
        2)
            echo -e "${BLUE}Enter disk name (e.g., sda):${NC}"
            read -r disk
            list_partitions "$disk"
            ;;
        3)
            echo -e "${BLUE}Enter disk name (e.g., sda):${NC}"
            read -r disk
            
            echo -e "${BLUE}Enter partition type (primary/logical/extended):${NC}"
            read -r part_type
            
            echo -e "${BLUE}Enter start position (e.g., 0%, 1M, 1G):${NC}"
            read -r start_pos
            
            echo -e "${BLUE}Enter end position (e.g., 100%, 50G, -1):${NC}"
            read -r end_pos
            
            create_partition "$disk" "$part_type" "$start_pos" "$end_pos"
            ;;
        4)
            echo -e "${BLUE}Enter partition name (e.g., sda1):${NC}"
            read -r partition
            
            echo -e "${BLUE}Enter filesystem type (ext4/xfs/swap):${NC}"
            read -r fs_type
            
            echo -e "${BLUE}Enter label for the filesystem:${NC}"
            read -r label
            
            format_partition "$partition" "$fs_type" "$label"
            ;;
        5)
            echo -e "${BLUE}Enter partition name (e.g., sda1):${NC}"
            read -r partition
            
            echo -e "${BLUE}Enter mount point:${NC}"
            read -r mount_point
            
            mount_partition "$partition" "$mount_point"
            ;;
        6)
            echo -e "${BLUE}Enter partition name (e.g., sda1):${NC}"
            read -r partition
            
            unmount_partition "$partition"
            ;;
        7)
            echo -e "${BLUE}Enter partition name (e.g., sda1):${NC}"
            read -r partition
            
            echo -e "${BLUE}Enter mount point:${NC}"
            read -r mount_point
            
            echo -e "${BLUE}Enter filesystem type:${NC}"
            read -r fs_type
            
            echo -e "${BLUE}Enter mount options (e.g., defaults,noatime):${NC}"
            read -r options
            
            echo -e "${BLUE}Enter dump value (usually 0):${NC}"
            read -r dump
            
            echo -e "${BLUE}Enter pass value (usually 1 for root, 2 for others):${NC}"
            read -r pass
            
            add_to_fstab "$partition" "$mount_point" "$fs_type" "$options" "$dump" "$pass"
            ;;
        8)
            echo -e "${BLUE}LVM Management${NC}"
            echo "1. Create physical volume (pvcreate)"
            echo "2. Create volume group (vgcreate)"
            echo "3. Create logical volume (lvcreate)"
            echo -e "${BLUE}Enter your choice [1-3]:${NC}"
            read -r lvm_choice
            
            case $lvm_choice in
                1) setup_lvm "pvcreate" ;;
                2) setup_lvm "vgcreate" ;;
                3) setup_lvm "lvcreate" ;;
                *) log "ERROR" "Invalid LVM operation choice"
                   echo -e "${RED}Invalid choice${NC}" ;;
            esac
            ;;
        9)
            check_disk_usage
            ;;
        10)
            check_disk_health
            ;;
        11)
            configure_quotas
            ;;
        12)
            log "INFO" "Exiting file system manager"
            echo -e "${GREEN}Exiting file system manager${NC}"
            exit 0
            ;;
        *)
            log "ERROR" "Invalid menu choice: $choice"
            echo -e "${RED}Invalid choice${NC}"
            ;;
    esac
    
    echo ""
    echo -e "${BLUE}Press Enter to continue...${NC}"
    read -r
    main_menu
}

# Main function
main() {
    check_root
    check_dependencies
    log "INFO" "Starting file system manager"
    main_menu
}

# Execute main function
main