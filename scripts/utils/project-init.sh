#!/bin/bash

# ==============================================================================
# Project Initialization Script
# Version: 2.0.0
# Date: 2025-07-30
# ==============================================================================
#
# Description:
# This script interactively sets up a new project from scratch, making it
# compatible with the self-hosted CI/CD pipeline. It creates a full project
# structure including app, tests, secure Docker files, a README, a LICENSE,
# a CHANGELOG, and other best-practice configurations to accelerate
# development.
#
# ==============================================================================

set -e

# --- Configuration ---
SCRIPT_VERSION="2.0.0"

# --- Color Definitions for Output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper functions for user prompts ---

# General purpose prompt for uncolored text.
function ask_value() {
    local question="$1"
    local default_value="$2"
    local prompt="[$default_value]"
    local reply

    read -p "$question $prompt: " reply
    echo "${reply:-$default_value}"
}

# Yes/No prompt that supports colored questions.
function ask_yes_no() {
    local question="$1"
    local default_answer="$2"
    local prompt
    local reply

    if [ "$default_answer" = "Y" ]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    while true; do
        printf "%b %s: " "$question" "$prompt"
        read reply
        if [ -z "$reply" ]; then
            reply="$default_answer"
        fi

        case "$reply" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
        esac
    done
}


# --- Main Script Logic ---

echo -e "${BLUE}🚀 Initializing new project for the CI/CD pipeline (v${SCRIPT_VERSION})...${NC}"
echo "This script will set up Git, a standard project structure, and Docker configs."
echo ""

# 1. Sanity Checks & Git Initialization
echo -e "${BLUE}--- Step 1: Checking Prerequisites ---${NC}"
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    if ! ask_yes_no "${YELLOW}⚠️  This is not a Git repository. Initialize one now?${NC}" "Y"; then
        echo "Aborted."
        exit 0
    fi
    git init --initial-branch=main > /dev/null
    echo -e "${GREEN}✅ Git repository initialized.${NC}"
fi

if [ -f "publish.yml" ] || [ -f "docker-compose.yml" ] || [ -d "app" ]; then
    if ! ask_yes_no "${YELLOW}⚠️  Configuration files or directories already exist. Overwrite them?${NC}" "N"; then
        echo "Aborted."
        exit 0
    fi
fi

# 2. Gather Project Information
echo -e "\n${BLUE}--- Step 2: Gather Project Information ---${NC}"
DEFAULT_PROJECT_NAME=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]/-/g' -e 's/--\+/-/g' -e 's/^-//' -e 's/-$//')
PROJECT_NAME=$(ask_value "Enter the project name" "$DEFAULT_PROJECT_NAME")
PROJECT_OWNER=$(ask_value "Enter the project owner/company name (for LICENSE)" "")
DEV_BRANCH=$(ask_value "Enter the development branch name" "develop")
INITIAL_VERSION=$(ask_value "Enter the initial version for this project" "0.1.0")
REGISTRY_PORT=$(ask_value "Enter the Docker registry port" "5000")
REMOTE_URL=$(ask_value "Enter the remote Git repository URL (optional)" "")

# 3. Create Project Directory Structure & Placeholders
echo -e "\n${BLUE}--- Step 3: Creating Project Files & Structure ---${NC}"
echo -e "⚙️  Creating project structure (app, config, docker, logs, tests)..."
mkdir -p app docker config logs tests
touch config/config.json config/.env logs/.gitkeep tests/.gitkeep
cat > config/.env.example << EOL
# Example environment variables for local development.
# Copy this file to config/.env and customize it.

# GREETING=Hello from the .env file!
EOL
echo -e "${GREEN}✅ Project structure created.${NC}"

# 4. Create Dockerfile Template
echo -e "⚙️  Creating multi-stage Dockerfile template with security hardening..."
cat > docker/Dockerfile << EOL
# =================================================================
# Dockerfile Template - TODO: Customize for your application
# =================================================================

# Stage 1: Builder - Install dependencies
FROM python:3.11-slim as builder
WORKDIR /app
COPY your-dependency-file .
RUN echo "TODO: Add command to install dependencies here"

# =================================================================
# Stage 2: Final Image - Minimal and Secure
# =================================================================
FROM python:3.11-slim
WORKDIR /app

# --- Security Best Practice: Run as a non-root user ---
# Create a dedicated user and group for the application.
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

# Copy built application files from previous stages
COPY --from=builder /app .
COPY ./app .

# Transfer ownership of the application files to the new user
RUN chown -R appuser:appgroup /app

# Switch to the non-root user before running the application
USER appuser
# --- End Security Section ---

EXPOSE 8000
# TODO: Change this to the command that starts your application.
CMD ["echo", "TODO: Add your application's start command here"]
EOL
echo -e "${GREEN}✅ Dockerfile template created.${NC}"

# 5. Create VERSION.txt
echo -e "⚙️  Creating VERSION.txt with initial version ${INITIAL_VERSION}..."
echo "${INITIAL_VERSION}" > VERSION.txt
echo -e "${GREEN}✅ VERSION.txt created.${NC}"

# 6. Create Docker Compose files
DOCKER_SERVICE_NAME=$(echo "${PROJECT_NAME}" | sed 's/[^a-zA-Z0-9_.-]//g')
echo -e "⚙️  Creating docker-compose.yml for production-like environments..."
cat > docker-compose.yml << EOL
# Docker Compose configuration for ${PROJECT_NAME}
services:
  ${DOCKER_SERVICE_NAME}:
    build:
      context: .
      dockerfile: ./docker/Dockerfile
    image: localhost:${REGISTRY_PORT}/${PROJECT_NAME}:${INITIAL_VERSION}
    container_name: ${PROJECT_NAME}
    restart: unless-stopped
    env_file:
      - ./config/.env
    volumes:
      - ./config/config.json:/app/config.json:ro
      - ./logs:/app/logs:rw
    ports:
      - 8000:8000
EOL

echo -e "⚙️  Creating docker-compose.override.yml for local development..."
cat > docker-compose.override.yml << EOL
# Development-only overrides
services:
  ${DOCKER_SERVICE_NAME}:
    volumes:
      # Mounts the local source code into the container for live-reloading.
      - ./app:/app
EOL
echo -e "${GREEN}✅ Docker Compose files created.${NC}"

# 7. Create publish.yml
echo -e "⚙️  Creating publish.yml with test step placeholder..."
cat > publish.yml << EOL
# ==============================================================================
# Publish Configuration (v${SCRIPT_VERSION})
# ==============================================================================
project_name: "${PROJECT_NAME}"

development_branch: "${DEV_BRANCH}"

version_file: "VERSION.txt"
version_bump_strategy: "patch"

pre_publish_steps:
  - echo "Running pre-publish checks for ${PROJECT_NAME}..."
  # TODO: Uncomment and add your test command below.
  # - docker-compose run --rm ${DOCKER_SERVICE_NAME} your-test-runner-command

post_publish_steps:
  - notify --channel slack "🚀 Version \${NEW_VERSION} of ${PROJECT_NAME} has been published."

delete_branch_after_merge: true
use_current_branch: true
default_to_dry_run: false
EOL
echo -e "${GREEN}✅ publish.yml created.${NC}"

# 8. Create README.md Template
echo -e "⚙️  Creating README.md project documentation..."
cat > README.md << EOL
# ${PROJECT_NAME}

A new project initialized with the DevOps setup.

---

## Getting Started

### Prerequisites
- [Docker](https://www.docker.com/get-started)
- [Docker Compose](https://docs.docker.com/compose/install/)

### Local Development

1.  **Configure Environment:**
    Copy the example environment file and customize it.
    \`\`\`bash
    cp config/.env.example config/.env
    \`\`\`

2.  **Build and Run:**
    Use Docker Compose to build and run the container. The override file will mount your local code for live-reloading.
    \`\`\`bash
    docker-compose up --build -d
    \`\`\`

3.  **View Logs:**
    \`\`\`bash
    docker-compose logs -f
    \`\`\`

4.  **Stop the Environment:**
    \`\`\`bash
    docker-compose down
    \`\`\`

## Testing

The \`./tests\` directory is ready for your test files. You can run your tests inside the Docker container using a command like:
\`\`\`bash
# Example for a pytest runner
docker-compose run --rm ${DOCKER_SERVICE_NAME} pytest
\`\`\`

## CI/CD Pipeline

This project is integrated with the self-hosted CI/CD pipeline. Pushing new version tags to the remote repository will automatically trigger a new build and deployment. Ensure your tests are configured in \`publish.yml\` to run before publishing.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
EOL
echo -e "${GREEN}✅ README.md created.${NC}"

# 9. Create standard project files (.gitignore, .dockerignore, LICENSE, CHANGELOG.md)
echo -e "⚙️  Creating standard project files..."
if [ ! -f ".gitignore" ]; then
    cat > .gitignore << EOL
# Secrets & Environment-specific files
.env
config/.env

# Log files
logs/*
!logs/.gitkeep

# Docker
docker-compose.override.yml

# Common IDE / OS files
.idea/
.vscode/
*.swp
*~
.DS_Store
EOL
    echo -e "   - .gitignore created."
fi

cat > .dockerignore << EOL
# Git and project config
.git
.gitignore
.dockerignore
README.md
CHANGELOG.md
LICENSE
publish.yml

# Local development files
docker-compose.override.yml
EOL
echo -e "   - .dockerignore created."

# Create MIT License
CURRENT_YEAR=$(date +"%Y")
cat > LICENSE << EOL
MIT License

Copyright (c) ${CURRENT_YEAR} ${PROJECT_OWNER}

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOL
echo -e "   - LICENSE (MIT) created."

# Create CHANGELOG.md
cat > CHANGELOG.md << EOL
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [${INITIAL_VERSION}] - $(date +"%Y-%m-%d")

### Added
- Initial project structure generated by initialization script (v${SCRIPT_VERSION}).
EOL
echo -e "   - CHANGELOG.md created."
echo -e "${GREEN}✅ Standard project files created.${NC}"

# 10. Perform Git Operations
echo -e "\n${BLUE}--- Step 4: Finalizing Git Repository ---${NC}"
git add .
git commit -m "feat(project): Initialize project structure for CI/CD v${SCRIPT_VERSION}" --quiet
echo -e "   | Initial commit created."

if [ -n "$REMOTE_URL" ]; then
    if git remote | grep -q 'origin'; then
        git remote set-url origin "$REMOTE_URL"
    else
        git remote add origin "$REMOTE_URL"
    fi
    echo -e "   | Pushing initial commit to remote..."
    git push -u origin main
fi

# Create and push the development branch
echo -e "⚙️  Creating development branch '${DEV_BRANCH}'..."
git checkout -b "$DEV_BRANCH"
if [ -n "$REMOTE_URL" ]; then
    echo "   | Pushing development branch to remote..."
    git push -u origin "$DEV_BRANCH"
fi
echo -e "${GREEN}✅ Development branch created and pushed.${NC}"

# 11. Final Summary
echo ""
echo -e "${GREEN}🎉 ========================================================== 🎉"
echo "      Project '${PROJECT_NAME}' is now initialized!    "
echo -e "🎉 ========================================================== 🎉${NC}"
echo ""
echo -e "${YELLOW}-------------------- Project Summary --------------------${NC}"
echo -e "  - ${BLUE}Project Name:${NC}         ${PROJECT_NAME}"
echo -e "  - ${BLUE}Initial Version:${NC}      ${INITIAL_VERSION}"
echo -e "  - ${BLUE}Development Branch:${NC}   ${DEV_BRANCH}"
echo -e "  - ${BLUE}Docker Image Name:${NC}    localhost:${REGISTRY_PORT}/${PROJECT_NAME}:${INITIAL_VERSION}"
echo -e "  - ${BLUE}License:${NC}              MIT (${CURRENT_YEAR} ${PROJECT_OWNER})"
echo -e "${YELLOW}-------------------------------------------------------${NC}"
echo ""
echo "NEXT ACTIONS:"
echo "1. Read the new README.md file for instructions on local development."
echo "2. Add your application code to './app' and tests to './tests'."
echo "3. Create your dependency file (e.g., requirements.txt, package.json)."
echo "4. Customize the template at './docker/Dockerfile' to build your app."
echo ""
echo "💡 When ready, add the project to the server lists:"
echo "   - On 'dev-server': Add the Git URL to the 'projects.list' file."
echo "   - On 'prod-server': Add the project name ('${PROJECT_NAME}') to 'projects-prod.list'."
echo ""
