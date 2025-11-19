#!/bin/bash

# Magic Trackpad Monitor Installation Script
# Universal installer for Fedora, Ubuntu, and other Linux distributions

set -e

PACKAGE_NAME="magic-trackpad-monitor"
VERSION="0.1.0"
INSTALL_PREFIX="${PREFIX:-$HOME/.local}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    else
        DISTRO="unknown"
    fi

    log_info "Detected distribution: $DISTRO"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install dependencies
install_dependencies() {
    log_info "Checking and installing dependencies..."

    local missing_deps=()

    # Check for required runtime dependencies
    if ! command_exists bluetoothctl; then
        missing_deps+=("bluez")
    fi

    if ! command_exists xinput; then
        missing_deps+=("xinput")
    fi

    # Check for build dependencies (for compiling xidle)
    if ! command_exists gcc; then
        missing_deps+=("gcc")
    fi

    if [ ${#missing_deps[@]} -eq 0 ]; then
        log_success "All dependencies are already installed"
        return 0
    fi

    log_warning "Missing dependencies: ${missing_deps[*]}"

    # Ask user if they want to install dependencies
    read -p "Install missing dependencies? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Dependencies required. Exiting."
        exit 1
    fi

    case "$DISTRO" in
        fedora|rhel|centos|rocky|almalinux)
            log_info "Installing dependencies with DNF/YUM..."
            if command_exists dnf; then
                sudo dnf install -y bluez xinput gcc
                sudo dnf install -y libXScrnSaver-devel || sudo dnf install -y libXss-devel
            else
                sudo yum install -y bluez xinput gcc
                sudo yum install -y libXScrnSaver-devel || sudo yum install -y libXss-devel
            fi
            ;;
        ubuntu|debian|pop)
            log_info "Installing dependencies with APT..."
            sudo apt update
            sudo apt install -y bluez xinput gcc libxss-dev libx11-dev
            ;;
        arch|manjaro)
            log_info "Installing dependencies with pacman..."
            sudo pacman -S --needed --noconfirm bluez xorg-xinput gcc libxss
            ;;
        opensuse*|sles)
            log_info "Installing dependencies with zypper..."
            sudo zypper install -y bluez xinput gcc
            sudo zypper install -y libXScrnSaver-devel || sudo zypper install -y libXss-devel
            ;;
        *)
            log_error "Unsupported distribution: $DISTRO"
            log_info "Please manually install: bluez, xinput, gcc, libXScrnSaver-devel or libXss-devel"
            exit 1
            ;;
    esac

    log_success "Dependencies installed successfully"
}

# Build xidle
build_xidle() {
    log_info "Compiling xidle..."

    if [ ! -f xidle.c ]; then
        log_error "xidle.c not found in current directory"
        exit 1
    fi

    gcc -o xidle xidle.c -lX11 -lXss

    if [ $? -eq 0 ]; then
        log_success "xidle compiled successfully"
    else
        log_error "Failed to compile xidle"
        exit 1
    fi
}

# Install files
install_files() {
    log_info "Installing files to $INSTALL_PREFIX..."

    # Create directories
    mkdir -p "$INSTALL_PREFIX/bin"
    mkdir -p "$INSTALL_PREFIX/share/$PACKAGE_NAME"
    mkdir -p "$HOME/.config/systemd/user"

    # Install binaries
    install -m 755 trackpad-monitor.sh "$INSTALL_PREFIX/bin/trackpad-monitor"
    install -m 755 magic-trackpad-status "$INSTALL_PREFIX/bin/magic-trackpad-status"
    install -m 755 xidle "$INSTALL_PREFIX/bin/xidle"

    # Install default config
    install -m 644 config.default "$INSTALL_PREFIX/share/$PACKAGE_NAME/config.default"

    # Install systemd service
    install -m 644 magic-trackpad-monitor.service "$HOME/.config/systemd/user/magic-trackpad-monitor.service"

    log_success "Files installed successfully"
}

# Setup systemd service
setup_service() {
    log_info "Setting up systemd user service..."

    # Reload systemd
    systemctl --user daemon-reload

    # Ask if user wants to enable service
    read -p "Enable service to start on login? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        systemctl --user enable magic-trackpad-monitor.service
        log_success "Service enabled"

        # Ask if user wants to start service now
        read -p "Start service now? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            systemctl --user start magic-trackpad-monitor.service
            log_success "Service started"
        fi
    fi
}

# Uninstall function
uninstall() {
    log_info "Uninstalling Magic Trackpad Monitor..."

    # Stop and disable service
    if systemctl --user is-active magic-trackpad-monitor.service &>/dev/null; then
        systemctl --user stop magic-trackpad-monitor.service
        log_info "Service stopped"
    fi

    if systemctl --user is-enabled magic-trackpad-monitor.service &>/dev/null; then
        systemctl --user disable magic-trackpad-monitor.service
        log_info "Service disabled"
    fi

    # Remove files
    rm -f "$INSTALL_PREFIX/bin/trackpad-monitor"
    rm -f "$INSTALL_PREFIX/bin/magic-trackpad-status"
    rm -f "$INSTALL_PREFIX/bin/xidle"
    rm -rf "$INSTALL_PREFIX/share/$PACKAGE_NAME"
    rm -f "$HOME/.config/systemd/user/magic-trackpad-monitor.service"

    systemctl --user daemon-reload

    log_success "Uninstall complete"
    log_info "User data preserved in: ~/.config/trackpad-monitor/ and ~/.local/share/trackpad-monitor/"

    # Ask if user wants to remove user data
    read -p "Remove user data (config and cache)? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$HOME/.config/trackpad-monitor"
        rm -rf "$HOME/.local/share/trackpad-monitor"
        log_success "User data removed"
    fi
}

# Main installation function
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║   Magic Trackpad Monitor Installer v$VERSION          ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""

    # Check if uninstall flag is provided
    if [ "$1" = "--uninstall" ] || [ "$1" = "-u" ]; then
        uninstall
        exit 0
    fi

    # Show help
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h        Show this help message"
        echo "  --uninstall, -u   Uninstall Magic Trackpad Monitor"
        echo ""
        echo "Environment Variables:"
        echo "  PREFIX            Installation prefix (default: \$HOME/.local)"
        echo ""
        echo "Examples:"
        echo "  $0                      # Install to ~/.local"
        echo "  PREFIX=/usr/local $0    # Install system-wide (requires sudo)"
        echo "  $0 --uninstall          # Uninstall"
        exit 0
    fi

    # Detect distribution
    detect_distro

    # Install dependencies
    install_dependencies

    # Build xidle
    build_xidle

    # Install files
    install_files

    # Setup service
    setup_service

    echo ""
    log_success "Installation complete!"
    echo ""
    log_info "Commands:"
    log_info "  magic-trackpad-status                      - Check trackpad status"
    log_info "  systemctl --user status magic-trackpad-monitor.service"
    log_info "  systemctl --user stop magic-trackpad-monitor.service"
    log_info "  systemctl --user restart magic-trackpad-monitor.service"
    echo ""
    log_info "Configuration: ~/.config/trackpad-monitor/config"
    log_info "Logs: journalctl --user -u magic-trackpad-monitor.service -f"
    echo ""

    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        log_warning "~/.local/bin is not in your PATH"
        log_info "Add this to your ~/.bashrc or ~/.zshrc:"
        echo ""
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
    fi
}

# Run main function
main "$@"
