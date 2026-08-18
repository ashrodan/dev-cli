---
name: hermes-herdr-blueprint
description: Recreate Hermes with Browser Use and Herdr.
version: 0.1.0
author: Ashley Rodan, Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Hermes, Herdr, Browser-Use, Codex, Bootstrap]
    related_skills: [hermes-agent, codex, computer-use]
---

# Hermes + Herdr Blueprint

Recreate a Linux Hermes coding-agent host with OpenAI Codex subscription authentication, local Browser Use automation, skill/tool discovery, and Herdr lifecycle integration.

## When to Use

- Rebuilding this coding-agent box on a new Linux VM.
- Repairing Hermes browser or Herdr integration.
- Auditing whether the expected components remain active.

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

## Herdr Rules

The installer generates the authoritative local Herdr skill using `herdr --skill`. That generated skill governs pane and agent control and requires `HERDR_ENV=1`. Do not bypass that guard to control a user's focused Herdr session from outside Herdr.

## Pitfalls

- Model names are not permanent. Use `hermes model` if the captured default is unavailable.
- Playwright Chromium paths contain a revision number. Rerun the installer after browser upgrades so the systemd unit points to the newest executable.
- Browser Use cloud authentication is optional; the blueprint uses local loopback CDP.
- Never bind Chromium's remote-debugging port to `0.0.0.0`.
- Never commit `~/.codex/auth.json`, `~/.hermes/auth.json`, or `~/.hermes/.env`.

## Verification

Run:

```text
terminal(command="./scripts/verify.sh", timeout=180)
```

Completion requires active Chromium, successful browser navigation, enabled tool search, Codex authentication, the local Herdr skill, and a current Herdr Hermes integration.
