---
name: onboard-repo-to-box
description: Clone a GitHub repo onto an exe.dev box and move its .env across safely. Use when a project exists on the laptop but not on the box, when a cloned repo is missing its secrets, or when setting up an existing project on a new box. Covers the github integration (so no token lands on the box), selective env copying, and the variables that silently break on a remote host.
allowed-tools: Bash, Read
argument-hint: [repo-name] [--vm herdr-1]
---

# onboard-repo-to-box

Getting a project onto the box is two jobs, and neither is a plain `git clone`:

1. **Code** arrives through an exe.dev GitHub integration, so no personal access
   token is ever written to the box.
2. **Secrets** never travel through git. They move separately, and several of
   them do not survive the trip unchanged.

Step 2 is where this goes wrong. A repo that clones cleanly and still fails at
runtime is almost always a `.env` that was copied verbatim when it should not
have been.

## When to invoke

- A project is in `~/dev/<name>` locally but not on the box.
- A repo was cloned on the box and the app fails on missing config.
- A new box needs a project that already runs elsewhere.

## Never

- Never put a GitHub PAT on a box. The integration exists so you don't have to.
- Never pass a secret value as a command-line argument — argv is visible to
  every process on the host. `dev env push` sends values over stdin for this
  reason.
- Never commit `.env` or a service-account key. Check `git check-ignore` before
  copying anything into the working tree.

## 1. Locate the project and its remote

```bash
ls -d ~/dev/*<name>*
cd ~/dev/<repo> && git remote -v
```

Take `owner/repo` from the remote — not from the directory name, which often
differs.

## 2. Check for an existing integration

```bash
ssh exe.dev "integrations list" | grep <repo>
```

The output ends with the attachment specs (`vm:herdr-1`, `tag:...`, `auto:all`).
If one already exists and is attached to your target VM, skip to step 4. If it
exists but is attached elsewhere, attach rather than re-add:

```bash
ssh exe.dev "integrations attach <name> vm:<vm>"
```

## 3. Add the integration

```bash
ssh exe.dev "integrations add github --name=<repo> --repository=<owner>/<repo> --attach=vm:<vm>"
```

- `--readonly` if the box should never push. Worth defaulting to for anything
  you only need to run.
- `--act-as-user` attributes commits to your GitHub account. Without it they
  come from `exe-dev-github-integration[bot]`, which Vercel and similar will not
  trust for deploys.
- The integration *name* is arbitrary here — unlike catalog integrations, the
  clone host is always `github.int.exe.xyz`.

## 4. Clone

```bash
ssh <vm> "test -e ~/<repo> && echo 'EXISTS already' || git clone https://github.int.exe.xyz/<owner>/<repo>.git"
ssh <vm> "cd ~/<repo> && git rev-parse --abbrev-ref HEAD && git log --oneline -1"
```

The clone lands on the **default branch**, not whatever you had checked out
locally. Check out the working branch explicitly if that matters.

## 5. Audit the .env before copying any of it

Compare what exists on each side. `dev env diff` shows key names only:

```bash
dev env diff -p /home/exedev/<repo>          # local-only vs remote-only keys
dev env ls   -p /home/exedev/<repo>          # what the box already has
```

Then check for the four classes of variable that do not survive a move. Report
key *names*; never print values.

**a. Path-valued vars — the value is a filename, not a secret.**

```bash
grep -E '^[A-Za-z_][A-Za-z0-9_]*=.*\.(json|pem|p12|key)' .env | cut -d= -f1
```

Typically `GOOGLE_APPLICATION_CREDENTIALS`, `GCP_SA_KEY_FILE`. Copying the
variable achieves nothing — the file itself has to go too (step 6), and it must
be gitignored on the far side.

**b. localhost URLs — reachable on your laptop, meaningless on the box.**

```bash
grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env | grep -iE 'localhost|127\.0\.0\.1' | cut -d= -f1
```

OAuth redirect URIs are the usual casualty. On the box the equivalent is
`https://<vm>.exe.xyz:<port>/`, and that URI normally has to be registered with
the provider before it will work. Related: servers on the box must bind
`0.0.0.0`, never `127.0.0.1`, or the exe.dev proxy cannot see them.

**c. Session-bound values — copying them moves a dead credential.**

Cookies, `VERCEL_OIDC_TOKEN`, anything short-lived. Regenerate on the box
(`vercel pull`, a fresh login) instead of copying. Long-lived refresh tokens and
API keys are fine to move.

**d. Environment toggles.** `NODE_ENV`, `*_DEV_MODE`, `PORT`, dataset names
pointing at a local database. Decide these per-host rather than inheriting them.

Also check for keys that live only in a sibling file:

```bash
comm -13 <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*' .env | sort) \
         <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*' .env.local | sort)
```

## 6. Copy

Selective, and it merges into any existing remote `.env` rather than replacing
it. The picker masks values (`******** (36 chars)`) and sends them over stdin:

```bash
dev env push -p /home/exedev/<repo>
```

Interactive — tab to select, enter to push. It defaults to
`~/dev/<repo>/.env` as the source; use `--from` for another file.

For the whole file unchanged:

```bash
scp ~/dev/<repo>/.env <vm>:<repo>/.env
```

Then any side files the env *points at*:

```bash
scp ~/dev/<repo>/<service-account>.json <vm>:<repo>/
ssh <vm> "chmod 600 ~/<repo>/<service-account>.json"
```

## 7. Verify

```bash
dev env diff -p /home/exedev/<repo>    # only intentional differences remain
dev ps                                 # the app's port, and its reachable URL
```

Start the app and confirm it binds `0.0.0.0`. `dev ps` flags localhost-bound
ports precisely because they look fine from a shell on the box and are invisible
through the proxy.

## Gotchas

**The box is shared.** Every agent running on it can read every `.env` and every
service-account key there. Prefer `--readonly` integrations, copy the minimum
set of variables, and keep production credentials off it entirely.

**`dev env push` merges, `scp` replaces.** If the box already has a working
`.env`, `scp` will silently discard box-specific edits — the localhost fixes from
step 5b among them.

**A missing `.env` is expected after cloning.** It is gitignored; that is the
system working. Only `.env.example` should arrive with the code.
