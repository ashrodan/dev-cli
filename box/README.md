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
