# Secret injection on the dev box — decision pending

Status: **tabled** (2026-08-15). No backend chosen; nothing installed.

## Problem

`herdr-1` runs five coding agents — claude, codex, gemini, grok, omp — all as the
same unix user, `exedev`. Anything readable by that user is readable by all of
them. Today secrets live in plaintext `.env` files:

    -rw------- 1 exedev exedev 6245  ~/ccare-app/.env

The global `AGENTS.md` instructs agents never to print or transmit credentials.
That is a policy control, not a technical one.

## The constraint that shapes every option

Runtime injection (`doppler run --`, `op run --`, `infisical run --`) moves a
secret from *"in a file indefinitely"* to *"in a process environment while the
process runs"*. That is a real improvement, but it is **not isolation** — any
process running as `exedev` can read `/proc/<pid>/environ`. Nor does Docker help:
`exedev` is in the `docker` group, which is root-equivalent.

Real isolation would need the app to run as a separate unix user. That is a
larger change and is not currently proposed.

So the highest-leverage control remains environmental, not technical:

> **Dev and preview get throwaway credentials and mock modes. Production
> credentials never land on this box.**

Everything below is defence in depth layered on that.

## Current state (audited 2026-08-15)

Value lengths only — values were not read.

| Key | Length | Reads as |
|---|---|---|
| `SF_CLIENT_ID` | 33 | placeholder — real Salesforce consumer keys are ~85+ |
| `TWILIO_ACCOUNT_SID` | 15 | placeholder — real SIDs are 34 (`AC` + 32 hex) |
| `TWILIO_AUTH_TOKEN` | 17 | placeholder — real tokens are 32 |
| `GOOGLE_MAPS_API_KEY` | 34 | ambiguous — real keys are 39. **Verify this one.** |
| `SESSION_ENCRYPTION_KEY` | 64 | generated locally during setup |
| `POSTGRES_DB` | 49 | local container URL, not Neon |
| `VAPID_PRIVATE_KEY` | 0 | empty |

`SF_MOCK_MODE` and `SMS_MOCK_MODE` are both `true`, and `SF_WRITEBACK_ENABLED`
is `false`. So the box appears to hold no production credentials. This was
inferred from length signatures, not from the values themselves.

## Options

All four are in the exe.dev integrations catalog, so in every case the backend's
own auth token can be held at the edge (`*.int.exe.xyz`) rather than on the box.
None of the CLIs are installed yet.

### Infisical — best fit for this box

Open source and self-hostable. Same `infisical run -- npm run dev` ergonomics as
Doppler. The differentiator is **dynamic secrets**: short-lived database
credentials minted on demand and auto-expired.

That matters here specifically. A leaked static Postgres credential is valid
until noticed and rotated by hand; a dynamic one dies on a TTL. Given five agents
can read the environment, shrinking credential lifetime is worth more than
shrinking credential exposure.

Against: younger product, CLI and API have churned across versions — pin them.
Self-hosting adds another service to a box already running herdr, tailscaled,
taildrop-inbox, Postgres and dev servers.

### Doppler — the boring, stable choice

More mature, larger integration ecosystem, stable CLI. Solves "secret not on
disk" cleanly. Credentials remain static, so a leak is open-ended until rotated.

### 1Password — only if already paid for

`op run --env-file=.env.tpl -- npm run dev` with `op://vault/item/field`
references, which makes the template safe to commit. Weakest fit for machine
workloads; no dynamic secrets.

### sops + age — protects git, not the box

Encrypted `.env` committed to the repo, decrypted at runtime. No subscription, no
network dependency. But the age private key must sit on the box where the agents
can read it, so it protects repository history rather than the running box.

## Caveat

Free-tier limits and which features sit behind paid plans shift frequently for
all four. Verify current terms before committing.

## Recommendation

**Infisical** if dynamic Postgres credentials for Neon are wanted and a younger
tool is acceptable. **Doppler** if static-secrets-not-on-disk is sufficient and
stability matters more.

## Planned work once a backend is chosen

1. Install the CLI on `herdr-1`, pinned to a known version.
2. Add the exe.dev catalog integration and attach to `vm:herdr-1`, so the
   backend auth token stays at the edge — same pattern as neon, cloudflare,
   tailscale, github.
3. Migrate `~/ccare-app/.env` off plaintext; keep a committed template holding
   references only.
4. Add `dev run <worktree> -- <cmd>` to this CLI, wrapping the chosen `run`
   command so injection is the default path rather than something to remember.
5. Extend `agent-doctor` with a preflight that fails loudly if a
   production-shaped credential appears in any `.env` on the box.

## Related open items

- `~/ccare-app/.env` still points at local Postgres, not the `herdr-1-diag` Neon
  branch (`ep-red-dew-a7nl3iyz`). Whatever backend is chosen should hold that
  connection string rather than a file.
- `ccare-data-52f5483b345a.json` in the ccare-app repo looks like a GCP service
  account key, committed and readable by all agents. Unresolved.
- The Neon API key `napi_xo36…` was exposed in a terminal transcript and still
  wants rotating.
