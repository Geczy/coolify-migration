# Coolify Migration Script

A comprehensive bash script to backup and migrate your entire Coolify instance from one server to another. This script handles Docker volumes, the Coolify database, SSH keys, and all associated data.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
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
- **Interactive Configuration**: Prompts for SSH key and destination host if not pre-configured
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

### Setting Up SSH Keys

The script needs a private key on the **source** server that can authenticate to the **destination** server. If you don't already have this:

1. **Generate a keypair on the source server:**
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/coolify_migration_key
   ```
   This creates two files:
   - `~/.ssh/coolify_migration_key` — private key (stays on source server)
   - `~/.ssh/coolify_migration_key.pub` — public key (goes on destination server)

2. **Copy the public key to the destination server:**
   ```bash
   ssh-copy-id -i ~/.ssh/coolify_migration_key.pub root@<destination-ip>
   ```
   Or manually — append the `.pub` file contents to `~/.ssh/authorized_keys` on the destination server.

3. **Test the connection:**
   ```bash
   ssh -i ~/.ssh/coolify_migration_key root@<destination-ip> "echo works"
   ```

4. **Set the path in the script:**
   ```bash
   sshKeyPath="$HOME/.ssh/coolify_migration_key"
   destinationHost="<destination-ip>"
   ```

> **Note:** If running the script with `sudo`, `$HOME` becomes `/root`. Either copy the key to `/root/.ssh/` or use the full path instead of `$HOME`.

## 🚀 Installation

1. Clone or download this repository:
```bash
git clone https://github.com/rogerb831/coolify-migration.git
cd coolify-migration
```

2. Edit the configuration section (optional - you can also be prompted at runtime):
```bash
nano migrate.sh
```

3. Run the script:
```bash
sudo bash migrate.sh
```

## ⚙️ Configuration

The script has two configuration options at the top of the file:

```bash
sshKeyPath="$HOME/.ssh/your_private_key"  # Path to SSH private key
destinationHost="server.example.com"     # Destination server hostname/IP
```

### Configuration Methods

**Option 1: Edit the script directly**
- Modify lines 9-10 in `migrate.sh`
- Set your actual SSH key path and destination host

**Option 2: Interactive prompts**
- Leave the defaults as-is
- The script will prompt you for values at runtime

### Additional Configuration

The script uses these default paths (can be modified in the script):
- **Backup source directory**: `/data/coolify/`
- **Backup filename**: `coolify_backup.tar.gz` (created in current directory)

## 📖 Usage

### Basic Usage

1. **Ensure all containers you want to migrate are running** on the source server

2. **Run the script**:
```bash
./migrate.sh
```

3. **Follow the interactive prompts**:
   - Configure SSH key and destination (if not pre-configured)
   - Choose whether to install `pigz` if not available
   - Confirm Docker stop (recommended for data consistency)
   - Confirm backup file cleanup after migration

### Step-by-Step Process

1. **Configuration Check**: Script verifies or prompts for SSH key and destination host
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
  - Test SSH manually: `ssh -i your_key root@destination`

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

### Important Notes

- The script **stops Docker** on the destination server during extraction
- Existing SSH keys on destination are **merged**, not replaced
- The script requires **root access** on the destination server
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
