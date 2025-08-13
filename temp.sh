#!/bin/bash

# Discord incoming webhook URL
discord_url="https://discord.com/api/webhooks/1376823779589619793/KW8t-jiMM1qrKOWTGe-1NW5YNLdlmWqHjjD8Rr0QkOjsGJMtAHP0UOeWJ26Hh0JqgBq3"  # Replace with your real webhook URL

# Threshold temperature in °C
threshold=95

# Read all matching temperature lines
sensors | grep -E "Package id 0" | while read -r line; do
    # Extract the temperature value
    temp=$(echo "$line" | awk -F "+" '{ print $2 }' | awk -F "." '{ print $1 }')

    if (( temp > threshold )); then
        # Use proper JSON escaping for Discord
        payload=$(jq -n \
            --arg content "🔥 ALERT on $(hostname): Temperature is ${temp}°C" \
            '{content: $content}')
        
        curl -s -X POST -H "Content-Type: application/json" \
            -d "$payload" "$discord_url"
    fi
done
