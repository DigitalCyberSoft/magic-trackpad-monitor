# Makefile for Magic Trackpad Monitor
# Supports building, installing, and packaging

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share
SERVICEDIR ?= $(HOME)/.config/systemd/user

VERSION ?= 0.2.2
PACKAGE_NAME = magic-trackpad-monitor

# Detect architecture
ARCH := $(shell uname -m)

.PHONY: all build install uninstall clean rpm deb help

all: build

help:
	@echo "Magic Trackpad Monitor - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  build      - Compile xidle binary"
	@echo "  install    - Install to system (PREFIX=$(PREFIX))"
	@echo "  uninstall  - Remove from system"
	@echo "  rpm        - Build RPM package"
	@echo "  deb        - Build DEB package (requires alien)"
	@echo "  clean      - Remove build artifacts"
	@echo "  help       - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX     - Installation prefix (default: /usr/local)"
	@echo "  BINDIR     - Binary installation directory (default: PREFIX/bin)"
	@echo "  VERSION    - Package version (default: 0.1.0)"

build: xidle
	@echo "Build complete"

xidle: xidle.c
	@echo "Compiling xidle for $(ARCH)..."
	gcc -o xidle xidle.c -lX11 -lXss
	@echo "xidle compiled successfully"

install: build
	@echo "Installing Magic Trackpad Monitor..."

	# Install binaries
	install -D -m 755 trackpad-monitor.sh $(DESTDIR)$(BINDIR)/trackpad-monitor
	install -D -m 755 magic-trackpad-status $(DESTDIR)$(BINDIR)/magic-trackpad-status
	install -D -m 755 xidle $(DESTDIR)$(BINDIR)/xidle

	# Install default config
	install -D -m 644 config.default $(DESTDIR)$(DATADIR)/$(PACKAGE_NAME)/config.default

	# Install systemd user service (only for non-package installs)
	@if [ -z "$(DESTDIR)" ]; then \
		mkdir -p $(SERVICEDIR); \
		install -D -m 644 magic-trackpad-monitor.service $(SERVICEDIR)/magic-trackpad-monitor.service; \
		echo "Systemd user service installed to $(SERVICEDIR)"; \
		echo ""; \
		echo "To enable and start the service:"; \
		echo "  systemctl --user daemon-reload"; \
		echo "  systemctl --user enable magic-trackpad-monitor.service"; \
		echo "  systemctl --user start magic-trackpad-monitor.service"; \
	fi

	@echo ""
	@echo "Installation complete!"
	@echo "Configuration will be created at: ~/.config/trackpad-monitor/config"

uninstall:
	@echo "Uninstalling Magic Trackpad Monitor..."

	# Stop and disable service if running
	@if systemctl --user is-active magic-trackpad-monitor.service &>/dev/null; then \
		systemctl --user stop magic-trackpad-monitor.service; \
		echo "Service stopped"; \
	fi
	@if systemctl --user is-enabled magic-trackpad-monitor.service &>/dev/null; then \
		systemctl --user disable magic-trackpad-monitor.service; \
		echo "Service disabled"; \
	fi

	# Remove files
	rm -f $(BINDIR)/trackpad-monitor
	rm -f $(BINDIR)/magic-trackpad-status
	rm -f $(BINDIR)/xidle
	rm -rf $(DATADIR)/$(PACKAGE_NAME)
	rm -f $(SERVICEDIR)/magic-trackpad-monitor.service

	@echo "Uninstall complete"
	@echo "User data preserved in: ~/.config/trackpad-monitor/ and ~/.local/share/trackpad-monitor/"

clean:
	@echo "Cleaning build artifacts..."
	rm -f xidle
	rm -f *.rpm *.deb *.tar.gz
	rm -rf rpmbuild/
	@echo "Clean complete"

# RPM packaging target
rpm: build
	@echo "Building RPM package..."
	@if ! command -v rpmbuild >/dev/null 2>&1; then \
		echo "ERROR: rpmbuild not found. Install rpm-build package."; \
		exit 1; \
	fi

	# Create rpmbuild directory structure
	mkdir -p rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

	# Create source tarball
	tar czf rpmbuild/SOURCES/$(PACKAGE_NAME)-$(VERSION).tar.gz \
		--transform 's,^,$(PACKAGE_NAME)-$(VERSION)/,' \
		trackpad-monitor.sh magic-trackpad-status xidle.c config.default \
		magic-trackpad-monitor.service README.md xidle

	# Generate spec file
	sed -e 's/@VERSION@/$(VERSION)/g' \
	    -e 's/@PACKAGE_NAME@/$(PACKAGE_NAME)/g' \
	    magic-trackpad-monitor.spec > rpmbuild/SPECS/$(PACKAGE_NAME).spec

	# Build RPM
	rpmbuild --define "_topdir $(PWD)/rpmbuild" \
		-ba rpmbuild/SPECS/$(PACKAGE_NAME).spec

	# Copy RPM to current directory
	cp rpmbuild/RPMS/$(ARCH)/$(PACKAGE_NAME)-$(VERSION)-*.rpm .
	cp rpmbuild/SRPMS/$(PACKAGE_NAME)-$(VERSION)-*.src.rpm .

	@echo ""
	@echo "RPM packages built:"
	@ls -lh $(PACKAGE_NAME)-$(VERSION)-*.rpm

# DEB packaging target (using alien)
deb: rpm
	@echo "Building DEB package from RPM..."
	@if ! command -v alien >/dev/null 2>&1; then \
		echo "ERROR: alien not found. Install with: sudo apt install alien (Debian/Ubuntu) or sudo dnf install alien (Fedora)"; \
		exit 1; \
	fi

	# Convert RPM to DEB
	fakeroot alien --to-deb --scripts $(PACKAGE_NAME)-$(VERSION)-*.$(ARCH).rpm

	@echo ""
	@echo "DEB package built:"
	@ls -lh $(PACKAGE_NAME)_$(VERSION)-*.deb
