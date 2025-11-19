#!/bin/bash

# Magic Trackpad monitoring and auto-reconnect script
CHECK_INTERVAL=10  # seconds between checks
IDLE_THRESHOLD=600  # 10 minutes in seconds
STUCK_THRESHOLD=30  # seconds without events to consider trackpad stuck
LAST_CONNECTED_FILE="/tmp/trackpad-last-connected"
DEVICE_CACHE_FILE="/tmp/trackpad-mac-cache"
CACHE_EXPIRY_DAYS=30  # Only track trackpads connected in last 30 days

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Find Magic Trackpad MAC address
find_trackpad_mac() {
    # Check cache first
    if [[ -f "$DEVICE_CACHE_FILE" ]]; then
        local cache_age_days=$(( ($(date +%s) - $(stat -c %Y "$DEVICE_CACHE_FILE")) / 86400 ))
        if [[ $cache_age_days -lt $CACHE_EXPIRY_DAYS ]]; then
            local cached_mac=$(cat "$DEVICE_CACHE_FILE")
            # Verify device still exists
            if bluetoothctl devices | grep -q "$cached_mac"; then
                echo "$cached_mac"
                return 0
            fi
        fi
    fi

    # Find any paired Magic Trackpad
    local trackpad_mac=$(bluetoothctl devices | grep -i "magic trackpad" | head -1 | awk '{print $2}')

    if [[ -n "$trackpad_mac" ]]; then
        echo "$trackpad_mac" > "$DEVICE_CACHE_FILE"
        echo "$trackpad_mac"
        return 0
    fi

    return 1
}

# Get the trackpad MAC address
TRACKPAD_MAC=$(find_trackpad_mac)

if [[ -z "$TRACKPAD_MAC" ]]; then
    log "ERROR: No Magic Trackpad found in paired devices"
    log "Please pair your Magic Trackpad using bluetoothctl"
    exit 1
fi

log "Monitoring Magic Trackpad: $TRACKPAD_MAC"

# Get keyboard/mouse idle time in seconds using xidle (X11 idle time detector)
get_keyboard_idle_time() {
    local idle_ms
    idle_ms=$($HOME/.local/bin/xidle 2>/dev/null)

    if [[ -z "$idle_ms" ]]; then
        # If xidle fails, assume user is active (safer default)
        echo "0"
        return
    fi

    # Convert milliseconds to seconds
    echo $((idle_ms / 1000))
}

is_trackpad_connected() {
    if bluetoothctl info "$TRACKPAD_MAC" 2>/dev/null | grep -q "Connected: yes"; then
        # Update last connected timestamp
        date '+%Y-%m-%d %H:%M:%S (%s)' > "$LAST_CONNECTED_FILE"
        return 0
    fi
    return 1
}

is_trackpad_stuck() {
    # Check if trackpad device exists in xinput
    if ! xinput list | grep -q "Magic Trackpad"; then
        return 0  # Not present = stuck
    fi

    # Try to get trackpad event device
    local trackpad_id=$(xinput list | grep "Magic Trackpad" | grep -oP 'id=\K\d+' | head -1)

    if [[ -z "$trackpad_id" ]]; then
        return 0  # Can't find = stuck
    fi

    # Check if device is enabled
    if xinput list-props "$trackpad_id" 2>/dev/null | grep "Device Enabled" | grep -q "0$"; then
        return 0  # Disabled = stuck
    fi

    return 1  # Appears to be working
}

reset_bluetooth() {
    log "Resetting Bluetooth adapter to fix stuck trackpad..."
    # Modern BlueZ doesn't have hciconfig, use bluetoothctl power cycle instead
    bluetoothctl power off &>/dev/null
    sleep 1
    bluetoothctl power on &>/dev/null
    sleep 2
    log "Bluetooth adapter power cycled"
    return 0
}

connect_trackpad() {
    log "Attempting to connect to Magic Trackpad ($TRACKPAD_MAC)..."
    local output
    output=$(bluetoothctl connect "$TRACKPAD_MAC" 2>&1)

    if echo "$output" | grep -q "Connection successful\|already connected"; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S (%s)')
        echo "$timestamp" > "$LAST_CONNECTED_FILE"
        log "Magic Trackpad connected at $timestamp"
        return 0
    else
        log "Connection attempt failed: $output"
        return 1
    fi
}

reconnect_trackpad() {
    log "Disconnecting trackpad before reconnect..."
    bluetoothctl disconnect "$TRACKPAD_MAC" &>/dev/null
    sleep 1

    if connect_trackpad; then
        return 0
    fi

    # If normal connect fails, try Bluetooth reset
    reset_bluetooth
    sleep 2
    connect_trackpad
}

log "Starting Magic Trackpad monitor..."
log "Idle threshold: ${IDLE_THRESHOLD}s (${IDLE_THRESHOLD}/60 minutes)"
log "Check interval: ${CHECK_INTERVAL}s"

# Show last connected time if available
if [[ -f "$LAST_CONNECTED_FILE" ]]; then
    log "Last connected: $(cat "$LAST_CONNECTED_FILE")"
fi

# Initial connection attempt
if ! is_trackpad_connected; then
    log "Initial connection attempt..."
    connect_trackpad
else
    log "Magic Trackpad already connected"
fi

# Track last successful check
last_event_time=$(date +%s)

# Main monitoring loop
while true; do
    sleep "$CHECK_INTERVAL"

    # Check keyboard idle time
    keyboard_idle=$(get_keyboard_idle_time)

    if [[ $keyboard_idle -ge $IDLE_THRESHOLD ]]; then
        log "Keyboard idle for ${keyboard_idle}s (>= ${IDLE_THRESHOLD}s), user away - skipping checks"
        continue
    fi

    # User is active, check trackpad status
    if ! is_trackpad_connected; then
        log "Trackpad disconnected (keyboard active: idle ${keyboard_idle}s), reconnecting..."
        reconnect_trackpad
        last_event_time=$(date +%s)
    elif is_trackpad_stuck; then
        log "Trackpad appears stuck (keyboard active: idle ${keyboard_idle}s), attempting recovery..."
        reconnect_trackpad
        last_event_time=$(date +%s)
    fi
done
