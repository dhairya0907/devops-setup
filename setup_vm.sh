#!/bin/bash

# ==============================================================================
# General Multipass VM Setup Script for a Central Dev/Prod Server
# Version: 1.0.0
# Date: 2025-07-28
# ==============================================================================
#
# Description:
# This script is a self-contained utility to automate the creation of a
# development (build) OR production (runtime) VM. It is designed for a
# self-hosted CI/CD pipeline.
#
# It includes pre-flight checks, an authenticated Docker registry (for prod),
# security hardening (for prod), a dedicated automation user (for dev),
# system updates, timezone configuration, and developer tools (for dev).
#
# Usage:
#   1. Create a `.env` file (or let the script create one for you).
#   2. Make this script executable: `chmod +x setup_vm.sh`
#   3. From the script's directory, run:
#      - For production:  `./setup_vm.sh prod`
#      - For development: `./setup_vm.sh dev /path/to/your/local/developer/folder`
#
# ==============================================================================

set -e
trap 'echo "❌ Installation failed at stage [$((CURRENT_STAGE - 1))/8]: $STAGE_DESC. Exiting."' ERR

# --- CONFIGURATION ---
if [ ! -f .env ]; then
    echo "⚠️  .env file not found. Creating a default one."
    cat > .env << EOL
# =================================================
# VM and Server Configuration
# =================================================

# --- General Settings ---
TIMEZONE="Asia/Kolkata"

# --- Production Docker Registry Settings ---
REGISTRY_USER="automation"
REGISTRY_PASSWORD=""
REGISTRY_PORT="5000"
EOL
    echo "✅ Default .env file created. Please review and edit it if necessary."
    echo "⚠️  The REGISTRY_PASSWORD is empty. You MUST set a strong password before using this script in production."
    echo "   Press [Enter] to continue..."
    read
fi

export $(grep -v '^#' .env | xargs)

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CURRENT_STAGE=1
STAGE_DESC="Initializing Setup"

echo "🚀 Stage [$CURRENT_STAGE/8]: $STAGE_DESC..."
((CURRENT_STAGE++))

STAGE_DESC="Performing Pre-flight Checks"
echo "⚙️  Performing pre-flight checks..."
if ! command -v multipass &> /dev/null; then
    echo "❌ Error: The 'multipass' command could not be found."
    echo "Please install Multipass first: https://multipass.run/install"
    exit 1
fi
echo "✅ Multipass is installed."

echo "⚙️  Validating script arguments..."
if [[ "$1" != "dev" && "$1" != "prod" ]]; then
    echo "❌ Error: Invalid environment type. Please specify 'dev' or 'prod'."
    echo "Usage: $0 [dev|prod] [path_or_skip]"
    exit 1
fi

ENV_TYPE=$1
LOCAL_MOUNT_PATH=$2

if [ "$ENV_TYPE" == "dev" ] && [ -z "$LOCAL_MOUNT_PATH" ]; then
    echo "❌ Error: For 'dev' environment, you must provide a local path to mount."
    echo "Usage: $0 dev /path/to/your/folder"
    exit 1
fi

# Check for registry password only when setting up a prod server
if [ "$ENV_TYPE" == "prod" ] && [ -z "$REGISTRY_PASSWORD" ]; then
    echo "❌ REGISTRY_PASSWORD is not set. Please edit the .env file and set a strong password."
    exit 1
fi
echo "✅ Arguments and required files are valid."

if [ "$ENV_TYPE" == "dev" ]; then
    VM_NAME="dev-server"
    CPUS=2
    MEM="4G"
    DISK="20G"
else
    VM_NAME="prod-server"
    CPUS=4
    MEM="4G"
    DISK="50G"
fi

LOCAL_SSH_DIR="ssh"
VM_SSH_KEY_PATH="${LOCAL_SSH_DIR}/${VM_NAME}.key"
GITHUB_SSH_KEY_PATH="${LOCAL_SSH_DIR}/${VM_NAME}_github.key"
AUTOMATION_SSH_KEY_PATH="${LOCAL_SSH_DIR}/${VM_NAME}_automation.key"

STAGE_DESC="Provisioning Virtual Machine"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/8]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "🔍 Checking if VM '${VM_NAME}' already exists..."
if multipass info "${VM_NAME}" > /dev/null 2>&1; then
    echo "✅ VM '${VM_NAME}' already exists. Skipping entire setup."
    echo "   To start from scratch, first run: multipass delete ${VM_NAME} && multipass purge"
    exit 0
fi
echo "⚙️  VM does not exist. Proceeding with creation..."

mkdir -p "${SCRIPT_DIR}/${LOCAL_SSH_DIR}"
echo "⚙️  Launching VM: ${VM_NAME} (CPUs: ${CPUS}, Mem: ${MEM}, Disk: ${DISK}). This may take a moment..."
multipass launch 24.04 --name "$VM_NAME" --cpus "$CPUS" --memory "$MEM" --disk "$DISK" > /dev/null
echo "✅ VM '${VM_NAME}' launched successfully."

if [ "$ENV_TYPE" == "dev" ]; then
    echo "⚙️  [DEV] Mounting local directory: ${LOCAL_MOUNT_PATH}..."
    mkdir -p "$LOCAL_MOUNT_PATH"
    multipass mount "$LOCAL_MOUNT_PATH" "$VM_NAME:/home/ubuntu/Developer" > /dev/null
    echo "✅ [DEV] Directory mounted."
else
    echo "⚙️  [PROD] Skipping local directory mount as per production setup."
fi

STAGE_DESC="Configuring SSH Access"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/8]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "🔑 Generating SSH key for default 'ubuntu' user..."
if [ -f "${SCRIPT_DIR}/${VM_SSH_KEY_PATH}" ]; then
    echo "   Key already exists. Skipping creation."
else
    ssh-keygen -t ed25519 -f "${SCRIPT_DIR}/${VM_SSH_KEY_PATH}" -N "" -C "${USER}@${VM_NAME}" > /dev/null
    echo "   New SSH key generated."
fi

echo "⚙️  Transferring public key to '${VM_NAME}'..."
multipass transfer "${SCRIPT_DIR}/${VM_SSH_KEY_PATH}.pub" "${VM_NAME}:/home/ubuntu/vm_key.pub" > /dev/null
multipass exec "$VM_NAME" -- bash -c "mkdir -p /home/ubuntu/.ssh && cat /home/ubuntu/vm_key.pub >> /home/ubuntu/.ssh/authorized_keys && chmod 700 /home/ubuntu/.ssh && chmod 600 /home/ubuntu/.ssh/authorized_keys && chown -R ubuntu:ubuntu /home/ubuntu/.ssh && rm /home/ubuntu/vm_key.pub" > /dev/null
echo "✅ Public key configured for 'ubuntu' user."

echo "⚙️  Updating local ~/.ssh/config for easy access..."
VM_IP=$(multipass info "$VM_NAME" | grep IPv4 | awk '{print $2}')
CONFIG_BLOCK="
Host ${VM_NAME}
  HostName ${VM_IP}
  User ubuntu
  IdentityFile ${SCRIPT_DIR}/${VM_SSH_KEY_PATH}
  IdentitiesOnly yes"

SSH_CONFIG_TMP=$(mktemp)

if grep -q "Host ${VM_NAME}" ~/.ssh/config; then
    echo "   Updating existing SSH alias '${VM_NAME}' with new IP address..."
    awk -v host="${VM_NAME}" '
        $1 == "Host" && $2 == host {in_block=1; next}
        $1 == "Host" {in_block=0}
        !in_block {print}
    ' ~/.ssh/config > "$SSH_CONFIG_TMP"
    echo -e "${CONFIG_BLOCK}" >> "$SSH_CONFIG_TMP"
    cat "$SSH_CONFIG_TMP" > ~/.ssh/config
    rm "$SSH_CONFIG_TMP"
    echo "✅ SSH alias '${VM_NAME}' updated."
else
    echo "   Adding new SSH alias '${VM_NAME}' to local config..."
    echo -e "${CONFIG_BLOCK}" >> ~/.ssh/config
    echo "✅ SSH alias '${VM_NAME}' added."
fi

STAGE_DESC="Installing Docker Engine"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/8]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "⚙️  Installing Docker prerequisites and Git..."
multipass exec "$VM_NAME" -- bash -c '
    sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get update -y > /dev/null
    sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common net-tools git > /dev/null
'

echo "⚙️  Adding Docker GPG key and repository..."
multipass exec "$VM_NAME" -- bash -c '
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
' > /dev/null

echo "⚙️  Installing Docker Engine..."
multipass exec "$VM_NAME" -- bash -c '
    sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get update -y  > /dev/null
    sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin  > /dev/null
'

echo "⚙️  Performing post-installation steps..."
multipass exec "$VM_NAME" -- bash -c '
    sudo usermod -aG docker ubuntu > /dev/null
    echo "1" | sudo update-alternatives --config iptables > /dev/null
'

echo "⚙️  Restarting VM to apply group changes..."
multipass stop "$VM_NAME" > /dev/null
multipass start "$VM_NAME" > /dev/null

echo "🔍 Verifying Docker installation..."
sleep 10
multipass exec "$VM_NAME" -- bash -c "docker run hello-world > /dev/null 2>&1"
multipass exec "$VM_NAME" -- bash -c "docker system prune -af > /dev/null 2>&1"
echo "✅ Docker installed and verified successfully."

STAGE_DESC="Setting up Local Docker Registry"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/8]: $STAGE_DESC..."
if [ "$ENV_TYPE" == "prod" ]; then
    echo "📦 [PROD] Deploying self-hosted authenticated Docker registry..."
    multipass exec "$VM_NAME" -- bash -c '
        docker pull registry:2 > /dev/null 2>&1
        sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y apache2-utils > /dev/null
        mkdir -p ~/registry/auth
        htpasswd -B -c -b ~/registry/auth/htpasswd '"$REGISTRY_USER"' '"$REGISTRY_PASSWORD"' > /dev/null
        docker run -d \
          -p '"$REGISTRY_PORT"':5000 \
          --restart=always \
          --name registry \
          -v ~/registry/auth:/auth \
          -e "REGISTRY_AUTH=htpasswd" \
          -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
          -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
          registry:2 > /dev/null 2>&1
    '
    echo "✅ [PROD] Docker registry container is running with authentication."

    echo "⚙️  [PROD] Configuring Docker to trust local registry..."
    multipass exec "$VM_NAME" -- bash -c 'echo '\''{"insecure-registries": ["localhost:'"$REGISTRY_PORT"'"]}'\'' | sudo tee /etc/docker/daemon.json > /dev/null'
    multipass exec "$VM_NAME" -- sudo systemctl restart docker
    echo "✅ [PROD] Docker daemon configured and restarted."
else
    echo "⏭️  Skipping local registry setup for ${ENV_TYPE} environment."
fi
((CURRENT_STAGE++))

STAGE_DESC="Installing Developer & Automation Tools"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/8]: $STAGE_DESC..."
if [ "$ENV_TYPE" == "dev" ]; then
    echo "📦 [DEV] Installing Python 3.13 and tools..."
    multipass exec "$VM_NAME" -- bash -c '
        sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get update -y > /dev/null
        sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y software-properties-common > /dev/null
        sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 add-apt-repository -y ppa:deadsnakes/ppa > /dev/null
        sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get update -y > /dev/null
        sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y python3.13 python3.13-venv > /dev/null
    '
    echo "✅ [DEV] Python 3.13 installed."

    echo "👤 [DEV] Creating dedicated 'automation' user..."
    multipass exec "$VM_NAME" -- sudo useradd -m -s /bin/bash automation
    multipass exec "$VM_NAME" -- sudo usermod -aG docker automation
    echo "✅ [DEV] 'automation' user created and added to docker group."

    echo "🔑 [DEV] Generating SSH key for 'automation' user..."
    if [ -f "${SCRIPT_DIR}/${AUTOMATION_SSH_KEY_PATH}" ]; then
        echo "   Key already exists. Skipping creation."
    else
        ssh-keygen -t ed25519 -f "${SCRIPT_DIR}/${AUTOMATION_SSH_KEY_PATH}" -N "" -C "automation@${VM_NAME}" > /dev/null
        echo "   New SSH key generated for 'automation' user."
    fi
    multipass transfer "${SCRIPT_DIR}/${AUTOMATION_SSH_KEY_PATH}.pub" "${VM_NAME}:/tmp/automation_key.pub" > /dev/null
    multipass exec "$VM_NAME" -- sudo bash <<'END_SCRIPT_1'
        mkdir -p /home/automation/.ssh
        mv /tmp/automation_key.pub /home/automation/.ssh/automation_key.pub
        cat /home/automation/.ssh/automation_key.pub >> /home/automation/.ssh/authorized_keys
        chown -R automation:automation /home/automation/.ssh
        chmod 700 /home/automation/.ssh
        chmod 600 /home/automation/.ssh/authorized_keys
        rm /home/automation/.ssh/automation_key.pub
END_SCRIPT_1
    echo "✅ [DEV] SSH access configured for 'automation' user."

    echo "🔑 Generating dedicated SSH key for GitHub..."
    if [ -f "${SCRIPT_DIR}/${GITHUB_SSH_KEY_PATH}" ]; then
        echo "   Key already exists. Skipping creation."
    else
        ssh-keygen -t ed25519 -f "${SCRIPT_DIR}/${GITHUB_SSH_KEY_PATH}" -N "" -C "github-${VM_NAME}" > /dev/null
        echo "   New GitHub SSH key generated."
    fi

    echo ""
    echo "❗ ACTION REQUIRED for ${VM_NAME} ❗"
    echo "   Please add the following public key to your main GitHub account:"
    echo "   Go to: https://github.com/settings/keys"
    echo "   Click 'New SSH key', give it a title (e.g., '${VM_NAME}'), and paste the key below."
    echo "   --------------------------------------------------------------------------------"
    cat "${SCRIPT_DIR}/${GITHUB_SSH_KEY_PATH}.pub" | sed 's/^/   /'
    echo "   --------------------------------------------------------------------------------"
    read -p "   Press [Enter] to continue once the key has been added to GitHub..."

    echo "⚙️  Transferring and configuring private key on '${VM_NAME}'..."
    multipass transfer "${SCRIPT_DIR}/${GITHUB_SSH_KEY_PATH}" "${VM_NAME}:/tmp/id_github" > /dev/null
    multipass exec "$VM_NAME" -- sudo bash <<'END_SCRIPT_2'
        mv /tmp/id_github /home/automation/.ssh/id_github
        chown automation:automation /home/automation/.ssh/id_github
        chmod 600 /home/automation/.ssh/id_github
        echo -e 'Host github.com\n  IdentityFile ~/.ssh/id_github\n  StrictHostKeyChecking accept-new' >> /home/automation/.ssh/config
        chown automation:automation /home/automation/.ssh/config
END_SCRIPT_2

    echo "🔍 Testing GitHub SSH connection from VM..."
    auth_output=$(multipass exec "$VM_NAME" -- sudo --login --user automation ssh -T git@github.com 2>&1 || true)
    if echo "$auth_output" | grep -q "successfully authenticated"; then
        echo "✅ GitHub authentication succeeded."
    else
        echo "❌ GitHub authentication failed! Please ensure the SSH key was added correctly."
        echo "   GitHub's response:"
        echo "$auth_output" | sed 's/^/   | /'
        exit 1
    fi
else
    echo "⏭️  Skipping GitHub Integration for ${ENV_TYPE} environment."
fi
((CURRENT_STAGE++))

STAGE_DESC="Applying Security Hardening"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/8]: $STAGE_DESC..."
if [ "$ENV_TYPE" == "prod" ]; then
    echo "🛡️  Installing UFW and Fail2Ban..."
    multipass exec "$VM_NAME" -- bash -c 'sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y ufw fail2ban > /dev/null'

    echo "⚙️  Configuring Firewall..."
    multipass exec "$VM_NAME" -- bash -c 'sudo ufw default deny incoming > /dev/null'
    multipass exec "$VM_NAME" -- bash -c 'sudo ufw default allow outgoing > /dev/null'
    multipass exec "$VM_NAME" -- bash -c 'sudo ufw allow ssh > /dev/null'
    multipass exec "$VM_NAME" -- bash -c 'sudo ufw allow http > /dev/null'
    multipass exec "$VM_NAME" -- bash -c 'sudo ufw allow https > /dev/null'
    multipass exec "$VM_NAME" -- bash -c 'sudo ufw allow '"$REGISTRY_PORT"'/tcp > /dev/null'
    multipass exec "$VM_NAME" -- bash -c 'sudo ufw --force enable > /dev/null'
    echo "✅ Firewall enabled. Fail2Ban active."
else
    echo "⏭️  Skipping security hardening for ${ENV_TYPE} environment."
fi
((CURRENT_STAGE++))

STAGE_DESC="Finalizing Configuration"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/8]: $STAGE_DESC..."

echo "⚙️  Setting timezone to ${TIMEZONE}..."
multipass exec "$VM_NAME" -- sudo timedatectl set-timezone "${TIMEZONE}" > /dev/null
echo "✅ Timezone configured."

if [ "$ENV_TYPE" == "dev" ]; then
    echo "⚙️  [DEV] Configuring Docker to trust and log in to prod-server registry..."
    PROD_IP=$(multipass info prod-server | grep IPv4 | awk '{print $2}' || echo "not_found")
    if [ "$PROD_IP" != "not_found" ]; then
        multipass exec "$VM_NAME" -- bash -c "echo '{\"insecure-registries\": [\"${PROD_IP}:${REGISTRY_PORT}\"]}' | sudo tee /etc/docker/daemon.json > /dev/null"
        multipass exec "$VM_NAME" -- sudo systemctl restart docker
        sleep 5
        
        AUTH_STRING=$(echo -n "${REGISTRY_USER}:${REGISTRY_PASSWORD}" | base64)
        DOCKER_CONFIG_JSON="{\"auths\": {\"${PROD_IP}:${REGISTRY_PORT}\": {\"auth\": \"${AUTH_STRING}\"}}}"
        
        multipass exec "$VM_NAME" -- sudo --login --user automation bash -c "
            mkdir -p ~/.docker
            echo '${DOCKER_CONFIG_JSON}' > ~/.docker/config.json
            chmod 600 ~/.docker/config.json
        "
        echo "✅ [DEV] Docker on dev-server is now configured for the 'automation' user."
    else
        echo "⚠️  [DEV] Could not find prod-server to automatically configure Docker registry access."
        echo "   Please run the prod-server setup first, then re-run this script for the dev-server."
    fi
fi

echo ""
echo "🎉 =============================================== 🎉"
echo "      Setup for ${VM_NAME} is complete!              "
echo "      Connect to your VM using: ssh ${VM_NAME}       "
if [ "$ENV_TYPE" == "dev" ]; then
    AUTOMATION_ALIAS="${VM_NAME}-automation"
    echo "⚙️  [DEV] Updating SSH alias for 'automation' user..."
    AUTOMATION_CONFIG_BLOCK="
Host ${AUTOMATION_ALIAS}
  HostName ${VM_IP}
  User automation
  IdentityFile ${SCRIPT_DIR}/${AUTOMATION_SSH_KEY_PATH}
  IdentitiesOnly yes
"
    AUTOMATION_SSH_CONFIG_TMP=$(mktemp)
    if grep -q "Host ${AUTOMATION_ALIAS}" ~/.ssh/config; then
        awk -v host="${AUTOMATION_ALIAS}" '
            $1 == "Host" && $2 == host {in_block=1; next}
            $1 == "Host" {in_block=0}
            !in_block {print}
        ' ~/.ssh/config > "$AUTOMATION_SSH_CONFIG_TMP"
        echo -e "${AUTOMATION_CONFIG_BLOCK}" >> "$AUTOMATION_SSH_CONFIG_TMP"
        cat "$AUTOMATION_SSH_CONFIG_TMP" > ~/.ssh/config
        rm "$AUTOMATION_SSH_CONFIG_TMP"
    else
        echo -e "${AUTOMATION_CONFIG_BLOCK}" >> ~/.ssh/config
    fi
    echo "      Connect as automation user with: ssh ${AUTOMATION_ALIAS}"
fi
echo "🎉 =============================================== 🎉"

