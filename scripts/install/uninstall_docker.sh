#!/bin/bash

# ==============================================================================
# Standalone Docker & Git Uninstallation Script
# Version: 1.0.0
# Date: 2025-07-28
# ==============================================================================
#
# Description:
# This script completely removes Docker Engine, Git (from PPA), and all
# related configurations from an Ubuntu system. It is designed to be a
# destructive but clean uninstallation utility.
#
# Usage:
#   1. Make this script executable: `chmod +x uninstall_docker.sh`
#   2. Run the script: `./uninstall_docker.sh`
#
# ==============================================================================

set -e
trap 'echo "❌ Uninstallation failed at stage [$((CURRENT_STAGE - 1))/5]: $STAGE_DESC. Exiting."' ERR

echo "⚠️  This script will completely remove Docker, Git, and related configurations."
echo "   It will stop and delete all containers, images, and volumes."
read -p "   Are you sure you want to continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

CURRENT_STAGE=1
STAGE_DESC="Initializing Cleanup"

echo "🚀 Stage [$CURRENT_STAGE/5]: $STAGE_DESC..."
((CURRENT_STAGE++))

STAGE_DESC="Stopping and Pruning Docker System"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/5]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "⚙️  Stopping Docker services..."
sudo systemctl stop docker.service docker.socket || true
sudo systemctl disable docker.service docker.socket || true

echo "⚙️  Removing all containers, images, and volumes..."
# This command might fail if Docker is already partially removed, so we ignore errors.
docker system prune -a --volumes -f || true
echo "✅ Docker system pruned."

STAGE_DESC="Uninstalling Packages"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/5]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "⚙️  Removing Docker and Git packages..."
sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get purge -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-compose-plugin \
    git > /dev/null
echo "✅ Packages removed."

echo "⚙️  Removing leftover Docker directories..."
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
sudo rm -rf /etc/docker
echo "✅ Leftover directories cleaned."

STAGE_DESC="Cleaning Up System Configuration"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/5]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "⚙️  Removing Docker and Git APT repositories..."
sudo rm -f /etc/apt/keyrings/docker.gpg
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo add-apt-repository --remove -y ppa:git-core/ppa > /dev/null || true
echo "✅ Repositories removed."

echo "⚙️  Restoring iptables to default..."
echo "0" | sudo update-alternatives --config iptables > /dev/null
echo "✅ iptables restored."

echo "⚙️  Removing 'docker' user group..."
sudo groupdel docker || echo "   'docker' group not found or already removed."
echo "✅ Docker group handled."

STAGE_DESC="Finalizing Cleanup"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/5]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "⚙️  Autoremoving unused packages and cleaning APT cache..."
sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get autoremove -y > /dev/null
sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get clean > /dev/null
echo "✅ System cleaned."

echo ""
echo "🎉 =============================================== 🎉"
echo "      Docker & Git cleanup is complete!              "
echo "      A system reboot is recommended to ensure     "
echo "      all changes are applied.                       "
echo "🎉 =============================================== 🎉"
