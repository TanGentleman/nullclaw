#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Load .env ---
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "Missing .env — copy .env.example and fill in your secrets"
  exit 1
fi

set -a
source "$SCRIPT_DIR/.env"
set +a

# --- Validate required secrets ---
missing=()
[ -z "${OPENROUTER_API_KEY:-}" ]        && missing+=(OPENROUTER_API_KEY)
[ -z "${SLACK_PLANNER_BOT_TOKEN:-}" ]   && missing+=(SLACK_PLANNER_BOT_TOKEN)
[ -z "${SLACK_PLANNER_APP_TOKEN:-}" ]   && missing+=(SLACK_PLANNER_APP_TOKEN)
[ -z "${SLACK_BUILDER_BOT_TOKEN:-}" ]   && missing+=(SLACK_BUILDER_BOT_TOKEN)
[ -z "${SLACK_BUILDER_APP_TOKEN:-}" ]   && missing+=(SLACK_BUILDER_APP_TOKEN)

if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing required secrets in .env: ${missing[*]}"
  exit 1
fi

# --- Check binary + config ---
if [ ! -f "$SCRIPT_DIR/nullclaw-linux-musl" ]; then
  echo "Missing nullclaw-linux-musl — run ./install.sh first"
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/config.slack.json" ]; then
  echo "Missing config.slack.json — run ./install.sh first"
  exit 1
fi

# --- Deploy ---
echo ">>> Deploying to Modal..."
modal deploy "$SCRIPT_DIR/modal_app.py"

echo ""
echo ">>> Deployed! View logs:"
echo "  modal app logs nullclaw-slack"
