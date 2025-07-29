#!/bin/bash

# ==============================================================================
# Central Publish Command
# Version: 2.0.0
# Date: 2025-07-29
# ==============================================================================
#
# Description:
# This script automates the process of creating a new release. It is intended
# to be run by a developer from within a project directory on the dev-server.
# It reads a `publish.yml` file for project-specific instructions and always
# merges releases into the 'main' branch.
#
# It includes critical safety checks for uncommitted changes, branch synchronization,
# and forces a review of any changes to the project's docker-compose.yml file.
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

# Prompts the user for input with a default value.
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
        read -p "$1 $prompt: " reply
        if [ -z "$reply" ]; then
            reply=$default
        fi
        case "$reply" in
            Y*|y*) echo "Y"; return 0 ;;
            N*|n*) echo "N"; return 0 ;;
            *) echo "$reply"; return 0 ;;
        esac
    done
}

# Parses simple key-value pairs from the provided YAML file.
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

# Executes a list of commands defined under a specific key in the YAML file.
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

# Increments a version string based on the provided strategy (major, minor, or patch).
function bump_version {
    local current_version=$1
    local strategy=$2
    local major=$(echo $current_version | cut -d. -f1)
    local minor=$(echo $current_version | cut -d. -f2)
    local patch=$(echo $current_version | cut -d. -f3)

    case $strategy in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
        *) echo "❌ Invalid version_bump_strategy '${strategy}'." >&2; exit 1 ;;
    esac
    echo "${major}.${minor}.${patch}"
}

# Provides clear instructions to the user if a merge conflict occurs.
function handle_merge_conflict {
    echo ""
    echo "❌ MERGE CONFLICT DETECTED!" >&2
    echo "   Automatic merge of '${DEV_BRANCH}' into '${MAIN_BRANCH}' failed." >&2
    echo "   Please resolve the conflicts manually:" >&2
    echo "   1. Open the conflicting files in your editor." >&2
    echo "   2. Resolve the conflicts and save the files." >&2
    echo "   3. Run 'git add .' to stage the resolved files." >&2
    echo "   4. Run 'git commit' to complete the merge." >&2
    echo "   5. Once the merge is complete, re-run the 'publish' script to continue the release." >&2
    exit 1
}


# --- Main Script Logic ---

echo "🚀 Starting publish process..."

# Parse command-line arguments for --dry-run and --yes flags.
DRY_RUN=false
NON_INTERACTIVE=false
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true; shift ;;
    -y|--yes) NON_INTERACTIVE=true; shift ;;
  esac
done

if $DRY_RUN; then echo "⚠️  Running in DRY-RUN mode. No changes will be made."; fi

# Perform initial checks to ensure a clean state before proceeding.
if [ ! -f "publish.yml" ]; then echo "❌ Error: 'publish.yml' not found." >&2; exit 1; fi
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then echo "❌ Error: Not a Git repository." >&2; exit 1; fi
if ! git diff-index --quiet HEAD --; then echo "❌ Error: Uncommitted changes found. Please commit or stash." >&2; exit 1; fi

# Load and validate configuration from the publish.yml file.
eval $(parse_yaml publish.yml "config_")
PROJECT_NAME=${config_project_name}
DEV_BRANCH=${config_development_branch}
MAIN_BRANCH="main" # The release branch is always 'main'.
VERSION_FILE=${config_version_file}
BUMP_STRATEGY=${config_version_bump_strategy}
DELETE_BRANCH=${config_delete_branch_after_merge:-false}
USE_CURRENT_BRANCH=${config_use_current_branch:-false}
DEFAULT_DRY_RUN=${config_default_to_dry_run:-false}

if [ "$DEFAULT_DRY_RUN" = true ]; then DRY_RUN=true; echo "⚠️  Defaulting to DRY-RUN mode."; fi

# Determine the correct development branch to use.
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$USE_CURRENT_BRANCH" = true ]; then
    DEV_BRANCH=$CURRENT_BRANCH
    echo "ℹ️  Using current branch '${DEV_BRANCH}' as development branch."
else
    if [ "$CURRENT_BRANCH" != "$DEV_BRANCH" ]; then
        echo "⚙️  Switching from '${CURRENT_BRANCH}' to configured development branch '${DEV_BRANCH}'..."
        if ! $DRY_RUN; then
            git checkout "$DEV_BRANCH"
        else
            echo "   | [DRY RUN] Would switch to branch '${DEV_BRANCH}'."
        fi
        echo "✅ Switched to '${DEV_BRANCH}'."
    fi
fi

# This check is now correctly placed after handling use_current_branch and potential checkout.
if [ -z "$DEV_BRANCH" ] || [ -z "$VERSION_FILE" ] || [ -z "$BUMP_STRATEGY" ] || [ -z "$PROJECT_NAME" ]; then echo "❌ Error: 'publish.yml' is missing required keys, or development_branch could not be determined." >&2; exit 1; fi

# This safety check prevents merging a branch into itself.
if [ "$DEV_BRANCH" == "$MAIN_BRANCH" ]; then
    echo "❌ Error: 'development_branch' cannot be the same as the main release branch ('main')." >&2
    exit 1
fi

echo "✅ Configuration loaded for project: '${PROJECT_NAME}'."

# Fetch the latest state from the remote repository.
echo "⚙️  Fetching latest changes from remote..."
git fetch --all --tags

# This safety check ensures the local branch is not behind the remote.
if [ $(git rev-list HEAD...origin/${DEV_BRANCH} --count) != 0 ]; then
    echo "❌ Error: Your local branch '${DEV_BRANCH}' is behind the remote." >&2
    echo "   Please run 'git pull' to update before publishing." >&2
    exit 1
fi
echo "✅ Local branch is up-to-date with remote."

# Run any pre-publish steps defined in the configuration, such as tests.
run_steps "pre_publish_steps"

# This safety check forces a review of any changes to the docker-compose.yml file.
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)
if git diff --quiet $LATEST_TAG HEAD -- docker-compose.yml; then
    echo "✅ No changes detected in docker-compose.yml."
else
    echo "⚠️  Changes detected in docker-compose.yml since last release (${LATEST_TAG}):"
    git diff $LATEST_TAG HEAD -- docker-compose.yml | sed 's/^/   | /'
    echo ""
    if [ "$NON_INTERACTIVE" = false ] && [ "$(ask "Do you want to include these changes in the new release?" "N")" != "Y" ]; then
        echo "⚙️  Reverting changes to docker-compose.yml..."
        if ! $DRY_RUN; then git checkout $LATEST_TAG -- docker-compose.yml; fi
        echo "✅ docker-compose.yml has been reverted. Continuing with publish."
    else
        echo "✅ Changes to docker-compose.yml confirmed."
    fi
fi

# Determine the next version number.
if [ ! -f "$VERSION_FILE" ]; then echo "❌ Error: Version file '${VERSION_FILE}' not found." >&2; exit 1; fi
CURRENT_VERSION=$(cat $VERSION_FILE)
NEXT_VERSION=$(bump_version $CURRENT_VERSION $BUMP_STRATEGY)
NEW_VERSION=""

if $NON_INTERACTIVE; then
    NEW_VERSION=$NEXT_VERSION
    echo "✅ Auto-confirming new version: ${NEW_VERSION}"
else
    echo ""
    USER_VERSION=$(ask "Current version is ${CURRENT_VERSION}. New version will be ${NEXT_VERSION}. Press [Enter] to confirm, or enter a different version" "$NEXT_VERSION")
    NEW_VERSION=$USER_VERSION
fi

TAG_NAME="v${NEW_VERSION}"
echo "✅ New version confirmed: ${NEW_VERSION}"

# Perform all Git operations for the release.
echo ""
echo "⚙️  Performing Git operations..."

if $DRY_RUN; then
    echo "   | [DRY RUN] Would update '${VERSION_FILE}' to '${NEW_VERSION}'"
    echo "   | [DRY RUN] Would update 'docker-compose.yml' image tag to '${NEW_VERSION}'"
    echo "   | [DRY RUN] Would commit version bump"
    echo "   | [DRY RUN] Would merge '${DEV_BRANCH}' into '${MAIN_BRANCH}'"
    echo "   | [DRY RUN] Would create tag '${TAG_NAME}'"
    echo "   | [DRY RUN] Would push '${MAIN_BRANCH}' and '${TAG_NAME}' to remote"
    if [ "$DELETE_BRANCH" = true ]; then echo "   | [DRY RUN] Would delete remote branch '${DEV_BRANCH}'"; fi
else
    echo "   | Bumping version in '${VERSION_FILE}'..."
    echo "$NEW_VERSION" > "$VERSION_FILE"
    
    echo "   | Updating image tag in 'docker-compose.yml'..."
    sed -i -E "s|image:.*${PROJECT_NAME}:.*|image: \${REGISTRY_URL}/${PROJECT_NAME}:${NEW_VERSION}|g" docker-compose.yml
    
    git add "$VERSION_FILE" docker-compose.yml
    git commit -m "chore: Bump version to ${NEW_VERSION}"

    echo "   | Merging '${DEV_BRANCH}' into '${MAIN_BRANCH}'..."
    git checkout "$MAIN_BRANCH"
    git pull origin "$MAIN_BRANCH"
    # Attempt the merge and call the handler function on failure.
    git merge --no-ff "$DEV_BRANCH" -m "Merge branch '${DEV_BRANCH}' for release ${TAG_NAME}" || handle_merge_conflict

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

# Run any post-publish steps, such as sending notifications.
echo ""
run_steps "post_publish_steps"

echo ""
echo "🎉 =============================================== 🎉"
echo "      Successfully published version ${NEW_VERSION}! "
echo "      The CI/CD pipeline on the dev-server         "
echo "      will now begin the deployment process.         "
echo "🎉 =============================================== 🎉"

