# Scripts that live on the box

These run on herdr-1, not the Mac. Copied here for version control; deploy with
`scp box/<name> dai:~/.local/bin/`.

## agent-notify

Polls `herdr agent list` and pushes a notification when an agent transitions out
of `working` into `blocked` (needs you) or `idle`/`done` (finished). herdr's
agent-state hooks keep those states accurate for claude, codex, grok, omp and pi.

Delivery is the exe.dev `notify` integration — `POST https://notify-2.int.exe.xyz/`
— which pushes to every device signed into the exe.dev app. No credential lives
on the box; the integration proxy injects it at the edge.

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
