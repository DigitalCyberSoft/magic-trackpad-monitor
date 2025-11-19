# Packaging Guide for Magic Trackpad Monitor

This document explains how to build and distribute packages for Magic Trackpad Monitor.

## Overview

The project supports three packaging methods:
1. **RPM** - For Fedora, RHEL, CentOS, and other RPM-based distributions
2. **DEB** - For Ubuntu, Debian, and other Debian-based distributions (via alien)
3. **COPR** - For automated builds in Fedora's COPR repository system

## Prerequisites

### For RPM Building
```bash
# Fedora
sudo dnf install rpm-build rpmlint gcc libXScrnSaver-devel

# RHEL/CentOS
sudo yum install rpm-build rpmlint gcc libXScrnSaver-devel
```

### For DEB Building
```bash
# Install alien (converts RPM to DEB)
sudo dnf install alien  # Fedora
sudo apt install alien  # Ubuntu/Debian
```

## Building Packages Locally

### Build RPM Package

1. Ensure you're in the project root directory
2. Run the build command:
```bash
make rpm
```

This will:
- Compile xidle
- Create a source tarball
- Generate the RPM spec file with version substitution
- Build both binary RPM and source RPM
- Place packages in the current directory

Output files:
- `magic-trackpad-monitor-0.1.0-1.fc42.x86_64.rpm` - Binary package
- `magic-trackpad-monitor-0.1.0-1.fc42.src.rpm` - Source package

### Build DEB Package

1. First build the RPM (see above)
2. Convert to DEB using alien:
```bash
make deb
```

This will:
- Use the previously built RPM
- Convert it to DEB format using alien
- Preserve scripts and dependencies

Output file:
- `magic-trackpad-monitor_0.1.0-2_amd64.deb`

### Test Packages Locally

#### Test RPM
```bash
# Install
sudo dnf install ./magic-trackpad-monitor-*.rpm

# Test
magic-trackpad-status
systemctl --user status magic-trackpad-monitor.service

# Uninstall
sudo dnf remove magic-trackpad-monitor
```

#### Test DEB
```bash
# Install
sudo apt install ./magic-trackpad-monitor_*.deb

# Test
magic-trackpad-status
systemctl --user status magic-trackpad-monitor.service

# Uninstall
sudo apt remove magic-trackpad-monitor
```

## COPR Repository Setup

COPR (Cool Other Package Repo) is Fedora's build system for third-party packages.

### Initial COPR Setup

1. Create a COPR account at https://copr.fedorainfracloud.org/
2. Create a new project named `magic-trackpad-monitor`
3. Configure the project:
   - **Chroots**: Select Fedora versions to support (e.g., Fedora 40, 41, 42)
   - **Build source**: Custom
   - **Instructions**: Leave blank (we use Makefile)

### Configure Git Repository for COPR

1. Push your code to a Git repository (GitHub, GitLab, etc.)
2. Tag a release:
```bash
git tag -a v0.1.0 -m "Initial release"
git push origin v0.1.0
```

### Configure COPR to Build from Git

1. In COPR project settings, configure "Source":
   - **Type**: Custom script or Makefile
   - **Script**: Uses `.copr/Makefile`
   - **Repository URL**: Your git repository URL

2. The `.copr/Makefile` will:
   - Detect the version from git tags
   - Install build dependencies
   - Compile xidle
   - Create source tarball
   - Generate spec file
   - Build SRPM

### Trigger COPR Build

#### Manual Build via Web Interface
1. Go to your COPR project
2. Click "New Build"
3. Select "Custom" source
4. Enter your Git repository URL and commit/tag
5. Click "Build"

#### Automatic Builds on Git Push
Configure webhook in your Git repository:
1. Get webhook URL from COPR project settings
2. Add webhook to your Git repository settings
3. Every push/tag will trigger a build

### Using COPR Repository

Once built, users can install from your COPR:

```bash
# Enable repository
sudo dnf copr enable yourusername/magic-trackpad-monitor

# Install package
sudo dnf install magic-trackpad-monitor
```

## Version Management

### Updating Version

1. Update version in these files:
   - `Makefile` - Set `VERSION` variable
   - `magic-trackpad-monitor.spec` - Update `Version:` field (or use @VERSION@ placeholder)

2. Tag the release:
```bash
git tag -a v0.2.0 -m "Version 0.2.0 - New features..."
git push origin v0.2.0
```

3. Build packages with new version:
```bash
VERSION=0.2.0 make rpm
VERSION=0.2.0 make deb
```

### Release Numbering

The release number in COPR is automatically incremented:
- `.copr/Makefile` queries existing builds
- Finds the highest release number for the current version
- Increments by 1

Example:
- First build of 0.1.0: `magic-trackpad-monitor-0.1.0-1.fc42`
- Rebuild (same version): `magic-trackpad-monitor-0.1.0-2.fc42`
- New version: `magic-trackpad-monitor-0.2.0-1.fc42`

## Multi-Architecture Support

### Building for Different Architectures

The package supports x86_64 and aarch64 (ARM64).

For COPR:
- Enable additional chroots in project settings
- COPR builds for all enabled architectures automatically

For local builds:
```bash
# Current architecture (automatic)
make rpm

# For specific architecture (requires cross-compilation setup)
rpmbuild --target=aarch64 ...
```

## Package Contents

### Files Installed

| File | Location | Description |
|------|----------|-------------|
| trackpad-monitor | /usr/bin/ | Main monitoring script |
| magic-trackpad-status | /usr/bin/ | Status checker |
| xidle | /usr/bin/ | X11 idle detector |
| config.default | /usr/share/magic-trackpad-monitor/ | Default configuration |
| magic-trackpad-monitor.service | /usr/lib/systemd/user/ | Systemd service |

### User-Specific Files (created at runtime)

| File | Location | Description |
|------|----------|-------------|
| config | ~/.config/trackpad-monitor/ | User configuration |
| last-connected | ~/.local/share/trackpad-monitor/ | Connection timestamp |
| device-mac-cache | ~/.local/share/trackpad-monitor/ | Cached device MAC |

## Debugging Package Builds

### Check RPM Contents
```bash
rpm -qlp magic-trackpad-monitor-*.rpm
```

### Check RPM Dependencies
```bash
rpm -qRp magic-trackpad-monitor-*.rpm
```

### Verify RPM Scripts
```bash
rpm -qp --scripts magic-trackpad-monitor-*.rpm
```

### Test in Clean Environment
```bash
# Using mock (Fedora)
mock -r fedora-42-x86_64 rebuild magic-trackpad-monitor-*.src.rpm
```

## Distribution-Specific Notes

### Fedora
- Uses `/usr/lib/systemd/user/` for user services
- Package name: `magic-trackpad-monitor`

### Ubuntu/Debian
- Alien converts paths automatically
- May need manual dependency adjustment in some cases
- Service files work the same way via systemd

### RHEL/CentOS
- Requires EPEL repository for some dependencies
- `.copr/Makefile` automatically enables EPEL

## Troubleshooting

### Build Fails in COPR

Check build logs in COPR web interface:
1. Click on failed build
2. View "build.log.gz"
3. Look for compilation or dependency errors

Common issues:
- Missing build dependencies (add to spec file)
- Compilation errors (test locally first)
- Network issues (COPR builders have limited network access)

### RPM Lint Warnings

Run rpmlint to check for issues:
```bash
rpmlint magic-trackpad-monitor-*.rpm
```

Common warnings:
- `no-manual-page-for-binary` - OK for simple scripts
- `systemd-service-file-outside-var-run` - OK, we use user services

## Best Practices

1. **Test locally before COPR**: Always test RPM builds locally
2. **Version tags**: Use semantic versioning (v0.1.0, v0.2.0, etc.)
3. **Changelog**: Update spec file changelog for each release
4. **Dependencies**: Declare all runtime dependencies in spec
5. **Clean builds**: Test in clean environment (mock or COPR)

## References

- [Fedora Packaging Guidelines](https://docs.fedoraproject.org/en-US/packaging-guidelines/)
- [COPR Documentation](https://docs.pagure.org/copr.copr/)
- [RPM Packaging Guide](https://rpm-packaging-guide.github.io/)
- [Alien User's Guide](https://man7.org/linux/man-pages/man1/alien.1p.html)
