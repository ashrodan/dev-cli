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

That file also carries the working rules — finish the task, verify locally, ask
before touching production, commit as you go, worktree off a dirty branch, draft
PR for unfinished work, green CI before marking ready. The canonical copy is
[docs/agent-rules.md](agent-rules.md); paste it in as a `## Working rules`
section, since AGENTS.md has no include mechanism and the box has no clone of
this repo:

```sh
scp docs/agent-rules.md <vm>:/tmp/
ssh <vm> "sed '1s/^# /## /' /tmp/agent-rules.md >> ~/.config/shelley/AGENTS.md && rm /tmp/agent-rules.md"
```

Being a copy, it can drift — re-paste when the rules change.

## 6. Skills

Agents ship with no skills by default — a fresh box runs `claude` without even
`using-exe-dev`, which is the one it most needs there. Skills live in
[ashrodan/ar-agent-skills](https://github.com/ashrodan/ar-agent-skills), in the
open `SKILL.md` format, so one repo serves Claude, Codex and anything reading a
skills directory.

```sh
ssh exe.dev "integrations add github --name ar-agent-skills \
  --repository ashrodan/ar-agent-skills --attach vm:<vm>"

ssh <vm> 'git clone https://github.int.exe.xyz/ashrodan/ar-agent-skills.git && \
          cd ar-agent-skills && ./install.sh'
```

`install.sh` symlinks rather than copies, so `git pull` in the clone updates
every tool at once. It populates:

```
~/.claude/skills     29 skills
~/.codex/skills      29 skills, plus 25 prompts and 20 agent .toml configs
~/.agents/skills     29 skills   (generic, for anything else)
```

Claude Code can alternatively consume it as a plugin marketplace:
`/plugin marketplace add ashrodan/ar-agent-skills`.

## 7. Taildrop inbox

Files sent from a phone share sheet land automatically:

```ini
# /etc/systemd/system/taildrop-inbox.service
ExecStart=/bin/tailscale file get --loop --conflict=rename --verbose /home/exedev/inbox/
```

Requires `sudo tailscale set --operator=exedev` first, or the CLI needs root.
`drop -i` then prints the newest image path to hand to an agent — much better
than pasting image data through an SSH session.

## 8. Notifications

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

## 9. GitHub

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

## Workload Identity Federation — what actually bites

Setting up GCP WIF for `dash-ai-uat` worked, but not on the first pass. In
order of how much time each cost:

**The subject in the integration form is not necessarily the one the VM
presents.** Bind the wrong one and every symptom points at permissions. Read it
from a live token instead:

```sh
ssh <vm> 'curl -sS https://<integration>.team.exe.xyz/token' |
  python3 -c 'import base64,json,sys
t=json.load(sys.stdin)["token"].split(".")[1]; t+="="*(-len(t)%4)
c=json.loads(base64.urlsafe_b64decode(t))
print("iss", c["iss"]); print("sub", c["sub"]); print("aud", c["aud"])'
```

**Team integrations attach to tags only.** `vm:<name>` is rejected. Attach to a
tag the VM already carries rather than inventing one. Allow ~20s to propagate —
until then `/token` returns "not found or not attached to this VM".

**Two audience formats, both correct.** The JWT's `aud` is
`https://iam.googleapis.com/projects/...` and the provider's `--allowed-audiences`
must match it exactly. The credential config file uses `//iam.googleapis.com/...`
— that one `gcloud create-cred-config` writes for you.

**`gcloud` ignores `GOOGLE_APPLICATION_CREDENTIALS`.** That variable is for
client libraries; the Go BigQuery client picks it up with no code change. The
CLI needs `gcloud auth login --cred-file=<config>` plus
`gcloud config set account <sa>` — `gcloud auth list` will show the account
ACTIVE while `core/account` is still unset, which is not a helpful signal.

**IAM propagates slowly, twice.** A service account seconds old is invisible to
the project-level IAM API, and a fresh `workloadIdentityUser` binding takes
another ~20-40s before impersonation succeeds. Retry rather than re-configure.

Public datasets need no grant at all: `bigquery-public-data.thelook_ecommerce`
carries `allUsers: READER`, so `roles/bigquery.jobUser` on the billing project
is the entire permission set.
