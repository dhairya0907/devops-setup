#!/bin/bash

# ==============================================================================
# Global Notification Command
# Version: 1.0.0
# Date: 2025-07-28
# ==============================================================================
#
# Description:
# A general-purpose script to send notifications to various channels.
# It reads its configuration and secrets from /etc/notify.conf.
#
# Usage:
#   notify --channel slack "Your message here"
#   notify --channel slack --slack-channel "C12345" "Message to a specific channel"
#   notify --channel email --subject "Custom Subject" "Your message here"
#   notify --channel email --recipient "user@example.com" "Message to a specific user"
#
# ==============================================================================

set -e

CONFIG_FILE="/etc/notify.conf"

# --- Helper Functions ---

function usage() {
    echo "Usage: $0 --channel <slack|email> [options] \"Message\""
    echo ""
    echo "Options:"
    echo "  --channel <type>        Specify the notification channel (required)."
    echo "  --slack-channel <id>    Specify a Slack channel ID to override the default."
    echo "  --subject <subject>     Specify a custom subject line (for email)."
    echo "  --recipient <email>     Specify a recipient email to override the default."
    echo "  -h, --help              Display this help message."
    exit 1
}

# Function to read a value from the ini-style config file using awk for robustness.
function get_config_value() {
    local section=$1
    local key=$2
    awk -F'=' -v sec="[$section]" -v k="$key" '
        BEGIN { in_sec = 0 }
        $0 == sec { in_sec = 1; next }
        $0 ~ /^\[/ { in_sec = 0 }
        in_sec && $1 == k {
            val = substr($0, index($0, "=") + 1)
            gsub(/^[ "]+|["]+$/, "", val)
            print val
            exit
        }
    ' "$CONFIG_FILE"
}

function send_slack_notification() {
    local message=$1
    local target_channel=$2
    local bot_token=$(get_config_value "slack" "bot_token")
    local default_channel=$(get_config_value "slack" "default_channel")

    if [ -z "$bot_token" ] || [ "$bot_token" == "YOUR_SLACK_BOT_TOKEN_HERE" ]; then
        echo "❌ Error: Slack bot_token is not configured in $CONFIG_FILE" >&2
        exit 1
    fi
    
    # Use the override channel if provided, otherwise use the default
    if [ -n "$target_channel" ]; then
        channel=$target_channel
    elif [ -n "$default_channel" ]; then
        channel=$default_channel
    else
        echo "❌ Error: No Slack channel specified. Provide one with --slack-channel or set default_channel in $CONFIG_FILE" >&2
        exit 1
    fi

    # Construct the JSON payload for Slack
    json_payload=$(printf '{"channel": "%s", "text": "%s"}' "$channel" "$message")

    echo "⚙️  Sending notification to Slack channel ${channel}..."
    response=$(curl -s -X POST "https://slack.com/api/chat.postMessage" \
      -H "Authorization: Bearer $bot_token" \
      -H 'Content-type: application/json; charset=utf-8' \
      --data "$json_payload")

    # Check if the API call was successful
    if echo "$response" | grep -q '"ok":true'; then
        echo "✅ Notification sent successfully."
    else
        echo "❌ Error: Slack API returned a failure." >&2
        echo "   Response: $response" >&2
        exit 1
    fi
}

function send_email_notification() {
    local subject=$1
    local message=$2
    local target_recipient=$3
    
    local smtp_url=$(get_config_value "email" "smtp_url")
    local smtp_user=$(get_config_value "email" "smtp_user")
    local smtp_password=$(get_config_value "email" "smtp_password")
    local from_address=$(get_config_value "email" "from_address")
    local default_recipient=$(get_config_value "email" "default_recipient")

    if [ -z "$smtp_url" ] || [ -z "$smtp_user" ] || [ -z "$smtp_password" ] || [ -z "$from_address" ] || [ -z "$default_recipient" ]; then
        echo "❌ Error: Email settings (smtp_url, smtp_user, etc.) are not fully configured in $CONFIG_FILE" >&2
        exit 1
    fi

    # Use the override recipient if provided, otherwise use the default
    local recipient
    if [ -n "$target_recipient" ]; then
        recipient=$target_recipient
    else
        recipient=$default_recipient
    fi

    # Create a temporary file for the email payload
    local mail_payload=$(mktemp)
    
    # Create the email headers and body
    printf "From: %s\nTo: %s\nSubject: %s\n\n%s" "$from_address" "$recipient" "$subject" "$message" > "$mail_payload"

    echo "⚙️  Sending notification via email to ${recipient}..."
    curl -s --url "$smtp_url" \
         --user "${smtp_user}:${smtp_password}" \
         --mail-from "$from_address" \
         --mail-rcpt "$recipient" \
         --upload-file "$mail_payload"

    # Clean up the temporary file
    rm "$mail_payload"
    
    echo "✅ Notification sent."
}


# --- Main Script Logic ---

# 1. Check for config file
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Error: Configuration file not found at $CONFIG_FILE" >&2
    exit 1
fi

# 2. Parse Command-Line Arguments
CHANNEL=""
SLACK_CHANNEL=""
SUBJECT="Notification from Server" # Default subject
RECIPIENT=""

if [ "$#" -eq 0 ]; then
    usage
fi

# The message is always the last argument on the command line
MESSAGE="${!#}"

# Process flags, ignoring the last argument (the message)
while [[ "$#" -gt 1 ]]; do
    case $1 in
        -h|--help) usage ;;
        --channel) CHANNEL="$2"; shift ;;
        --slack-channel) SLACK_CHANNEL="$2"; shift ;;
        --subject) SUBJECT="$2"; shift ;;
        --recipient) RECIPIENT="$2"; shift ;;
        *)
            echo "❌ Error: Unknown option or too many arguments: $1" >&2
            usage
            ;;
    esac
    shift
done

if [ -z "$CHANNEL" ]; then
    echo "❌ Error: --channel is a required argument." >&2
    usage
fi

if [ -z "$MESSAGE" ]; then
    echo "❌ Error: Message cannot be empty." >&2
    usage
fi

# 3. Route to the correct notification function
case $CHANNEL in
    slack)
        send_slack_notification "$MESSAGE" "$SLACK_CHANNEL"
        ;;
    email)
        send_email_notification "$SUBJECT" "$MESSAGE" "$RECIPIENT"
        ;;
    *)
        echo "❌ Error: Invalid channel '$CHANNEL'. Supported channels are 'slack' and 'email'." >&2
        exit 1
        ;;
esac

exit 0

