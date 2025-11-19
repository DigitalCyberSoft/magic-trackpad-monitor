# Magic Trackpad Monitor

Automatic monitoring and reconnection service for Apple Magic Trackpad on Linux systems.

## Features

- **Dynamic Device Discovery** - Automatically finds any paired Magic Trackpad
- **Smart Idle Detection** - Only monitors when user is active (keyboard idle < 10 minutes)
- **Stuck Device Recovery** - Detects frozen trackpad and power cycles Bluetooth adapter
- **Last Connection Tracking** - Tracks when trackpad was last successfully connected
- **XDG-Compliant** - Configuration in `~/.config/trackpad-monitor/`, data in `~/.local/share/trackpad-monitor/`
- **Easy Packaging** - RPM, DEB, and bash installer support

## Components

- **trackpad-monitor** - Main monitoring script
- **trackpad-status** - Status checker command-line tool
- **xidle** - X11 idle time detector (lightweight xprintidle alternative)
- **trackpad-fast-reconnect.service** - systemd user service file

## Installation

### Option 1: Package Manager (Recommended)

#### Fedora/RHEL/CentOS (RPM)
```bash
# From COPR repository (once published)
sudo dnf copr enable yourusername/magic-trackpad-monitor
sudo dnf install magic-trackpad-monitor

# Or install local RPM
sudo dnf install magic-trackpad-monitor-*.rpm
```

#### Ubuntu/Debian (DEB)
```bash
# Install local DEB package
sudo apt install ./magic-trackpad-monitor_*.deb
```

### Option 2: Bash Installer
```bash
# Clone repository
git clone https://github.com/yourusername/linux-magictrackpad-reconnect.git
cd linux-magictrackpad-reconnect

# Run installer (installs to ~/.local by default)
./install.sh

# Or install system-wide (requires sudo)
PREFIX=/usr/local sudo ./install.sh
```

### Option 3: Manual Installation with Make
```bash
# Install dependencies (Fedora)
sudo dnf install -y gcc libXScrnSaver-devel bluez xinput

# Or on Ubuntu/Debian
sudo apt install -y gcc libxss-dev libx11-dev bluez xinput

# Build and install
make build
make install

# Enable and start service
systemctl --user daemon-reload
systemctl --user enable trackpad-fast-reconnect.service
systemctl --user start trackpad-fast-reconnect.service
```

### Post-Installation

After installing via any method, enable and start the service:
```bash
systemctl --user daemon-reload
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

Configuration file: `~/.config/trackpad-monitor/config`

The configuration file is automatically created with defaults on first run. You can edit it to customize behavior:

```bash
# Time between connection checks (in seconds)
CHECK_INTERVAL=10

# Idle threshold before pausing monitoring (in seconds)
IDLE_THRESHOLD=600

# Time without input events to consider trackpad stuck (in seconds)
STUCK_THRESHOLD=30

# Days before device MAC cache expires
CACHE_EXPIRY_DAYS=30
```

After editing the config, restart the service:
```bash
systemctl --user restart trackpad-fast-reconnect.service
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

## Building Packages

### Build RPM
```bash
make rpm
```

### Build DEB (requires alien)
```bash
make deb
```

### Build for COPR
```bash
cd .copr
make srpm outdir=/path/to/output
```

## Uninstallation

### Via Package Manager
```bash
# Fedora/RHEL
sudo dnf remove magic-trackpad-monitor

# Ubuntu/Debian
sudo apt remove magic-trackpad-monitor
```

### Via Bash Installer
```bash
./install.sh --uninstall
```

### Via Make
```bash
make uninstall
```

## Requirements

- Linux with systemd
- X11 (not Wayland)
- BlueZ 5.x (bluez package)
- xinput
- libXScrnSaver
- gcc (only for building from source)

## File Locations

- **Binaries**: `~/.local/bin/` or `/usr/bin/` or `/usr/local/bin/`
- **Configuration**: `~/.config/trackpad-monitor/config`
- **Data/Cache**: `~/.local/share/trackpad-monitor/`
- **Service**: `~/.config/systemd/user/trackpad-fast-reconnect.service`

## License

MIT License

## Credits

Created to solve the common Magic Trackpad freezing issue on Linux systems.

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.
