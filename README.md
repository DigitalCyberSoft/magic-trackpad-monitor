# Magic Trackpad Monitor

Automatic monitoring and reconnection service for Apple Magic Trackpad on Linux systems.

## Features

- **Dynamic Device Discovery** - Automatically finds any paired Magic Trackpad
- **Smart Idle Detection** - Only monitors when user is active (keyboard idle < 10 minutes)
- **Stuck Device Recovery** - Detects frozen trackpad and power cycles Bluetooth adapter
- **Last Connection Tracking** - Tracks when trackpad was last successfully connected
- **XDG-Compliant** - Configuration in `~/.config/trackpad-monitor/`, data in `~/.local/share/trackpad-monitor/`
- **Display Server Support** - Works on both **X11/Xorg** and **Wayland** with automatic detection
- **Easy Packaging** - RPM, DEB, and bash installer support

## Components

- **trackpad-monitor** - Main monitoring script
- **trackpad-status** - Status checker command-line tool
- **xidle** - X11 idle time detector (lightweight xprintidle alternative)
- **magic-trackpad-monitor.service** - systemd user service file

## Installation

### Option 1: Package Manager (Recommended)

#### Fedora/RHEL/CentOS (RPM)
```bash
# From COPR repository (once published)
sudo dnf copr enable DigitalCyberSoft/magic-trackpad-monitor
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
git clone https://github.com/DigitalCyberSoft/magic-trackpad-monitor.git
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
systemctl --user enable magic-trackpad-monitor.service
systemctl --user start magic-trackpad-monitor.service
```

### Post-Installation

After installing via any method, you have two options to set up the service:

#### Option A: Interactive Setup (Easiest)
Simply run `trackpad-status` and it will guide you through the setup:
```bash
trackpad-status
```

If the service isn't installed, enabled, or running, `trackpad-status` will detect this and offer to:
- Install the service for your user
- Enable it to start on login
- Start it immediately

#### Option B: Manual Setup
Manually enable and start the service:
```bash
systemctl --user daemon-reload
systemctl --user enable magic-trackpad-monitor.service
systemctl --user start magic-trackpad-monitor.service
```

### Verifying Installation

Check that everything is working:
```bash
# Check service status (interactive helper)
trackpad-status

# Or check manually
systemctl --user status magic-trackpad-monitor.service

# View live logs
journalctl --user -u magic-trackpad-monitor.service -f
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
journalctl --user -u magic-trackpad-monitor.service -f
```

### Manually Control Service
```bash
systemctl --user status magic-trackpad-monitor.service
systemctl --user restart magic-trackpad-monitor.service
systemctl --user stop magic-trackpad-monitor.service
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

# Display server detection (auto, x11, wayland, fallback)
DISPLAY_SERVER=auto
```

After editing the config, restart the service:
```bash
systemctl --user restart magic-trackpad-monitor.service
```

## Display Server Support

Magic Trackpad Monitor automatically detects and adapts to your display server (X11 or Wayland).

### Supported Display Servers

✅ **X11/Xorg** (Full support)
- Precise idle detection (millisecond accuracy via xidle)
- Complete stuck detection (xinput device status)
- Works on all X11-based desktops

✅ **Wayland** (Full support with adaptations)
- Idle detection via systemd-logind
- Device presence detection via /proc
- Simplified stuck detection
- Tested on: GNOME, KDE Plasma, Sway

✅ **Fallback Mode**
- Uses /dev/input monitoring when display server unknown
- Works without X11 or Wayland

### Detection Method

The monitor automatically detects your display server using (in order):
1. `$XDG_SESSION_TYPE` environment variable
2. `$WAYLAND_DISPLAY` and `$DISPLAY` sockets
3. `loginctl` session type query

You can override detection by setting `DISPLAY_SERVER` in the config.

### X11 vs Wayland Differences

| Feature | X11 | Wayland |
|---------|-----|---------|
| Idle Detection | Millisecond precision (xidle) | ~5min threshold (logind) |
| Device Stuck Detection | Full (xinput properties) | Simplified (presence only) |
| Reconnection | ✅ Identical | ✅ Identical |
| Bluetooth Control | ✅ Identical | ✅ Identical |

**Note:** The 10-minute idle threshold works well with both X11's precise detection and Wayland's coarser-grained system idle hints.

### Dependencies by Display Server

**X11:**
- `xinput` - Input device management
- `xidle` - Idle time detection (included in package)
- `libXScrnSaver` - X11 Screen Saver extension

**Wayland:**
- `systemd` - For logind idle detection (standard on modern Linux)
- `/proc/bus/input/devices` - For device detection (kernel interface)

**Both:**
- `bluetoothctl` - Bluetooth management (BlueZ)

## Troubleshooting

### Service won't start
Check logs:
```bash
journalctl --user -u magic-trackpad-monitor.service -n 50
```

### Trackpad not found
Ensure it's paired:
```bash
bluetoothctl devices | grep -i "magic trackpad"
```

### xidle not working (X11 only)
Test manually:
```bash
~/.local/bin/xidle
```
Should return idle time in milliseconds.

**Note:** xidle is only used on X11. On Wayland, systemd-logind is used instead.

### Check which display server is detected
View the service logs to see which display server was detected:
```bash
journalctl --user -u magic-trackpad-monitor.service | grep "Detected display server"
```

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

### Core Requirements (All Platforms)
- Linux with systemd
- BlueZ 5.x (bluez package)

### Display Server Specific

**X11/Xorg:**
- xinput - Input device management
- libXScrnSaver - For xidle idle detection
- xidle (included in package)

**Wayland:**
- systemd-logind (standard on modern Linux)
- Kernel with /proc/bus/input/devices support (standard)

### Build Requirements (Source Only)
- gcc - C compiler
- libXScrnSaver-devel / libxss-dev - For compiling xidle

## File Locations

- **Binaries**: `~/.local/bin/` or `/usr/bin/` or `/usr/local/bin/`
- **Configuration**: `~/.config/trackpad-monitor/config`
- **Data/Cache**: `~/.local/share/trackpad-monitor/`
- **Service**: `~/.config/systemd/user/magic-trackpad-monitor.service`

## License

MIT License

## Credits

Created to solve the common Magic Trackpad freezing issue on Linux systems.

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.
