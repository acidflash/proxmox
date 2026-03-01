#!/bin/bash
set -euo pipefail

# -------- CONFIG --------
MQTT_HOST="XXXX"
MQTT_PORT="1883"
MQTT_USER="homeassistant"
MQTT_PASS="XXX"
# ------------------------

HOST="$(hostname -s | tr '[:upper:]' '[:lower:]')"     # ex: pve04

# ===== Auto-detect manufacturer + model (+ serial) via DMI =====
get_dmi_value() {
  local file="$1"
  if [ -r "/sys/class/dmi/id/${file}" ]; then
    tr -d '\0' < "/sys/class/dmi/id/${file}" | sed 's/^[ \t]*//;s/[ \t]*$//'
  else
    echo "Unknown"
  fi
}

DEVICE_MANUFACTURER="$(get_dmi_value sys_vendor)"
DEVICE_MODEL="$(get_dmi_value product_name)"
DEVICE_SERIAL="$(get_dmi_value product_serial)"

[ -z "$DEVICE_MANUFACTURER" ] && DEVICE_MANUFACTURER="Unknown"
[ -z "$DEVICE_MODEL" ] && DEVICE_MODEL="Unknown"
[ -z "$DEVICE_SERIAL" ] && DEVICE_SERIAL="Unknown"

DEVICE_ID="$HOST"
DEVICE_NAME="Proxmox Server ${HOST^^}"
SW_VERSION="$(pveversion 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown")"

BASE_TOPIC="proxmox/${HOST}"

# Sensorlista:
# SENSOR_KEY|REL_STATE_TOPIC|CHIP_NAME|LABEL|UNIT|DEVICE_CLASS
SENSORS=(
  "cpu_package|temperature/cpu_package|coretemp-isa-0000|Package id 0|°C|temperature"
  "cpu_core0|temperature/cpu_core0|coretemp-isa-0000|Core 0|°C|temperature"
  "cpu_core1|temperature/cpu_core1|coretemp-isa-0000|Core 1|°C|temperature"
  "cpu_core2|temperature/cpu_core2|coretemp-isa-0000|Core 2|°C|temperature"
  "cpu_core3|temperature/cpu_core3|coretemp-isa-0000|Core 3|°C|temperature"
  "cpu_core4|temperature/cpu_core4|coretemp-isa-0000|Core 4|°C|temperature"
  "cpu_core5|temperature/cpu_core5|coretemp-isa-0000|Core 5|°C|temperature"
  "power_total|power/total|power_meter-acpi-0|power1|W|power"
)

for ENTRY in "${SENSORS[@]}"; do
  IFS='|' read -r SENSOR_KEY REL_STATE_TOPIC CHIP LABEL UNIT CLASS <<< "$ENTRY"

  STATE_TOPIC="${BASE_TOPIC}/${REL_STATE_TOPIC}"

  # Hämta raden från rätt chip
  RAW_LINE=$(sensors "$CHIP" 2>/dev/null | grep -m1 "$LABEL" || true)
  [ -z "$RAW_LINE" ] && continue

  VALUE=""
  case "$UNIT" in
    "°C")
      # Format: 'Package id 0:  +40.0°C  (high = ...'
      VALUE=$(echo "$RAW_LINE" \
        | awk -F'+' '{print $2}' \
        | awk '{print $1}' \
        | cut -d'.' -f1)
      ;;
    "W")
      # Format: 'power1:       36.00 W  (interval = 300.00 s)'
      VALUE=$(echo "$RAW_LINE" \
        | awk '{print $(NF-1)}' \
        | cut -d'.' -f1)
      ;;
  esac
  [ -z "$VALUE" ] && continue

  # Snyggt namn i HA
  SENSOR_NAME="$(echo "${SENSOR_KEY}" \
    | sed 's/_/ /g' \
    | awk '{ for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print }')"

  # Viktigt: unika ID per host
  ENTITY_ID="${HOST}_${SENSOR_KEY}"
  UNIQUE_ID="proxmox_${HOST}_${SENSOR_KEY}"

  # Discovery topic måste vara unikt per host
  DISCOVERY_TOPIC="homeassistant/sensor/${ENTITY_ID}/config"

  # Home Assistant Discovery payload (retained)
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
    -u "$MQTT_USER" -P "$MQTT_PASS" \
    -t "$DISCOVERY_TOPIC" -r \
    -m "{
      \"name\": \"${HOST^^} ${SENSOR_NAME}\",
      \"state_topic\": \"${STATE_TOPIC}\",
      \"unit_of_measurement\": \"${UNIT}\",
      \"device_class\": \"${CLASS}\",
      \"unique_id\": \"${UNIQUE_ID}\",
      \"device\": {
        \"identifiers\": [\"${DEVICE_ID}\", \"${DEVICE_SERIAL}\"],
        \"name\": \"${DEVICE_NAME}\",
        \"manufacturer\": \"${DEVICE_MANUFACTURER}\",
        \"model\": \"${DEVICE_MODEL}\",
        \"sw_version\": \"${SW_VERSION}\"
      }
    }"

  # Skicka själva värdet
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" \
    -u "$MQTT_USER" -P "$MQTT_PASS" \
    -t "$STATE_TOPIC" -m "$VALUE"
done
