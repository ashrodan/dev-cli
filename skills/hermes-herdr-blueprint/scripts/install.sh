#!/usr/bin/env bash
set -Eeuo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_DIR="${HERMES_INSTALL_DIR:-$HERMES_HOME/hermes-agent}"
HERMES_MODEL="${HERMES_MODEL:-gpt-5.6-sol}"
CDP_PORT="${HERMES_BROWSER_CDP_PORT:-9222}"
CDP_URL="http://127.0.0.1:${CDP_PORT}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

for command in curl git sudo systemctl; do
  command -v "$command" >/dev/null || die "missing required command: $command"
done

log "Installing Hermes when needed"
if ! command -v hermes >/dev/null 2>&1; then
  installer="$(mktemp)"
  trap 'rm -f "${installer:-}"' EXIT
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o "$installer"
  bash "$installer" --skip-setup --skip-browser --skip-computer-use
  export PATH="$HOME/.local/bin:$PATH"
fi
command -v hermes >/dev/null || die "Hermes launcher is not on PATH"

if [[ ! -d "$HERMES_DIR" ]]; then
  detected="$(dirname "$(dirname "$(readlink -f "$(command -v hermes)")")")"
  [[ -d "$detected/node_modules/playwright" ]] && HERMES_DIR="$detected"
fi
[[ -d "$HERMES_DIR" ]] || die "cannot locate Hermes install directory: $HERMES_DIR"

log "Migrating Hermes configuration"
hermes config migrate </dev/null || true

log "Installing Playwright Chromium and system dependencies"
(
  cd "$HERMES_DIR"
  npx playwright install --with-deps chromium
)

log "Installing Browser Use CLI"
UV="$HERMES_HOME/bin/uv"
[[ -x "$UV" ]] || die "Hermes managed uv not found at $UV"
"$UV" tool install --upgrade browser-use

CHROME_PATH="$(find "$HOME/.cache/ms-playwright" -type f -path '*/chrome-linux*/chrome' -perm -u+x 2>/dev/null | sort -V | tail -n 1)"
[[ -n "$CHROME_PATH" ]] || die "Playwright Chromium executable not found"
ln -sfn "$CHROME_PATH" "$HOME/.local/bin/google-chrome"

log "Installing persistent loopback-only Chromium service"
SERVICE_TMP="$(mktemp)"
trap 'rm -f "${installer:-}" "${SERVICE_TMP:-}"' EXIT
cat >"$SERVICE_TMP" <<EOF
[Unit]
Description=Headless Chromium for Hermes Browser Use
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$(id -un)
Group=$(id -gn)
Environment=HOME=$HOME
ExecStart=$CHROME_PATH --headless=new --no-sandbox --disable-dev-shm-usage --disable-gpu --remote-debugging-address=127.0.0.1 --remote-debugging-port=$CDP_PORT --user-data-dir=$HERMES_HOME/browser-use-profile about:blank
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
sudo install -m 0644 "$SERVICE_TMP" /etc/systemd/system/hermes-browser.service
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-browser.service

log "Configuring Browser Use and tool discovery"
mkdir -p "$HERMES_HOME"
touch "$HERMES_HOME/.env"
if grep -q '^BU_CDP_URL=' "$HERMES_HOME/.env"; then
  sed -i "s|^BU_CDP_URL=.*|BU_CDP_URL=$CDP_URL|" "$HERMES_HOME/.env"
else
  printf '\n# Local headless Chromium managed by hermes-browser.service\nBU_CDP_URL=%s\n' "$CDP_URL" >>"$HERMES_HOME/.env"
fi
chmod 0600 "$HERMES_HOME/.env"

hermes config set browser.backend browser-use
hermes config set tools.tool_search.enabled true
hermes config set tools.tool_search.listing true
hermes config set model.provider openai-codex
hermes config set model.default "$HERMES_MODEL"

log "Installing Herdr integration and authoritative local skill"
if command -v herdr >/dev/null 2>&1; then
  herdr integration install hermes
  skill_dir="$HERMES_HOME/skills/autonomous-ai-agents/herdr"
  mkdir -p "$skill_dir"
  herdr --skill >"$skill_dir/SKILL.md"
  chmod 0644 "$skill_dir/SKILL.md"
else
  printf 'warning: herdr is not installed; skipping Herdr integration\n' >&2
fi

blueprint_skill_dir="$HERMES_HOME/skills/software-development/hermes-herdr-blueprint"
mkdir -p "$blueprint_skill_dir"
install -m 0644 "$REPO_ROOT/skills/hermes-herdr-blueprint/SKILL.md" "$blueprint_skill_dir/SKILL.md"

log "Checking local browser"
for _ in $(seq 1 30); do
  curl -fsS "$CDP_URL/json/version" >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS "$CDP_URL/json/version" >/dev/null || die "Chromium CDP did not become ready"

BU_CDP_URL="$CDP_URL" browser-use --reload >/dev/null 2>&1 || true
BU_CDP_URL="$CDP_URL" browser-use <<'PY'
ensure_real_tab()
goto_url('https://example.com')
info = page_info()
assert info.get('title') == 'Example Domain', info
print('Browser Use OK:', info['title'])
PY

log "Installation complete"
printf '%s\n' \
  "Run 'hermes model' to authenticate/select the ChatGPT or Codex subscription." \
  "Then run: ./scripts/verify.sh"
