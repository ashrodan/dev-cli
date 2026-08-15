# dev

A worktree-first navigator for a remote [herdr](https://github.com/) dev box.

Projects live on a remote VM; you sit in front of a Mac. `dev` lists every git
worktree across every repo on that box and drops you into one — either attached
to its herdr session, or open in VS Code over Remote-SSH.

Worktrees are the unit of work. The main checkout is just the worktree that
happens to hold the primary branch.

## Usage

```
dev                     pick a worktree
                          enter   → attach the herdr session, focused there
                          ctrl-o  → open in VS Code (Remote-SSH)
dev ls                  list every worktree across every repo
dev new [repo] <branch> [--base ref]
dev code  [query]       open in VS Code, skipping the picker on a unique match
dev herdr [query]       attach herdr, same matching
dev rm    [query]       remove a worktree checkout
```

A `●` in the listing marks a worktree that already has an open herdr workspace.

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

## Install

```sh
git clone https://github.com/ashrodan/dev-cli.git ~/dev-cli
ln -s ~/dev-cli/dev ~/.local/bin/dev
```

## Notes

`dev rm` requires the worktree to be open as a herdr workspace, since removal
goes through the workspace API. Open it first if it isn't already. Removing a
worktree leaves the branch intact — delete that separately if you want it gone.
