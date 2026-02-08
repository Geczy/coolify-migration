#!/bin/bash
# Reset the TARGET Coolify server so you can run the migration again.
# Run this script on the SOURCE (same machine you run migrate.sh from). It SSHs to the
# target and wipes Coolify data and volumes there.
#
# Usage: ./reset-target.sh [OPTIONS] USER@HOST

set -e

usage() {
  echo "Usage: $0 [OPTIONS] USER@HOST"
  echo ""
  echo "  USER@HOST  Full SSH target: user and hostname or IP (e.g. root@server.example.com)"
  echo ""
  echo "Options:"
  echo "  --yes  Skip confirmation prompt (must type DESTROY otherwise)"
  echo "  --no-strict-host-key  Disable SSH host key verification"
  echo ""
  echo "Example: $0 root@server.example.com"
  echo "Example: $0 --yes root@server.example.com"
  exit 1
}

skipConfirm="no"
sshNoStrictHostKey="no"

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  usage
fi
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --yes) skipConfirm="yes"; shift ;;
    --no-strict-host-key) sshNoStrictHostKey="yes"; shift ;;
    *) echo "❌ Unknown option: $1"; echo ""; usage ;;
  esac
done
if [ -z "${1:-}" ]; then
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

# Build SSH options
if [ "$sshNoStrictHostKey" = "yes" ]; then
  sshOpts="-o StrictHostKeyChecking=no -o ConnectTimeout=5"
else
  sshOpts="-o ConnectTimeout=5"
fi

# SSH key: same auto-detect as migrate.sh
sshKeyPath="$HOME/.ssh/your_private_key"
if [ "$sshKeyPath" = "$HOME/.ssh/your_private_key" ]; then
  sshDir="$HOME/.ssh"
  if [ ! -d "$sshDir" ]; then
    echo "❌ No SSH directory found at $sshDir"
    exit 1
  fi
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
    exit 1
  fi
fi

# Check SSH connectivity
if ! ssh -i "$sshKeyPath" $sshOpts "$sshTarget" "exit"; then
  echo "❌ SSH connection to $sshTarget failed"
  exit 1
fi
echo "✅ SSH connection successful"

if [ "$skipConfirm" != "yes" ]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════════════╗"
  echo "║  ⚠️  DESTRUCTIVE RESET — COOLIFY INSTANCE AND ALL SERVICES WILL BE DESTROYED  ║"
  echo "╠══════════════════════════════════════════════════════════════════════════════╣"
  echo "║  This will PERMANENTLY on the TARGET machine ($sshTarget):                    ║"
  echo "║    • Stop and remove ALL containers                                              ║"
  echo "║    • DELETE /data/coolify (Coolify config, apps, databases, compose files)     ║"
  echo "║    • DELETE all Docker data (/var/lib/docker, /var/lib/containerd)             ║"
  echo "║    • UNINSTALL Docker (packages removed; Docker will be gone)                  ║"
  echo "║  Target will have no Coolify and no Docker, as before any install.             ║"
  echo "║  This cannot be undone. Use only to reset a migration test target.             ║"
  echo "╚══════════════════════════════════════════════════════════════════════════════╝"
  echo ""
  printf "To confirm, type DESTROY (all caps): "
  read -r answer
  if [ "$answer" != "DESTROY" ]; then
    echo "Aborted. (You typed something other than DESTROY.)"
    exit 0
  fi
  echo ""
fi

# Remote commands (run on target).
# Stop Coolify (all containers), stop Docker, remove Coolify data and Docker
# (packages + data). Target ends with no Coolify and no Docker, as before install.
remoteCommands="
  set -e
  echo 'Stopping all containers (Coolify and everything)...'
  docker stop \$(docker ps -aq) 2>/dev/null || true
  echo 'Removing all containers...'
  docker rm \$(docker ps -aq) 2>/dev/null || true
  echo 'Stopping Docker daemon...'
  systemctl stop docker 2>/dev/null || true
  systemctl stop docker.socket 2>/dev/null || true
  echo 'Removing Coolify data...'
  rm -rf /data/coolify
  echo 'Removing Docker data (volumes, images, etc.)...'
  rm -rf /var/lib/docker /var/lib/containerd /etc/docker
  echo 'Uninstalling Docker packages...'
  if [ -f /etc/debian_version ] || { [ -f /etc/os-release ] && grep -iq 'raspbian\\|debian\\|ubuntu' /etc/os-release; }; then
    apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io 2>/dev/null || true
    apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io 2>/dev/null || true
  elif [ -f /etc/redhat-release ] || { [ -f /etc/os-release ] && grep -iq 'rhel\\|centos\\|fedora' /etc/os-release; }; then
    yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
    dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
  elif [ -f /etc/SuSE-release ] || { [ -f /etc/os-release ] && grep -iq suse /etc/os-release; }; then
    zypper remove -y docker-ce docker-ce-cli containerd.io 2>/dev/null || true
  elif [ -f /etc/arch-release ]; then
    pacman -R --noconfirm docker docker-compose 2>/dev/null || true
  elif [ -f /etc/alpine-release ]; then
    apk del docker docker-cli-compose 2>/dev/null || true
  else
    echo '⚠️  Unknown OS; skipping package removal. Remove Docker manually if needed.'
  fi
  echo 'Done. Target has no Coolify and no Docker (as before install).'
"

echo "Running reset on $sshTarget..."
ssh -i "$sshKeyPath" $sshOpts "$sshTarget" "$remoteCommands"
echo "✅ Target reset complete."
