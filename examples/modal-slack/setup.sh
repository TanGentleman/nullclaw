#!/usr/bin/env bash
set -euo pipefail
# Set up Slack channel and bot accounts for nullclaw multi-agent deployment.
#
# Creates a private channel, invites both bots + you, and patches
# config.slack.json / .env with the correct values.
#
# Prerequisites (one-time, ~5 min):
#   1. Create 2 Slack apps at https://api.slack.com/apps → Create New App
#   2. For EACH app:
#      - OAuth & Permissions → Bot Token Scopes:
#          chat:write, app_mentions:read, channels:history, channels:read,
#          groups:read, groups:write, groups:history
#      - Socket Mode → Enable → Create App-Level Token (connections:write)
#      - Event Subscriptions → Enable → Subscribe:
#          message.channels, message.groups, app_mention
#      - Install to Workspace → copy xoxb-... Bot User OAuth Token
#   3. Run this script with your tokens
#
# Usage:
#   ./setup.sh [--channel-id C01234...]
#   ./setup.sh --dry-run

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
API="https://slack.com/api"
DRY_RUN=false
CHANNEL_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --channel-id) CHANNEL_ID="$2"; shift 2 ;;
    *)            echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Check dependencies ---
for cmd in curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing: $cmd"; exit 1; }
done

# --- Collect tokens ---
echo ">>> Slack setup for nullclaw multi-agent"
echo ""
echo "Enter tokens from your 2 Slack apps (from api.slack.com/apps):"
echo ""
read -rp "Planner bot token (xoxb-...): " PLANNER_BOT
read -rp "Planner app token (xapp-...): " PLANNER_APP
read -rp "Builder bot token (xoxb-...): " BUILDER_BOT
read -rp "Builder app token (xapp-...): " BUILDER_APP
read -rp "Your Slack User ID (U01234ABC — profile → Copy member ID): " HUMAN_UID

for var in PLANNER_BOT PLANNER_APP BUILDER_BOT BUILDER_APP HUMAN_UID; do
  [[ -n "${!var}" ]] || { echo "All fields required."; exit 1; }
done

# --- Helper: call Slack API ---
slack() {
  local method="$1" token="$2"
  shift 2
  curl -sf -X POST "$API/$method" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "$@"
}

# --- Validate tokens ---
echo ""
echo ">>> Validating tokens..."
PLANNER_UID=$(slack auth.test "$PLANNER_BOT" | jq -re '.user_id // empty') \
  || { echo "  Error: planner auth failed"; exit 1; }
echo "  Planner bot: $PLANNER_UID"

BUILDER_UID=$(slack auth.test "$BUILDER_BOT" | jq -re '.user_id // empty') \
  || { echo "  Error: builder auth failed"; exit 1; }
echo "  Builder bot: $BUILDER_UID"

# --- Create or find channel ---
if [[ -n "$CHANNEL_ID" ]]; then
  echo ""
  echo ">>> Using channel ID: $CHANNEL_ID"
else
  echo ""
  echo ">>> Creating private channel nullclaw-agents..."
  resp=$(slack conversations.create "$PLANNER_BOT" \
    -d '{"name":"nullclaw-agents","is_private":true}')
  ok=$(echo "$resp" | jq -r '.ok')
  if [[ "$ok" == "true" ]]; then
    CHANNEL_ID=$(echo "$resp" | jq -r '.channel.id')
    echo "  Channel: $CHANNEL_ID"
  elif [[ "$(echo "$resp" | jq -r '.error')" == "name_taken" ]]; then
    echo "  Channel exists, looking up..."
    CHANNEL_ID=$(slack conversations.list "$PLANNER_BOT" \
      -d '{"types":"private_channel","limit":200}' \
      | jq -r '.channels[] | select(.name=="nullclaw-agents") | .id // empty')
    if [[ -z "$CHANNEL_ID" ]]; then
      echo "  Error: channel exists but planner bot is not in it." >&2
      echo "  Run with --channel-id C01234..." >&2
      exit 1
    fi
    echo "  Channel: $CHANNEL_ID"
  else
    echo "  Error: $(echo "$resp" | jq -r '.error')" >&2
    exit 1
  fi
fi

# --- Invite builder + human ---
echo ">>> Inviting builder and you..."
slack conversations.invite "$PLANNER_BOT" \
  -d "{\"channel\":\"$CHANNEL_ID\",\"users\":\"$BUILDER_UID,$HUMAN_UID\"}" \
  >/dev/null 2>&1 || true
echo "  Invited."

# --- Test message ---
echo ">>> Sending test message..."
slack chat.postMessage "$PLANNER_BOT" \
  -d "{\"channel\":\"$CHANNEL_ID\",\"text\":\"nullclaw multi-agent room is live\"}" \
  >/dev/null
echo "  Sent."

# --- Patch config from template ---
CONFIG_SRC="$SCRIPT_DIR/config.slack.example.json"
CONFIG_DST="$SCRIPT_DIR/config.slack.json"

patched=$(jq \
  --arg cid "$CHANNEL_ID" \
  --arg huid "$HUMAN_UID" \
  --arg buid "$BUILDER_UID" \
  --arg puid "$PLANNER_UID" \
  '
  .channels.slack.accounts["planner-account"].channel_id = $cid |
  .channels.slack.accounts["planner-account"].allow_from = [$huid, $buid] |
  .channels.slack.accounts["builder-account"].channel_id = $cid |
  .channels.slack.accounts["builder-account"].allow_from = [$puid]
  ' "$CONFIG_SRC")

ENV_CONTENT="# Required — OpenRouter API key for LLM access
OPENROUTER_API_KEY=sk-or-...

# Required — Slack bot tokens (xoxb-...) for each bot app
SLACK_PLANNER_BOT_TOKEN=$PLANNER_BOT
SLACK_BUILDER_BOT_TOKEN=$BUILDER_BOT

# Required — Slack app-level tokens (xapp-...) for Socket Mode
SLACK_PLANNER_APP_TOKEN=$PLANNER_APP
SLACK_BUILDER_APP_TOKEN=$BUILDER_APP

# Optional — GitHub PAT for agent git operations
GITHUB_TOKEN=ghp_..."

if $DRY_RUN; then
  echo ""
  echo "=================================================="
  echo "config.slack.json"
  echo "=================================================="
  echo "$patched"
  echo ""
  echo "=================================================="
  echo ".env"
  echo "=================================================="
  echo "$ENV_CONTENT"
  exit 0
fi

echo "$patched" > "$CONFIG_DST"
echo ""
echo "  Wrote $CONFIG_DST"

echo "$ENV_CONTENT" > "$SCRIPT_DIR/.env"
echo "  Wrote $SCRIPT_DIR/.env"

echo ""
echo ">>> Done! Next steps:"
echo "  1. Edit .env — set OPENROUTER_API_KEY (and GITHUB_TOKEN if needed)"
echo "  2. Run ./install.sh  (cross-compile + copy binary)"
echo "  3. Run ./deploy.sh"
