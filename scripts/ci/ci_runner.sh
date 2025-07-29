#!/bin/bash

# ==============================================================================
# Self-Hosted CI Runner Script
# Version: 2.0.0
# Date: 2025-07-29
# ==============================================================================
#
# Description:
# This script acts as a self-hosted CI runner. It runs on the dev-server as the
# 'automation' user. It monitors a list of Git repositories (defined in a
# separate projects.list file) for new version tags.
#
# When a new tag is found, it builds a Docker image, pushes it to the private
# production registry, and syncs the project's configuration files (including
# docker-compose.yml and secrets). All output is logged.
#
# Usage:
#   1. Create a projects.list file at /home/automation/ci-runner/projects.list
#   2. Place this script in the 'automation' user's home directory.
#   3. Make it executable: `chmod +x ci_runner.sh`
#   4. Run it in the background: `nohup ./ci_runner.sh <prod_server_ip> <registry_port> <check_interval_seconds> &`
#   5. Monitor its activity: `tail -f /home/automation/ci-runner/logs/ci_runner.log`
#
# ==============================================================================

set -e
# The trap will now log the error to the file.
trap 'echo "❌ An error occurred in the CI runner. Restarting in 60 seconds..."' ERR

# --- ARGUMENT VALIDATION ---
if [ "$#" -ne 3 ]; then
    echo "❌ Error: Invalid arguments." >&2
    echo "Usage: $0 <prod_server_ip> <registry_port> <check_interval_seconds>" >&2
    exit 1
fi

PROD_SERVER_IP=$1
REGISTRY_PORT=$2
CHECK_INTERVAL=$3

# --- CONFIGURATION ---

# The base directory for all CI operations.
BASE_DIR="/home/automation/ci-runner"

# The file containing the list of project Git URLs to monitor.
PROJECT_LIST_FILE="${BASE_DIR}/projects.list"

# The location for the log file.
LOG_FILE="${BASE_DIR}/logs/ci_runner.log"

# --- SCRIPT LOGIC ---

REGISTRY_URL="${PROD_SERVER_IP}:${REGISTRY_PORT}"

# Sets up the logging by redirecting all output to a log file.
function setup_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    # Rotate the previous log file if it exists
    [ -f "$LOG_FILE" ] && mv "$LOG_FILE" "${LOG_FILE}.1"
    # Redirect all stdout and stderr to the log file for the rest of the script's execution
    exec &> "$LOG_FILE"
    echo "Log file initialized at $(date)"
}

# Parses key-value pairs from the publish.yml configuration file.
function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$w: \3|p" \
        -e "s|^\($s\)\($w\)$s:$s'\(.*\)'$s\$|\1$w: \3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$w: \3|p"  $1 |
   awk -F': ' '{
      key = $1;
      sub(/^ */, "", key);
      value = substr($0, index($0, ":") + 2);
      gsub(/^ *| *$/, "", value);
      printf("%s%s=\"%s\"\n", "'$prefix'", key, value);
   }'
}

# Checks for the latest version tag in a Git repository.
function get_latest_tag() {
    local repo_url=$1
    local bare_repo_dir=$2

    if [ ! -d "$bare_repo_dir" ]; then
        echo "   | Bare repository not found. Cloning for the first time..."
        git clone --bare "$repo_url" "$bare_repo_dir" > /dev/null 2>&1
    fi

    echo "   | Fetching latest tags from remote..."
    git --git-dir="$bare_repo_dir" fetch --tags --force > /dev/null 2>&1
    
    # Find the latest tag using version-sort, then return it.
    git --git-dir="$bare_repo_dir" tag --list --sort=-v:refname | head -n 1
}

# Builds and pushes a Docker image from a pre-cloned directory.
function build_and_push() {
    local temp_clone_dir=$1
    local tag=$2
    local project_name=$3
    
    echo "   | Building image for tag: ${tag}"
    
    local image_name="${REGISTRY_URL}/${project_name}:${tag#v}" # Removes the 'v' prefix for the image tag

    echo "   | Building Docker image: ${image_name}"
    docker build -t "$image_name" "$temp_clone_dir" > /dev/null

    echo "   | Pushing image to registry..."
    docker push "$image_name" > /dev/null

    echo "   | Build and push complete."
}

# Syncs configuration (docker-compose.yml and secrets) to the production server.
function sync_configs() {
    local project_name=$1
    local temp_clone_dir=$2
    local local_secrets_dir="/home/automation/secrets/${project_name}"
    local remote_project_dir="/home/ubuntu/${project_name}"

    echo "   | Syncing configuration files to production server..."
    # Ensure the remote project directory exists
    ssh "ubuntu@${PROD_SERVER_IP}" "mkdir -p ${remote_project_dir}"

    # Copy the docker-compose.yml from the cloned repository
    scp "${temp_clone_dir}/docker-compose.yml" "ubuntu@${PROD_SERVER_IP}:${remote_project_dir}/docker-compose.yml" > /dev/null
    echo "   | -> docker-compose.yml synced."

    # Copy any files from the corresponding secrets directory
    if [ -d "$local_secrets_dir" ]; then
        # Use scp to securely copy the entire directory contents
        scp -r "${local_secrets_dir}/." "ubuntu@${PROD_SERVER_IP}:${remote_project_dir}/" > /dev/null
        echo "   | -> Secrets directory synced successfully."
    else
        echo "   | -> No secrets directory found at '${local_secrets_dir}'. Skipping."
    fi
}


# --- MAIN LOOP ---

# Call the logging setup function once at the start.
setup_logging

echo "🚀 CI Runner started. Monitoring for new releases..."
mkdir -p "${BASE_DIR}/repos"
mkdir -p "${BASE_DIR}/clones"
mkdir -p "${BASE_DIR}/state"

if [ ! -f "$PROJECT_LIST_FILE" ]; then
    echo "❌ Error: Project list file not found at ${PROJECT_LIST_FILE}" >&2
    echo "   Please create it and add your repository URLs." >&2
    exit 1
fi

while true; do
    # Read the projects.list file into an array, ignoring comments and empty lines
    mapfile -t PROJECTS_TO_MONITOR < <(grep -v -e '^#' -e '^[[:space:]]*$' "$PROJECT_LIST_FILE")
    
    for repo_url in "${PROJECTS_TO_MONITOR[@]}"; do
        repo_name=$(basename "$repo_url" .git)
        bare_repo_dir="${BASE_DIR}/repos/${repo_name}.git"
        state_file="${BASE_DIR}/state/${repo_name}_last_tag.txt"

        echo "------------------------------------------------------------"
        echo "🔍 Checking project: ${repo_url}"

        latest_tag=$(get_latest_tag "$repo_url" "$bare_repo_dir")
        
        if [ ! -f "$state_file" ]; then
            touch "$state_file"
        fi
        last_deployed_tag=$(cat "$state_file")

        if [ -z "$latest_tag" ]; then
            echo "   | No releases found yet. Waiting."
        elif [ "$latest_tag" != "$last_deployed_tag" ]; then
            echo "✅ New release found! Version: ${latest_tag}"
            
            # Perform a single clone for this release process
            temp_clone_dir="${BASE_DIR}/clones/${repo_name}"
            rm -rf "$temp_clone_dir"
            git clone --branch "$latest_tag" "$repo_url" "$temp_clone_dir" > /dev/null 2>&1
            
            # Read the project_name from the publish.yml inside the clone
            eval $(parse_yaml "${temp_clone_dir}/publish.yml" "config_")
            PROJECT_NAME_FROM_CONFIG=${config_project_name}
            
            build_and_push "$temp_clone_dir" "$latest_tag" "$PROJECT_NAME_FROM_CONFIG"
            sync_configs "$PROJECT_NAME_FROM_CONFIG" "$temp_clone_dir"

            # Clean up the temporary clone after all operations are complete
            rm -rf "$temp_clone_dir"

            echo "$latest_tag" > "$state_file"
            echo "🎉 Successfully processed release ${latest_tag} for ${PROJECT_NAME_FROM_CONFIG}."
        else
            echo "   | Already up-to-date with latest release (${latest_tag})."
        fi
    done

    echo "------------------------------------------------------------"
    echo "Sleeping for ${CHECK_INTERVAL} seconds..."
    sleep "$CHECK_INTERVAL"
done
