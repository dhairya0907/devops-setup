#!/bin/bash

# ==============================================================================
# Master Multipass VM Setup Script for a Central Dev/Prod Server
# Version: 2.0.0
# Date: 2025-07-30
# ==============================================================================
#
# Description:
# This script is a self-contained utility to automate the creation AND
# configuration of a complete self-hosted CI/CD pipeline.
#
# It provisions the VMs, hardens the production server, and deploys all
# necessary utility scripts and background services.
#
# Usage:
#   1. Ensure all scripts (publish.sh, ci_runner.sh, etc.) are in their
#      correct subdirectories (scripts/utils/, scripts/ci/, etc.).
#   2. Create a `.env` file (or let the script create one for you).
#   3. Make this script executable: `chmod +x scripts/provision/setup_vm.sh`
#   4. From the root of the `devops-setup` repository, run:
#      - For production:  `./scripts/provision/setup_vm.sh prod`
#      - For development: `./scripts/provision/setup_vm.sh dev /path/to/your/local/developer/folder`
#
# ==============================================================================

set -e
trap 'echo "❌ Installation failed at stage [$((CURRENT_STAGE - 1))/10]: $STAGE_DESC. Exiting."' ERR

# --- CONFIGURATION ---
if [ ! -f .env ]; then
    echo "⚠️  .env file not found. Creating a default one."
    cat > .env << EOL
# =================================================
# Global Server Configuration
# =================================================

# --- General Settings ---
TIMEZONE="Asia/Kolkata"

# --- Background Service Intervals (in seconds) ---
CI_RUNNER_INTERVAL=60
DEPLOYMENT_POLLER_INTERVAL=60

# --- Production Docker Registry Settings ---
REGISTRY_USER="automation"
REGISTRY_PASSWORD="change-this-strong-password"
REGISTRY_PORT="5000"

# --- Notification Settings (Slack) ---
SLACK_BOT_TOKEN="YOUR_SLACK_BOT_TOKEN_HERE"
SLACK_DEFAULT_CHANNEL="YOUR_DEFAULT_CHANNEL_ID"

# --- Notification Settings (Email) ---
EMAIL_SMTP_URL="smtps://smtp.gmail.com:465"
EMAIL_SMTP_USER="your-gmail-address@gmail.com"
EMAIL_SMTP_PASSWORD="your-16-character-app-password"
EMAIL_FROM_ADDRESS="your-gmail-address@gmail.com"
EMAIL_DEFAULT_RECIPIENT="recipient@example.com"
EOL
    echo "✅ Default .env file created. Please review and edit it with your secrets."
    echo "   Press [Enter] to continue..."
    read
fi

export $(grep -v '^#' .env | xargs)

# --- SCRIPT LOGIC ---
REPO_ROOT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/../.." &> /dev/null && pwd )
CURRENT_STAGE=1
STAGE_DESC="Initializing Setup"

echo "🚀 Stage [$CURRENT_STAGE/10]: $STAGE_DESC..."
((CURRENT_STAGE++))

STAGE_DESC="Performing Pre-flight Checks"
echo "⚙️  Performing pre-flight checks..."
if ! command -v multipass &> /dev/null; then
    echo "❌ Error: The 'multipass' command could not be found."
    exit 1
fi
echo "✅ Multipass is installed."

echo "⚙️  Validating script arguments..."
if [[ "$1" != "dev" && "$1" != "prod" ]]; then
    echo "❌ Error: Invalid environment type. Please specify 'dev' or 'prod'."
    exit 1
fi

ENV_TYPE=$1
LOCAL_MOUNT_PATH=$2

if [ "$ENV_TYPE" == "dev" ] && [ -z "$LOCAL_MOUNT_PATH" ]; then
    echo "❌ Error: For 'dev' environment, you must provide a local path to mount."
    exit 1
fi

if [ "$ENV_TYPE" == "prod" ] && [ -z "$REGISTRY_PASSWORD" ]; then
    echo "❌ REGISTRY_PASSWORD is not set in .env file."
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

LOCAL_SSH_DIR="${REPO_ROOT}/ssh"
VM_SSH_KEY_PATH="${LOCAL_SSH_DIR}/${VM_NAME}.key"
AUTOMATION_SSH_KEY_PATH="${LOCAL_SSH_DIR}/${VM_NAME}_automation.key"

STAGE_DESC="Provisioning Virtual Machine"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/10]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "🔍 Checking if VM '${VM_NAME}' already exists..."
if multipass info "${VM_NAME}" > /dev/null 2>&1; then
    echo "✅ VM '${VM_NAME}' already exists. Skipping entire setup."
    exit 0
fi
echo "⚙️  VM does not exist. Proceeding with creation..."

mkdir -p "${LOCAL_SSH_DIR}"
echo "⚙️  Launching VM: ${VM_NAME}..."
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

STAGE_DESC="Applying Initial VM Configuration"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/10]: $STAGE_DESC..."
((CURRENT_STAGE++))
echo "⚙️  Configuring package manager for non-interactive mode..."
NEEDRESTART_CONFIG=$(cat <<'EOC'
$nrconf{restart} = 'a';
$nrconf{ui} = 'Noninteractive';
$nrconf{kernelhints} = -1;
EOC
)
multipass exec "$VM_NAME" -- sudo bash -c "cat > /etc/needrestart/conf.d/99-non-interactive.conf" <<< "$NEEDRESTART_CONFIG"
echo "✅ System configured for silent updates."

STAGE_DESC="Configuring SSH Access"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/10]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "🔑 Generating SSH key for default 'ubuntu' user..."
if [ -f "${VM_SSH_KEY_PATH}" ]; then
    echo "   Key already exists. Skipping creation."
else
    ssh-keygen -t ed25519 -f "${VM_SSH_KEY_PATH}" -N "" -C "${USER}@${VM_NAME}" > /dev/null
    echo "   New SSH key generated."
fi

echo "⚙️  Transferring public key to '${VM_NAME}'..."
multipass transfer "${VM_SSH_KEY_PATH}.pub" "${VM_NAME}:/home/ubuntu/vm_key.pub" > /dev/null
multipass exec "$VM_NAME" -- bash -c "mkdir -p /home/ubuntu/.ssh && cat /home/ubuntu/vm_key.pub >> /home/ubuntu/.ssh/authorized_keys && chmod 700 /home/ubuntu/.ssh && chmod 600 /home/ubuntu/.ssh/authorized_keys && chown -R ubuntu:ubuntu /home/ubuntu/.ssh && rm /home/ubuntu/vm_key.pub" > /dev/null
echo "✅ Public key configured for 'ubuntu' user."

echo "⚙️  Updating local ~/.ssh/config for easy access..."
VM_IP=$(multipass info "$VM_NAME" | grep IPv4 | awk '{print $2}')
CONFIG_BLOCK="
Host ${VM_NAME}
  HostName ${VM_IP}
  User ubuntu
  IdentityFile ${VM_SSH_KEY_PATH}
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

STAGE_DESC="Installing Docker Engine & Tools"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/10]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "⚙️  Installing Docker prerequisites, Git, and JQ..."
multipass exec "$VM_NAME" -- sudo bash <<'END_INSTALL_PREREQS'
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get update -y > /dev/null
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common net-tools git jq > /dev/null
END_INSTALL_PREREQS

echo "⚙️  Adding Docker GPG key and repository..."
multipass exec "$VM_NAME" -- sudo bash <<'END_ADD_GPG'
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
END_ADD_GPG

echo "⚙️  Installing Docker Engine..."
multipass exec "$VM_NAME" -- sudo bash <<'END_INSTALL_DOCKER'
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get update -y  > /dev/null
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin  > /dev/null
END_INSTALL_DOCKER

echo "⚙️  Performing post-installation steps..."
multipass exec "$VM_NAME" -- sudo bash <<'END_POST_INSTALL'
    usermod -aG docker ubuntu > /dev/null
    echo "1" | update-alternatives --config iptables > /dev/null
END_POST_INSTALL

echo "⚙️  Restarting VM to apply group changes..."
multipass stop "$VM_NAME" > /dev/null
multipass start "$VM_NAME" > /dev/null

echo "🔍 Verifying Docker installation..."
sleep 10
multipass exec "$VM_NAME" -- bash -c "docker run hello-world > /dev/null 2>&1"
multipass exec "$VM_NAME" -- bash -c "docker system prune -af > /dev/null 2>&1"
echo "✅ Docker and tools installed and verified successfully."

STAGE_DESC="Deploying CI/CD Scripts & Tools"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/10]: $STAGE_DESC..."
((CURRENT_STAGE++))

echo "⚙️  Transferring scripts and examples to the VM..."
multipass transfer --recursive "${REPO_ROOT}/scripts" "${VM_NAME}:/tmp/scripts" > /dev/null
multipass transfer --recursive "${REPO_ROOT}/examples" "${VM_NAME}:/tmp/examples" > /dev/null
echo "✅ Scripts and examples transferred."

echo "⚙️  Installing global commands..."
if [ "$ENV_TYPE" == "dev" ]; then
    multipass exec "$VM_NAME" -- sudo bash <<'END_DEV_INSTALL'
        cp /tmp/scripts/utils/project-init.sh /usr/local/bin/project-init
        cp /tmp/scripts/utils/publish.sh /usr/local/bin/publish
        cp /tmp/scripts/utils/notify.sh /usr/local/bin/notify
        chmod +x /usr/local/bin/*
END_DEV_INSTALL
    echo "✅ Global commands 'project-init', 'publish', and 'notify' installed."
else # prod
    multipass exec "$VM_NAME" -- sudo bash <<'END_PROD_INSTALL'
        cp /tmp/scripts/utils/notify.sh /usr/local/bin/notify
        chmod +x /usr/local/bin/notify
END_PROD_INSTALL
    echo "✅ Global command 'notify' installed."
fi

STAGE_DESC="Setting up Local Docker Registry"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/10]: $STAGE_DESC..."
if [ "$ENV_TYPE" == "prod" ]; then
    echo "📦 [PROD] Deploying self-hosted authenticated Docker registry..."
    multipass exec "$VM_NAME" -- sudo bash -c '
        docker pull registry:2 > /dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y apache2-utils > /dev/null
        mkdir -p /home/ubuntu/registry/auth
        chown ubuntu:ubuntu /home/ubuntu/registry -R
        htpasswd -B -c -b /home/ubuntu/registry/auth/htpasswd '"$REGISTRY_USER"' '"$REGISTRY_PASSWORD"' > /dev/null 2>&1
        docker run -d \
          -p '"$REGISTRY_PORT"':5000 \
          --restart=always \
          --name registry \
          -v /home/ubuntu/registry/auth:/auth \
          -e "REGISTRY_AUTH=htpasswd" \
          -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
          -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
          registry:2 > /dev/null 2>&1
    '
    echo "✅ [PROD] Docker registry container is running with authentication."

    echo "⚙️  [PROD] Configuring Docker to trust local registry..."
    multipass exec "$VM_NAME" -- sudo bash -c 'echo '\''{"insecure-registries": ["localhost:'"$REGISTRY_PORT"'"]}'\'' | sudo tee /etc/docker/daemon.json > /dev/null'
    multipass exec "$VM_NAME" -- sudo systemctl restart docker
    echo "✅ [PROD] Docker daemon configured and restarted."
else
    echo "⏭️  Skipping local registry setup for ${ENV_TYPE} environment."
fi
((CURRENT_STAGE++))

STAGE_DESC="Installing Developer & Automation Tools"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/10]: $STAGE_DESC..."
if [ "$ENV_TYPE" == "dev" ]; then
    echo "📦 [DEV] Installing Python 3.13 and tools..."
    multipass exec "$VM_NAME" -- sudo bash <<'END_PYTHON_INSTALL'
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get update -y > /dev/null
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y software-properties-common > /dev/null
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 add-apt-repository -y ppa:deadsnakes/ppa > /dev/null
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get update -y > /dev/null
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y python3.13 python3.13-venv > /dev/null
END_PYTHON_INSTALL
    echo "✅ [DEV] Python 3.13 installed."

    echo "👤 [DEV] Creating dedicated 'automation' user..."
    multipass exec "$VM_NAME" -- sudo useradd -m -s /bin/bash automation
    multipass exec "$VM_NAME" -- sudo usermod -aG docker automation
    echo "✅ [DEV] 'automation' user created and added to docker group."

    echo "🔑 [DEV] Generating SSH key for 'automation' user..."
    if [ -f "${AUTOMATION_SSH_KEY_PATH}" ]; then
        echo "   Key already exists. Skipping creation."
    else
        ssh-keygen -t ed25519 -f "${AUTOMATION_SSH_KEY_PATH}" -N "" -C "automation@${VM_NAME}" > /dev/null
        echo "   New SSH key generated for 'automation' user."
    fi
    multipass transfer "${AUTOMATION_SSH_KEY_PATH}.pub" "${VM_NAME}:/tmp/automation_key.pub" > /dev/null
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

    echo "🔑 [DEV] Generating dedicated GitHub SSH key for 'automation' user..."
    GITHUB_SSH_KEY_PATH="${LOCAL_SSH_DIR}/${VM_NAME}_github.key"
    if [ -f "${GITHUB_SSH_KEY_PATH}" ]; then
        echo "   Key already exists. Skipping creation."
    else
        ssh-keygen -t ed25519 -f "${GITHUB_SSH_KEY_PATH}" -N "" -C "github-automation-${VM_NAME}" > /dev/null
        echo "   New GitHub SSH key generated."
    fi

    echo ""
    echo "❗ ACTION REQUIRED for 'automation' user on ${VM_NAME} ❗"
    echo "   Please add the following public key to your main GitHub account:"
    echo "   Go to: https://github.com/settings/keys"
    echo "   Click 'New SSH key', give it a title (e.g., 'automation-${VM_NAME}'), and paste the key below."
    echo "   --------------------------------------------------------------------------------"
    cat "${GITHUB_SSH_KEY_PATH}.pub" | sed 's/^/   /'
    echo "   --------------------------------------------------------------------------------"
    read -p "   Press [Enter] to continue once the key has been added to GitHub..."

    echo "⚙️  [DEV] Transferring and configuring GitHub private key for 'automation' user..."
    multipass transfer "${GITHUB_SSH_KEY_PATH}" "${VM_NAME}:/tmp/id_github" > /dev/null
    multipass exec "$VM_NAME" -- sudo bash <<'END_SCRIPT_2'
        mv /tmp/id_github /home/automation/.ssh/id_github
        chown automation:automation /home/automation/.ssh/id_github
        chmod 600 /home/automation/.ssh/id_github
        echo -e 'Host github.com\n  IdentityFile ~/.ssh/id_github\n  StrictHostKeyChecking accept-new' >> /home/automation/.ssh/config
        chown automation:automation /home/automation/.ssh/config
END_SCRIPT_2

    echo "🔍 [DEV] Testing GitHub SSH connection from 'automation' user..."
    auth_output=$(multipass exec "$VM_NAME" -- sudo --login --user automation ssh -T git@github.com 2>&1 || true)
    if echo "$auth_output" | grep -q "successfully authenticated"; then
        echo "✅ [DEV] GitHub authentication succeeded for 'automation' user."
    else
        echo "❌ GitHub authentication failed for 'automation' user!"
        echo "   GitHub's response:"
        echo "$auth_output" | sed 's/^/   | /'
        exit 1
    fi
else
    echo "⏭️  Skipping Developer & Automation Tools install for ${ENV_TYPE} environment."
fi
((CURRENT_STAGE++))

STAGE_DESC="Applying Security Hardening & Final Configuration"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/9]: $STAGE_DESC..."
((CURRENT_STAGE++))

if [ "$ENV_TYPE" == "prod" ]; then
    echo "🛡️  Installing UFW and Fail2Ban..."
    multipass exec "$VM_NAME" -- sudo bash -c 'DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1 apt-get install -y ufw fail2ban > /dev/null'

    echo "⚙️  Configuring Firewall..."
    multipass exec "$VM_NAME" -- sudo bash -c 'ufw default deny incoming > /dev/null'
    multipass exec "$VM_NAME" -- sudo bash -c 'ufw default allow outgoing > /dev/null'
    multipass exec "$VM_NAME" -- sudo bash -c 'ufw allow ssh > /dev/null'
    multipass exec "$VM_NAME" -- sudo bash -c 'ufw allow http > /dev/null'
    multipass exec "$VM_NAME" -- sudo bash -c 'ufw allow https > /dev/null'
    multipass exec "$VM_NAME" -- sudo bash -c 'ufw allow '"$REGISTRY_PORT"'/tcp > /dev/null'
    multipass exec "$VM_NAME" -- sudo bash -c 'ufw --force enable > /dev/null'
    echo "✅ Firewall enabled. Fail2Ban active."
else
    echo "⏭️  Skipping security hardening for ${ENV_TYPE} environment."
fi

echo "⚙️  Setting timezone to ${TIMEZONE}..."
multipass exec "$VM_NAME" -- sudo timedatectl set-timezone "${TIMEZONE}" > /dev/null
echo "✅ Timezone configured."

if [ "$ENV_TYPE" == "dev" ]; then
    echo "⚙️  [DEV] Configuring Docker to trust and log in to prod-server registry..."
    PROD_IP=$(multipass info prod-server | grep IPv4 | awk '{print $2}' || echo "not_found")
    if [ "$PROD_IP" != "not_found" ]; then
        multipass exec "$VM_NAME" -- sudo bash -c "echo '{\"insecure-registries\": [\"${PROD_IP}:${REGISTRY_PORT}\"]}' | sudo tee /etc/docker/daemon.json > /dev/null"
        multipass exec "$VM_NAME" -- sudo systemctl restart docker
        sleep 5
        
        AUTH_STRING=$(echo -n "${REGISTRY_USER}:${REGISTRY_PASSWORD}" | base64)
        DOCKER_CONFIG_JSON="{\"auths\": {\"${PROD_IP}:${REGISTRY_PORT}\": {\"auth\": \"${AUTH_STRING}\"}}}"
        
        multipass exec "$VM_NAME" -- sudo --login --user automation bash <<END_DOCKER_CONFIG
            mkdir -p ~/.docker
            echo '${DOCKER_CONFIG_JSON}' > ~/.docker/config.json
            chmod 600 ~/.docker/config.json
END_DOCKER_CONFIG
        echo "✅ [DEV] Docker on dev-server is now configured for the 'automation' user."
    else
        echo "⚠️  [DEV] Could not find prod-server to automatically configure Docker registry access."
        echo "   Please run the prod-server setup first, then re-run this script for the dev-server."
    fi
fi

STAGE_DESC="Starting Background Services"
echo ""
echo "🚀 Stage [$CURRENT_STAGE/9]: $STAGE_DESC..."
((CURRENT_STAGE++))

# Generate notify.conf from .env variables
NOTIFY_CONFIG=$(cat <<EOC
[slack]
bot_token="${SLACK_BOT_TOKEN}"
default_channel="${SLACK_DEFAULT_CHANNEL}"

[email]
smtp_url="${EMAIL_SMTP_URL}"
smtp_user="${EMAIL_SMTP_USER}"
smtp_password="${EMAIL_SMTP_PASSWORD}"
from_address="${EMAIL_FROM_ADDRESS}"
default_recipient="${EMAIL_DEFAULT_RECIPIENT}"
EOC
)
multipass exec "$VM_NAME" -- sudo bash -c "cat > /etc/notify.conf && chmod 600 /etc/notify.conf" <<< "$NOTIFY_CONFIG"
echo "✅ /etc/notify.conf generated from .env secrets."

if [ "$ENV_TYPE" == "dev" ]; then
    echo "⚙️  [DEV] Setting up and starting CI runner service..."
    PROD_IP=$(multipass info prod-server | grep IPv4 | awk '{print $2}')
    multipass exec "$VM_NAME" -- sudo bash <<'END_CI_SETUP'
        mkdir -p /home/automation/ci-runner/logs
        mkdir -p /home/automation/ci-runner/state
        cp /tmp/scripts/ci/ci_runner.sh /home/automation/ci-runner/
        touch /home/automation/ci-runner/projects.list
        chmod +x /home/automation/ci-runner/ci_runner.sh
        chown -R automation:automation /home/automation/ci-runner
END_CI_SETUP
    
    CI_RUNNER_SERVICE=$(cat <<EOC
[Unit]
Description=Self-Hosted CI Runner Service
After=network-online.target

[Service]
User=automation
Group=automation
WorkingDirectory=/home/automation/ci-runner
ExecStart=/home/automation/ci-runner/ci_runner.sh ${PROD_IP} ${REGISTRY_PORT} ${CI_RUNNER_INTERVAL}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOC
)
    multipass exec "$VM_NAME" -- sudo bash -c "cat > /etc/systemd/system/ci-runner.service" <<< "$CI_RUNNER_SERVICE"
    multipass exec "$VM_NAME" -- sudo systemctl daemon-reload
    multipass exec "$VM_NAME" -- sudo systemctl enable ci-runner.service
    multipass exec "$VM_NAME" -- sudo systemctl start ci-runner.service
    echo "✅ CI runner is now running in the background."

else # prod
    echo "⚙️  [PROD] Setting up and starting deployment poller service..."
    multipass exec "$VM_NAME" -- sudo bash -c "
        mkdir -p /home/ubuntu/deploy-runner/logs
        mkdir -p /home/ubuntu/deploy-runner/state
        cp /tmp/scripts/cd/deploy.sh /home/ubuntu/deploy-runner/
        cp /tmp/scripts/cd/deployment_poller.sh /home/ubuntu/deploy-runner/
        touch /home/ubuntu/deploy-runner/projects-prod.list
        chmod +x /home/ubuntu/deploy-runner/*.sh
        chown -R ubuntu:ubuntu /home/ubuntu/deploy-runner
    "

    DEPLOYMENT_POLLER_SERVICE=$(cat <<EOC
[Unit]
Description=Deployment Poller Service
After=network-online.target docker.service
Requires=docker.service

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu/deploy-runner
ExecStart=/home/ubuntu/deploy-runner/deployment_poller.sh ${REGISTRY_PORT} ${DEPLOYMENT_POLLER_INTERVAL}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOC
)
    multipass exec "$VM_NAME" -- sudo bash -c "cat > /etc/systemd/system/deployment-poller.service" <<< "$DEPLOYMENT_POLLER_SERVICE"
    multipass exec "$VM_NAME" -- sudo systemctl daemon-reload
    multipass exec "$VM_NAME" -- sudo systemctl enable deployment-poller.service
    multipass exec "$VM_NAME" -- sudo systemctl start deployment-poller.service
    echo "✅ Deployment poller is now running in the background."
fi

# Final cleanup of transferred scripts
multipass exec "$VM_NAME" -- sudo rm -rf /tmp/scripts /tmp/examples

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
  IdentityFile ${AUTOMATION_SSH_KEY_PATH}
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
echo ""
echo "💡 NEXT STEPS:"
if [ "$ENV_TYPE" == "dev" ]; then
    echo "   1. SSH into the dev server as the automation user: ssh dev-server-automation"
    echo "   2. Edit the project list: vim ~/ci-runner/projects.list"
    echo "   3. Add your project secret files to: ~/secrets/<project_name>/"
else # prod
    echo "   1. SSH into the prod server: ssh prod-server"
    echo "   2. Edit the project list: vim ~/deploy-runner/projects-prod.list"
fi
