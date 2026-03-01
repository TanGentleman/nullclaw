#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# --- Check prerequisites ---
missing=()
command -v zig   >/dev/null 2>&1 || missing+=(zig)
command -v python3 >/dev/null 2>&1 || missing+=(python3)
command -v modal >/dev/null 2>&1 || missing+=(modal)

if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing prerequisites: ${missing[*]}"
  echo ""
  echo "Install:"
  echo "  zig     — https://ziglang.org/download/"
  echo "  python3 — https://www.python.org/"
  echo "  modal   — pip install modal && modal setup"
  exit 1
fi

# --- Cross-compile for Linux musl ---
echo ">>> Cross-compiling nullclaw for x86_64-linux-musl..."
(cd "$REPO_ROOT" && zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSmall -Dchannels=slack)

BINARY="$REPO_ROOT/zig-out/bin/nullclaw"
if [ ! -f "$BINARY" ]; then
  echo "Build failed — binary not found at $BINARY"
  exit 1
fi

cp "$BINARY" "$SCRIPT_DIR/nullclaw-linux-musl"
echo "  Binary: $SCRIPT_DIR/nullclaw-linux-musl ($(du -h "$SCRIPT_DIR/nullclaw-linux-musl" | cut -f1))"

# --- Copy templates if they don't exist ---
if [ ! -f "$SCRIPT_DIR/config.slack.json" ]; then
  cp "$SCRIPT_DIR/config.slack.example.json" "$SCRIPT_DIR/config.slack.json"
  echo "  Created config.slack.json from template"
else
  echo "  config.slack.json already exists, skipping"
fi

if [ ! -f "$SCRIPT_DIR/.env" ]; then
  cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
  echo "  Created .env from template"
else
  echo "  .env already exists, skipping"
fi

echo ""
echo ">>> Done! Next steps:"
echo "  1. Edit examples/modal-slack/config.slack.json"
echo "     — Set channel_id, allow_from (Slack User IDs) for each account"
echo "     — Leave bot_token and app_token empty (injected from .env)"
echo "  2. Edit examples/modal-slack/.env"
echo "     — Set OPENROUTER_API_KEY and Slack bot/app tokens"
echo "  3. Run ./deploy.sh"
