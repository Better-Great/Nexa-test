#!/bin/bash
#
# Creates timestamped backups of directories with rotation and verification
#

# Config - change these to match your setup
BACKUP_DIR="/var/backups/system"
LOG_FILE="/var/log/backup_manager.log"
KEEP_BACKUPS=7
DATE_FORMAT="%Y%m%d_%H%M%S"
DIRS_TO_BACKUP=(
    "/etc"
    "/home"
    "/var/www"
    # Add more directories here
)

# Make sure backup dir exists
if ! mkdir -p "$BACKUP_DIR"; then
    echo "ERROR: Couldn't create backup directory $BACKUP_DIR"
    exit 1
fi

# Simple logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null
    
    # Print to console if verbose mode is on
    if [ "$VERBOSE" = "yes" ]; then
        echo "$1"
    fi
}

# Need to be root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script needs to be run as root."
    exit 1
fi

# Parse command line args
VERBOSE="no"
while [ $# -gt 0 ]; do
    case "$1" in
        -v|--verbose)
            VERBOSE="yes"
            ;;
        -d|--dir)
            shift
            DIRS_TO_BACKUP=("$1")
            ;;
        -k|--keep)
            shift
            KEEP_BACKUPS="$1"
            ;;
        -h|--help)
            echo "Usage: $0 [-v|--verbose] [-d|--dir directory] [-k|--keep num_backups]"
            echo "  -v, --verbose     Show detailed output"
            echo "  -d, --dir DIR     Backup only this directory"
            echo "  -k, --keep NUM    Keep NUM backups (default: $KEEP_BACKUPS)"
            echo "  -h, --help        Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
    shift
done

# Create a backup of a directory
backup_directory() {
    local dir="$1"
    local timestamp
    local dirname
    
    timestamp=$(date +"$DATE_FORMAT")
    dirname=$(basename "$dir")
    local backup_file="$BACKUP_DIR/${dirname}_${timestamp}.tar.gz"
    
    # Make sure directory exists
    if [ ! -d "$dir" ]; then
        log "WARNING: Directory $dir doesn't exist, skipping"
        return 1
    fi
    
    log "Starting backup of $dir"
    
    # Create the backup
    if ! tar czf "$backup_file" -C "$(dirname "$dir")" "$(basename "$dir")" 2>/dev/null; then
        log "ERROR: Backup of $dir failed"
        return 1
    fi
    
    log "Backup of $dir completed: $backup_file ($(du -h "$backup_file" | cut -f1))"
    return 0
}

# Verify a backup's integrity
verify_backup() {
    local backup_file="$1"
    
    log "Verifying backup: $backup_file"
    
    # Check if the file exists
    if [ ! -f "$backup_file" ]; then
        log "ERROR: Backup file not found: $backup_file"
        return 1
    fi
    
    # Test the tarball integrity
    if ! tar tzf "$backup_file" >/dev/null 2>&1; then
        log "ERROR: Backup verification failed for $backup_file"
        return 1
    fi
    
    log "Backup verified successfully: $backup_file"
    return 0
}

# Handle rotation of old backups
rotate_backups() {
    local dirname="$1"
    local backup_count
    local old_backups
    
    backup_count=$(find "$BACKUP_DIR" -maxdepth 1 -name "${dirname}_*.tar.gz" | wc -l)
    
    if [ "$backup_count" -le "$KEEP_BACKUPS" ]; then
        # No need to delete any backups yet
        return 0
    fi
    
    log "Rotating backups for $dirname, keeping $KEEP_BACKUPS of $backup_count backups"
    
    # Get list of backups sorted by date (oldest first)
    old_backups=$(find "$BACKUP_DIR" -maxdepth 1 -name "${dirname}_*.tar.gz" -printf "%T@ %p\n" | sort -nr | tail -n +$((KEEP_BACKUPS+1)) | cut -d' ' -f2-)
    
    # Delete old backups
    for old_backup in $old_backups; do
        log "Removing old backup: $old_backup"
        if ! rm -f "$old_backup"; then
            log "WARNING: Failed to remove $old_backup"
        fi
    done
}

# Run full backup process
run_backups() {
    local start_time
    local end_time
    local duration
    local total_dirs
    local success=0
    local failed=0
    local latest_backup
    
    start_time=$(date +%s)
    total_dirs=${#DIRS_TO_BACKUP[@]}
    
    log "=== Starting backup job ==="
    log "Total directories to backup: $total_dirs"
    
    for dir in "${DIRS_TO_BACKUP[@]}"; do
        # Clean up directory name to handle trailing slashes
        dir="${dir%/}"
        dirname=$(basename "$dir")
        
        # Create backup
        if backup_directory "$dir"; then
            # Find the most recent backup file
            latest_backup=$(find "$BACKUP_DIR" -maxdepth 1 -name "${dirname}_*.tar.gz" -printf "%T@ %p\n" | sort -nr | head -1 | cut -d' ' -f2-)
            
            # Verify it
            if verify_backup "$latest_backup"; then
                # Rotate old ones if needed
                rotate_backups "$dirname"
                ((success++))
            else
                ((failed++))
            fi
        else
            ((failed++))
        fi
    done
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log "=== Backup job completed ==="
    log "Duration: $duration seconds"
    log "Success: $success, Failed: $failed"
}

# Handle Ctrl+C
trap "echo 'Backup interrupted'; log 'Backup interrupted by user'; exit 1" INT

# Main function
main() {
    # Create lock file to prevent running multiple instances
    if [ -f "/tmp/backup_manager.lock" ]; then
        pid=$(cat /tmp/backup_manager.lock)
        if ps -p "$pid" > /dev/null; then
            echo "Backup already running (PID: $pid)"
            exit 1
        fi
        # Lock file exists but process is gone, remove it
        rm -f /tmp/backup_manager.lock
    fi
    
    # Create lock file
    echo $$ > /tmp/backup_manager.lock
    
    # Run the backup
    run_backups
    
    # Remove lock file
    rm -f /tmp/backup_manager.lock
    
    return 0
}

# Run main function
main
exit $?