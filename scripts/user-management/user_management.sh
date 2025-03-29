#!/bin/bash
# Comprehensive User Management Script

# Logging configuration
log_file="/var/log/user_management.log"

# Validate username format
validate_username() {
    local username="$1"
    
    # Check if username is empty
    if [ -z "$username" ]; then
        echo "Username cannot be empty."
        return 1
    fi
    
    # Username validation rules:
    # 1. Start with a lowercase letter
    # 2. Contain only lowercase letters, numbers, and underscores
    # 3. 1-32 characters long
    if [[ ! "$username" =~ ^[a-z][a-z0-9_]{0,31}$ ]]; then
        echo "Invalid username. Must start with a lowercase letter, contain only lowercase letters, numbers, or underscores, and be 1-32 characters long."
        return 1
    fi
    
    return 0
}

# Validate SSH key
validate_ssh_key() {
    local ssh_key="$1"
    
    # Basic SSH key validation
    if [[ -z "$ssh_key" ]]; then
        echo "SSH key cannot be empty."
        return 1
    fi
    
    # Check for typical SSH key formats
    if [[ ! "$ssh_key" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ssh-dss) ]]; then
        echo "Invalid SSH key format."
        return 1
    fi
    
    return 0
}

# Ensure script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root (use sudo)." | tee -a "$log_file"
        exit 1
    fi
}

# Function to create or verify group
create_or_verify_group() {
    local group_name="$1"
    
    # Validate group name
    if [[ ! "$group_name" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Invalid group name: $group_name" | tee -a "$log_file"
        return 1
    fi
    
    # Check if group exists, create if it doesn't
    if ! getent group "$group_name" &>/dev/null; then
        sudo groupadd "$group_name"
        echo "Created new group: $group_name" | tee -a "$log_file"
    else
        echo "Group $group_name already exists" | tee -a "$log_file"
    fi
}

# Function to create a single user
create_single_user() {
    # Prompt for username
    while true; do
        read -r -p "Enter username to create: " username
        
        # Validate username
        if validate_username "$username"; then
            break
        fi
    done
    
    # Check if user already exists
    if id "$username" &>/dev/null; then
        echo "User $username already exists." | tee -a "$log_file"
        return 1
    fi
    
    # Prompt for group
    read -r -p "Enter group for the user (leave blank if none): " group
    
    # Create or verify group if specified
    if [ -n "$group" ]; then
        create_or_verify_group "$group" || return 1
    fi
    
    # Create user
    sudo useradd -m -s /bin/bash "$username"
    
    # Add user to group if specified
    if [ -n "$group" ]; then
        sudo usermod -aG "$group" "$username"
    fi
    
    # Prompt for SSH key
    read -r -p "Do you want to add an SSH key? (y/n): " add_ssh
    if [[ "$add_ssh" == "y" || "$add_ssh" == "Y" ]]; then
        while true; do
            read -r -p "Paste the SSH public key: " ssh_key
            
            # Validate SSH key
            if validate_ssh_key "$ssh_key"; then
                sudo -u "$username" mkdir -p "/home/$username/.ssh"
                echo "$ssh_key" | sudo tee "/home/$username/.ssh/authorized_keys"
                sudo chown -R "$username:$username" "/home/$username/.ssh"
                sudo chmod 700 "/home/$username/.ssh"
                sudo chmod 600 "/home/$username/.ssh/authorized_keys"
                echo "SSH key added for user $username" | tee -a "$log_file"
                break
            fi
        done
    fi
    
    # Prompt for sudo access
    read -r -p "Grant sudo access to $username? (y/n): " sudo_access
    if [[ "$sudo_access" == "y" || "$sudo_access" == "Y" ]]; then
        sudo usermod -aG sudo "$username"
        echo "Granted sudo access to $username" | tee -a "$log_file"
    fi
    
    # Set password for the user
    set_user_password "$username"
    
    # Log the action
    echo "Created user $username with group $group" | tee -a "$log_file"
}

# Function to create multiple users
create_multiple_users() {
    # Prompt for group name
    while true; do
        read -r -p "Enter group name for multiple users: " group_name
        
        # Validate group name
        if [[ "$group_name" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            break
        else
            echo "Invalid group name. Use lowercase letters, numbers, underscores, and hyphens."
        fi
    done
    
    # Create or verify group
    create_or_verify_group "$group_name" || return 1
    
    # Prompt for number of users
    while true; do
        read -r -p "Enter number of users to create: " num_users
        
        # Validate number of users
        if [[ "$num_users" =~ ^[0-9]+$ ]] && [ "$num_users" -gt 0 ]; then
            break
        else
            echo "Number of users must be a positive integer"
        fi
    done
    
    # Create users
    for ((i=1; i<=num_users; i++)); do
        local username="${group_name}user${i}"
        
        # Check if user already exists, skip if it does
        if id "$username" &>/dev/null; then
            echo "User $username already exists. Skipping..." | tee -a "$log_file"
            continue
        fi
        
        # Create user
        sudo useradd -m -s /bin/bash "$username"
        
        # Add user to group
        sudo usermod -aG "$group_name" "$username"
        
        # Prompt for sudo access for each user
        read -r -p "Grant sudo access to $username? (y/n): " sudo_access
        if [[ "$sudo_access" == "y" || "$sudo_access" == "Y" ]]; then
            sudo usermod -aG sudo "$username"
            echo "Granted sudo access to $username" | tee -a "$log_file"
        fi
        
        # Set password for the user
        set_user_password "$username"
        
        # Log user creation
        echo "Created user $username in group $group_name" | tee -a "$log_file"
    done
    
    echo "Finished creating $num_users users in group $group_name" | tee -a "$log_file"
}

# Function to delete a user
delete_user() {
    echo "User Deletion Options:"
    echo "1. Delete a single user"
    echo "2. Delete multiple users"
    
    read -r -p "Enter your choice (1 or 2): " delete_choice
    
    case "$delete_choice" in
        1)
            # Delete single user
            read -r -p "Enter username to delete: " username
            
            # Validate username exists
            if ! id "$username" &>/dev/null; then
                echo "User $username does not exist." | tee -a "$log_file"
                return 1
            fi
            
            # Confirm deletion
            read -r -p "Are you sure you want to delete user $username? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                # Remove user and home directory
                sudo userdel -r "$username"
                echo "Deleted user $username and their home directory" | tee -a "$log_file"
            else
                echo "User deletion cancelled" | tee -a "$log_file"
            fi
            ;;
        
        2)
            # Delete multiple users
            read -r -p "Enter group name to delete users from: " group_name
            
            # Check if group exists
            if ! getent group "$group_name" &>/dev/null; then
                echo "Group $group_name does not exist." | tee -a "$log_file"
                return 1
            fi
            
            # Get users in the group
            group_users=$(getent group "$group_name" | cut -d: -f4 | tr ',' ' ')
            
            echo "Users in group $group_name:"
            for user in $group_users; do
                echo "- $user"
            done
            
            # Confirm deletion
            read -r -p "Delete ALL users in this group? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                for user in $group_users; do
                    sudo userdel -r "$user"
                    echo "Deleted user $user" | tee -a "$log_file"
                done
                
                # Optional: Delete the group
                read -r -p "Delete the group $group_name as well? (y/n): " delete_group
                if [[ "$delete_group" == "y" || "$delete_group" == "Y" ]]; then
                    sudo groupdel "$group_name"
                    echo "Deleted group $group_name" | tee -a "$log_file"
                fi
            else
                echo "User deletion cancelled" | tee -a "$log_file"
            fi
            ;;
        
        *)
            echo "Invalid choice. Returning to main menu." | tee -a "$log_file"
            ;;
    esac
}

# Function to set password policy
set_password_policy() {
    echo "Setting System-Wide Password Policy..."
    
    # Make backup of login.defs
    sudo cp /etc/login.defs /etc/login.defs.backup
    echo "Backed up /etc/login.defs" | tee -a "$log_file"
    
    # Configure password aging policies in login.defs
    sudo sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS 90/' /etc/login.defs
    sudo sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS 1/' /etc/login.defs
    sudo sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE 7/' /etc/login.defs
    echo "Set password aging parameters in /etc/login.defs" | tee -a "$log_file"

    # Check if libpam-pwquality is installed
    if ! dpkg -l | grep -q libpam-pwquality; then
        echo "Installing libpam-pwquality package..."
        sudo apt-get update
        sudo apt-get install -y libpam-pwquality
        echo "Installed libpam-pwquality" | tee -a "$log_file"
    fi
    
    # Make backup of common-password
    sudo cp /etc/pam.d/common-password /etc/pam.d/common-password.backup
    
    # Update PAM configuration for password quality
    PAM_PWQUALITY_LINE="password requisite pam_pwquality.so retry=3 minlen=12 difok=3 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1 reject_username enforce_for_root"
    
    # Check if the line already exists and replace or add it
    if grep -q "pam_pwquality.so" /etc/pam.d/common-password; then
        sudo sed -i "/pam_pwquality.so/c\\$PAM_PWQUALITY_LINE" /etc/pam.d/common-password
    else
        # Find pam_unix.so line and add pwquality before it
        sudo sed -i "/pam_unix.so/i\\$PAM_PWQUALITY_LINE" /etc/pam.d/common-password
    fi
    
    echo "Updated password quality requirements in PAM" | tee -a "$log_file"
    
    # Explain the policy that was set
    echo "Password policy has been configured with the following requirements:" | tee -a "$log_file"
    echo "- Minimum password length: 12 characters" | tee -a "$log_file"
    echo "- Requires at least 1 uppercase letter" | tee -a "$log_file"
    echo "- Requires at least 1 lowercase letter" | tee -a "$log_file"
    echo "- Requires at least 1 digit" | tee -a "$log_file"
    echo "- Requires at least 1 special character" | tee -a "$log_file"
    echo "- Cannot contain the username" | tee -a "$log_file"
    echo "- Password expires after 90 days" | tee -a "$log_file"
    echo "- Password change allowed after 1 day" | tee -a "$log_file"
    echo "- Warning 7 days before password expiration" | tee -a "$log_file"
}

# Function to set password for a user
set_user_password() {
    local username="$1"
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        echo "User $username does not exist." | tee -a "$log_file"
        return 1
    fi
    
    # Prompt for password
    echo "Setting password for $username"
    echo "Note: Password must meet the system policy requirements."
    sudo passwd "$username"
    
    # Set password expiration for the user
    sudo chage -M 90 -m 1 -W 7 "$username"
    echo "Password expiration policy applied to $username" | tee -a "$log_file"
}

# Main script logic
main() {
    # Check root permissions
    check_root
    
    # Welcome message
    echo "Welcome to the Enhanced User Management Script"
    
    # Prompt for user action
    echo "Choose an option:"
    echo "1. Create a single user"
    echo "2. Create multiple users"
    echo "3. Delete user(s)"
    echo "4. Set system-wide password policy"
    echo "5. Exit"
    
    # Read user choice
    read -r -p "Enter your choice (1-5): " choice
    
    # Determine action based on choice
    case "$choice" in 
        1)
            create_single_user
            ;;
        2)
            create_multiple_users
            ;;
        3)
            delete_user
            ;;
        4)
            set_password_policy
            ;;
        5)
            echo "Exiting user management script."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please select 1-5." | tee -a "$log_file"
            exit 1
            ;;
    esac
}

# Run main function
main