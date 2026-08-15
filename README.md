# dev

A worktree-first navigator for a remote [herdr](https://github.com/) dev box.

Projects live on a remote VM; you sit in front of a Mac. `dev` lists every git
worktree across every repo on that box and drops you into one — either attached
to its herdr session, or open in VS Code over Remote-SSH.

Worktrees are the unit of work. The main checkout is just the worktree that
happens to hold the primary branch.

## Usage

```
dev                     browse worktrees with a live preview pane
                          ↑ ↓        move, preview updates as you go
                          → enter    open the action menu
                          ← esc      back out of the menu / quit
                          ctrl-o     VS Code      ctrl-h  herdr
                          ctrl-p     preview      ctrl-e  env push
                          ctrl-r     refresh
dev ls                  list every worktree, with any servers it is running
dev ps                  every listening server on the box, with preview URLs
dev preview [query]     open a running server in the browser
dev new [repo] <branch> [--base ref]
dev code  [query]       open in VS Code, skipping the picker on a unique match
dev herdr [query]       attach herdr, same matching
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

## Requirements

Local: `bash`, `fzf`, `python3`, `ssh`, and the `code` CLI for the VS Code path.
Remote: `herdr` on `PATH`, `git`, `python3`.

An SSH host alias for the box — the default is `dai`:

```sshconfig
Host dai
  HostName your-box.example.com
  User you
```

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `DEV_REMOTE` | `dai` | SSH host alias for the box |
| `DEV_REMOTE_HOME` | `/home/exedev` | Remote home, where repos are searched |
| `DEV_WT_ROOT` | `$DEV_REMOTE_HOME/worktrees` | Where new worktrees are created |
| `DEV_SESSION` | `default` | herdr session to attach |
| `DEV_PROXY_HOST` | `herdr-1.exe.xyz` | hostname the exe.dev proxy serves |
| `DEV_PROXY_PORT` | `8000` | the designated port, served at the bare hostname |
| `DEV_TS_HOST` | `herdr-1` | Tailscale/MagicDNS name, used for ports outside 3000-9999 |

## Install

```sh
git clone https://github.com/ashrodan/dev-cli.git ~/dev/dev-cli
ln -s ~/dev/dev-cli/dev ~/.local/bin/dev
```

## Notes

`dev rm` requires the worktree to be open as a herdr workspace, since removal
goes through the workspace API. Open it first if it isn't already. Removing a
worktree leaves the branch intact — delete that separately if you want it gone.
