#!/bin/bash

# ==============================================================================
# Project Initialization Script
# Version: 1.0.0
# Date: 2025-07-29
# ==============================================================================
#
# Description:
# This script interactively sets up a new project from scratch, making it
# compatible with the self-hosted CI/CD pipeline. It handles Git initialization,
# remote configuration, and creation of the required CI/CD files.
#
# Usage:
#   1. Install this script as a global command on your dev-server:
#      sudo cp project-init.sh /usr/local/bin/project-init
#      sudo chmod +x /usr/local/bin/project-init
#   2. To initialize a new project, create an empty directory, navigate into it,
#      and simply run the command: `project-init`
#
# ==============================================================================

set -e

# --- Helper function for user prompts ---
function ask() {
    local prompt default reply
    if [ "${2:-}" = "Y" ]; then
        prompt="[Y/n]"
        default=Y
    elif [ "${2:-}" = "N" ]; then
        prompt="[y/N]"
        default=N
    else
        prompt="[$2]"
        default=$2
    fi

    while true; do
        # Ask the question
        read -p "$1 $prompt: " reply

        # Default?
        if [ -z "$reply" ]; then
            reply=$default
        fi

        # Check if the reply is valid
        case "$reply" in
            Y*|y*) echo "Y"; return 0 ;;
            N*|n*) echo "N"; return 0 ;;
            *) echo "$reply"; return 0 ;;
        esac
    done
}

# --- Main Script Logic ---

echo "🚀 Initializing new project for the CI/CD pipeline..."
echo "This script will set up Git and create the necessary configuration files."
echo ""

# 1. Sanity Checks & Git Initialization
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    if [ "$(ask "⚠️  This is not a Git repository. Initialize one now?" "Y")" != "Y" ]; then
        echo "Aborted."
        exit 0
    fi
    git init
    echo "✅ Git repository initialized."
fi

if [ -f "publish.yml" ] || [ -f "VERSION.txt" ]; then
    if [ "$(ask "⚠️  Configuration files already exist. Overwrite them?" "N")" != "Y" ]; then
        echo "Aborted."
        exit 0
    fi
fi

# 2. Gather Project Information
PROJECT_NAME=$(ask "Enter a human-readable project name" "$(basename `pwd`)")
DEV_BRANCH=$(ask "Enter the main development branch name" "develop")
MAIN_BRANCH=$(ask "Enter the primary release branch name" "main")
INITIAL_VERSION=$(ask "Enter the initial version for this project" "0.0.0")
REMOTE_URL=$(ask "Enter the remote Git repository URL (optional)" "")

# 3. Create VERSION.txt
echo "⚙️  Creating VERSION.txt with initial version ${INITIAL_VERSION}..."
echo "${INITIAL_VERSION}" > VERSION.txt
echo "✅ VERSION.txt created."

# 4. Create publish.yml
echo "⚙️  Creating publish.yml..."
cat > publish.yml << EOL
# ==============================================================================
# Publish Configuration
# ==============================================================================
# This file defines the release process for this project.
# It is read by the global \`publish\` command on the dev-server.
# ==============================================================================

project_name: "${PROJECT_NAME}"

development_branch: "${DEV_BRANCH}"

main_branch: "${MAIN_BRANCH}"

version_file: "VERSION.txt"

version_bump_strategy: "patch"

pre_publish_steps:
  - echo "Running pre-publish checks for ${PROJECT_NAME}..."
  # - pytest

post_publish_steps:
  - notify --channel slack "🚀 Version \${NEW_VERSION} of ${PROJECT_NAME} has been published."

delete_branch_after_merge: true

use_current_branch: true

default_to_dry_run: false
EOL
echo "✅ publish.yml created."

# 5. Create a basic .gitignore if one doesn't exist
if [ ! -f ".gitignore" ]; then
    echo "⚙️  No .gitignore found. Creating a basic one..."
    cat > .gitignore << EOL
# Python
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
env/
venv/

# Secrets
.env
EOL
    echo "✅ .gitignore created."
fi

# 6. Perform Git Operations
echo "⚙️  Finalizing Git repository setup..."
# Ensure we are on the main branch
if git rev-parse --verify "$MAIN_BRANCH" >/dev/null 2>&1; then
    git checkout "$MAIN_BRANCH"
else
    git checkout -b "$MAIN_BRANCH"
fi
echo "   | Switched to '${MAIN_BRANCH}' branch."

git add .
git commit -m "chore: Initialize project for CI/CD"
echo "   | Initial commit created."

if [ -n "$REMOTE_URL" ]; then
    if git remote | grep -q 'origin'; then
        git remote set-url origin "$REMOTE_URL"
        echo "   | Updated existing remote 'origin'."
    else
        git remote add origin "$REMOTE_URL"
        echo "   | Added new remote 'origin'."
    fi
    
    echo "   | Pushing initial commit to remote..."
    git push -u origin "$MAIN_BRANCH"
fi

echo ""
echo "🎉 =============================================== 🎉"
echo "      Project '${PROJECT_NAME}' is now initialized!    "
if [ -n "$REMOTE_URL" ]; then
    echo "      The initial commit has been pushed to the remote."
else
    echo "      Please add a remote repository and push the initial commit."
fi
echo "🎉 =============================================== 🎉"

