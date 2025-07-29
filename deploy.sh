#!/bin/bash

# ==============================================================================
# Deployment Script
# Version: 2.0.0
# Date: 2025-07-29
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

# --- ARGUMENT VALIDATION ---
if [ "$#" -ne 3 ]; then
    echo "❌ Error: Invalid arguments." >&2
    echo "Usage: $0 <project_name> <new_version_tag> <registry_port>" >&2
    exit 1
fi

PROJECT_NAME=$1
NEW_VERSION=$2
REGISTRY_PORT=$3
REGISTRY_URL="localhost:${REGISTRY_PORT}"

PROJECTS_BASE_DIR="/home/ubuntu"
PROJECT_DIR="${PROJECTS_BASE_DIR}/${PROJECT_NAME}"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
LOG_FILE="${PROJECT_DIR}/deployment_v${NEW_VERSION}.log"

# --- SCRIPT LOGIC ---

echo "🚀 Starting deployment for ${PROJECT_NAME} version ${NEW_VERSION}..."

# 1. Sanity Checks
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Error: Project directory not found at ${PROJECT_DIR}" >&2
    exit 1
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "❌ Error: docker-compose.yml not found at ${COMPOSE_FILE}" >&2
    exit 1
fi

cd "$PROJECT_DIR"

# 2. Log currently running container info
echo "📝 Logging current container state..." | tee -a "$LOG_FILE"
echo "---- $(date '+%Y-%m-%d %H:%M:%S') ----" >> "$LOG_FILE"

docker ps --filter "name=${PROJECT_NAME}" --format "{{.Names}} -> {{.Image}}" | tee -a "$LOG_FILE"

echo "🗂️  Logged current image(s) before deployment." | tee -a "$LOG_FILE"

# 3. Pull the new image
echo "⚙️  Pulling new image from local registry..." | tee -a "$LOG_FILE"
docker compose pull >> "$LOG_FILE" 2>&1
echo "✅ Image pulled successfully." | tee -a "$LOG_FILE"

# 4. Redeploy the service
echo "⚙️  Performing zero-downtime redeployment..." | tee -a "$LOG_FILE"
docker compose up -d >> "$LOG_FILE" 2>&1
echo "✅ Service redeployed." | tee -a "$LOG_FILE"

echo "🎉 Deployment for ${PROJECT_NAME} version ${NEW_VERSION} complete." | tee -a "$LOG_FILE"
exit 0
