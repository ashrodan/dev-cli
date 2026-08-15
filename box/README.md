# Scripts that live on the box

These run on herdr-1, not the Mac. Copied here for version control; deploy with
`scp box/<name> dai:~/.local/bin/`.

## agent-notify

Polls `herdr agent list` and pushes a notification when an agent transitions out
of `working` into `blocked` (needs you) or `idle`/`done` (finished). herdr's
agent-state hooks keep those states accurate for claude, codex, grok, omp and pi.

Delivery is ntfy, configured via drop-in at
`/etc/systemd/system/agent-notify.service.d/override.conf`:

```ini
Environment=AGENT_NOTIFY_NTFY=https://ntfy.sh
Environment=AGENT_NOTIFY_TOPIC=<topic>
Environment=AGENT_NOTIFY_CLICK=termius://
```

ntfy is used rather than the exe.dev `notify` integration because it carries a
**click target**, so tapping the notification can open Termius — where herdr's
TUI actually renders — instead of whichever app owns the push channel. Set
`AGENT_NOTIFY_EXE=https://notify-2.int.exe.xyz/` to also push through exe.dev;
both couriers fire independently and one failing does not silence the other.

Published as JSON rather than HTTP headers, because titles contain `·` and `—`
which cannot travel in a header.

`blocked` sends at priority 4 with a warning tag; `idle`/`done` at priority 3.

Each notification carries an **Open Termius** action button alongside the click
target. Note that `termius://` only launches the app — the scheme carries no
route, so there is no way to deep-link to a specific host. The title names the
workspace instead. Relabel with `AGENT_NOTIFY_ACTION_LABEL`, or set it empty to
drop the button.

Runs as `agent-notify.service`. Silent on first pass, so restarting it does not
fire a notification for every agent already sitting idle. Transitions into
`working`, and anything involving `unknown`, are ignored — `unknown` flaps while
a pane redraws.

```sh
scp box/agent-notify dai:~/.local/bin/
scp box/agent-notify.service dai:/tmp/ && ssh dai 'sudo mv /tmp/agent-notify.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now agent-notify'
```

Test the transition logic without burning a real agent run by pointing it at a
stub: `AGENT_NOTIFY_HERDR=/tmp/stub-herdr AGENT_NOTIFY_POLL=2 agent-notify`.

## drop

Prints the path of the most recent file Taildropped into `~/inbox`, which the
`taildrop-inbox.service` unit receives automatically.

```sh
drop          # newest file
drop -i       # newest image
drop -n 5     # five newest
```

Getting an image to an agent from a phone: share sheet → Tailscale → herdr-1,
then `drop -i` and paste the path into the agent. Beats pasting image data
through an SSH session.

## ntfy (self-hosted, optional)

`ntfy.service` runs ntfy 2.27.0 bound to the **Tailscale interface only**
(`100.75.93.117:2586`), so it is unreachable from the internet — note the listen
address is not `0.0.0.0`, and 2586 sits outside the 3000-9999 range exe.dev
proxies. Config in `ntfy-server.yml`.

This is an alternative to ntfy.sh for keeping notification content private.
Trade-off: iOS cannot receive from a self-hosted server without relaying through
ntfy.sh for APNs, so an iPad either transits a third party anyway or goes
without. Android connects to a self-hosted server directly.

## agent-action

A small HTTP endpoint so a phone notification can unblock an agent without
opening a terminal. An ntfy `http` action button POSTs here; this asks herdr to
send a confirmation keystroke to the waiting pane.

Bound to the **Tailscale interface only** (`100.75.93.117:2587`) — the service
refuses to start if `AGENT_ACTION_BIND` is unset, rather than defaulting to all
interfaces.

Acting on a notification means approving something you have not read on screen,
so the endpoint is deliberately narrow:

- only panes whose **current** state is `blocked` are actionable. A stale
  notification tapped ten minutes later hits a `409` rather than injecting a
  keystroke into a running agent.
- only fixed keys are ever sent — `continue` → enter, `dismiss` → esc. There is
  no free-text path, so it cannot be used to prompt an agent.
- every request is logged with its outcome (`journalctl -u agent-action`).

The bearer token is defence in depth, not the primary control: it travels inside
the ntfy message, so anyone holding the topic can read it. What actually gates
this is that the listener exists only on the tailnet.

Verified guards:

```
wrong token                 403
agent idle, not blocked     409  "agent is idle, not waiting — refusing"
unknown pane                404
unknown action              404
```

### Why the web app fails and the Android app does not

`TypeError: Failed to fetch` from the ntfy **web** app is two browser rules, not
a bug in the endpoint:

1. **Mixed content** — the ntfy page is `https://`, the endpoint is `http://`.
   Browsers block that outright, and CORS headers do not help.
2. **CORS preflight** — the `Authorization` header makes the browser send an
   `OPTIONS` request first. Handled now.

The **native Android app** performs http actions itself, subject to neither
rule, so Continue works there against a plain-http tailnet endpoint.

To make the web app work as well, the endpoint has to be served over TLS. On a
tailnet that means enabling HTTPS certificates for the tailnet
(`httpsEnabled` in tailnet settings) and fronting it with `tailscale serve`.
Note that issuing those certificates publishes device names to public
Certificate Transparency logs.
