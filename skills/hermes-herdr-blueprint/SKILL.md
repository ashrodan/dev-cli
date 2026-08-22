---
name: hermes-herdr-blueprint
description: Recreate Hermes with Browser Use, official messaging progress behaviour, and Herdr.
version: 0.2.0
author: Ashley Rodan, Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Hermes, Herdr, Browser-Use, Codex, Bootstrap]
    related_skills: [hermes-agent, codex, computer-use]
---

# Hermes + Herdr Blueprint

Recreate a Linux Hermes coding-agent host with OpenAI Codex subscription authentication, local Browser Use automation, skill/tool discovery, official messaging progress behaviour, and Herdr lifecycle integration.

## When to Use

- Rebuilding this coding-agent box on a new Linux VM.
- Repairing Hermes browser or Herdr integration.
- Auditing whether the expected components remain active.
- Configuring or auditing Hermes typing, streaming, tool-progress, and long-running status behaviour on chat platforms.

Do not use this skill to migrate credential files or expose the browser CDP endpoint publicly.

## Prerequisites

- Linux with systemd, `sudo`, Git, curl, and Node.js.
- An authenticated Codex CLI session or access to the Hermes device-code login.
- Herdr installed when agent management is required.
- A checkout of this blueprint repository.

## Procedure

1. Read `BLUEPRINT.md` and confirm the target host meets its prerequisites.
2. Run `scripts/install.sh` through the `terminal` tool from the repository root.
3. If Codex authentication is absent, ask the user to complete `hermes model` and select **ChatGPT or Codex Subscription**. Never read, print, copy, or commit auth files.
4. Run `scripts/verify.sh` through the `terminal` tool.
5. Do not declare success until every required verification passes.

## Messaging Gateway Behaviour

Treat the transport acknowledgement and the conversation as separate layers:

- A webhook receiver SHOULD return 2xx quickly so the upstream transport does not retry. That HTTP response is invisible to the user.
- Hermes starts the platform typing indicator immediately. It does **not** send a canned chat acknowledgement on every request.
- Natural interim assistant commentary stays enabled independently of tool-progress verbosity.
- The first long-running status appears after 180 seconds by default as `⏳ Working — N min`; later heartbeats update the same message where the adapter supports editing.
- Native WhatsApp/Baileys supports edit-in-place progress. WhatsApp Cloud currently does not, so its quiet platform defaults suppress permanent progress chatter.

Read `BLUEPRINT.md` before attaching a messaging transport. A wrapper that shells out to `hermes chat` receives only final CLI output and cannot claim parity with Hermes' structured gateway events.

## Herdr Rules

The installer generates the authoritative local Herdr skill using `herdr --skill`. That generated skill governs pane and agent control and requires `HERDR_ENV=1`. Do not bypass that guard to control a user's focused Herdr session from outside Herdr.

## Pitfalls

- Model names are not permanent. Use `hermes model` if the captured default is unavailable.
- Playwright Chromium paths contain a revision number. Rerun the installer after browser upgrades so the systemd unit points to the newest executable.
- Browser Use cloud authentication is optional; the blueprint uses local loopback CDP.
- Never bind Chromium's remote-debugging port to `0.0.0.0`.
- Never commit `~/.codex/auth.json`, `~/.hermes/auth.json`, or `~/.hermes/.env`.
- Never confuse an upstream webhook's fast HTTP 200 with a user-visible acknowledgement.
- Never add an immediate canned “I'm on it” reply to imitate typing. Preserve typing, interim commentary, and the three-minute Hermes heartbeat instead.

## Verification

Run:

```text
terminal(command="./scripts/verify.sh", timeout=180)
```

Completion requires active Chromium, successful browser navigation, enabled tool search, Codex authentication, the local Herdr skill, and a current Herdr Hermes integration. When messaging is configured, also verify typing starts promptly, fast turns produce no canned acknowledgement, long-turn status starts only at the configured threshold, and the final answer is the last message.
