#!/bin/bash

# This script will backup your Coolify instance and move everything to a new server. Docker volumes, Coolify database, and ssh keys

# 1. Script must run on the source server
# 2. Have all the containers running that you want to migrate

# Require full SSH target as first argument (user@host)
usage() {
  echo "Usage: $0 USER@HOST"
  echo ""
  echo "  USER@HOST  Full SSH target: user and hostname or IP (e.g. root@server.example.com)"
  echo ""
  echo "Example: $0 root@server.example.com"
  exit 1
}
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
fi
if [ -z "$1" ]; then
  echo "❌ Error: SSH target (user@host) is required"
  echo ""
  usage
fi
if [[ "$1" != *"@"* ]]; then
  echo "❌ Error: SSH target must be in the form user@host (e.g. root@server.example.com)"
  echo ""
  usage
fi
sshTarget="$1"

# Configuration - Modify as needed (SSH key is auto-detected from ~/.ssh when default is set)
sshKeyPath="$HOME/.ssh/your_private_key" # Key to destination server

# Auto-detect best SSH private key from ~/.ssh when default is set
if [ "$sshKeyPath" = "$HOME/.ssh/your_private_key" ]; then
  sshDir="$HOME/.ssh"
  if [ ! -d "$sshDir" ]; then
    echo "❌ No SSH directory found at $sshDir"
    exit 1
  fi
  # Prefer ed25519, then ecdsa, then rsa (standard key names, best to good)
  for keyName in id_ed25519 id_ecdsa id_rsa; do
    candidate="$sshDir/$keyName"
    if [ -f "$candidate" ] && [ -r "$candidate" ]; then
      if ssh-keygen -l -f "$candidate" >/dev/null 2>&1; then
        sshKeyPath="$candidate"
        echo "✅ Using SSH key: $sshKeyPath"
        break
      fi
    fi
  done
  if [ "$sshKeyPath" = "$HOME/.ssh/your_private_key" ]; then
    echo "❌ No usable SSH private key found in $sshDir"
    echo "   Looked for: id_ed25519, id_ecdsa, id_rsa (with correct permissions)"
    echo "   Create a key with: ssh-keygen -t ed25519 -f $sshDir/id_ed25519"
    exit 1
  fi
fi

# -- Shouldn't need to modify anything below --
backupSourceDir="/data/coolify/"
backupFileName="coolify_backup.tar.gz"

# Check if pigz is available (for faster compression)
if ! command -v pigz >/dev/null 2>&1; then
  echo "⚠️  WARNING: pigz is not installed. The backup will use gzip instead, which may be slower."
  echo ""
  echo "Do you want to try to auto-install pigz? (y/n)"
  read -r install_answer
  if [ "$install_answer" = "${install_answer#[Yy]}" ]; then
    # User declined auto-install, ask if they want to continue
    echo ""
    echo "Do you want to continue without pigz? (y/n)"
    read -r answer
    if [ "$answer" != "${answer#[Yy]}" ]; then
      echo "✅ Continuing with gzip..."
    else
      echo "❌ Aborted by user. Please install pigz and try again."
      exit 1
    fi
  else
    # Try to auto-install pigz
    echo "🚸 Attempting to install pigz..."
    
    # Determine if we need sudo (check if we're root)
    if [ "$EUID" -eq 0 ]; then
      SUDO_CMD=""
    else
      SUDO_CMD="sudo"
    fi
    
    # Detect OS and install pigz accordingly
    if [ -f /etc/debian_version ] || { [ -f /etc/os-release ] && grep -iq "raspbian\|debian\|ubuntu" /etc/os-release; }; then
      echo "ℹ️ Detected Debian-based system"
      if $SUDO_CMD apt-get update && $SUDO_CMD apt-get install -y pigz; then
        echo "✅ pigz installed successfully"
      else
        echo "❌ Failed to install pigz on Debian-based system"
        echo ""
        echo "Do you want to continue without pigz? (y/n)"
        read -r answer
        if [ "$answer" != "${answer#[Yy]}" ]; then
          echo "✅ Continuing with gzip..."
        else
          echo "❌ Aborted by user. Please install pigz manually and try again."
          exit 1
        fi
      fi
    elif [ -f /etc/redhat-release ] || { [ -f /etc/os-release ] && grep -iq "rhel\|centos\|fedora" /etc/os-release; }; then
      echo "ℹ️ Detected Redhat-based system"
      if $SUDO_CMD yum install -y pigz 2>/dev/null || $SUDO_CMD dnf install -y pigz; then
        echo "✅ pigz installed successfully"
      else
        echo "❌ Failed to install pigz on Redhat-based system"
        echo ""
        echo "Do you want to continue without pigz? (y/n)"
        read -r answer
        if [ "$answer" != "${answer#[Yy]}" ]; then
          echo "✅ Continuing with gzip..."
        else
          echo "❌ Aborted by user. Please install pigz manually and try again."
          exit 1
        fi
      fi
    elif [ -f /etc/SuSE-release ] || { [ -f /etc/os-release ] && grep -iq "suse" /etc/os-release; }; then
      echo "ℹ️ Detected SUSE-based system"
      if $SUDO_CMD zypper install -y pigz; then
        echo "✅ pigz installed successfully"
      else
        echo "❌ Failed to install pigz on SUSE-based system"
        echo ""
        echo "Do you want to continue without pigz? (y/n)"
        read -r answer
        if [ "$answer" != "${answer#[Yy]}" ]; then
          echo "✅ Continuing with gzip..."
        else
          echo "❌ Aborted by user. Please install pigz manually and try again."
          exit 1
        fi
      fi
    elif [ -f /etc/arch-release ]; then
      echo "ℹ️ Detected Arch Linux"
      if $SUDO_CMD pacman -Sy --noconfirm pigz; then
        echo "✅ pigz installed successfully"
      else
        echo "❌ Failed to install pigz on Arch Linux"
        echo ""
        echo "Do you want to continue without pigz? (y/n)"
        read -r answer
        if [ "$answer" != "${answer#[Yy]}" ]; then
          echo "✅ Continuing with gzip..."
        else
          echo "❌ Aborted by user. Please install pigz manually and try again."
          exit 1
        fi
      fi
    elif [ -f /etc/alpine-release ]; then
      echo "ℹ️ Detected Alpine Linux"
      if $SUDO_CMD apk add --no-cache pigz; then
        echo "✅ pigz installed successfully"
      else
        echo "❌ Failed to install pigz on Alpine Linux"
        echo ""
        echo "Do you want to continue without pigz? (y/n)"
        read -r answer
        if [ "$answer" != "${answer#[Yy]}" ]; then
          echo "✅ Continuing with gzip..."
        else
          echo "❌ Aborted by user. Please install pigz manually and try again."
          exit 1
        fi
      fi
    else
      echo "❌ Unsupported OS. Cannot auto-install pigz."
      echo ""
      echo "Do you want to continue without pigz? (y/n)"
      read -r answer
      if [ "$answer" != "${answer#[Yy]}" ]; then
        echo "✅ Continuing with gzip..."
      else
        echo "❌ Aborted by user. Please install pigz manually and try again."
        exit 1
      fi
    fi
  fi
fi

# Check if the source directory exists
if [ ! -d "$backupSourceDir" ]; then
  echo "❌ Source directory $backupSourceDir does not exist"
  exit 1
fi
echo "✅ Source directory exists"

# Check if the SSH key file exists
if [ ! -f "$sshKeyPath" ]; then
  echo "❌ SSH key file $sshKeyPath does not exist"
  exit 1
fi
echo "✅ SSH key file exists"

# Check if we can SSH to the destination server, ignore "The authenticity of host can't be established." errors
if ! ssh -i "$sshKeyPath" -o "StrictHostKeyChecking no" -o "ConnectTimeout=5" "$sshTarget" "exit"; then
  echo "❌ SSH connection to $sshTarget failed"
  exit 1
fi
echo "✅ SSH connection successful"

# Get the names of all running Docker containers
if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker is not installed or not in PATH"
  exit 1
fi

containerNames=$(docker ps --format '{{.Names}}' 2>/dev/null)
if [ $? -ne 0 ]; then
  echo "❌ Failed to get Docker container list. Is Docker running?"
  exit 1
fi

# Initialize an empty string to hold the volume paths
volumePaths=""

# Loop over the container names
for containerName in $containerNames; do
  # Get the volumes for the current container
  volumeNames=$(docker inspect --format '{{range .Mounts}}{{printf "%s\n" .Name}}{{end}}' "$containerName" 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "⚠️  Warning: Failed to inspect container $containerName, skipping"
    continue
  fi

  # Loop over the volume names
  for volumeName in $volumeNames; do
    # Check if the volume name is not empty
    if [ -n "$volumeName" ]; then
      # Add the volume path to the volume paths string
      volumePaths="$volumePaths /var/lib/docker/volumes/$volumeName"
    fi
  done
done

# Calculate the total size of the volumes
if [ -n "$volumePaths" ]; then
  # shellcheck disable=SC2086
  totalSize=$(du -csh $volumePaths 2>/dev/null | grep total | awk '{print $1}')
else
  totalSize="0"
fi

# Print the total size of the volumes
echo "✅ Total size of volumes to migrate: $totalSize"

# Print size of backupSourceDir
backupSourceDirSize=$(du -csh $backupSourceDir 2>/dev/null | grep total | awk '{print $1}')
echo "✅ Size of the source directory: $backupSourceDirSize"

# Check if the backup file already exists
if [ ! -f "$backupFileName" ]; then
  echo "🚸 Backup file does not exist, creating"

  # Recommend stopping docker before creating the backup
  echo "🚸 It's recommended to stop all Docker containers before creating the backup"
  echo "Do you want to stop Docker? (y/n)"
  read -r answer
  if [ "$answer" != "${answer#[Yy]}" ]; then
    if command -v systemctl >/dev/null 2>&1; then
      if ! systemctl stop docker; then
        echo "❌ Docker stop failed"
        exit 1
      fi
      echo "✅ Docker stopped"
    else
      echo "⚠️  systemctl not found, cannot stop Docker service"
      echo "🚸 Continuing with backup (Docker may still be running)"
    fi
  else
    echo "🚸 Docker not stopped, continuing with the backup"
  fi

  # Choose compressor
  if command -v pigz >/dev/null 2>&1; then
    echo "✅ Using pigz for parallel gzip"
    # Get number of CPU cores, fallback to 1 if nproc is not available
    if command -v nproc >/dev/null 2>&1; then
      cores=$(nproc)
    else
      cores=1
    fi
    compressor="pigz -p${cores}"
  else
    echo "ℹ️ pigz not found, using gzip"
    compressor="gzip"
  fi

  # shellcheck disable=SC2086
  tar --exclude='*.sock' --warning=no-file-changed -I "$compressor" -Pcf "${backupFileName}" \
    -C / $backupSourceDir $HOME/.ssh/authorized_keys $volumePaths
  rc=$?
  if [ $rc -gt 1 ]; then
    echo "❌ Backup file creation failed"
    exit 1
  fi
  echo "✅ Backup file created (with change warnings suppressed)"
else
  echo "🚸 Backup file already exists, skipping creation"
fi

# Define the remote commands to be executed
remoteCommands="
  # Check if Docker is a service
  if systemctl is-active --quiet docker; then
    # Stop Docker if it's a service
    if ! systemctl stop docker; then
      echo '❌ Docker stop failed';
      exit 1;
    fi
    echo '✅ Docker stopped';
  else
    echo 'ℹ️ Docker is not a service, skipping stop command';
  fi

  echo '🚸 Checking if curl is installed...';
  if ! command -v curl &> /dev/null; then
    echo 'ℹ️  curl is not installed. Installing curl...';

      # Detect OS and install curl accordingly
      if [ -f /etc/debian_version ] || { [ -f /etc/os-release ] && grep -iq "raspbian\|debian\|ubuntu" /etc/os-release; }; then
        echo 'ℹ️ Detected Debian-based or Raspberry Pi OS';
        if ! (apt-get update && apt-get install -y curl); then
          echo '❌ Failed to install curl on Debian-based or Raspberry Pi OS';
          exit 1;
        fi
      elif [ -f /etc/redhat-release ] || { [ -f /etc/os-release ] && grep -iq "rhel\|centos\|fedora" /etc/os-release; }; then
        echo 'ℹ️ Detected Redhat-based system';
        if ! (yum install -y curl 2>/dev/null || dnf install -y curl); then
          echo '❌ Failed to install curl on Redhat-based system';
          exit 1;
        fi
      elif [ -f /etc/SuSE-release ] || { [ -f /etc/os-release ] && grep -iq "suse" /etc/os-release; }; then
        echo 'ℹ️ Detected SUSE-based system';
        if ! zypper install -y curl; then
        echo '❌ Failed to install curl on SUSE-based system';
        exit 1;
        fi
      elif [ -f /etc/arch-release ]; then
        echo 'ℹ️ Detected Arch Linux';
        if ! pacman -Sy --noconfirm curl; then
        echo '❌ Failed to install curl on Arch Linux';
        exit 1;
        fi
      elif [ -f /etc/alpine-release ]; then
        echo 'ℹ️ Detected Alpine Linux';
        if ! apk add --no-cache curl; then
        echo '❌ Failed to install curl on Alpine Linux';
        exit 1;
        fi
      else
        echo '❌ Unsupported OS. Please install curl manually.';
        exit 1;
      fi

      echo '✅ curl installed';
    else
      echo '✅ curl is already installed';
    fi

  echo '🚸 Saving existing authorized keys...';
  if [ -f ~/.ssh/authorized_keys ]; then
    cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys_backup;
  else
    touch ~/.ssh/authorized_keys_backup;
  fi

  echo '🚸 Extracting backup file...'
  if command -v pigz >/dev/null 2>&1; then
    echo '✅ Using pigz for parallel decompression'
    if ! tar -I pigz -Pxf - -C /; then
      echo '❌ Backup file extraction failed'
      exit 1
    fi
  else
    if ! tar -Pzxf - -C /; then
      echo '❌ Backup file extraction failed'
      exit 1
    fi
  fi
  echo '✅ Backup file extracted'

  echo '🚸 Merging authorized keys...';
  if [ -f ~/.ssh/authorized_keys_backup ] && [ -f ~/.ssh/authorized_keys ]; then
    cat ~/.ssh/authorized_keys_backup ~/.ssh/authorized_keys | sort | uniq > ~/.ssh/authorized_keys_temp;
    mv ~/.ssh/authorized_keys_temp ~/.ssh/authorized_keys;
  elif [ -f ~/.ssh/authorized_keys_backup ]; then
    cp ~/.ssh/authorized_keys_backup ~/.ssh/authorized_keys;
  fi
  chmod 600 ~/.ssh/authorized_keys 2>/dev/null || true;
  echo '✅ Authorized keys merged';

  if ! curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash; then
    echo '❌ Coolify installation failed';
    exit 1;
  fi
  echo '✅ Coolify installed';
"

# SSH to the destination server, execute the remote commands
if ! ssh -i "$sshKeyPath" -o "StrictHostKeyChecking no" "$sshTarget" "$remoteCommands" <"${backupFileName}"; then
  echo "❌ Remote commands execution or Docker restart failed"
  exit 1
fi
echo "✅ Remote commands executed successfully"

# Clean up - Ask the user for confirmation before removing the local backup file
echo "Do you want to remove the local backup file? (y/n)"
read -r answer
if [ "$answer" != "${answer#[Yy]}" ]; then
  if ! rm -f "${backupFileName}"; then
    echo "❌ Failed to remove local backup file"
    exit 1
  fi
  echo "✅ Local backup file removed"
else
  echo "🚸 Local backup file not removed"
fi
