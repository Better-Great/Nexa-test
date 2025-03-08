#!/bin/bash

# Set timezone to WAT (West Africa Time)
export TZ=Africa/Lagos

# Get the current time in WAT
current_time=$(date +"%H:%M:%S")

# Display the current time
echo "The current time in WAT is: $current_time"
