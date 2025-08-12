#!/bin/bash

# ==============================================================================
# Deployment Script
# Version: 2.0.0
# Date: 2025-08-12
# ==============================================================================
#
# Description:
# This script performs a zero-downtime deployment for a specific project.
# It is designed to be called by the `deployment_poller.sh` script.
#
# It pulls the new image from the local registry and redeploys the service.
# It logs the old container state before the deployment into a versioned log file.
#
# Usage:
#   ./deploy.sh <project_name> <new_version_tag> <registry_port>
#
# ==============================================================================

set -e

# --- HELPER FUNCTIONS ---

function notify_slack() {
    local message=$1
    notify --channel slack "$message"
}

trap 'echo "❌ An error occurred in the CI runner. Restarting in 60 seconds..."; notify_slack "❌ An error occurred in the CI runner. Restarting in 60 seconds..."' ERR

# --- ARGUMENT VALIDATION ---
if [ "$#" -ne 3 ]; then
    echo "❌ Error: Invalid arguments." >&2
    echo "Usage: $0 <project_name> <new_version_tag> <registry_port>" >&2
    notify_slack "❌ Deployment failed: Invalid arguments passed to deploy.sh"
    exit 1
fi

PROJECT_NAME=$1
NEW_VERSION=$2
REGISTRY_PORT=$3

export REGISTRY_URL="localhost:${REGISTRY_PORT}"

PROJECTS_BASE_DIR="/home/ubuntu"
PROJECT_DIR="${PROJECTS_BASE_DIR}/${PROJECT_NAME}"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
LOG_FILE="${PROJECT_DIR}/deployment_v${NEW_VERSION}.log"

# --- SCRIPT LOGIC ---

echo "🚀 Starting deployment for ${PROJECT_NAME} version ${NEW_VERSION}..."

# 1. Sanity Checks
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Error: Project directory not found at ${PROJECT_DIR}" >&2
    notify_slack "❌ Deployment failed: Project directory not found at ${PROJECT_DIR}"
    exit 1
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "❌ Error: docker-compose.yml not found at ${COMPOSE_FILE}" >&2
    notify_slack "❌ Deployment failed: docker-compose.yml not found at ${COMPOSE_FILE}"
    exit 1
fi

cd "$PROJECT_DIR"

# 2. Log currently running container info
echo "📝 Logging current container state..." | tee -a "$LOG_FILE"
echo "---- $(date '+%Y-%m-%d %H:%M:%S') ----" >> "$LOG_FILE"

COMPOSE_PROJECT_NAME=$(basename "${PROJECT_DIR}")
docker ps --filter "name=${COMPOSE_PROJECT_NAME}-${PROJECT_NAME}" --format "{{.Names}} -> {{.Image}}" | tee -a "$LOG_FILE"

echo "🗂️  Logged current image(s) before deployment." | tee -a "$LOG_FILE"

# 3. Pull the new image
echo "⚙️  Pulling new image from local registry..." | tee -a "$LOG_FILE"
if docker compose pull >> "$LOG_FILE" 2>&1; then
    echo "✅ Image pulled successfully." | tee -a "$LOG_FILE"
else
    echo "❌ Failed to pull new image." | tee -a "$LOG_FILE"
    notify_slack "❌ Deployment failed: Could not pull new image for ${PROJECT_NAME} version ${NEW_VERSION}"
    exit 1
fi

# 4. Redeploy the service
echo "⚙️  Performing zero-downtime redeployment..." | tee -a "$LOG_FILE"
if docker compose up -d >> "$LOG_FILE" 2>&1; then
    echo "✅ Service redeployed." | tee -a "$LOG_FILE"
else
    echo "❌ Service redeployment failed." | tee -a "$LOG_FILE"
    notify_slack "❌ Deployment failed: Service redeployment failed for ${PROJECT_NAME} version ${NEW_VERSION}"
    exit 1
fi

echo "🎉 Deployment for ${PROJECT_NAME} version ${NEW_VERSION} complete." | tee -a "$LOG_FILE"
notify_slack "🎉 Deployment successful: ${PROJECT_NAME} version ${NEW_VERSION} deployed successfully."

exit 0
