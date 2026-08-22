# Blueprint specification

## Goal

Provide a reproducible Hermes installation that uses an existing OpenAI Codex subscription, can automate a real browser locally, can discover skills/tools, preserves Hermes' official messaging progress behaviour, and participates in Herdr-managed coding-agent workflows.

## Tested baseline

Captured on August 17, 2026; messaging behaviour revalidated against upstream Hermes on August 22, 2026:

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
| Messaging reference revision | `7d6db4efb885856078e4d19f804035226df81e0d` |
| Long-turn notification interval | 180 seconds |

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

## Messaging gateway behaviour

### Transport ACK is not a chat acknowledgement

An inbound webhook should be acknowledged with HTTP 2xx as soon as authentication, parsing, policy, deduplication, and durable enqueueing succeed. That prevents upstream retries and duplicate turns. The user never sees this transport response.

Do not turn the transport ACK into an immediate WhatsApp message. Official Hermes uses presentation primitives instead:

1. Start the platform typing indicator immediately and keep refreshing it while the turn owns the session.
2. Surface natural interim assistant commentary independently of tool-progress verbosity.
3. Stream or edit answer text progressively where the adapter supports it.
4. After `HERMES_AGENT_NOTIFY_INTERVAL` seconds—180 by default—send `⏳ Working — N min`.
5. On later intervals, edit the same status message where possible; send a new status only when editing is unsupported.
6. Stop progress tasks before the terminal success, timeout, or failure reply so status can never arrive after the final message.

Fast turns therefore produce typing followed by one final answer. They do not produce an automatic “I'm on it” bubble.

### Hermes display defaults

Hermes resolves chat presentation in `gateway/display_config.py` and runs the long-turn notifier in `gateway/run.py`.

| Surface | Native WhatsApp/Baileys | WhatsApp Cloud API |
|---|---|---|
| Typing | enabled | enabled |
| Streaming/editing | supported | adapter does not implement editing |
| Tool progress | `new`, accumulated into one editable message | off |
| Interim assistant commentary | enabled | off |
| Long-running notification | enabled, first at 180 seconds | off |
| Busy acknowledgement detail | enabled | off |

An explicit native WhatsApp configuration can preserve those defaults:

```yaml
streaming:
  enabled: true

display:
  platforms:
    whatsapp:
      tool_progress: new
      tool_progress_grouping: accumulate
      interim_assistant_messages: true
      long_running_notifications: true
      busy_ack_detail: true
```

Set `HERMES_AGENT_NOTIFY_INTERVAL=0` to disable long-running notifications or a positive number of seconds to change the cadence. Do not set it to zero as a way to request an immediate acknowledgement; zero means disabled in Hermes.

### Native gateway versus CLI wrappers

For exact behaviour, run the official Hermes gateway and its native platform adapter. The gateway receives structured message, commentary, tool, and notice events and can stream or edit them.

A custom bridge that invokes `hermes chat -Q -q` as a subprocess sees only the final CLI output. Its faithful fallback is limited to:

- best-effort typing, refreshed about every 10 seconds;
- no immediate canned acknowledgement;
- a 180-second `⏳ Working — N min` timer while the subprocess remains active;
- the final response after every progress worker has stopped.

Such a bridge cannot surface natural interim commentary, per-tool status, or edit-in-place streaming unless it integrates with the gateway event stream. Document that limitation rather than describing the fallback as full Hermes parity.

### Messaging verification

Use deterministic fake turns before any live-chat test:

- a turn shorter than the notification threshold emits no user-visible status;
- a slow turn emits its first status at or after the threshold;
- a completed turn cancels the notifier;
- the final answer is always the last outbound message;
- duplicate inbound IDs produce one turn and one final reply;
- typing starts and stops without delaying the agent turn.

A live WhatsApp message is a production write. Run one only with explicit approval.

Upstream references:

- [`website/docs/user-guide/messaging/index.md`](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/messaging/index.md)
- [`gateway/display_config.py`](https://github.com/NousResearch/hermes-agent/blob/7d6db4efb885856078e4d19f804035226df81e0d/gateway/display_config.py)
- [`gateway/run.py`](https://github.com/NousResearch/hermes-agent/blob/7d6db4efb885856078e4d19f804035226df81e0d/gateway/run.py#L28785-L28889)

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
hermes gateway status
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
- When a messaging gateway is configured, typing begins promptly and fast turns send no canned acknowledgement.
- Native WhatsApp long turns first surface `⏳ Working — N min` at the configured interval, default 180 seconds.
- Progress workers stop before the final reply; the final reply is always last.
