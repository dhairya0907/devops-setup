#!/bin/bash

# ==============================================================================
# Deployment Poller Script
# Version: 1.0.0
# Date: 2025-07-29
# ==============================================================================
#
# Description:
# This script runs on the prod-server. It continuously monitors the local
# Docker registry for new image tags for a list of specified projects.
#
# When it detects a new version that has not been deployed, it triggers the
# `deploy.sh` script to perform a zero-downtime update. All output is logged.
#
# Usage:
#   1. Create a projects-prod.list file at /home/ubuntu/deploy-runner/projects-prod.list
#   2. Place this script and `deploy.sh` in /home/ubuntu/deploy-runner/
#   3. Make them executable: `chmod +x deployment_poller.sh deploy.sh`
#   4. Run this script in the background: `nohup ./deployment_poller.sh <registry_port> <check_interval_seconds> &`
#   5. Monitor its activity: `tail -f /home/ubuntu/deploy-runner/logs/poller.log`
#
# ==============================================================================

set -e
trap 'echo "❌ An error occurred in the deployment poller. Restarting in 60 seconds..."' ERR

# --- ARGUMENT VALIDATION ---
if [ "$#" -ne 2 ]; then
    echo "❌ Error: Invalid arguments." >&2
    echo "Usage: $0 <registry_port> <check_interval_seconds>" >&2
    exit 1
fi

REGISTRY_PORT=$1
CHECK_INTERVAL=$2

# --- CONFIGURATION ---

# The base directory for all deployment operations.
BASE_DIR="/home/ubuntu/deploy-runner"

# The file containing the list of project names to monitor.
# These names MUST match the 'project_name' in their respective publish.yml files.
PROJECT_LIST_FILE="${BASE_DIR}/projects-prod.list"

# The location for the log file.
LOG_FILE="${BASE_DIR}/logs/poller.log"

# --- SCRIPT LOGIC ---

REGISTRY_URL="localhost:${REGISTRY_PORT}"

# Sets up the logging by redirecting all output to a log file.
function setup_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    # Rotate the previous log file if it exists
    [ -f "$LOG_FILE" ] && mv "$LOG_FILE" "${LOG_FILE}.1"
    # Redirect all stdout and stderr to the log file
    exec &> "$LOG_FILE"
    echo "Log file initialized at $(date)"
}

# Queries the local Docker registry to find the latest version tag for a project.
function get_latest_tag_from_registry() {
    local project_name=$1
    
    echo "   | Querying registry for tags of '${project_name}'..."
    # Use curl to hit the registry's API, jq to parse the JSON, and sort to find the latest version.
    # The `|| true` prevents the script from exiting if the repo doesn't exist yet.
    local latest_tag=$(curl -s "http://${REGISTRY_URL}/v2/${project_name}/tags/list" | jq -r '.tags[]' | sort -V | tail -n 1 || true)
    echo "$latest_tag"
}

# --- MAIN LOOP ---

setup_logging

echo "🚀 Deployment Poller started. Monitoring local registry for new images..."
mkdir -p "${BASE_DIR}/state"

if [ ! -f "$PROJECT_LIST_FILE" ]; then
    echo "❌ Error: Project list file not found at ${PROJECT_LIST_FILE}" >&2
    echo "   Please create it and add your project names." >&2
    exit 1
fi

# Check for jq, a required dependency for parsing JSON.
if ! command -v jq &> /dev/null; then
    echo "❌ Error: 'jq' is not installed. Please install it with 'sudo apt-get install jq'." >&2
    exit 1
fi

while true; do
    # Read the projects-prod.list file, ignoring comments and empty lines
    mapfile -t PROJECTS_TO_MONITOR < <(grep -v -e '^#' -e '^[[:space:]]*$' "$PROJECT_LIST_FILE")
    
    for project_name in "${PROJECTS_TO_MONITOR[@]}"; do
        state_file="${BASE_DIR}/state/${project_name}_deployed_version.txt"

        echo "------------------------------------------------------------"
        echo "🔍 Checking project: ${project_name}"

        latest_tag=$(get_latest_tag_from_registry "$project_name")
        
        if [ ! -f "$state_file" ]; then
            touch "$state_file"
        fi
        current_deployed_tag=$(cat "$state_file")

        if [ -z "$latest_tag" ]; then
            echo "   | No images found in registry for this project yet. Waiting."
        elif [ "$latest_tag" != "$current_deployed_tag" ]; then
            echo "✅ New image found! Version: ${latest_tag}. Triggering deployment..."
            
            # Execute the deployment script, passing the project name, new tag, and registry port.
            if ${BASE_DIR}/deploy.sh "$project_name" "$latest_tag" "$REGISTRY_PORT"; then
                # Only update the state file if the deployment was successful.
                echo "$latest_tag" > "$state_file"
                echo "🎉 Successfully deployed version ${latest_tag} for ${project_name}."
            else
                echo "❌ Deployment script failed for ${project_name} version ${latest_tag}. Will retry on next cycle."
            fi
        else
            echo "   | Already up-to-date with latest version (${latest_tag})."
        fi
    done

    echo "------------------------------------------------------------"
    echo "Sleeping for ${CHECK_INTERVAL} seconds..."
    sleep "$CHECK_INTERVAL"
done
