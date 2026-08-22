---
name: wagw-shim-config
description: Configure and diagnose a GOWA + wagw-shimmy WhatsApp gateway connected to an agent. Use when wiring a WhatsApp number or group to an agent, changing DM/group allowlists or require-mention policy, adding per-group channel routing, configuring cross-box exe.dev peerings and directional tokens, enabling media/reactions/calls/typing, repairing empty or duplicate inbound messages, or aligning a Hermes-backed adapter with official Hermes progress behaviour.
allowed-tools: Bash, Read, Grep, Ask, Write, Edit
argument-hint: "[shim-host] [agent-host] [channel]"
---

# wagw-shim config

Configure the existing three-layer path; do not build a second WhatsApp gateway:

```text
WhatsApp ⇄ GOWA :3000 ──signed webhook──▶ wagw-shimmy :8080
                                             │
                                             │ bearer + normalized JSON
                                             ▼
                                      agent /whatsapp/inbound
                                             │
                                             │ bearer + echo chat_id
                                             ▼
                                      wagw-shimmy /send ──▶ GOWA
```

GOWA owns pairing and the long-lived WhatsApp session. `wagw-shimmy` owns HMAC verification, admission policy, deduplication, the durable forward queue, media proxy, channel routing, and send rate limiting. The agent owns conversation state and reply generation.

## Non-negotiable invariants

1. **Echo `chat_id` verbatim.** An inbound group JID ends in `@g.us`; a DM ends in `@s.whatsapp.net`. The agent must send the exact inbound `chat_id` back to `/send`. Never substitute the participant `from` JID or group replies will land in a DM.
2. **Token direction matters.** `WHATSAPP_WEBHOOK_TOKEN` authenticates shim → agent inbound. `WHATSAPP_GATEWAY_TOKEN` authenticates agent → shim replies/media/presence.
3. **A webhook HTTP 200 is not a user acknowledgement.** It prevents GOWA retries and is invisible in WhatsApp. User feedback comes from typing, agent commentary, long-running status, and the final reply.
4. **One number, one GOWA session owner.** Do not pair the same number to a second gateway while GOWA owns it.
5. **Never expose GOWA `:3000`, shim `:8080`, Chromium CDP, or secret-bearing inbound routes publicly.** Use loopback or private exe.dev peerings.
6. **Never print or copy secret values through argv, logs, chat, or git.** Filled env files remain root-owned mode `0600`.

## Production boundary

Read-only inspection is safe. Pairing, editing `/etc/*.env`, changing peerings, rotating tokens, restarting services, sending a live WhatsApp message, or replaying a real payload are production actions. Prepare and validate staged files first, then request explicit approval naming the exact install/restart/send commands. Approval for one action is not standing approval for another.

## 1. Locate the authoritative deployment

Expected source checkout and services on the shim host:

```text
~/wagw-shimmy-deploy/
gowa.service
wagw-shimmy.service
```

A custom Hermes bridge may run on a separate agent host, for example as `wagw-hermes-adapter.service`. Do not assume the downstream service name or port; read its systemd unit and health route.

First inspect without exposing environment contents:

```sh
ssh <shim-host> 'systemctl is-active gowa.service wagw-shimmy.service; systemctl show wagw-shimmy.service -p FragmentPath -p EnvironmentFiles -p WorkingDirectory'
ssh <agent-host> 'systemctl is-active <agent-service>; systemctl show <agent-service> -p FragmentPath -p EnvironmentFiles -p WorkingDirectory'
```

Read the deployed repository's `.env.example`, `README.md`, `docs/AGENT-WHATSAPP-CONTRACT.md`, `docs/CHANNEL-CONNECTIONS.md`, and `docs/PAIRING.md`. Prefer current source and tests when an older prose section disagrees with the deployed binary.

If `deploy/fleet.yaml` and `deploy/tenants/<id>.yaml` manage the host, those files plus the secret store are authoritative. Change them and rerender; do not hand-edit generated `/etc` files and create silent drift.

## 2. Map configuration by owner

### GOWA — `/etc/gowa.env`

Required concepts:

- REST basic authentication for all GOWA endpoints.
- `WHATSAPP_WEBHOOK_URL=http://127.0.0.1:8080/webhook/gowa`.
- `WHATSAPP_WEBHOOK_SECRET` exactly matches the shim's `GOWA_WEBHOOK_SECRET` and is not the default `secret`.
- `WHATSAPP_WEBHOOK_EVENTS=message,message.reaction,call.offer` when all supported inbound event kinds are wanted.
- `WHATSAPP_AUTO_DOWNLOAD_MEDIA=true` for the shim's media proxy.
- Optional `WHATSAPP_AUTO_REJECT_CALL=true`; GOWA/whatsmeow cannot answer call audio.

The deployed multi-device build uses a chosen device identifier such as the tenant name. `GOWA_DEVICE_ID` is that chosen device ID, **not** the linked WhatsApp JID. The JID is informational inventory.

### wagw-shimmy — `/etc/wagw-shimmy.env`

Core values:

```text
SHIM_BIND=127.0.0.1:8080
GOWA_URL=http://127.0.0.1:3000
GOWA_DEVICE_ID=<chosen-device-id>
AGENT_INBOUND_URL=<agent-base-url>
WHATSAPP_WEBHOOK_TOKEN=<shim-to-agent bearer>
WHATSAPP_GATEWAY_TOKEN=<agent-to-shim bearer>
WA_DM_POLICY=open|allowlist|off
WA_GROUP_POLICY=open|allowlist|off
WA_REQUIRE_MENTION=true|false
WA_SEND_RATE_PER_MIN=20
SHIM_QUEUE_DIR=/var/lib/wagw/shim/queue
```

Use `WA_DM_ALLOW` for sender numbers/JIDs and `WA_GROUP_ALLOW` for group JIDs. `WA_REQUIRE_MENTION=true` accepts an `@` tag of `WA_SELF_NUMBER`, a reply to one of the bot's recent messages, or a configured free-response group. `WA_FREE_RESPONSE_CHATS` bypasses mention requirements for listed groups.

For media, `SHIM_MEDIA_BASE_URL` must resolve from the agent and equal the agent's `WHATSAPP_GATEWAY_URL`. A loopback URL works only when the shim and agent share a host.

### Agent

The agent must expose:

- `POST /whatsapp/inbound`, authenticated with `WHATSAPP_WEBHOOK_TOKEN`;
- a 2xx health route;
- idempotency on inbound `id` because shim delivery is at-least-once;
- asynchronous turn execution so inbound returns quickly;
- outbound `/send`, media, reaction, and chat-presence calls authenticated with `WHATSAPP_GATEWAY_TOKEN`;
- exact `chat_id` echo and optional `reply_to` echo of the inbound message ID.

Typical agent values:

```text
AGENT_CHANNELS=<must include whatsapp when the agent uses a channel list>
WHATSAPP_GATEWAY_URL=<shim-base-url>
WHATSAPP_GATEWAY_SEND_PATH=/send
WHATSAPP_WEBHOOK_TOKEN=<same inbound bearer as shim>
WHATSAPP_GATEWAY_TOKEN=<same outbound bearer as shim>
```

## 3. Wire cross-box exe.dev peerings

exe.dev peerings are directional and private to the source VM. A cross-box channel needs two:

```text
<shim>-to-<agent>  attached to shim,  targets agent service port  → inbound
<agent>-to-<shim>  attached to agent, targets shim :8080           → replies
```

Configure:

```text
# shim host
AGENT_INBOUND_URL=https://<shim>-to-<agent>.int.exe.xyz

# agent host
WHATSAPP_GATEWAY_URL=https://<agent>-to-<shim>.int.exe.xyz
```

The shim appends `/whatsapp/inbound`; the agent appends `/send`. A `.int.exe.xyz` hostname is expected to fail from a laptop or unrelated VM. Test it from the peering's attached source host. Confirm the reply peering reaches shim `:8080`, not GOWA `:3000`, by requesting `/livez`.

## 4. Configure per-group channel routing

`default` is implicit and reserved. For an extra channel label `blair`:

```text
WA_CHANNELS=blair
WA_CHANNEL_BLAIR_URL=https://<shim>-to-<blair-agent>.int.exe.xyz
WA_CHANNEL_BLAIR_TOKEN=<optional channel-specific webhook token>
WA_GROUP_CHANNELS=<group-jid>:blair
```

Rules:

- Labels are lowercase `[a-z0-9_]`.
- The shim appends `/whatsapp/inbound` to each channel URL.
- A channel token defaults to `WHATSAPP_WEBHOOK_TOKEN` when omitted.
- A mapped group is implicitly admitted under group allowlist policy.
- Unmapped groups and DMs use `default`.
- The outbound `WHATSAPP_GATEWAY_TOKEN` is shared by agents replying through this shim unless the implementation explicitly adds per-channel outbound credentials.
- Session identity remains per conversation (`chat_id`); the `channel` selects persona/behaviour, not the reply destination.

## 5. Preserve official Hermes progress behaviour

For a Hermes-backed agent, prefer the official Hermes gateway and native WhatsApp adapter when exact streaming and edit-in-place progress are required. A wrapper that shells out to `hermes chat -Q -q` sees final CLI output only.

Do not add an immediate canned “I'm on it” message. The faithful presentation order is:

1. Start chat presence immediately and refresh `start` about every 10 seconds; send `stop` when the turn ends.
2. Allow natural interim assistant commentary when the gateway event stream is available.
3. For native WhatsApp/Baileys, keep tool progress at `new` with accumulated edit-in-place rendering.
4. First emit `⏳ Working — N min` after `HERMES_AGENT_NOTIFY_INTERVAL=180` seconds; update it on later intervals where editing is supported.
5. Stop every notifier before sending terminal success, timeout, or failure text so the final reply is last.

`HERMES_AGENT_NOTIFY_INTERVAL=0` disables Hermes long-running notifications. It does not mean “acknowledge immediately”. Remove obsolete custom `LONG_TURN_ACK_SECS` and `LONG_TURN_ACK_REPLY` settings when cutting over.

WhatsApp Cloud currently lacks edit support in Hermes and intentionally uses quiet defaults: typing on, but tool progress, interim commentary, and long-running messages off. Do not create permanent-message spam to mimic the native adapter.

## 6. Stage changes safely

1. Copy the existing generated config to a secure backup outside the repository.
2. Build a complete staged env file with mode `0600`; never append blindly and create duplicate keys.
3. Validate names, URLs, policy enums, channel mappings, and token **presence/match** without printing values.
4. Run local/unit/contract tests once against staged code and configuration.
5. Ask for production approval with the exact `install`, renderer, peering, restart, pairing, or live-send commands.
6. After approval, use atomic install and restart only affected services. Restart GOWA only for GOWA configuration or pairing changes; restart shim for shim env changes; restart agent for agent env/code changes.

Keep rollback copies of every replaced service file and env file. Never commit generated env files, auth databases, `whatsapp.db`, pairing output, or media.

## 7. Verify without sending WhatsApp traffic

Run probes from the correct hosts:

```sh
# Agent host: 401 means route mounted and auth enforced; 404 means missing route.
curl -sS -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:<agent-port>/whatsapp/inbound

# Agent host: reply peering lands on shim.
curl -fsS https://<agent>-to-<shim>.int.exe.xyz/livez

# Shim host: inbound peering reaches agent health.
curl -fsS https://<shim>-to-<agent>.int.exe.xyz/health

# Shim host: process, GOWA, and optional agent readiness.
curl -fsS http://127.0.0.1:8080/livez
curl -fsS http://127.0.0.1:8080/readyz
```

Also verify:

- `gowa.service`, `wagw-shimmy.service`, and the target agent service are active;
- the durable queue has no unexpected pending/dead entries;
- the agent's loaded process environment contains the expected variable **names** and no obsolete ACK keys, without printing secret values;
- a deterministic fake slow agent proves fast shim ACK, one turn per inbound ID, correct `chat_id`, correct `reply_to`, typing lifecycle, long-status timing, and final-message ordering.

A synthetic request aimed at an invalid/dummy chat is not automatically safe: policy, routing, or classifier changes can make it real. Do not use a live `/send` or signed production inbound merely as a smoke test without explicit approval.

## 8. Pair only when required

Pairing belongs to GOWA, not the shim or agent. It is interactive and production-affecting.

For the deployed multi-device build:

1. Create a device with a chosen ID such as the tenant name.
2. Request pairing code or QR with `X-Device-Id: <chosen-id>`.
3. Link from WhatsApp → Settings → Linked Devices.
4. Confirm `is_logged_in: true` and record the resulting JID as inventory only.
5. Keep `GOWA_DEVICE_ID=<chosen-id>`.
6. Back up the live whatsmeow SQLite store immediately using the repository's SQLite-consistent backup flow.

Do not raw-copy the live SQLite database. Use WAL checkpoint plus SQLite `.backup`, then test a restore on a scratch host. Rebooting should not require re-pairing; only a real restore drill proves the backup.

## 9. Diagnose from evidence

| Symptom | Check first | Likely class |
|---|---|---|
| Inbound returns 404 | agent route/channel enabled | agent config, not shim auth |
| Inbound returns 401 | webhook token direction/match | auth wiring |
| Replies land in DM | outbound destination equals inbound `chat_id` | participant JID substituted |
| Duplicate replies | shim/agent dedup by inbound `id`; webhook ACK latency | synchronous handler or lost ACK |
| Shim logs forwarded `chars=0` | raw redacted webhook shape and deployed GOWA build | payload extraction drift |
| Voice/image missing | `WHATSAPP_AUTO_DOWNLOAD_MEDIA`, `media[]`, proxy URL reachability | GOWA media store or cross-host URL |
| No typing | `/send/chat-presence`, correct gateway bearer, device presence available | presence path/device state |
| Canned ACK on every turn | custom `LONG_TURN_ACK_*` logic | confused transport ACK and presentation |
| Status arrives after final | notifier cancellation/join and outbound serialization | progress race |
| `/readyz` degraded but `/livez` green | GOWA `/devices` or optional agent probe | dependency readiness |
| `.int.exe.xyz` times out from laptop | test from peering source VM | expected peering scope |

When an inbound message reaches the agent with empty `body` and no media, do not invent a nested payload path. First capture a **redacted structural shape** at DEBUG—field names, value types, string lengths, and correlation/message ID, never content—before dedup. Compare it with the deployed GOWA source and retained GOWA message data. Duplicate deliveries can differ; the first accepted copy may be empty while a later copy contains text, so proximity in logs is not proof of payload identity.

## Completion criteria

- Directional peerings resolve from their source hosts and terminate on the correct service ports.
- Both bearer directions match without secret disclosure.
- GOWA webhook HMAC, event list, device ID, and media auto-download are correct.
- DM/group admission and channel mappings match the requested policy.
- Inbound is ack-fast and at-least-once delivery is idempotent.
- The agent echoes `chat_id` and `reply_to` correctly.
- Typing and Hermes long-turn behaviour follow the official pattern; no immediate canned acknowledgement remains.
- Services, health/readiness probes, deterministic contract tests, and rollback files are confirmed.
- Any live WhatsApp verification was explicitly approved and its result observed end to end.
