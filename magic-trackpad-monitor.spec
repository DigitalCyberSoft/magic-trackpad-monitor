%global _hardened_build 1
%global debug_package %{nil}

Name:           magic-trackpad-monitor
Version:        @VERSION@
Release:        1%{?dist}
Summary:        Automatic monitoring and reconnection service for Apple Magic Trackpad on Linux

License:        MIT
URL:            https://github.com/DigitalCyberSoft/magic-trackpad-monitor
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  systemd-rpm-macros
%if ! 0%{?rhel} >= 10
# X11 libraries not available on RHEL 10
BuildRequires:  libXScrnSaver-devel
%endif

Requires:       bluez
Requires:       systemd
%if ! 0%{?rhel} >= 10
# X11 dependencies not required on RHEL 10
Requires:       xinput
Requires:       libXScrnSaver
%endif

%description
Magic Trackpad Monitor is an automatic monitoring and reconnection service
for Apple Magic Trackpad on Linux systems. It continuously monitors the
trackpad's Bluetooth connection status, detects when the user is active
using X11 idle time, and automatically reconnects the trackpad when it
disconnects or appears stuck.

Features:
- Automatic trackpad reconnection on disconnect
- Smart idle detection (only monitors when user is active)
- Bluetooth adapter power cycling for recovery
- Configurable check intervals and thresholds
- XDG-compliant configuration and data storage

%prep
%setup -q

%build
# Compile xidle (skip on RHEL 10 where X11 libs may not be available)
%if ! 0%{?rhel} >= 10
gcc -o xidle xidle.c -lX11 -lXss
%endif

%install
# Create directories
install -d %{buildroot}%{_bindir}
install -d %{buildroot}%{_datadir}/%{name}
install -d %{buildroot}%{_userunitdir}

# Install binaries
install -D -m 755 trackpad-monitor.sh %{buildroot}%{_bindir}/trackpad-monitor
install -D -m 755 magic-trackpad-status %{buildroot}%{_bindir}/magic-trackpad-status
%if ! 0%{?rhel} >= 10
install -D -m 755 xidle %{buildroot}%{_bindir}/xidle
%endif

# Install default config
install -D -m 644 config.default %{buildroot}%{_datadir}/%{name}/config.default

# Install systemd user service
install -D -m 644 magic-trackpad-monitor.service %{buildroot}%{_userunitdir}/magic-trackpad-monitor.service

%files
%doc README.md
%{_bindir}/trackpad-monitor
%{_bindir}/magic-trackpad-status
%if ! 0%{?rhel} >= 10
%{_bindir}/xidle
%endif
%{_datadir}/%{name}/config.default
%{_userunitdir}/magic-trackpad-monitor.service

%post
echo ""
echo "Magic Trackpad Monitor installed successfully!"
echo ""
echo "To enable and start the service:"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user enable magic-trackpad-monitor.service"
echo "  systemctl --user start magic-trackpad-monitor.service"
echo ""
echo "Configuration file will be created at: ~/.config/trackpad-monitor/config"
echo "Check status with: magic-trackpad-status"
echo ""

%preun
# Stop service before uninstall
if systemctl --user is-active magic-trackpad-monitor.service &>/dev/null; then
    systemctl --user stop magic-trackpad-monitor.service
fi

%postun
# Clean up on uninstall (not upgrade)
if [ $1 -eq 0 ]; then
    systemctl --user daemon-reload
    echo "User data preserved in ~/.config/trackpad-monitor/ and ~/.local/share/trackpad-monitor/"
fi

%changelog
* Wed Nov 19 2025 Builder - @VERSION@-1
- Initial package release
- XDG-compliant configuration and data directories
- Pre-compiled xidle binary included
- Systemd user service for automatic startup
