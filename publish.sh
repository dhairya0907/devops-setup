#!/bin/bash

# ==============================================================================
# Central Publish Command
# Version: 1.0.0
# Date: 2025-07-28
# ==============================================================================
#
# Description:
# This script automates the process of creating a new release. It is intended
# to be run by a developer from within a project directory on the dev-server.
# It reads a `publish.yml` file for project-specific instructions.
#
# The script performs the following actions:
#   1. Runs pre-publish checks (like tests).
#   2. Bumps the version number based on the defined strategy.
#   3. Merges the development branch into the main branch.
#   4. Creates and pushes a new Git tag.
#   5. Optionally deletes the feature branch and runs post-publish hooks.
#
# Usage:
#   1. Place this script in `/usr/local/bin/publish` on the dev-server.
#   2. Make it executable: `sudo chmod +x /usr/local/bin/publish`
#   3. From a project directory, run:
#      - Interactive: `publish`
#      - Dry Run:     `publish --dry-run`
#      - Automated:   `publish --yes`
#
# ==============================================================================

set -e
trap 'echo -e "\n❌ An error occurred. Aborting publish process." >&2; exit 1' ERR

# --- Helper Functions ---

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

# Executes a list of commands defined in the YAML file.
function run_steps {
    local step_type=$1
    echo "⚙️  Running ${step_type} steps..."
    
    local steps_file=$(mktemp)
    awk "/${step_type}:/,/^[a-zA-Z]/{if(/^-/){print substr(\$0,3)}}" publish.yml > "$steps_file"
    
    while IFS= read -r step; do
        if [ -n "$step" ]; then
            local expanded_step=$(eval echo "$step")
            echo "   | Executing: $expanded_step"
            if ! $DRY_RUN; then
                eval "$expanded_step"
            fi
        fi
    done < "$steps_file"
    
    rm "$steps_file"
    echo "✅ ${step_type} steps completed successfully."
}

# Bumps the version based on the strategy (major, minor, patch).
function bump_version {
    local current_version=$1
    local strategy=$2
    
    local major=$(echo $current_version | cut -d. -f1)
    local minor=$(echo $current_version | cut -d. -f2)
    local patch=$(echo $current_version | cut -d. -f3)

    case $strategy in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            echo "❌ Error: Invalid version_bump_strategy '${strategy}'. Must be major, minor, or patch." >&2
            exit 1
            ;;
    esac
    echo "${major}.${minor}.${patch}"
}


# --- Main Script Logic ---

echo "🚀 Starting publish process..."

# 1. Parse Arguments
DRY_RUN=false
NON_INTERACTIVE=false
for arg in "$@"; do
  case $arg in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -y|--yes)
      NON_INTERACTIVE=true
      shift
      ;;
  esac
done

if $DRY_RUN; then
    echo "⚠️  Running in DRY-RUN mode. No changes will be made."
fi

# 2. Sanity Checks
if [ ! -f "publish.yml" ]; then
    echo "❌ Error: 'publish.yml' not found in the current directory." >&2
    exit 1
fi

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "❌ Error: This is not a Git repository." >&2
    exit 1
fi

if ! git diff-index --quiet HEAD --; then
    echo "❌ Error: You have uncommitted changes. Please commit or stash them before publishing." >&2
    exit 1
fi

# 3. Parse Configuration
eval $(parse_yaml publish.yml "config_")
PROJECT_NAME=${config_project_name}
DEV_BRANCH=${config_development_branch}
MAIN_BRANCH=${config_main_branch}
VERSION_FILE=${config_version_file}
BUMP_STRATEGY=${config_version_bump_strategy}
DELETE_BRANCH=${config_delete_branch_after_merge:-false}
USE_CURRENT_BRANCH=${config_use_current_branch:-false}
DEFAULT_DRY_RUN=${config_default_to_dry_run:-false}

if [ "$DEFAULT_DRY_RUN" = true ]; then
    DRY_RUN=true
    echo "⚠️  Defaulting to DRY-RUN mode as configured in 'publish.yml'."
fi

if [ "$USE_CURRENT_BRANCH" = true ]; then
    DEV_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    echo "ℹ️  Using current branch '${DEV_BRANCH}' as development branch."
fi

if [ -z "$DEV_BRANCH" ] || [ -z "$MAIN_BRANCH" ] || [ -z "$VERSION_FILE" ] || [ -z "$BUMP_STRATEGY" ] || [ -z "$PROJECT_NAME" ]; then
    echo "❌ Error: 'publish.yml' is missing one or more required keys." >&2
    exit 1
fi

echo "✅ Configuration loaded for project: '${PROJECT_NAME}'."

# 4. Fetch latest changes and run pre-publish steps
echo "⚙️  Fetching latest changes from remote..."
git fetch --all --tags

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "$DEV_BRANCH" ]; then
    echo "❌ Error: You must be on the '${DEV_BRANCH}' branch to publish." >&2
    exit 1
fi

run_steps "pre_publish_steps"

# 5. Versioning
if [ ! -f "$VERSION_FILE" ]; then
    echo "❌ Error: Version file '${VERSION_FILE}' not found." >&2
    exit 1
fi

CURRENT_VERSION=$(cat $VERSION_FILE)
NEXT_VERSION=$(bump_version $CURRENT_VERSION $BUMP_STRATEGY)
NEW_VERSION=""

if $NON_INTERACTIVE; then
    NEW_VERSION=$NEXT_VERSION
    echo "✅ Auto-confirming new version: ${NEW_VERSION}"
else
    echo ""
    read -p "Current version is ${CURRENT_VERSION}. New version will be ${NEXT_VERSION}. Press [Enter] to confirm, or enter a different version: " USER_VERSION

    if [ -n "$USER_VERSION" ]; then
        NEW_VERSION=$USER_VERSION
    else
        NEW_VERSION=$NEXT_VERSION
    fi
fi

TAG_NAME="v${NEW_VERSION}"
echo "✅ New version confirmed: ${NEW_VERSION}"

# 6. Git Operations
echo ""
echo "⚙️  Performing Git operations..."

if $DRY_RUN; then
    echo "   | [DRY RUN] Would update '${VERSION_FILE}' to '${NEW_VERSION}'"
    echo "   | [DRY RUN] Would commit version bump"
    echo "   | [DRY RUN] Would merge '${DEV_BRANCH}' into '${MAIN_BRANCH}'"
    echo "   | [DRY RUN] Would create tag '${TAG_NAME}'"
    echo "   | [DRY RUN] Would push '${MAIN_BRANCH}' and '${TAG_NAME}' to remote"
    if [ "$DELETE_BRANCH" = true ]; then
        echo "   | [DRY RUN] Would delete remote branch '${DEV_BRANCH}'"
    fi
else
    echo "   | Bumping version in '${VERSION_FILE}'..."
    echo "$NEW_VERSION" > "$VERSION_FILE"
    git add "$VERSION_FILE"
    git commit -m "chore: Bump version to ${NEW_VERSION}"

    echo "   | Merging '${DEV_BRANCH}' into '${MAIN_BRANCH}'..."
    git checkout "$MAIN_BRANCH"
    git pull origin "$MAIN_BRANCH"
    git merge --no-ff "$DEV_BRANCH" -m "Merge branch '${DEV_BRANCH}' for release ${TAG_NAME}"

    echo "   | Creating annotated tag '${TAG_NAME}'..."
    git tag -a "$TAG_NAME" -m "Release version ${NEW_VERSION}"

    echo "   | Pushing changes to remote..."
    git push origin "$MAIN_BRANCH"
    git push origin "$TAG_NAME"

    if [ "$DELETE_BRANCH" = true ]; then
        echo "   | Deleting remote branch '${DEV_BRANCH}'..."
        git push origin --delete "$DEV_BRANCH"
    fi

    echo "   | Returning to '${DEV_BRANCH}' branch..."
    git checkout "$DEV_BRANCH"
fi

# 7. Post-Publish Steps
echo ""
run_steps "post_publish_steps"

echo ""
echo "🎉 =============================================== 🎉"
echo "      Successfully published version ${NEW_VERSION}! "
echo "      The CI/CD pipeline on the dev-server         "
echo "      will now begin the deployment process.         "
echo "🎉 =============================================== 🎉"

