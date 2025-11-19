# Linux Magic Trackpad Auto-Reconnect

Automatic monitoring and reconnection service for Apple Magic Trackpad on Linux systems.

## Features

- **Dynamic Device Discovery** - Automatically finds any paired Magic Trackpad
- **Smart Idle Detection** - Only monitors when user is active (keyboard idle < 10 minutes)
- **Stuck Device Recovery** - Detects frozen trackpad and power cycles Bluetooth adapter
- **Last Connection Tracking** - Tracks when trackpad was last successfully connected
- **30-Day Device Cache** - Remembers your trackpad for 30 days

## Components

- **trackpad-monitor.sh** - Main monitoring script
- **trackpad-status** - Status checker command-line tool
- **xidle.c** - X11 idle time detector (lightweight xprintidle alternative)
- **trackpad-fast-reconnect.service** - systemd user service file

## Installation

1. **Install dependencies:**
   ```bash
   sudo dnf install -y libXScrnSaver-devel gcc
   ```

2. **Compile xidle:**
   ```bash
   gcc -o ~/.local/bin/xidle xidle.c -lX11 -lXss
   ```

3. **Install scripts:**
   ```bash
   cp trackpad-monitor.sh ~/
   chmod +x ~/trackpad-monitor.sh

   cp trackpad-status ~/.local/bin/
   chmod +x ~/.local/bin/trackpad-status
   ```

4. **Install systemd service:**
   ```bash
   mkdir -p ~/.config/systemd/user
   cp trackpad-fast-reconnect.service ~/.config/systemd/user/

   systemctl --user enable trackpad-fast-reconnect.service
   systemctl --user start trackpad-fast-reconnect.service
   ```

## Usage

### Check Status
```bash
trackpad-status
```

Shows:
- Monitored device MAC and name
- Current connection status
- Last verified connection time
- Service running/enabled status
- Cache age

### View Logs
```bash
journalctl --user -u trackpad-fast-reconnect.service -f
```

### Manually Control Service
```bash
systemctl --user status trackpad-fast-reconnect.service
systemctl --user restart trackpad-fast-reconnect.service
systemctl --user stop trackpad-fast-reconnect.service
```

## How It Works

1. **Device Discovery**: Finds any paired "Magic Trackpad" via `bluetoothctl devices`
2. **Idle Detection**: Uses `xidle` to check X11 idle time
3. **Smart Monitoring**:
   - Checks trackpad every 10 seconds
   - Skips checks when keyboard idle > 10 minutes (user away)
4. **Recovery**:
   - Detects disconnected or stuck trackpad
   - Attempts reconnection
   - Power cycles Bluetooth adapter if needed

## Configuration

Edit `trackpad-monitor.sh` to customize:

```bash
CHECK_INTERVAL=10      # seconds between checks
IDLE_THRESHOLD=600     # 10 minutes in seconds
CACHE_EXPIRY_DAYS=30   # device cache expiry
```

## Troubleshooting

### Service won't start
Check logs:
```bash
journalctl --user -u trackpad-fast-reconnect.service -n 50
```

### Trackpad not found
Ensure it's paired:
```bash
bluetoothctl devices | grep -i "magic trackpad"
```

### xidle not working
Test manually:
```bash
~/.local/bin/xidle
```
Should return idle time in milliseconds.

## Requirements

- Linux with systemd
- X11 (not Wayland)
- BlueZ 5.x
- libXScrnSaver

## License

Public Domain

## Credits

Created to solve the common Magic Trackpad freezing issue on Linux systems.
