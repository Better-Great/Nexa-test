#!/bin/bash

# Set timezone to WAT (West Africa Time)
export TZ=Africa/Lagos

# Get the current time in WAT
current_time=$(date +"%H:%M:%S")

# Display the current time
echo "The current time in WAT is: $current_time"

# Check if the current time is between 9:00 AM and 5:00 PM
if [[ "$current_time" > "09:00:00" && "$current_time" < "17:00:00" ]]; then
    echo "It is currently working hours."
else
    echo "It is currently outside of working hours."
fi
