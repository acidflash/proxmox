#!/bin/bash

# -------- CONFIG --------
# Skicka till MQTT
MQTT_HOST="home.labnat.local"           # <-- din MQTT-server (Home Assistant eller annan)
MQTT_PORT="1883"
MQTT_TOPIC="proxmox/temperature/cpu"
MQTT_USER="homeassistant"              # valfritt om du har auth
MQTT_PASS="ohnai0uhi8yoochohvohnaiphahl5ieviegh6ag7ohDei9shooquaoKai0theZu1"              # valfritt om du har auth

SENSOR_NAME="Proxmox CPU Temp"
SENSOR_ID="proxmox_cpu_temp"
STATE_TOPIC="proxmox/temperature/cpu"
DISCOVERY_TOPIC="homeassistant/sensor/${SENSOR_ID}/config"

DEVICE_ID="pve01"
DEVICE_NAME="Proxmox Server"
DEVICE_MANUFACTURER="Minisforum"
DEVICE_MODEL="MA-01"
SW_VERSION="1"
# ------------------------

# Sensorlista: namn, sensors-nyckel, grep-mönster
SENSORS=(
  "proxmox_cpu_temp|proxmox/temperature/cpu|Package id 0"
  "nvme_composite|proxmox/temperature/nvme_composite|Composite"
  "nvme_sensor_1|proxmox/temperature/nvme_sensor_1|Sensor 1"
  "nvme_sensor_2|proxmox/temperature/nvme_sensor_2|Sensor 2"
)

for ENTRY in "${SENSORS[@]}"; do
  IFS='|' read SENSOR_ID STATE_TOPIC GREP_PATTERN <<< "$ENTRY"

  TEMP=$(sensors | grep -A 5 "nvme-pci-0100" | grep -E "$GREP_PATTERN" | awk -F "+" '{ print $2 }' | awk -F "." '{ print $1 }')
  if [ -z "$TEMP" ]; then
    TEMP=$(sensors | grep -E "$GREP_PATTERN" | awk -F "+" '{ print $2 }' | awk -F "." '{ print $1 }')
  fi

  SENSOR_NAME="$(echo "$SENSOR_ID" | sed 's/_/ /g' | awk '{ for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print }')"
  DISCOVERY_TOPIC="homeassistant/sensor/${SENSOR_ID}/config"

  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
    -u "$MQTT_USER" -P "$MQTT_PASS" \
    -t "$DISCOVERY_TOPIC" -r \
    -m "{
      \"name\": \"$SENSOR_NAME\",
      \"state_topic\": \"$STATE_TOPIC\",
      \"unit_of_measurement\": \"\u00b0C\",
      \"device_class\": \"temperature\",
      \"unique_id\": \"${SENSOR_ID}_1\",
      \"device\": {
        \"identifiers\": [\"$DEVICE_ID\"],
        \"name\": \"$DEVICE_NAME\",
        \"manufacturer\": \"$DEVICE_MANUFACTURER\",
        \"model\": \"$DEVICE_MODEL\",
        \"sw_version\": \"$SW_VERSION\"
      }
    }"

  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
    -u "$MQTT_USER" -P "$MQTT_PASS" \
    -t "$STATE_TOPIC" -m "$TEMP"
done
