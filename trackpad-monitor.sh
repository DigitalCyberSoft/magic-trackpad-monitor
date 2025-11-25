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
DISPLAY_SERVER="auto"  # auto, x11, wayland, or fallback

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
            DISPLAY_SERVER) DISPLAY_SERVER="$value" ;;
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

# Display server detection (auto, x11, wayland, fallback)
# Default: auto (automatically detect)
DISPLAY_SERVER=auto
EOF
fi

# Data files in XDG data directory
LAST_CONNECTED_FILE="$DATA_DIR/last-connected"
DEVICE_CACHE_FILE="$DATA_DIR/device-mac-cache"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Detect display server type
detect_display_server() {
    # Allow manual override from config
    if [[ "$DISPLAY_SERVER" != "auto" ]]; then
        echo "$DISPLAY_SERVER"
        return
    fi

    # Method 1: Check XDG_SESSION_TYPE (most reliable)
    if [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
        echo "wayland"
        return
    elif [[ "$XDG_SESSION_TYPE" == "x11" ]]; then
        echo "x11"
        return
    fi

    # Method 2: Check for Wayland display socket
    if [[ -n "$WAYLAND_DISPLAY" ]]; then
        echo "wayland"
        return
    fi

    # Method 3: Check for X11 display
    if [[ -n "$DISPLAY" ]] && [[ -z "$WAYLAND_DISPLAY" ]]; then
        echo "x11"
        return
    fi

    # Method 4: Check loginctl session type
    local session_id=$(loginctl show-user $(id -u) -p Display --value 2>/dev/null)
    if [[ -n "$session_id" ]]; then
        local session_type=$(loginctl show-session "$session_id" -p Type --value 2>/dev/null)
        if [[ "$session_type" == "wayland" ]]; then
            echo "wayland"
            return
        elif [[ "$session_type" == "x11" ]]; then
            echo "x11"
            return
        fi
    fi

    # Fallback: unknown
    echo "fallback"
}

# Get idle time using X11 (xidle)
get_idle_time_x11() {
    local idle_ms
    # Try to find xidle in multiple locations
    local xidle_cmd=""
    for path in "$HOME/.local/bin/xidle" "/usr/local/bin/xidle" "/usr/bin/xidle"; do
        if [[ -x "$path" ]]; then
            xidle_cmd="$path"
            break
        fi
    done

    if [[ -z "$xidle_cmd" ]]; then
        log "WARNING: xidle not found for X11, falling back"
        get_idle_time_fallback
        return
    fi

    idle_ms=$($xidle_cmd 2>/dev/null)

    if [[ -z "$idle_ms" ]]; then
        # If xidle fails, assume user is active (safer default)
        echo "0"
        return
    fi

    # Convert milliseconds to seconds
    echo $((idle_ms / 1000))
}

# Get idle time using Wayland (systemd-logind)
get_idle_time_wayland() {
    # Get current user session ID
    local session_id=$(loginctl show-user $(id -u) -p Display --value 2>/dev/null)

    if [[ -z "$session_id" ]]; then
        log "WARNING: Could not get session ID, using fallback"
        get_idle_time_fallback
        return
    fi

    # Check if session is idle
    local idle_hint=$(loginctl show-session "$session_id" -p IdleHint --value 2>/dev/null)

    if [[ "$idle_hint" == "yes" ]]; then
        # Get time since idle started
        local idle_since=$(loginctl show-session "$session_id" -p IdleSinceHint --value 2>/dev/null)
        if [[ -n "$idle_since" ]]; then
            local idle_epoch=$(date -d "$idle_since" +%s 2>/dev/null)
            if [[ -n "$idle_epoch" ]]; then
                local now=$(date +%s)
                echo $((now - idle_epoch))
                return
            fi
        fi
        # If idle but can't determine time, return threshold to trigger idle state
        echo "$IDLE_THRESHOLD"
    else
        # Not idle
        echo "0"
    fi
}

# Get idle time using fallback method (/dev/input monitoring)
get_idle_time_fallback() {
    local now=$(date +%s)
    local latest=0

    # Find all input devices
    for device in /dev/input/event*; do
        [[ -e "$device" ]] || continue  # Skip if glob didn't match
        if [[ -r "$device" ]]; then
            local mtime=$(stat -c %Y "$device" 2>/dev/null)
            if [[ -n "$mtime" ]] && [[ "$mtime" -gt "$latest" ]]; then
                latest=$mtime
            fi
        fi
    done

    if [[ $latest -eq 0 ]]; then
        # Can't read input devices, assume active
        echo "0"
    else
        echo $((now - latest))
    fi
}

# Check if trackpad is present using X11 (xinput)
is_trackpad_present_x11() {
    # Check if trackpad device exists in xinput
    if ! xinput list 2>/dev/null | grep -q "Magic Trackpad"; then
        return 1  # Not present
    fi
    return 0
}

# Check if trackpad is present using Wayland (/proc)
is_trackpad_present_wayland() {
    # Check /proc/bus/input/devices for Magic Trackpad
    if grep -q "Magic Trackpad" /proc/bus/input/devices 2>/dev/null; then
        return 0  # Present
    fi
    return 1  # Not present
}

# Check if trackpad is present (fallback - same as Wayland)
is_trackpad_present_fallback() {
    is_trackpad_present_wayland
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

# Detect and log display server
DETECTED_DISPLAY_SERVER=$(detect_display_server)
log "Detected display server: $DETECTED_DISPLAY_SERVER"
log "Monitoring Magic Trackpad: $TRACKPAD_MAC"

# Get keyboard/mouse idle time - unified interface
get_keyboard_idle_time() {
    case "$DETECTED_DISPLAY_SERVER" in
        x11)
            get_idle_time_x11
            ;;
        wayland)
            get_idle_time_wayland
            ;;
        *)
            get_idle_time_fallback
            ;;
    esac
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
    case "$DETECTED_DISPLAY_SERVER" in
        x11)
            # X11: Full stuck detection using xinput
            if ! is_trackpad_present_x11; then
                return 0  # Not present = stuck
            fi

            # Try to get trackpad event device
            local trackpad_id=$(xinput list 2>/dev/null | grep "Magic Trackpad" | grep -oP 'id=\K\d+' | head -1)

            if [[ -z "$trackpad_id" ]]; then
                return 0  # Can't find = stuck
            fi

            # Check if device is enabled
            if xinput list-props "$trackpad_id" 2>/dev/null | grep "Device Enabled" | grep -qE '\b0\s*$'; then
                return 0  # Disabled = stuck
            fi

            return 1  # Appears to be working
            ;;
        wayland|*)
            # Wayland/Fallback: Simplified - just check if device is present
            # Cannot reliably detect "stuck" state on Wayland
            if ! is_trackpad_present_wayland; then
                return 0  # Not present = stuck
            fi
            return 1  # Present = not stuck (simplified)
            ;;
    esac
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

    # Check keyboard idle time
    keyboard_idle=$(get_keyboard_idle_time)

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
