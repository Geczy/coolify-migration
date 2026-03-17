#!/bin/bash
set -euo pipefail

# This script will backup your Coolify instance and move everything to a new server. Docker volumes, Coolify database, and ssh keys

# 1. Script must run on the source server
# 2. Have all the containers running that you want to migrate

# Configuration - Modify as needed
sshKeyPath="$HOME/.ssh/your_private_key" # Key to destination server
destinationHost="server.example.com"

# Prompt for configuration if defaults are still set
if [ "$sshKeyPath" = "$HOME/.ssh/your_private_key" ] || [ "$destinationHost" = "server.example.com" ]; then
  echo "⚠️  Configuration not set. Please provide the following:"
  echo ""
  
  if [ "$sshKeyPath" = "$HOME/.ssh/your_private_key" ]; then
    echo "Enter the path to your SSH private key for the destination server:"
    read -r sshKeyPath
    if [ -z "$sshKeyPath" ]; then
      echo "❌ SSH key path cannot be empty"
      exit 1
    fi
  fi
  
  if [ "$destinationHost" = "server.example.com" ]; then
    echo "Enter the destination server hostname or IP address:"
    read -r destinationHost
    if [ -z "$destinationHost" ]; then
      echo "❌ Destination host cannot be empty"
      exit 1
    fi
  fi
  
  echo ""
fi

# -- Shouldn't need to modify anything below --
backupSourceDir="/data/coolify/"
backupFileName="coolify_backup.tar.gz"
dockerWasStopped=false

# Check if pigz (parallel implementation of gzip) is available for faster compression
if ! command -v pigz >/dev/null 2>&1; then
  echo "⚠️  WARNING: pigz is not installed. The backup will use gzip instead, which may be slower."
  echo ""
  echo "Do you want to try to auto-install pigz? (y/n)"
  read -r install_answer
  case "$install_answer" in
    [Yy]*) install_pigz=true ;;
    *) install_pigz=false ;;
  esac
  if [ "$install_pigz" = "false" ]; then
    # User declined auto-install, ask if they want to continue
    echo ""
    echo "Do you want to continue without pigz? (y/n)"
    read -r answer
    case "$answer" in
      [Yy]*)
        echo "✅ Continuing with gzip..."
        ;;
      *)
        echo "❌ Aborted by user. Please install pigz and try again."
        exit 1
        ;;
    esac
  else
    # Try to auto-install pigz
    echo "🚸 Attempting to install pigz..."
    
    # Determine if we need sudo (check if we're root)
    if [ "$(id -u)" -eq 0 ]; then
      SUDO_CMD=""
    else
      SUDO_CMD="sudo"
    fi
    
    # Detect OS and install pigz accordingly
    if [ -f /etc/debian_version ] || { [ -f /etc/os-release ] && grep -iq "raspbian\|debian\|ubuntu" /etc/os-release; }; then
      echo "ℹ️ Detected Debian-based system"
      # shellcheck disable=SC2086
      if $SUDO_CMD apt-get update && $SUDO_CMD apt-get install -y pigz; then
        echo "✅ pigz installed successfully"
      else
        echo "❌ Failed to install pigz on Debian-based system"
        echo ""
        echo "Do you want to continue without pigz? (y/n)"
        read -r answer
        case "$answer" in
          [Yy]*)
            echo "✅ Continuing with gzip..."
            ;;
          *)
            echo "❌ Aborted by user. Please install pigz manually and try again."
            exit 1
            ;;
        esac
      fi
    elif [ -f /etc/redhat-release ] || { [ -f /etc/os-release ] && grep -iq "rhel\|centos\|fedora" /etc/os-release; }; then
      echo "ℹ️ Detected Redhat-based system"
      # shellcheck disable=SC2086
      if $SUDO_CMD yum install -y pigz 2>/dev/null || $SUDO_CMD dnf install -y pigz; then
        echo "✅ pigz installed successfully"
      else
        echo "❌ Failed to install pigz on Redhat-based system"
        echo ""
        echo "Do you want to continue without pigz? (y/n)"
        read -r answer
        case "$answer" in
          [Yy]*)
            echo "✅ Continuing with gzip..."
            ;;
          *)
            echo "❌ Aborted by user. Please install pigz manually and try again."
            exit 1
            ;;
        esac
      fi
    elif [ -f /etc/SuSE-release ] || { [ -f /etc/os-release ] && grep -iq "suse" /etc/os-release; }; then
      echo "ℹ️ Detected SUSE-based system"
      # shellcheck disable=SC2086
      if $SUDO_CMD zypper install -y pigz; then
        echo "✅ pigz installed successfully"
      else
        echo "❌ Failed to install pigz on SUSE-based system"
        echo ""
        echo "Do you want to continue without pigz? (y/n)"
        read -r answer
        case "$answer" in
          [Yy]*)
            echo "✅ Continuing with gzip..."
            ;;
          *)
            echo "❌ Aborted by user. Please install pigz manually and try again."
            exit 1
            ;;
        esac
      fi
    elif [ -f /etc/arch-release ]; then
      echo "ℹ️ Detected Arch Linux"
      # shellcheck disable=SC2086
      if $SUDO_CMD pacman -Sy --noconfirm pigz; then
        echo "✅ pigz installed successfully"
      else
        echo "❌ Failed to install pigz on Arch Linux"
        echo ""
        echo "Do you want to continue without pigz? (y/n)"
        read -r answer
        case "$answer" in
          [Yy]*)
            echo "✅ Continuing with gzip..."
            ;;
          *)
            echo "❌ Aborted by user. Please install pigz manually and try again."
            exit 1
            ;;
        esac
      fi
    elif [ -f /etc/alpine-release ]; then
      echo "ℹ️ Detected Alpine Linux"
      # shellcheck disable=SC2086
      if $SUDO_CMD apk add --no-cache pigz; then
        echo "✅ pigz installed successfully"
      else
        echo "❌ Failed to install pigz on Alpine Linux"
        echo ""
        echo "Do you want to continue without pigz? (y/n)"
        read -r answer
        case "$answer" in
          [Yy]*)
            echo "✅ Continuing with gzip..."
            ;;
          *)
            echo "❌ Aborted by user. Please install pigz manually and try again."
            exit 1
            ;;
        esac
      fi
    else
      echo "❌ Unsupported OS. Cannot auto-install pigz."
      echo ""
      echo "Do you want to continue without pigz? (y/n)"
      read -r answer
      case "$answer" in
        [Yy]*)
          echo "✅ Continuing with gzip..."
          ;;
        *)
          echo "❌ Aborted by user. Please install pigz manually and try again."
          exit 1
          ;;
      esac
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

# Check if we can SSH to the destination server (accept-new auto-accepts on first connect, rejects if key changes)
if ! ssh -i "$sshKeyPath" -o "StrictHostKeyChecking accept-new" -o "ConnectTimeout=5" "root@${destinationHost}" "exit"; then
  echo "❌ SSH connection to $destinationHost failed"
  exit 1
fi
echo "✅ SSH connection successful"

# Check if the backup file already exists
if [ ! -f "$backupFileName" ]; then
  # Get the names of all running Docker containers
  if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker is not installed or not in PATH"
    exit 1
  fi

  if ! containerNames=$(docker ps --format '{{.Names}}' 2>/dev/null); then
    echo "❌ Failed to get Docker container list. Is Docker running?"
    exit 1
  fi

  # Initialize an empty string to hold the volume paths
  volumePaths=""

  # Loop over the container names
  # shellcheck disable=SC2086
  for containerName in $containerNames; do
    # Get the volumes for the current container
    if ! volumeNames=$(docker inspect --format '{{range .Mounts}}{{printf "%s\n" .Name}}{{end}}' "$containerName" 2>/dev/null); then
      echo "⚠️  Warning: Failed to inspect container $containerName, skipping"
      continue
    fi

    # Loop over the volume names
    # shellcheck disable=SC2086
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
    totalSize=$(du -csh $volumePaths 2>/dev/null | grep total | awk '{print $1}') || totalSize="unknown"
  else
    totalSize="0"
  fi

  # Print the total size of the volumes
  echo "✅ Total size of volumes to migrate: $totalSize"

  # Print size of backupSourceDir
  backupSourceDirSize=$(du -csh "$backupSourceDir" 2>/dev/null | grep total | awk '{print $1}') || backupSourceDirSize="unknown"
  echo "✅ Size of the source directory: $backupSourceDirSize"

  # Check available disk space before creating backup
  availableSpace=$(df -P . | awk 'NR==2 {print $4}')
  if [ -n "$availableSpace" ] && [ "$availableSpace" -lt 1048576 ] 2>/dev/null; then
    availableHuman=$(df -Ph . | awk 'NR==2 {print $4}')
    echo "⚠️  Low disk space: only ${availableHuman} available in current directory"
    echo "Do you want to continue anyway? (y/n)"
    read -r answer
    case "$answer" in
      [Yy]*) echo "🚸 Continuing despite low disk space..." ;;
      *)
        echo "❌ Aborted. Free up disk space and try again."
        exit 1
        ;;
    esac
  fi

  echo "🚸 Backup file does not exist, creating"

  # Recommend stopping docker before creating the backup
  echo "🚸 It's recommended to stop all Docker containers before creating the backup"
  echo "Do you want to stop Docker? (y/n)"
  read -r answer
  case "$answer" in
    [Yy]*)
      if command -v systemctl >/dev/null 2>&1; then
        if ! systemctl stop docker; then
          echo "❌ Docker stop failed"
          exit 1
        fi
        dockerWasStopped=true
        echo "✅ Docker stopped"
      else
        echo "⚠️  systemctl not found, cannot stop Docker service"
        echo "🚸 Continuing with backup (Docker may still be running)"
      fi
      ;;
    *)
      echo "🚸 Docker not stopped, continuing with the backup"
      ;;
  esac

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

  # Check if authorized_keys exists locally before attempting to back it up
  authKeysPath="$HOME/.ssh/authorized_keys"
  authKeysArg=""
  if [ -f "$authKeysPath" ]; then
    authKeysArg="$authKeysPath"
  fi

  rc=0
  # shellcheck disable=SC2086
  tar --exclude='*.sock' --warning=no-file-changed -I "$compressor" -Pcf "${backupFileName}" \
    -C / "$backupSourceDir" ${authKeysArg:+"$authKeysArg"} ${volumePaths:+$volumePaths} || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "❌ Backup file creation failed"
    exit 1
  fi
  echo "✅ Backup file created (with change warnings suppressed)"
else
  echo "🚸 Backup file already exists, skipping creation"
  # Check if Docker is stopped from a previous failed run
  if command -v systemctl >/dev/null 2>&1 && ! systemctl is-active --quiet docker 2>/dev/null; then
    echo "⚠️  Docker appears to be stopped on this (source) server."
    echo "It may have been stopped by a previous run. Noting for restart prompt later."
    dockerWasStopped=true
  fi
fi

# Define the remote commands to be executed
remoteCommands="
  set -euo pipefail

  # Check if Docker is a service
  if systemctl is-active --quiet docker </dev/null; then
    # Stop Docker if it's a service
    if ! systemctl stop docker </dev/null; then
      echo '❌ Docker stop failed';
      exit 1;
    fi
    echo '✅ Docker stopped';
  else
    echo 'ℹ️ Docker is not a service, skipping stop command';
  fi

  echo '🚸 Checking if curl is installed...';
  if ! command -v curl >/dev/null 2>&1; then
    echo 'ℹ️  curl is not installed. Installing curl...';

      # Detect OS and install curl accordingly
      if [ -f /etc/debian_version ] || { [ -f /etc/os-release ] && grep -iq 'raspbian\|debian\|ubuntu' /etc/os-release; }; then
        echo 'ℹ️ Detected Debian-based or Raspberry Pi OS';
        if ! (apt-get update </dev/null && apt-get install -y curl </dev/null); then
          echo '❌ Failed to install curl on Debian-based or Raspberry Pi OS';
          exit 1;
        fi
      elif [ -f /etc/redhat-release ] || { [ -f /etc/os-release ] && grep -iq 'rhel\|centos\|fedora' /etc/os-release; }; then
        echo 'ℹ️ Detected Redhat-based system';
        if ! (yum install -y curl </dev/null 2>/dev/null || dnf install -y curl </dev/null); then
          echo '❌ Failed to install curl on Redhat-based system';
          exit 1;
        fi
      elif [ -f /etc/SuSE-release ] || { [ -f /etc/os-release ] && grep -iq 'suse' /etc/os-release; }; then
        echo 'ℹ️ Detected SUSE-based system';
        if ! zypper install -y curl </dev/null; then
        echo '❌ Failed to install curl on SUSE-based system';
        exit 1;
        fi
      elif [ -f /etc/arch-release ]; then
        echo 'ℹ️ Detected Arch Linux';
        if ! pacman -Sy --noconfirm curl </dev/null; then
        echo '❌ Failed to install curl on Arch Linux';
        exit 1;
        fi
      elif [ -f /etc/alpine-release ]; then
        echo 'ℹ️ Detected Alpine Linux';
        if ! apk add --no-cache curl </dev/null; then
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
  mkdir -p ~/.ssh;
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
    sort -u ~/.ssh/authorized_keys_backup ~/.ssh/authorized_keys > ~/.ssh/authorized_keys_temp;
    mv ~/.ssh/authorized_keys_temp ~/.ssh/authorized_keys;
  elif [ -f ~/.ssh/authorized_keys_backup ]; then
    cp ~/.ssh/authorized_keys_backup ~/.ssh/authorized_keys;
  fi
  rm -f ~/.ssh/authorized_keys_backup;
  chmod 700 ~/.ssh 2>/dev/null || true;
  chmod 600 ~/.ssh/authorized_keys 2>/dev/null || true;
  echo '✅ Authorized keys merged';

  if ! bash -c 'set -o pipefail; curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash' </dev/null; then
    echo '❌ Coolify installation failed';
    exit 1;
  fi
  echo '✅ Coolify installed';
"

# SSH to the destination server, execute the remote commands
if ! ssh -i "$sshKeyPath" -o "StrictHostKeyChecking accept-new" -o "ServerAliveInterval=30" -o "ServerAliveCountMax=5" "root@${destinationHost}" "$remoteCommands" <"${backupFileName}"; then
  echo "❌ Remote commands execution or Docker restart failed"
  exit 1
fi
echo "✅ Remote commands executed successfully"

# Ask user whether to restart Docker on the source server
if [ "$dockerWasStopped" = "true" ]; then
  echo "Docker was stopped on this (source) server during backup."
  echo "Do you want to restart Docker on the source server? (y/n)"
  read -r answer
  case "$answer" in
    [Yy]*)
      if command -v systemctl >/dev/null 2>&1; then
        if ! systemctl start docker; then
          echo "❌ Failed to restart Docker on source server"
        else
          echo "✅ Docker restarted on source server"
        fi
      else
        echo "⚠️  systemctl not found, cannot restart Docker service"
      fi
      ;;
    *)
      echo "🚸 Docker left stopped on source server"
      ;;
  esac
fi

# Clean up - Ask the user for confirmation before removing the local backup file
echo "Do you want to remove the local backup file? (y/n)"
read -r answer
case "$answer" in
  [Yy]*)
    if ! rm -f "${backupFileName}"; then
      echo "❌ Failed to remove local backup file"
      exit 1
    fi
    echo "✅ Local backup file removed"
    ;;
  *)
    echo "🚸 Local backup file not removed"
    ;;
esac

echo ""
echo "✅ Migration complete! Your Coolify instance has been migrated to ${destinationHost}."
