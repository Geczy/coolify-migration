# Coolify Migration Script

A comprehensive bash script to backup and migrate your entire Coolify instance from one server to another. This script handles Docker volumes, the Coolify database, SSH keys, and all associated data.

**Run this script on the source server**—the server that currently has Coolify running. Do not run it from your laptop or from the destination server.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Reset Target (Re-testing)](#reset-target-re-testing)
- [What Gets Migrated](#what-gets-migrated)
- [How It Works](#how-it-works)
- [Supported Operating Systems](#supported-operating-systems)
- [Troubleshooting](#troubleshooting)
- [Safety Considerations](#safety-considerations)
- [Contributing](#contributing)
- [License](#license)

## 🎯 Overview

This script automates the complete migration of a Coolify instance, including:
- All Docker volumes from running containers
- Coolify database and configuration files
- SSH authorized keys
- Complete data integrity preservation

The script runs on the **source server** and transfers everything to the **destination server** via SSH.

## ✨ Features

- **Automatic Docker Volume Detection**: Automatically discovers and backs up all volumes from running containers
- **Parallel Compression**: Uses `pigz` (parallel gzip) for faster backups when available, with automatic fallback to `gzip`
- **Auto-Installation**: Can automatically install `pigz` if not present (supports multiple package managers)
- **Interactive Configuration**: Auto-detects SSH key from `~/.ssh`; full SSH target (user@host) is a required command-line argument
- **Comprehensive Error Handling**: Validates prerequisites and provides clear error messages
- **SSH Key Merging**: Safely merges existing SSH keys on destination server
- **Automatic Coolify Installation**: Installs Coolify on the destination server if needed
- **Size Reporting**: Shows total size of data to be migrated before starting
- **Safe Operations**: Includes confirmation prompts for critical operations

## 📦 Prerequisites

### Source Server Requirements

- Bash shell
- Docker installed and running
- SSH access to destination server
- Sufficient disk space for backup file
- Root or sudo access (for stopping Docker if needed)

### Destination Server Requirements

- Root SSH access
- Sufficient disk space for all migrated data
- Internet connection (for Coolify installation)

### Network Requirements

- SSH connectivity from source to destination server
- SSH key-based authentication configured

## 🚀 Installation

On the **source server** (where Coolify currently runs), do the following:

1. Clone or download this repository:
```bash
git clone https://github.com/rogerb831/coolify-migration.git
cd coolify-migration
```

2. Make the scripts executable:
```bash
chmod +x migrate.sh reset-target.sh
```

3. Edit the configuration section (optional - you can also be prompted at runtime):
```bash
nano migrate.sh
```

## ⚙️ Configuration

The script requires the **full SSH target** (user@host) as a command-line argument. No user is assumed. The SSH key is auto-detected from `~/.ssh` (or can be set in the script).

```bash
./migrate.sh USER@HOST
```

Example: `./migrate.sh root@server.example.com`

**Optional**: You can set `sshKeyPath` in the script if you want to use a specific key instead of auto-detection.

### Additional Configuration

The script uses these default paths (can be modified in the script):
- **Backup source directory**: `/data/coolify/`
- **Backup filename**: `coolify_backup.tar.gz` (created in current directory)

## 📖 Usage

### Basic Usage

**Run the script on the source server** (the machine that currently runs Coolify).

1. **Ensure all containers you want to migrate are running** on the source server.

2. **From the source server**, run the script with the full SSH target (user@host) as the first argument:
```bash
./migrate.sh root@server.example.com
```

Or with another user and hostname:
```bash
./migrate.sh deploy@coolify-dest.mycompany.com
```

Use `./migrate.sh --help` to show usage and options (e.g. `--no-strict-host-key`).

3. **Follow the interactive prompts**:
   - SSH key is auto-detected from `~/.ssh` (or use one set in the script)
   - Choose whether to install `pigz` if not available
   - Confirm Docker stop (recommended for data consistency)
   - Confirm backup file cleanup after migration

### Step-by-Step Process

1. **Argument Check**: Full SSH target (user@host) is required as first argument; SSH key is auto-detected from `~/.ssh`
2. **Pigz Detection**: Checks for `pigz` and offers auto-installation if missing
3. **Prerequisites Validation**: 
   - Verifies source directory exists
   - Checks SSH key file exists
   - Tests SSH connectivity to destination
4. **Docker Volume Discovery**: Scans all running containers for volumes
5. **Size Calculation**: Reports total data size to be migrated
6. **Backup Creation**: 
   - Optionally stops Docker for consistency
   - Creates compressed backup archive
7. **Remote Transfer**: 
   - Transfers backup to destination server
   - Extracts files
   - Merges SSH keys
   - Installs/updates Coolify
8. **Cleanup**: Optionally removes local backup file

## 🔄 Reset Target (Re-testing)

To run the migration again against the same destination, reset the **target** server first. Use the included `reset-target.sh` script. The target is left with **no Coolify and no Docker**, as it would be before any install.

**Same as migration:** Run `reset-target.sh` **on the source** (the machine you run `migrate.sh` from). Pass the **target** as `USER@HOST`. The script SSHs to the target and performs the reset there.

### What the reset script does (on the target)

- Stops and removes all containers (Coolify and everything else)
- Stops the Docker daemon
- Removes `/data/coolify` (Coolify config, compose files, app data)
- Removes all Docker data (`/var/lib/docker`, `/var/lib/containerd`, `/etc/docker`)
- Uninstalls Docker packages (Debian/Ubuntu, RHEL/Fedora, SUSE, Arch, Alpine)

After the reset, the target has no Coolify and no Docker. The next migration will install Docker again (via the Coolify install script) and then restore your data.

### How to run it

From the **source** server (same as for migration):

```bash
./reset-target.sh USER@HOST
```

Example:

```bash
./reset-target.sh root@server.example.com
```

You must type **DESTROY** (all caps) when prompted to confirm. Options:

- `--yes` — Skip confirmation (e.g. for automation)
- `--no-strict-host-key` — Disable SSH host key verification

```bash
./reset-target.sh --help
```

After the reset, the target has no Coolify and no Docker; you can run `./migrate.sh USER@TARGET` from the source again for a clean re-test (the migration will install Docker and Coolify on the target).

## 📦 What Gets Migrated

The script migrates the following:

### 1. Coolify Data Directory
- Location: `/data/coolify/`
- Contains: Database, configuration files, application data

### 2. Docker Volumes
- All volumes attached to running containers
- Location: `/var/lib/docker/volumes/`
- Automatically discovered from running containers

### 3. SSH Authorized Keys
- Source: `~/.ssh/authorized_keys`
- Safely merged with existing keys on destination server

## 🔧 How It Works

### Backup Process

1. **Volume Discovery**: 
   - Lists all running Docker containers
   - Inspects each container for mounted volumes
   - Collects volume paths

2. **Compression**:
   - Uses `pigz` (parallel gzip) if available for faster compression
   - Falls back to `gzip` if `pigz` is not available
   - Excludes socket files (`*.sock`) from backup
   - Suppresses file-changed warnings during compression

3. **Archive Creation**:
   - Creates a tar archive with all data
   - Compresses using the selected compressor
   - Saves as `coolify_backup.tar.gz`

### Migration Process

1. **Transfer**:
   - Streams backup file to destination via SSH
   - Uses stdin/stdout for efficient transfer

2. **Extraction**:
   - Stops Docker on destination (if running as service)
   - Extracts backup archive
   - Detects and uses `pigz` for decompression if available

3. **SSH Key Management**:
   - Backs up existing authorized_keys
   - Merges with new keys from source
   - Removes duplicates
   - Sets proper permissions

4. **Coolify Installation**:
   - Installs curl if needed (with OS detection)
   - Runs official Coolify installation script
   - Ensures Coolify is ready to use

## 🖥️ Supported Operating Systems

The script supports auto-installation of `pigz` on:

- **Debian/Ubuntu/Raspberry Pi OS**: Uses `apt-get`
- **Red Hat/CentOS/Fedora**: Uses `yum` or `dnf`
- **SUSE/openSUSE**: Uses `zypper`
- **Arch Linux**: Uses `pacman`
- **Alpine Linux**: Uses `apk`

For other distributions, you can manually install `pigz` or the script will use `gzip` as fallback.

## 🐛 Troubleshooting

### Common Issues

#### "SSH connection failed"
- **Cause**: Network connectivity or authentication issues
- **Solution**: 
  - Verify destination server is reachable
  - Check SSH key permissions: `chmod 600 your_key`
  - Test SSH manually: `ssh -i your_key user@destination`

#### "Source directory does not exist"
- **Cause**: Coolify data directory not at `/data/coolify/`
- **Solution**: Modify `backupSourceDir` variable in the script

#### "Docker is not installed"
- **Cause**: Docker not in PATH or not installed
- **Solution**: Install Docker or ensure it's in your PATH

#### "Failed to install pigz"
- **Cause**: Package manager issues or insufficient permissions
- **Solution**: 
  - Install manually: `sudo apt-get install pigz` (or equivalent)
  - Or continue with `gzip` (slower but functional)

#### "Backup file creation failed"
- **Cause**: Insufficient disk space or permission issues
- **Solution**: 
  - Check available disk space: `df -h`
  - Ensure write permissions in current directory
  - Check if backup file already exists and remove if needed

#### "Container inspection failed"
- **Cause**: Container may have been stopped during migration
- **Solution**: Ensure all containers remain running during volume discovery

#### Volume warning: "already exists but was not created by Docker Compose"
- **Cause**: After migration, restored volumes (e.g. `..._runner-data`) already exist on disk but were not created by Docker Compose, so Compose suggests `external: true`.
- **Impact**: **Safe to ignore.** The service uses the existing volume correctly; your data is intact. The message is only a warning.

### Getting Help

If you encounter issues:
1. Check the error messages - they provide specific guidance
2. Verify all prerequisites are met
3. Ensure sufficient disk space on both servers
4. Test SSH connectivity manually before running the script

## ⚠️ Safety Considerations

### Before Migration

1. **Backup First**: Always have a backup of your data before migration
2. **Test Connectivity**: Verify SSH access works before running the script
3. **Check Disk Space**: Ensure destination has enough space for all data
4. **Stop Services**: Consider stopping non-critical services during migration

### During Migration

1. **Don't Interrupt**: Let the script complete - interrupting may leave data in inconsistent state
2. **Monitor Progress**: Watch for error messages
3. **Network Stability**: Ensure stable network connection throughout

### After Migration

1. **Verify Data**: Check that all containers and data are present
2. **Test Functionality**: Verify Coolify is working correctly
3. **Clean Up**: Remove backup file after confirming successful migration
4. **Volume warning**: You may see a warning like `volume "..._runner-data" already exists but was not created by Docker Compose. Use external: true`. This is expected after migration and safe to ignore; see [Troubleshooting](#-troubleshooting).

### Important Notes

- The script **stops Docker** on the destination server during extraction
- Existing SSH keys on destination are **merged**, not replaced
- The script requires SSH access to the destination server (use the user that has access, e.g. root or a deploy user)
- Socket files (`*.sock`) are **excluded** from backup (they're runtime-only)

## 🤝 Contributing

Contributions are welcome! This repository was converted from a [popular gist](https://gist.github.com/Geczy/83c1c77389be94ed4709fc283a0d7e23) to better manage PRs and updates.

### How to Contribute

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Original gist by [Geczy](https://gist.github.com/Geczy/83c1c77389be94ed4709fc283a0d7e23)
- Community contributors who have improved the script

## 📝 Changelog

### Recent Improvements

- Added early `pigz` detection with auto-installation
- Added interactive configuration prompts
- Improved error handling and validation
- Fixed variable quoting issues
- Added comprehensive Docker error handling
- Improved OS detection patterns
- Added fallback for `nproc` command
- Enhanced SSH key merging logic

---

**Note**: Always test the migration process in a non-production environment first to ensure it meets your specific requirements.
