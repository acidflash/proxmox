#!/bin/bash

# Discord incoming webhook URL
discord_url="https://discord.com/api/webhooks/XXXX"  # Replace with your real webhook URL

# Threshold temperature in °C
alert_threshold=50
clear_threshold=45

#Create tmp file
state_dir="/var/tmp/nvme-temp-alerts"
mkdir -p "$state_dir"

# Set hostname
hostname_value="$(hostname)"

# Read all matching temperature lines
sensors 2>/dev/null | awk '
    /^[^[:space:]][^:]*$/ {
        chip=$0
        next
    }

    /^Adapter: PCI adapter$/ {
        pci=1
        next
    }

    /^Adapter:/ {
        pci=0
        next
    }

    pci && /^[[:space:]]*Composite:/ {
        temp=$2
        gsub(/[^0-9.]/, "", temp)
        sub(/\..*/, "", temp)

        if (temp != "") {
            printf "%s|%s\n", chip, temp
        }
    }
' | while IFS='|' read -r chip temp; do
    state_file="${state_dir}/${chip}.state"
    current_state="ok"

    [[ -f "$state_file" ]] && current_state="$(cat "$state_file")"

    if (( temp >= alert_threshold )); then
        if [[ "$current_state" != "alerted" ]]; then
            payload=$(jq -n \
                --arg content "🔥 ALERT on ${hostname_value}: ${chip} Composite is ${temp}°C" \
                '{content: $content}')

            curl -s -X POST \
                -H "Content-Type: application/json" \
                -d "$payload" \
                "$discord_url" >/dev/null

            echo "alerted" > "$state_file"
        fi
    elif (( temp <= clear_threshold )); then
        if [[ "$current_state" == "alerted" ]]; then
            payload=$(jq -n \
                --arg content "✅ CLEAR on ${hostname_value}: ${chip} Composite is back to ${temp}°C" \
                '{content: $content}')

            curl -s -X POST \
                -H "Content-Type: application/json" \
                -d "$payload" \
                "$discord_url" >/dev/null
        fi

        echo "ok" > "$state_file"
    fi
done
