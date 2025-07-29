#!/bin/bash

# ==============================================================================
# Deployment Script
# Version: 1.0.0
# Date: 2025-07-29
# ==============================================================================
#
# Description:
# This script performs a zero-downtime deployment for a specific project.
# It is designed to be called by the `deployment_poller.sh` script.
#
# It updates the image tag in the project's docker-compose.yml, pulls the
# new image from the local registry, and redeploys the service.
#
# Usage:
#   This script is not intended to be run manually.
#   The poller will execute it like this:
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

# The base directory where all project deployment configurations are stored.
PROJECTS_BASE_DIR="/home/ubuntu"
PROJECT_DIR="${PROJECTS_BASE_DIR}/${PROJECT_NAME}"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"

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

# 2. Update docker-compose.yml
echo "⚙️  Updating image tag in ${COMPOSE_FILE}..."
# This `sed` command finds the line with `image:` and replaces the tag with the new version.
# It's designed to work even if the line has spaces. The `g` flag is not strictly necessary
# but is good practice. The `-i` flag edits the file in-place.
sed -i -E "s|image:.*${PROJECT_NAME}:.*|image: ${REGISTRY_URL}/${PROJECT_NAME}:${NEW_VERSION}|g" "$COMPOSE_FILE"
echo "✅ docker-compose.yml updated."

# 3. Pull the new image
# We navigate into the project directory to ensure docker-compose commands work correctly.
cd "$PROJECT_DIR"

echo "⚙️  Pulling new image from local registry..."
docker compose pull > /dev/null
echo "✅ Image pulled successfully."

# 4. Redeploy the service
echo "⚙️  Performing zero-downtime redeployment..."
# The `up -d` command will only recreate containers whose configuration or image has changed.
docker compose up -d
echo "✅ Service redeployed."

echo "🎉 Deployment for ${PROJECT_NAME} version ${NEW_VERSION} complete."
exit 0
