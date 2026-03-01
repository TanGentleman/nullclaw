"""Deploy nullclaw Slack gateway on Modal.

Secrets are loaded from .env via modal.Secret.from_dotenv() and injected
into config.json at container startup — they never touch the config file
on disk.

Deploy:
  ./deploy.sh

Logs:
  modal app logs nullclaw-slack
"""

import json
import os
import subprocess
from pathlib import Path

import modal

example_dir = str(Path(__file__).resolve().parent)

image = (
    modal.Image.debian_slim(python_version="3.12")
    .apt_install("ca-certificates", "curl", "git")
    .add_local_file(
        f"{example_dir}/nullclaw-linux-musl",
        "/opt/nullclaw",
    )
    .add_local_file(
        f"{example_dir}/config.slack.json",
        "/tmp/config.slack.json",
    )
)

app = modal.App("nullclaw-slack")


def inject_secrets(config: dict) -> dict:
    """Patch config dict with secrets from environment variables."""
    api_key = os.environ.get("OPENROUTER_API_KEY", "")
    if api_key:
        config.setdefault("models", {}).setdefault("providers", {}).setdefault("openrouter", {})
        config["models"]["providers"]["openrouter"]["api_key"] = api_key

    accounts = config.get("channels", {}).get("slack", {}).get("accounts", {})

    for account_id, account in accounts.items():
        if account_id == "planner-account":
            bot = os.environ.get("SLACK_PLANNER_BOT_TOKEN", "")
            app_tok = os.environ.get("SLACK_PLANNER_APP_TOKEN", "")
            if bot:
                account["bot_token"] = bot
            if app_tok:
                account["app_token"] = app_tok
        elif account_id == "builder-account":
            bot = os.environ.get("SLACK_BUILDER_BOT_TOKEN", "")
            app_tok = os.environ.get("SLACK_BUILDER_APP_TOKEN", "")
            if bot:
                account["bot_token"] = bot
            if app_tok:
                account["app_token"] = app_tok

    return config


@app.function(
    image=image,
    secrets=[modal.Secret.from_dotenv(path=example_dir)],
    min_containers=1,
    timeout=86400,
)
@modal.web_server(3000)
def gateway():
    # Load config and inject secrets
    with open("/tmp/config.slack.json") as f:
        config = json.load(f)

    config = inject_secrets(config)

    # Write patched config for nullclaw
    config_dir = Path("/nullclaw-data/.nullclaw")
    config_dir.mkdir(parents=True, exist_ok=True)
    config_path = config_dir / "config.json"
    config_path.write_text(json.dumps(config, indent=2))

    # Set up workspace
    workspace = Path("/nullclaw-data/workspace")
    workspace.mkdir(parents=True, exist_ok=True)

    # Expose GITHUB_TOKEN to git via .netrc
    token = os.environ.get("GITHUB_TOKEN", "")
    if token:
        netrc_path = Path("/nullclaw-data/.netrc")
        netrc_path.write_text(
            f"machine github.com\nlogin x-access-token\npassword {token}\n"
        )
        netrc_path.chmod(0o600)

    env = os.environ.copy()
    env["HOME"] = "/nullclaw-data"
    env["NULLCLAW_WORKSPACE"] = "/nullclaw-data/workspace"

    subprocess.Popen(
        ["/opt/nullclaw", "gateway", "--port", "3000", "--host", "::"],
        env=env,
    )
