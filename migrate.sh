#!/bin/bash

# This script will backup your Coolify instance and move everything to a new server. Docker volumes, Coolify database, and ssh keys

# 1. Script must run on the source server
# 2. Have all the containers running that you want to migrate

# Configuration - Modify as needed
sshKeyPath="$HOME/.ssh/key.pem" # Key to destination server
destinationHost="102.223.37.36"
sourceUser="root" # User on the source server (ensure this user has permissions for Docker and file access)
destinationUser="root" # User on the destination server

# -- Shouldn't need to modify anything below --
backupSourceDir="/data/coolify/"
backupFileName="coolify_backup.tar.gz"

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
if ! ssh -i "$sshKeyPath" -o "StrictHostKeyChecking no" -o "ConnectTimeout=5" ${destinationUser}@$destinationHost "exit"; then
  echo "❌ SSH connection to ${destinationUser}@$destinationHost failed"
  exit 1
fi
echo "✅ SSH connection successful"

# Get the names of all running Docker containers
containerNames=$(docker ps --format '{{.Names}}')

# Initialize an empty string to hold the volume paths
volumePaths=""

# Loop over the container names
for containerName in $containerNames; do
  # Get the volumes for the current container
  volumeNames=$(docker inspect --format '{{range .Mounts}}{{.Name}} {{end}}' "$containerName")

  # Loop over the volume names
  for volumeName in $volumeNames; do
    # Check if the volume name is not empty
    if [ -n "$volumeName" ]; then
      # Add the volume path to the volume paths string
      volumePaths+=" /var/lib/docker/volumes/$volumeName"
    fi
  done
done

# Calculate the total size of the volumes
# shellcheck disable=SC2086
totalSize=$(du -csh $volumePaths 2>/dev/null | grep total | awk '{print $1}')

# Print the total size of the volumes
echo "✅ Total size of volumes to migrate: $totalSize"

# Print size of backupSourceDir
backupSourceDirSize=$(du -csh $backupSourceDir 2>/dev/null | grep total | awk '{print $1}')
echo "✅ Size of the source directory: $backupSourceDirSize"

# Check if the backup file already exists
if [ ! -f "$backupFileName" ]; then
  echo "🚸 Backup file does not exist, creating"

  # Recommend stopping docker before creating the backup
  echo "🚸 It's recommended to stop all Docker containers before creating the backup
  Do you want to stop Docker? (y/n)"
  read -r answer
  if [ "$answer" != "${answer#[Yy]}" ]; then
    if ! systemctl stop docker; then
      echo "❌ Docker stop failed"
      exit 1
    fi
    echo "✅ Docker stopped"
  else
    echo "🚸 Docker not stopped, continuing with the backup"
  fi

  # shellcheck disable=SC2086
  # Note: If sourceUser is not the user running this script, $HOME/.ssh/authorized_keys might point to the wrong location.
  # Ensure the correct authorized_keys for the sourceUser is backed up if not running as sourceUser.
  if ! tar --exclude='*.sock' -Pczf $backupFileName -C / $backupSourceDir $HOME/.ssh/authorized_keys $volumePaths; then
    echo "❌ Backup file creation failed"
    exit 1
  fi
  echo "✅ Backup file created"
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
      if [ -f /etc/debian_version ] || { [ -f /etc/os-release ] && grep -iq "raspbian" /etc/os-release; }; then
        echo 'ℹ️ Detected Debian-based or Raspberry Pi OS';
        if ! apt-get update && apt-get install -y curl; then
        echo '❌ Failed to install curl on Debian-based or Raspberry Pi OS';
        exit 1;
        fi
      elif [ -f /etc/redhat-release ]; then
        echo 'ℹ️ Detected Redhat-based system';
        if ! yum install -y curl; then
        echo '❌ Failed to install curl on Redhat-based system';
        exit 1;
        fi
      elif [ -f /etc/SuSE-release ] || [ -f /etc/os-release ] && grep -iq "suse" /etc/os-release; then
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
  cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys_backup;

  echo '🚸 Extracting backup file...';
  if ! tar -Pxzf - -C /; then
    echo '❌ Backup file extraction failed';
    exit 1;
  fi
  echo '✅ Backup file extracted';

  echo '🚸 Merging authorized keys...';
  cat ~/.ssh/authorized_keys_backup ~/.ssh/authorized_keys | sort | uniq > ~/.ssh/authorized_keys_temp;
  mv ~/.ssh/authorized_keys_temp ~/.ssh/authorized_keys;
  chmod 600 ~/.ssh/authorized_keys;
  echo '✅ Authorized keys merged';

  if ! curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash; then
    echo '❌ Coolify installation failed';
    exit 1;
  fi
  echo '✅ Coolify installed';
"

# SSH to the destination server, execute the remote commands
if ! ssh -i "$sshKeyPath" -o "StrictHostKeyChecking no" ${destinationUser}@$destinationHost "$remoteCommands" <$backupFileName; then
  echo "❌ Remote commands execution or Docker restart failed"
  exit 1
fi
echo "✅ Remote commands executed successfully"

# Clean up - Ask the user for confirmation before removing the local backup file
echo "Do you want to remove the local backup file? (y/n)"
read -r answer
if [ "$answer" != "${answer#[Yy]}" ]; then
  if ! rm -f $backupFileName; then
    echo "❌ Failed to remove local backup file"
    exit 1
  fi
  echo "✅ Local backup file removed"
else
  echo "🚸 Local backup file not removed"
fi
