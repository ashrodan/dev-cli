# dev

A worktree-first navigator for a remote [herdr](https://github.com/) dev box.

Projects live on a remote VM; you sit in front of a Mac. `dev` lists every git
worktree across every repo on that box and drops you into one — either attached
to its herdr session, or open in VS Code over Remote-SSH.

Worktrees are the unit of work. The main checkout is just the worktree that
happens to hold the primary branch.

## Usage

```
dev -P [command]        interactively pick an exe.dev SSH profile
dev --profile [command] long form of `-P`
dev -H HOST [command]   use another SSH config alias and its configured key
dev -H PROFILE -B BOX  select an exe.dev box through an account/lobby alias
dev                     browse worktrees with a live preview pane
                          ↑ ↓        move, preview updates as you go
                          → enter    open the action menu
                          ← esc      back out of the menu / quit
                          ctrl-o     VS Code      ctrl-h  herdr
                          ctrl-s     herdr, in a chosen or new session
                          ctrl-p     preview      ctrl-e  env push
                          ctrl-r     refresh
dev ls                  list every worktree, with any servers it is running
dev ps                  every listening server on the box, with preview URLs
dev preview [query]     open a running server in the browser
dev new [repo] <branch> [--base ref]
dev code  [query]       open in VS Code, skipping the picker on a unique match
dev herdr [query]       attach herdr, same matching
dev herdr -S [query]    pick the session first
dev herdr -s NAME       attach in a named session, created if it does not exist
dev sessions            list herdr sessions on the box
dev rm    [query]       remove a worktree checkout

dev env push [query] [--from FILE]
                        interactively pick .env vars and copy them over
dev env ls   [query]    key names present on the remote worktree
dev env diff [query]    which keys are local-only vs remote-only
```

A `●` marks a worktree with an open herdr workspace, `*n` uncommitted files, and
`▶ port` a server it is running.

The preview pane shows branch, HEAD, relative age and subject, working-tree
state, ahead/behind against upstream, the herdr workspace, and any URLs the
worktree is serving. It renders from the cached scan rather than hitting the box
per keystroke, so arrowing through the list is instant. `ctrl-r` re-scans, and
the cache refreshes automatically after any action that could change state.

Navigation loops rather than exits: backing out of the action menu with `←`
returns to the list, and finishing a non-terminal action returns there too.

## Sessions

herdr nests as **session → workspace → tab → pane**. Tabs and workspaces are for
multitasking inside one context, and `dev` already gives every worktree its own
workspace. A second *session* is a different thing: an independent herdr with
its own socket and its own workspaces, for work you want isolated or disposable.

`ctrl-s` in the browser (or `dev herdr -S`) lists the sessions on the box and
offers `+new`. Picking a name that does not exist yet creates it on attach —
empty, since workspaces do not carry across. The worktree-open and focus calls
are scoped to the chosen session too, because the socket API is per-session.

`dev code foo` and `dev herdr foo` skip the picker entirely when `foo` matches
exactly one worktree, so they compose well with shell history.

## How it works

Everything is driven through herdr's socket API over a single SSH connection:

- `herdr worktree list --cwd <repo>` for discovery, one call per repo found
- `herdr worktree create|open|remove` for lifecycle
- `herdr workspace focus` before attaching, so the session opens where you meant

Repo discovery is a `find -maxdepth 3` for `.git` under the remote home,
skipping dotfiles and `node_modules`. New worktrees are created under
`~/worktrees/<repo>/<branch>` with `/` in branch names flattened to `-`.

## Running servers

`dev ls` annotates each worktree with the ports it is listening on, found by
matching listening sockets to the owning process's `/proc/<pid>/cwd`. `dev ps`
lists them with the URL that actually reaches them:

```
servers in worktrees
  ccare-app     3000    https://herdr-1.exe.xyz:3000/
other listeners
  MainThread    8000    https://herdr-1.exe.xyz/
```

URLs follow the exe.dev proxy rules — the designated port is served at the bare
hostname, 3000-9999 are forwarded per-port, anything else falls back to the
Tailscale address. Ports bound to `127.0.0.1` are flagged as unreachable rather
than offered, since the proxy cannot see them.

## Asking an agent, in context

```
dev ask -w ccare 'why is the migration failing?'   one-shot answer
dev ask -a gemini -w ccare 'summarise this repo'   pick the agent
dev ask -w ccare                                   interactive session there
```

The agent runs *inside* the worktree, so it starts with the repo, the branch and
the box's global `AGENTS.md` as context rather than being told about them. With
no question it drops you into an interactive session in that directory instead.

Agents: `claude` (default), `codex`, `gemini`, `grok`. The prompt travels over
stdin and the remote shell builds argv, so quoting and apostrophes are safe.

## Copying env vars

`dev env push` opens a multi-select picker over the keys in a local `.env`
(defaulting to `~/dev/<repo>/.env`), and merges the chosen ones into the
worktree's `.env` on the box. Existing keys are updated in place, preserving
comments and ordering; new keys are appended under a dated header. The previous
file is backed up alongside, and both end up mode `600`.

Values are handled carefully, because the box runs several coding agents as the
same unix user:

- **Nothing goes through a command line.** `argv` is readable via `ps`, so
  values travel over stdin only. The remote merge script is passed as base64 and
  contains no secrets itself.
- **Nothing touches an intermediate file** on either machine — the payload is a
  process substitution piped straight into SSH.
- **The picker shows key names and value lengths**, never values.

This is a convenience over a plaintext file, not a secret manager. See
[docs/secrets.md](docs/secrets.md) for the real design discussion and why
runtime injection is not the same thing as isolation.

## Cloud credentials without keys

`bin/exe-gcp-wif` does the GCP side of an exe.dev Workload Identity Federation
integration: enables the APIs, creates the pool, the OIDC provider and the
service account, and binds the exe.dev subject to impersonate it. Idempotent —
existing pools, providers and accounts are left alone — and `--dry-run` prints
what it would do.

```sh
exe-gcp-wif --project dash-ai-uat --sa dash-agent-uat \
  --issuer https://exe.dev/issuer/<name> --subject sub-XXXX \
  --audience <from the integration page> --bq-job-user
```

Run one per project, and take issuer/subject/audience from that integration's
own page — they are not shared, and mixing them up fails like a permissions
error. The credential config the VM ends up with holds no secret; it only says
where to fetch a fresh short-lived token.

Two grants are needed for BigQuery and they live in different places:
`roles/bigquery.jobUser` on the project that bills the query, and
`roles/bigquery.dataViewer` on each dataset that holds data. `metadataViewer`
gives structure without rows, which is usually the right default for an agent.

## Fleet discovery

Two helpers in `bin/`, for reaching the box and its siblings from other devices.

`exe-tailscale-enroll` joins every exe.dev VM tagged `tailscale` to the tailnet.
Each VM mints its own single-use, 10-minute auth key through the exe.dev
integration proxy, so no Tailscale credential is held locally or written to any
VM's disk. Already-joined VMs are skipped, so it is safe to re-run.

```sh
ssh exe.dev "tag <vm> tailscale"
ssh exe.dev "integrations attach tailscale tag:tailscale"   # once
exe-tailscale-enroll
```

`fleet-hosts` writes an SSH config entry for every running exe.dev VM into
`~/.ssh/config.d/fleet`, and ensures `~/.ssh/config` includes it. VMs on the
tailnet are addressed by Tailscale IP — no exe.dev auth in the path, reachable
from any device on the tailnet — and also get a `-pub` alias on the public
hostname as a fallback for when Tailscale is off. Everything else uses the
public hostname. exe.dev tags and comments are carried through as comments.

```sh
fleet-hosts --dry-run
fleet-hosts
```

Run it on a schedule so the list stays current:

```xml
<!-- ~/Library/LaunchAgents/dev.fleet-hosts.plist -->
<key>ProgramArguments</key><array><string>~/dev/dev-cli/bin/fleet-hosts</string></array>
<key>RunAtLoad</key><true/>
<key>StartInterval</key><integer>900</integer>
```

Termius imports from `~/.ssh/config`, and a Termius account syncs the result to
your phone and tablet. Note that Termius' import is a one-time copy rather than
a live subscription — re-import when the fleet changes.

## Requirements

Local: `bash`, `fzf`, `python3`, `ssh`, and the `code` CLI for the VS Code path.
Remote: `herdr` on `PATH`, `git`, `python3`.

An SSH host alias for the box — the default is `dai`. Put each box's key on its
own alias; `dev -H work-box` uses the same `HostName`, `User`, `IdentityFile`,
and other SSH config that `ssh work-box` uses:

```sshconfig
Host dai
  HostName your-box.example.com
  User you
  IdentityFile ~/.ssh/id_ed25519

Host work-box
  HostName another-box.example.com
  User you
  IdentityFile ~/.ssh/work-box
  IdentitiesOnly yes
```

An exe.dev lobby alias such as `exe-dash` can also be passed directly. `dev`
lists that account's running boxes and keeps the alias's identity while
connecting. A single box is selected automatically; select among several with
`dev -H exe-dash -B box-name`.

`dev -P` reads exact `Host` aliases from `~/.ssh/config` and its `Include`
files, keeps aliases whose resolved hostname is `exe.dev`, and shows their
identity keys in an interactive picker. The selected profile then uses the same
box selection above. `dev -H` with no host opens the same picker.

VS Code Remote-SSH cannot inherit a one-off `HostName` override. For `dev code`
through a lobby profile, give the box name its own SSH config alias with the
same key (for example `Host box-name`); `dev` uses that alias when available.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `DEV_REMOTE` | `dai` | SSH host or exe.dev lobby alias |
| `DEV_BOX` | unset | Box name when `DEV_REMOTE` is an exe.dev lobby alias |
| `DEV_REMOTE_HOME` | `/home/exedev` | Remote home, where repos are searched |
| `DEV_WT_ROOT` | `$DEV_REMOTE_HOME/worktrees` | Where new worktrees are created |
| `DEV_SESSION` | `default` | herdr session to attach |
| `DEV_PROXY_HOST` | resolved SSH hostname | hostname the exe.dev proxy serves |
| `DEV_PROXY_PORT` | `8000` | the designated port, served at the bare hostname |
| `DEV_TS_HOST` | resolved hostname without `.exe.xyz` | Tailscale/MagicDNS name, used for ports outside 3000-9999 |

## Install

```sh
git clone https://github.com/ashrodan/dev-cli.git ~/dev/dev-cli
ln -s ~/dev/dev-cli/dev ~/.local/bin/dev
```

## Skills

[`skills/`](skills/) holds agent skills in the open `SKILL.md` format, so any
tool that reads a skills directory can use them.

- **onboard-repo-to-box** — clone one of your repos onto the box and move its
  `.env` across. Covers the GitHub integration (so no token lands on the box),
  the audit that catches variables which don't survive the move — path-valued
  vars, localhost URLs, session-bound tokens — and the copy itself.
- **omp-model-graph** — wire omp into a multi-model agent graph: roles pinned to
  models, specialist agents as nodes, spawn rules as edges, typed handoffs, and
  the config flags that are off by default. Includes which model to put where,
  and how to spot a model that silently reroutes.
- **gcp-wif-for-boxes** — give a VM short-lived GCP credentials via Workload
  Identity Federation instead of a key file. Both halves of the trust chain,
  how to read the real subject off a live token, and the failure table for the
  errors that all present as "permission denied" whatever their actual cause.
- **hermes-herdr-blueprint** — rebuild a Hermes coding-agent host with Codex
  subscription auth, local Browser Use automation, official messaging progress
  behaviour and herdr integration. Self-contained: `BLUEPRINT.md`,
  `scripts/install.sh`, `scripts/verify.sh` and the systemd template travel with
  the skill.
- **wagw-shim-config** — configure and diagnose the GOWA → wagw-shimmy → agent
  WhatsApp path: directional tokens and peerings, group/channel policy, media,
  typing, Hermes progress behaviour, durable queues, and safe verification.

Link them into whichever tool you use:

```sh
ln -s ~/dev/dev-cli/skills/onboard-repo-to-box ~/.claude/skills/
```

## Docs

- [docs/new-box.md](docs/new-box.md) — runbook for bringing a fresh exe.dev VM to
  the same state, including the gotchas that cost time the first go
- [docs/agent-rules.md](docs/agent-rules.md) — working rules every agent follows;
  symlinked to `~/.claude/CLAUDE.md` here and pasted into the box's `AGENTS.md`
- [docs/secrets.md](docs/secrets.md) — tabled decision on runtime secret injection
- [box/README.md](box/README.md) — the scripts that live on the box

## Notes

`dev rm` requires the worktree to be open as a herdr workspace, since removal
goes through the workspace API. Open it first if it isn't already. Removing a
worktree leaves the branch intact — delete that separately if you want it gone.
