# Modal + Slack multi-agent deployment

Deploy nullclaw with multiple agents in a shared Slack channel on [Modal](https://modal.com).

## Architecture

Two agents — planner and builder — run as separate Slack bot apps in the same channel using Socket Mode (outbound WebSocket, no public URL needed). Messages from each bot are visible in the channel, so you can watch the agents collaborate. You can type commands directly in the channel too.

Secrets flow: `.env` (local) → `modal.Secret.from_dotenv()` → container env vars → `inject_secrets()` patches config in-memory → nullclaw starts with real credentials. Secrets never touch config files on disk.

## Prerequisites

- [Zig](https://ziglang.org/) (for cross-compiling)
- Python 3
- [Modal CLI](https://modal.com/docs/guide) (`pip install modal && modal setup`)
- A Slack workspace where you can create apps

## Quick start

```sh
# 1. Create 2 Slack apps (one-time, ~5 min) — see checklist below
# 2. Run interactive setup (creates channel, patches config + .env)
./setup.sh

# 3. Edit .env — set OPENROUTER_API_KEY
# 4. Cross-compile + deploy
./install.sh
./deploy.sh
```

## Slack app checklist (one-time)

Create two Slack apps at https://api.slack.com/apps → **Create New App** → From scratch.

For **each** app:

1. **OAuth & Permissions** → Bot Token Scopes: `chat:write`, `app_mentions:read`, `channels:history`, `channels:read`, `groups:read`, `groups:write`, `groups:history`
2. **Socket Mode** → Enable → Create App-Level Token (`connections:write`) → copy `xapp-...`
3. **Event Subscriptions** → Enable → Subscribe: `message.channels`, `message.groups`, `app_mention`
4. **Install to Workspace** → copy `xoxb-...` Bot User OAuth Token

Then run `./setup.sh` — it creates the channel, invites both bots and you, and patches `config.slack.json` and `.env` from the templates.

## Files

| File | Tracked | Purpose |
|------|---------|---------|
| `setup.sh` | yes | Interactive setup — creates channel, patches config + .env |
| `.env.example` | yes | Secret template |
| `config.slack.example.json` | yes | Config template (no secrets) |
| `modal_app.py` | yes | Modal app definition |
| `install.sh` | yes | Cross-compile + setup |
| `deploy.sh` | yes | Validate + deploy |
| `.env` | no | Your secrets |
| `config.slack.json` | no | Your config |
| `nullclaw-linux-musl` | no | Cross-compiled binary |
