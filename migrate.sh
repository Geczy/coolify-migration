#!/bin/bash

# This script will backup your Coolify instance and move everything to a new server. Docker volumes, Coolify database, and ssh keys

# 1. Script must run on the source server
# 2. Have all the containers running that you want to migrate

# Require full SSH target (user@host) unless --backup-only
usage() {
  echo "Usage: $0 [OPTIONS] [USER@HOST]"
  echo ""
  echo "  USER@HOST  Full SSH target for migration (required unless --backup-only)"
  echo ""
  echo "Options:"
  echo "  --backup-only        Only create the backup; do not transfer or install (no USER@HOST needed)"
  echo "  --no-strict-host-key Disable SSH host key verification (accept/first-connect without prompt)"
  echo ""
  echo "Example: $0 root@server.example.com"
  echo "Example: $0 --backup-only"
  echo "Example: $0 --no-strict-host-key root@server.example.com"
  exit 1
}

# SSH: default is to verify host keys (strict); use --no-strict-host-key to disable for migration convenience
sshNoStrictHostKey="no"
backupOnly="no"

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
fi
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --backup-only) backupOnly="yes"; shift ;;
    --no-strict-host-key) sshNoStrictHostKey="yes"; shift ;;
    *) echo "❌ Unknown option: $1"; echo ""; usage ;;
  esac
done
if [ "$backupOnly" != "yes" ]; then
  if [ -z "${1:-}" ]; then
    echo "❌ Error: SSH target (user@host) is required (or use --backup-only)"
    echo ""
    usage
  fi
  if [[ "$1" != *"@"* ]]; then
    echo "❌ Error: SSH target must be in the form user@host (e.g. root@server.example.com)"
    echo ""
    usage
  fi
  sshTarget="$1"
else
  sshTarget=""
fi

# Build SSH options (disable StrictHostKeyChecking only when user passes --no-strict-host-key)
if [ "$sshNoStrictHostKey" = "yes" ]; then
  sshOpts="-o StrictHostKeyChecking=no -o ConnectTimeout=5"
else
  sshOpts="-o ConnectTimeout=5"
fi

# Configuration - Modify as needed (SSH key is auto-detected from ~/.ssh when default is set)
sshKeyPath="$HOME/.ssh/your_private_key" # Key to destination server

# Auto-detect best SSH private key (only needed for full migration, not --backup-only)
if [ "$backupOnly" != "yes" ]; then
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

# Check SSH key and connectivity (only for full migration)
if [ "$backupOnly" != "yes" ]; then
  if [ ! -f "$sshKeyPath" ]; then
    echo "❌ SSH key file $sshKeyPath does not exist"
    exit 1
  fi
  echo "✅ SSH key file exists"
  if ! ssh -i "$sshKeyPath" $sshOpts "$sshTarget" "exit"; then
    echo "❌ SSH connection to $sshTarget failed"
    exit 1
  fi
  echo "✅ SSH connection successful"
fi

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
dockerWasStopped=0
if [ ! -f "$backupFileName" ]; then
  echo "🚸 Backup file does not exist, creating"

  # Recommend stopping docker before creating the backup (socket too, so it doesn't restart Docker during backup)
  echo "🚸 It's recommended to stop all Docker containers before creating the backup"
  echo "Do you want to stop Docker? (y/n)"
  read -r answer
  if [ "$answer" != "${answer#[Yy]}" ]; then
    if command -v systemctl >/dev/null 2>&1; then
      if ! systemctl stop docker docker.socket 2>/dev/null; then
        systemctl stop docker 2>/dev/null || true
      fi
      if systemctl is-active --quiet docker 2>/dev/null; then
        echo "❌ Docker could not be stopped (socket may still be active)"
        exit 1
      fi
      echo "✅ Docker and docker.socket stopped"
      dockerWasStopped=1
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
    if [ "$dockerWasStopped" = "1" ] && command -v systemctl >/dev/null 2>&1; then
      echo "🚸 Starting Docker again on source..."
      systemctl start docker.socket docker 2>/dev/null || systemctl start docker 2>/dev/null || true
    fi
    exit 1
  fi
  echo "✅ Backup file created (with change warnings suppressed)"
  if [ "$dockerWasStopped" = "1" ] && command -v systemctl >/dev/null 2>&1; then
    echo "🚸 Starting Docker again on source (minimizing downtime)..."
    systemctl start docker.socket docker 2>/dev/null || systemctl start docker 2>/dev/null || true
    echo "✅ Docker started"
  fi
else
  echo "🚸 Backup file already exists, skipping creation"
fi

# Backup-only mode: skip transfer and exit after optional cleanup
if [ "$backupOnly" = "yes" ]; then
  echo ""
  echo "✅ Backup complete. Run $0 USER@HOST to migrate to a target server."
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
  exit 0
fi

# Define the remote commands to be executed
remoteCommands="
  set -e
  COOLIFY_OS=unknown
  if [ -f /etc/debian_version ] || { [ -f /etc/os-release ] && grep -iq 'raspbian\\|debian\\|ubuntu' /etc/os-release; }; then
    COOLIFY_OS=debian
  elif [ -f /etc/redhat-release ] || { [ -f /etc/os-release ] && grep -iq 'rhel\\|centos\\|fedora' /etc/os-release; }; then
    COOLIFY_OS=redhat
  elif [ -f /etc/SuSE-release ] || { [ -f /etc/os-release ] && grep -iq suse /etc/os-release; }; then
    COOLIFY_OS=suse
  elif [ -f /etc/arch-release ]; then
    COOLIFY_OS=arch
  elif [ -f /etc/alpine-release ]; then
    COOLIFY_OS=alpine
  fi

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

  echo '🚸 Ensuring curl is installed...';
  if ! command -v curl &> /dev/null; then
    echo 'ℹ️  Installing curl...';
    case \"\$COOLIFY_OS\" in
      debian) apt-get update && apt-get install -y curl ;;
      redhat) (yum install -y curl 2>/dev/null || dnf install -y curl) ;;
      suse) zypper install -y curl ;;
      arch) pacman -Sy --noconfirm curl ;;
      alpine) apk add --no-cache curl ;;
      *) echo '❌ Unsupported OS. Install curl manually.'; exit 1 ;;
    esac
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
# Rebuild ssh opts for transfer (no ConnectTimeout needed for long-running transfer; keep StrictHostKeyChecking choice)
if [ "$sshNoStrictHostKey" = "yes" ]; then
  sshTransferOpts="-o StrictHostKeyChecking=no"
else
  sshTransferOpts=""
fi
if ! ssh -i "$sshKeyPath" $sshTransferOpts "$sshTarget" "$remoteCommands" <"${backupFileName}"; then
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
