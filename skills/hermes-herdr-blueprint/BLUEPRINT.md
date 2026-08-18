# Blueprint specification

## Goal

Provide a reproducible Hermes installation that uses an existing OpenAI Codex subscription, can automate a real browser locally, can discover skills/tools, and participates in Herdr-managed coding-agent workflows.

## Tested baseline

Captured on August 17, 2026:

| Component | Working value |
|---|---|
| OS | Ubuntu Linux on exe.dev |
| Hermes | v0.20.1 |
| Provider | `openai-codex` |
| Model | `gpt-5.6-sol` |
| Browser backend | `browser-use` |
| Browser CDP endpoint | `http://127.0.0.1:9222` |
| Herdr | v0.8.0 |
| Herdr Hermes integration | v4 |

Versions are observations, not pins. The installer uses current upstream releases unless explicitly modified.

## Architecture

```text
Termius/SSH
    |
    v
Herdr persistent session
    |
    +-- Hermes Agent
    |     +-- OpenAI Codex OAuth subscription
    |     +-- skills + tool search
    |     +-- browser-use tool
    |
    +-- other coding agents (Codex, Claude, OMP, Grok, ...)

systemd: hermes-browser.service
    |
    v
Headless Chromium on loopback CDP :9222
```

The CDP endpoint binds to loopback only. It must not be exposed through the exe.dev proxy or a public interface.

## Installation procedure

### 1. Prerequisites

- Linux host with `sudo`, `curl`, Git, Node.js, and systemd.
- Herdr installed if Herdr management is desired.
- Codex CLI already authenticated with the intended ChatGPT/Codex subscription, or willingness to complete Hermes' device-code login.

Never copy credentials between machines or commit OAuth files.

### 2. Run the installer

```bash
./scripts/install.sh
```

The installer is intended to be idempotent. It:

1. Installs Hermes if absent.
2. Installs Playwright Chromium and Linux browser dependencies.
3. Installs Browser Use CLI using Hermes' managed `uv`.
4. Creates and enables `hermes-browser.service`.
5. Configures Hermes to use `browser-use` and loopback CDP.
6. Enables skill/tool search.
7. Installs the Hermes integration supplied by Herdr.
8. Generates a local Hermes Herdr skill from `herdr --skill`.

### 3. Configure subscription authentication

Run:

```bash
hermes model
```

Choose **ChatGPT or Codex Subscription**. If Hermes offers to import an existing Codex CLI login, explicitly approve it, or perform a fresh device-code login. A fresh Hermes session is preferable when both programs will run heavily at the same time.

Select the desired model. The captured setup used:

```bash
hermes config set model.provider openai-codex
hermes config set model.default gpt-5.6-sol
```

Model availability changes over time; use the model picker if that slug is unavailable.

### 4. Verify

```bash
./scripts/verify.sh
```

For an end-to-end model/tool test:

```bash
hermes -z 'Use the browser-use browser tool to open https://example.com and report its title.'
```

Expected title: `Example Domain`.

## Herdr operation

Install/check integrations:

```bash
herdr integration install hermes
herdr integration status
```

Launch or attach to Herdr:

```bash
herdr
```

Inside a Herdr workspace, start Hermes through the UI or with `herdr agent start ... --kind hermes`. The generated Herdr skill deliberately requires `HERDR_ENV=1` before it allows Hermes to inspect or control neighboring panes.

## Files created outside this repository

| Path | Purpose |
|---|---|
| `~/.hermes/` | Hermes configuration, sessions, skills, and auth |
| `~/.local/bin/hermes` | Hermes launcher |
| `~/.local/bin/browser-use` | Browser Use launcher |
| `~/.cache/ms-playwright/` | Chromium binaries |
| `~/.hermes/browser-use-profile/` | Persistent browser profile |
| `~/.hermes/skills/autonomous-ai-agents/herdr/SKILL.md` | Generated Herdr skill |
| `~/.hermes/plugins/herdr-agent-state/` | Herdr lifecycle plugin |
| `/etc/systemd/system/hermes-browser.service` | Persistent browser service |

## Operations

```bash
systemctl status hermes-browser
sudo systemctl restart hermes-browser
journalctl -u hermes-browser -n 100 --no-pager
hermes doctor
hermes auth status openai-codex
herdr status
herdr integration status
```

## Recovery

### Browser Use cannot connect

```bash
sudo systemctl restart hermes-browser
curl -fsS http://127.0.0.1:9222/json/version
set -a; . ~/.hermes/.env; set +a
browser-use --doctor
```

### Chromium path changed after an update

Rerun:

```bash
./scripts/install.sh
```

The installer discovers the newest Playwright Chromium executable and regenerates the systemd unit.

### Codex authentication expired

Use public authentication flows rather than editing auth files:

```bash
codex login
hermes model
```

### Herdr does not recognize Hermes

```bash
herdr integration install hermes
herdr server reload-config
herdr integration status
```

## Acceptance criteria

- `hermes auth status openai-codex` reports logged in after user authentication.
- `hermes config get browser.backend` prints `browser-use`.
- `systemctl is-active hermes-browser` prints `active`.
- Browser Use can navigate to `https://example.com` through CDP.
- `hermes config get tools.tool_search.enabled` prints `true`.
- `hermes skills list` contains the local `herdr` skill.
- `herdr integration status` reports the Hermes integration as current.
