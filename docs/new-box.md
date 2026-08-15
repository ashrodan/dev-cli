# Setting up a new box

Runbook for bringing a fresh exe.dev VM to the same state as `herdr-1`. Written
from what was actually done, not from what ought to work.

Order matters in a few places, flagged where it does.

## 1. Create and tag

```sh
ssh exe.dev "new --name=<vm> --comment='what it is'"
ssh exe.dev "tag <vm> tailscale"
```

The `tailscale` tag is load-bearing in two places: `exe-tailscale-enroll` uses it
to find boxes, and any SSH key registered with `--tag=tailscale` is scoped to
exactly those boxes. Tagging is therefore the single switch that both enrols a
box and grants your mobile key access to it.

## 2. Join the tailnet

The `tailscale` integration must be attached before enrolment, or the box cannot
mint itself a key. Attaching to the tag covers every current and future box:

```sh
ssh exe.dev "integrations attach tailscale tag:tailscale"   # once per account
exe-tailscale-enroll
fleet-hosts
```

`exe-tailscale-enroll` is idempotent — already-joined boxes are skipped — and
each VM mints its own single-use, 10-minute auth key through the integration
proxy, so no Tailscale credential is ever written to disk.

The exeuntu image ships `tailscale` already, so nothing needs installing.

## 3. herdr

Install, then make it survive reboots. Long-running work belongs in a herdr pane,
not a bare SSH session that dies with the connection.

```ini
# /etc/systemd/system/herdr.service
[Unit]
Description=herdr agent runtime (headless server)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=exedev
WorkingDirectory=/home/exedev
Environment=HOME=/home/exedev
Environment=PATH=/home/exedev/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/home/exedev/.local/bin/herdr server
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```

Then `herdr integration install <agent>` for each agent you install, so herdr can
track agent state. `herdr integration status` shows what is wired. Without these
hooks, `agent-notify` has nothing to watch.

## 4. Agents

Currently on herdr-1:

| | version |
|---|---|
| herdr | 0.8.0 |
| claude | 2.1.228 |
| codex | 0.147.0 |
| gemini | 0.55.1 |
| grok | 1.0.3 |
| omp | 17.3.0 |

Two gotchas that cost time the first go:

- **codex refuses to run outside a git repository.** Pass
  `--skip-git-repo-check` when there genuinely is no repo.
- **Non-TTY SSH blocks on stdin.** Any scripted agent invocation needs
  `</dev/null`, or it hangs until the timeout.

Copy `agent-doctor` over and run it. `agent-doctor --probe` sends a live prompt
to each agent — worth running on a schedule, because OAuth tokens expire quietly
and you would rather not find out mid-task.

## 5. Global context

One canonical file, symlinked everywhere an agent will look:

```
~/.config/shelley/AGENTS.md          the real file
~/.claude/CLAUDE.md      -> it
~/.codex/AGENTS.md       -> it
~/.gemini/GEMINI.md      -> it
~/AGENTS.md              -> it        (omp, shelley, anything walking up from cwd)
```

grok reads `~/.claude/` on its own. The home-level symlink matters: without it,
omp and shelley run with no awareness of the box at all — including the rules
about binding `0.0.0.0` and never publishing a share.

## 6. Taildrop inbox

Files sent from a phone share sheet land automatically:

```ini
# /etc/systemd/system/taildrop-inbox.service
ExecStart=/bin/tailscale file get --loop --conflict=rename --verbose /home/exedev/inbox/
```

Requires `sudo tailscale set --operator=exedev` first, or the CLI needs root.
`drop -i` then prints the newest image path to hand to an agent — much better
than pasting image data through an SSH session.

## 7. Notifications

See [box/README.md](../box/README.md) for the detail. In short:

- `agent-notify` polls `herdr agent list` and pushes on `working → blocked` or
  `working → idle/done`
- `agent-action` is a tailnet-only endpoint backing the Continue button
- delivery is ntfy, because it carries a click target and action buttons

Configure the topic via drop-in, never in the script:

```ini
# /etc/systemd/system/agent-notify.service.d/override.conf
[Service]
Environment=AGENT_NOTIFY_NTFY=https://ntfy.sh
Environment=AGENT_NOTIFY_TOPIC=<topic>
Environment=AGENT_NOTIFY_CLICK=termius://
Environment=AGENT_ACTION_URL=http://<tailscale-ip>:2587
```

## 8. GitHub

Never put a personal access token on a box. Attach an integration and clone
through the proxy hostname:

```sh
ssh exe.dev "integrations add github --name <name> --repository <owner>/<repo> --attach vm:<vm>"
git clone https://github.int.exe.xyz/<owner>/<repo>.git
export GH_HOST=github.int.exe.xyz
```

Commits are attributed to `exe-dev-github-integration[bot]` unless the
integration was created `--act-as-user`. **Set `git config user.email` to an
address linked to your GitHub account** — otherwise Vercel and similar will not
trust the commits, and the default `exedev@<vm>.exe.xyz` is linked to nothing.

## Gotchas worth remembering

**Bind `0.0.0.0`, never `127.0.0.1`.** The exe.dev proxy sits outside the VM, so
a localhost-bound port works locally and is invisible through the proxy. `dev ls`
flags localhost-bound ports for this reason.

**Ports 3000–9999 are proxied publicly** (behind exe.dev auth) at
`https://<vm>.exe.xyz:<port>/`. Anything you want tailnet-only should bind the
Tailscale IP and sit outside that range — which is what `ntfy` (2586) and
`agent-action` (2587) do.

**HTTPS pages cannot fetch HTTP endpoints.** The ntfy web app fails on the
Continue button for this reason; the native Android app is subject to neither
mixed-content nor CORS rules and works fine.

**Certificate Transparency is public and permanent.** Enabling Tailscale HTTPS
certs, or issuing a cert for a staging domain, publishes those hostnames to logs
that are actively scraped. An obscure hostname is not a private one.

**`~/.vscode-server` is a few hundred MB.** On a 25 GB disk with node_modules
around, worth knowing it is there.
