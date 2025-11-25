#!/bin/bash

# Magic Trackpad monitoring and auto-reconnect script

# XDG Base Directory Specification
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# Configuration and data directories
CONFIG_DIR="$XDG_CONFIG_HOME/trackpad-monitor"
DATA_DIR="$XDG_DATA_HOME/trackpad-monitor"
CONFIG_FILE="$CONFIG_DIR/config"

# Create directories if they don't exist
mkdir -p "$CONFIG_DIR" "$DATA_DIR"

# Default values
CHECK_INTERVAL=10  # seconds between checks
IDLE_THRESHOLD=600  # 10 minutes in seconds
STUCK_THRESHOLD=30  # seconds without events to consider trackpad stuck
CACHE_EXPIRY_DAYS=30  # Only track trackpads connected in last 30 days

# Load configuration file if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    # Source config file, filtering out comments and empty lines
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        # Remove any trailing comments
        value="${value%%#*}"
        # Trim whitespace
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        # Set the variable
        case "$key" in
            CHECK_INTERVAL) CHECK_INTERVAL="$value" ;;
            IDLE_THRESHOLD) IDLE_THRESHOLD="$value" ;;
            STUCK_THRESHOLD) STUCK_THRESHOLD="$value" ;;
            CACHE_EXPIRY_DAYS) CACHE_EXPIRY_DAYS="$value" ;;
        esac
    done < <(grep -v '^[[:space:]]*$' "$CONFIG_FILE")
else
    # Create default config file if it doesn't exist
    cat > "$CONFIG_FILE" << 'EOF'
# Magic Trackpad Monitor Configuration
# This file configures the trackpad monitoring service

# Time between connection checks (in seconds)
# Default: 10 seconds
CHECK_INTERVAL=10

# Idle threshold before pausing monitoring (in seconds)
# The monitor will pause when keyboard is idle for this duration
# Default: 600 seconds (10 minutes)
IDLE_THRESHOLD=600

# Time without input events to consider trackpad stuck (in seconds)
# Default: 30 seconds
STUCK_THRESHOLD=30

# Days before device MAC cache expires
# Default: 30 days
CACHE_EXPIRY_DAYS=30
EOF
fi

# Data files in XDG data directory
LAST_CONNECTED_FILE="$DATA_DIR/last-connected"
DEVICE_CACHE_FILE="$DATA_DIR/device-mac-cache"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Get idle time using cascading detection methods
# Priority: GNOME D-Bus > KDE D-Bus > xidle (X11) > assume active
get_idle_time() {
    local idle_ms

    # 1. Try GNOME Mutter D-Bus (works on GNOME X11 + Wayland)
    idle_ms=$(gdbus call --session \
        --dest=org.gnome.Mutter.IdleMonitor \
        --object-path /org/gnome/Mutter/IdleMonitor/Core \
        --method org.gnome.Mutter.IdleMonitor.GetIdletime 2>/dev/null)
    if [[ $? -eq 0 && -n "$idle_ms" ]]; then
        # Extract number from "(uint64 12345,)"
        idle_ms="${idle_ms//[^0-9]/}"
        echo $((idle_ms / 1000))
        return
    fi

    # 2. Try KDE KIdleTime D-Bus (works on KDE X11 + Wayland)
    idle_ms=$(qdbus org.kde.KIdleTime /KIdleTime idleTime 2>/dev/null)
    if [[ $? -eq 0 && -n "$idle_ms" ]]; then
        echo $((idle_ms / 1000))
        return
    fi

    # 3. Try xidle for X11 (works on Cinnamon, XFCE, i3, etc.)
    if [[ -n "$DISPLAY" ]]; then
        local xidle_cmd=""
        for path in "$HOME/.local/bin/xidle" "/usr/local/bin/xidle" "/usr/bin/xidle"; do
            if [[ -x "$path" ]]; then
                xidle_cmd="$path"
                break
            fi
        done
        if [[ -n "$xidle_cmd" ]]; then
            idle_ms=$($xidle_cmd 2>/dev/null)
            if [[ $? -eq 0 && -n "$idle_ms" ]]; then
                echo $((idle_ms / 1000))
                return
            fi
        fi
    fi

    # 4. Fallback: assume user is active (safe default - always reconnect)
    echo "0"
}

# Check if trackpad is present in the system
is_trackpad_present() {
    # Method 1: Check /proc/bus/input/devices (works on all Linux)
    if grep -q "Magic Trackpad" /proc/bus/input/devices 2>/dev/null; then
        return 0  # Present
    fi
    # Method 2: Try xinput if available (X11)
    if [[ -n "$DISPLAY" ]] && xinput list 2>/dev/null | grep -q "Magic Trackpad"; then
        return 0  # Present
    fi
    return 1  # Not present
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

is_trackpad_connected() {
    if bluetoothctl info "$TRACKPAD_MAC" 2>/dev/null | grep -q "Connected: yes"; then
        # Update last connected timestamp
        date '+%Y-%m-%d %H:%M:%S (%s)' > "$LAST_CONNECTED_FILE"
        return 0
    fi
    return 1
}

is_trackpad_stuck() {
    # Check if device is present at all
    if ! is_trackpad_present; then
        return 0  # Not present = stuck
    fi

    # On X11, also check if device is enabled via xinput
    if [[ -n "$DISPLAY" ]]; then
        local trackpad_id=$(xinput list 2>/dev/null | grep "Magic Trackpad" | grep -oP 'id=\K\d+' | head -1)
        if [[ -n "$trackpad_id" ]]; then
            if xinput list-props "$trackpad_id" 2>/dev/null | grep "Device Enabled" | grep -qE '\b0\s*$'; then
                return 0  # Disabled = stuck
            fi
        fi
    fi

    return 1  # Appears to be working
}

reset_bluetooth() {
    log "Resetting Bluetooth adapter to fix stuck trackpad..."
    # Modern BlueZ doesn't have hciconfig, use bluetoothctl power cycle instead
    if ! bluetoothctl power off &>/dev/null; then
        log "WARNING: Failed to power off Bluetooth adapter"
    fi
    sleep 1
    if ! bluetoothctl power on &>/dev/null; then
        log "WARNING: Failed to power on Bluetooth adapter"
        return 1
    fi
    sleep 2
    log "Bluetooth adapter power cycled"
    return 0
}

connect_trackpad() {
    log "Attempting to connect to Magic Trackpad ($TRACKPAD_MAC)..."
    local output
    output=$(bluetoothctl connect "$TRACKPAD_MAC" 2>&1)

    if echo "$output" | grep -qi "Connection successful\|already connected"; then
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

# Main monitoring loop
while true; do
    sleep "$CHECK_INTERVAL"

    # Check idle time
    keyboard_idle=$(get_idle_time)

    if [[ "$keyboard_idle" -ge "$IDLE_THRESHOLD" ]]; then
        log "Keyboard idle for ${keyboard_idle}s (>= ${IDLE_THRESHOLD}s), user away - skipping checks"
        continue
    fi

    # User is active, check trackpad status
    if ! is_trackpad_connected; then
        log "Trackpad disconnected (keyboard active: idle ${keyboard_idle}s), reconnecting..."
        reconnect_trackpad
    elif is_trackpad_stuck; then
        log "Trackpad appears stuck (keyboard active: idle ${keyboard_idle}s), attempting recovery..."
        reconnect_trackpad
    fi
done
