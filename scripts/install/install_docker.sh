#!/bin/bash

# ==============================================================================
# Standalone Docker & Git Installation Script
# Version: 1.0.0
# Date: 2025-07-28
# ==============================================================================
#
# Description:
# This script performs a full installation of Git (from the official PPA) and
# the latest Docker Engine on a fresh Ubuntu system. It is designed to be
# run non-interactively.
#
# Usage:
#   1. Make this script executable: `chmod +x install_docker.sh`
#   2. Run the script: `./install_docker.sh`
#
# ==============================================================================

set -e
trap 'echo "❌ Installation failed at stage [$((CURRENT_STAGE - 1))/5]: $STAGE_DESC. Exiting."' ERR

CURRENT_STAGE=1
STAGE_DESC="Initializing Setup"

echo "🚀 Stage [$CURRENT_STAGE/5]: $STAGE_DESC..."
((CURRENT_STAGE++))

STAGE_DESC="Installing System Packages & Git"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/5]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "⚙️  Adding official Git PPA..."
sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 add-apt-repository -y ppa:git-core/ppa > /dev/null

echo "⚙️  Updating package lists and installing prerequisites..."
sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get update -y > /dev/null
sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    net-tools \
    git > /dev/null
echo "✅ System packages and latest Git installed."

STAGE_DESC="Installing Docker Engine"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/5]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "⚙️  Adding Docker GPG key and repository..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "⚙️  Installing Docker Engine and Compose plugin..."
sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get update -y > /dev/null
sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null
echo "✅ Docker Engine installed successfully."

STAGE_DESC="Performing Post-Installation Steps"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/5]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "⚙️  Adding current user (${USER}) to the 'docker' group..."
sudo usermod -aG docker $USER
echo "✅ User added to docker group."

echo "⚙️  Setting iptables to legacy mode for compatibility..."
echo "1" | sudo update-alternatives --config iptables > /dev/null
echo "✅ iptables configured."

echo "⚙️  Starting and enabling Docker service..."
sudo systemctl start docker
sudo systemctl enable docker
echo "✅ Docker service is running."

STAGE_DESC="Finalizing Setup"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/5]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "🔍 Verifying Docker installation..."
docker --version
docker compose version
echo "✅ Docker installation verified."

echo ""
echo "🎉 =============================================== 🎉"
echo "      Docker & Git setup is complete!                "
echo "      Please log out and log back in for group     "
echo "      changes to take full effect.                   "
echo "🎉 =============================================== 🎉"
