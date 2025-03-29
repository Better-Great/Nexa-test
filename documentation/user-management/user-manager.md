# Linux User Management Script
## About This Task
This script is a comprehensive tool that helps manage users on a Linux system. Let's break down what it does and why it's useful.

## What This Script Does
The script helps with four main tasks:

1. **Creating Users:** You can add individual users or create multiple users at once.
2. **Setting Up SSH Keys:** The script allows secure remote access by adding SSH keys.
3. **Implementing Password Policies:** It enforces strong password rules and expiration.
4. **Managing User Groups:** You can organize users into groups for easier permission management.

## Why This Is Important
In real-world systems, managing users is a critical task:

1. **Security:** Proper user management prevents unauthorized access
2. **Organization:** Grouping users helps manage permissions efficiently
3. **Automation:** Scripts like this save time when working with multiple users

## How To Use The Script

1. Run the script with: `sudo ./user_management.sh`
2. Choose an option from the menu
3. Follow the prompts

The script requires root (sudo) access because only administrators can manage users on Linux systems.

## How The Script Works
### Creating Users
When you create a user with this script, it:
1. Asks for a username and validates it (making sure it follows proper Linux naming rules)
2. Creates the user's home directory
3. Sets up their default shell (bash)
4. Optionally adds them to a group
5. Sets a password with proper security policies

This is much faster than typing multiple commands manually!

### SSH Key Management
The script makes it easy to add SSH keys by:

1. Creating the .ssh directory in the user's home folder
2. Adding the key to the authorized_keys file
3. Setting the correct permissions (this is important for SSH to work properly)

### Password Policies
The password section:

1. Sets minimum length (12 characters)
2. Requires a mix of uppercase, lowercase, numbers, and special characters
3. Makes passwords expire after 90 days
4. Gives a warning 7 days before expiration

These policies help protect the system from weak passwords.

### User Groups
The script can:

1. Create new groups
2. Add users to groups
3. Delete groups when they're no longer needed
4. List all users in a group

Groups help organize users who need similar access permissions.

## What Makes This a Good Script
This script is well-designed because it:

1. **Validates Input:** It checks that usernames and other inputs are valid before using them
2. **Logs Actions:** Every action is logged, which helps track changes
3. **Provides Feedback:** It tells you what it's doing at each step
4. **Has Clear Options:** The menu makes it easy to choose what you want to do
5. **Handles Errors:** If something goes wrong, the script tells you what happened
6. **Follows Best Practices:** It implements security features like strong password policies