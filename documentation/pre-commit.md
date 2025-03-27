# Pre-commit Hook: Code Quality Assurance
## Purpose
This pre-commit hook is our first line of defense against potential code issues. It automatically checks the syntax and quality of shell and Python scripts before they can be committed to the repository.
## Why We Implemented This
### 1. Catch Errors Early
- Prevents committing scripts with syntax errors
- Identifies potential issues before code review
- Saves time by catching mistakes immediately

### 2. Maintain Code Quality
- Enforces basic coding standards
- Runs automated checks on every commit
- Reduces manual code review overhead

## What It Checks
### 1. Shell Scripts (*.sh)
- Basic syntax validation
- Comprehensive shell script analysis using Shellcheck
- Ensures scripts are properly formatted and free of common mistakes

### 2. Python Scripts (*.py)
- Syntax compilation check
- Pylint error detection
- Catches potential runtime and style issues

## Setup Requirements
### Dependencies
Install the following tools:
```sh 
# For Python linting
pip install pylint

# Install shellcheck
sudo apt install shellcheck
```
### Activation
To enable the pre-commit hook:
```sh
git config core.hooksPath .githooks
```

### How It Works
1. When you attempt to commit code
2. The hook automatically scans staged shell and Python scripts
3. If any issues are found, the commit is blocked
4. Detailed error messages help you fix the problems

### Benefits
1. Consistent code quality
2. Automated error detection
3. Reduced manual review time
4. Improved overall code reliability

### Troubleshooting
1. Ensure all dependencies are installed
2. Check error messages for specific script issues
3. If you need to bypass the hook (rarely recommended), use `git commit --no-verify`