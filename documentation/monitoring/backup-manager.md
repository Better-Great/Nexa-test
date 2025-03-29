# Backup Manager Script
This script makes compressed backups of important directories on your Linux system. It creates dated archives, checks that they're valid, and removes old backups to save space.

## Why is this useful?
- **Data Protection:** Keep safe copies of important files
- **Disaster Recovery:** Restore your system after problems
- **Space Management:** Automatically removes old backups
- **Flexibility:** Can back up any directories you choose
- **Verification:** Checks that backups are working properly

## Requirements
1. A Linux system
2. Root/sudo privileges (needed to access system directories)
3. Enough disk space for backups
4. The `tar` command (comes with most Linux systems)

## How to use the script
### Basic usage
1. Make the script executable:
```sh
chmod +x backup_manager.sh
```
2. Run with sudo to back up the default directories:
```sh
sudo ./backup_manager.sh
```
3. The script will create backups in `/var/backups/system/` by default.

## Different ways to run
#### Show detailed output while running:
```sh
sudo ./backup_manager.sh --verbose
or
sudo ./backup_manager.sh -v
```
#### Back up a specific directory only:
```sh
sudo ./backup_manager.sh --dir /home/username
or
sudo ./backup_manager.sh -d /home/username
```
#### Change how many backups to keep:
```sh
sudo ./backup_manager.sh --keep 14
or
sudo ./backup_manager.sh -k 14
```
#### Combine options:
```sh
sudo ./backup_manager.sh -v -d /home/username -k 10
```
#### Run as a scheduled task (cron job):
```sh
# Add to crontab (sudo crontab -e)
0 2 * * * /path/to/backup_manager.sh
```

## Understanding the script
### Main components
The script has several key parts:

1. **Configuration:** Sets up backup locations and preferences
2. **Directory backup:** Compresses directories into dated archive files
3. **Verification:** Checks that backups are valid and not corrupted
4. **Rotation:** Removes old backups to save space
5. **Locking:** Prevents multiple backups from running at once

## Step-by-step explanation
#### Configuration settings
```sh
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
```
These lines set:
- Where backups will be stored
- Where logs will be written
- How many backups to keep before deleting old ones
- How to format the date in backup filenames
- Which directories to back up

#### Command-line options
```sh
while [ $# -gt 0 ]; do
    case "$1" in
        -v|--verbose)
            VERBOSE="yes"
            ;;
        -d|--dir)
            shift
            DIRS_TO_BACKUP=("$1")
            ;;
        # More options...
    esac
    shift
done
```
This lets you change settings when running the script, like showing more details or backing up different directories.

#### Creating a backup
```sh
backup_directory() {
    # ...
    # Create the backup
    if ! tar czf "$backup_file" -C "$(dirname "$dir")" "$(basename "$dir")" 2>/dev/null; then
        log "ERROR: Backup of $dir failed"
        return 1
    fi
    # ...
}
```
This creates a compressed tar archive `(.tar.gz)` of a directory. The filename includes the directory name and current date/time.

#### Verifying backups
```sh
verify_backup() {
    # ...
    # Test the tarball integrity
    if ! tar tzf "$backup_file" >/dev/null 2>&1; then
        log "ERROR: Backup verification failed for $backup_file"
        return 1
    fi
    # ...
}
```
This checks if the backup file is valid by testing if tar can read its contents.

#### Removing old backups
```sh
rotate_backups() {
    # ...
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
```
This finds backups older than the newest `KEEP_BACKUPS (default: 7)` and deletes them.

#### Preventing multiple runs
```sh
if [ -f "/tmp/backup_manager.lock" ]; then
    pid=$(cat /tmp/backup_manager.lock)
    if ps -p "$pid" > /dev/null; then
        echo "Backup already running (PID: $pid)"
        exit 1
    fi
    # Lock file exists but process is gone, remove it
    rm -f /tmp/backup_manager.lock
fi
```
This creates a lock file to prevent multiple copies of the script from running at the same time, which could cause problems.

## Backup files Explained
The backups are stored as `.tar.gz` files, which are compressed archives. The filename format is:
```sh
directoryname_YYYYMMDD_HHMMSS.tar.gz
# For Example
etc_20250328_143022.tar.gz
```
This is a backup of the `/etc `directory made on March 28, 2025 at 2:30:22 PM.

## Customizing the script
### To change which directories are backed up:
Edit the `DIRS_TO_BACKUP` array:
```sh
DIRS_TO_BACKUP=(
    "/etc"
    "/home"
    "/var/www"
    "/path/to/your/directory"
)
```
### To change where backups are stored:
Edit the `BACKUP_DIR` variable:
```sh
BACKUP_DIR="/your/custom/backup/location"
# For example
/var/logs/
```
### To change how many backups to keep:
Edit the `KEEP_BACKUPS` variable:
```sh
KEEP_BACKUPS=14  # Keeps two weeks of backups
```
## Troubleshooting
#### "This script needs to be run as root" error:
- You need to run the script with root privileges: sudo ./backup_manager.sh

#### "Backup already running" message:
- Another instance of the script is already running
- If you're sure no other backup is running, delete `/tmp/backup_manager.lock`
#### Failed backups:
- Check the log file `(/var/log/backup_manager.log)` for error messages
- Make sure you have enough disk space
- Verify that the source directories exist and are readable

#### Missing backup files:
- Check if rotation removed them `(increase KEEP_BACKUPS if needed)`
- Make sure the backup directory is writable

## Restoring from a backup
To restore files from a backup:
1. Find your backup file
```sh
ls -l /var/backups/system/
```
2. Extract it (replace with the actual backup filename)
```sh
sudo tar -xzf /var/backups/system/etc_20250328_143022.tar.gz -C /
```
**CAUTION:** This will overwrite existing files! For safer restoration:
```sh
sudo tar -xzf /var/backups/system/etc_20250328_143022.tar.gz -C /tmp/restore/
```

