---
name: omp-model-graph
description: Configure omp (oh-my-pi) as a multi-model agent graph — a bank of specialist subagents, each pinned to a different model, wired together by spawn rules and typed handoffs. Use when setting up mixed-model workflows, adding a specialist agent, choosing which model fills which role, or diagnosing why a subagent ran on the wrong model.
allowed-tools: Bash, Read, Write, Edit
argument-hint: [role|agent name]
---

# omp-model-graph

omp is already a graph engine; most of it ships switched off. Nodes are agents,
edges are spawn rules, handoffs are JSON-Schema-typed, and each node's model
comes from a named role. Building a mixture-of-models workflow is configuration,
not code.

## When to invoke

- Deciding which model should do what, across more than one vendor.
- Adding a specialist agent (reviewer, scout, adversary, designer).
- A subagent ran on an unexpected model, or a batch failed to fan out.
- Spend or quota needs shaping across subscriptions.

## The model

```
session
└── agent (node)         ~/.omp/agent/agents/<name>.md
    ├── model: ["@role"] role → model + effort, from config
    ├── tools: [...]     capability restriction
    ├── spawns: [...]    edges; "*" means unrestricted
    ├── thinkingLevel    per-node effort
    └── output:          typed handoff (JSON Schema)
```

Start by reading the bundled agents rather than inventing a schema — they are
the reference implementation:

```bash
omp agents unpack --dir /tmp/agents --json    # 7 agents: scout, reviewer,
cat /tmp/agents/reviewer.md                   # librarian, designer, sonic,
                                              # security-reviewer, task
```

## The constraint that shapes everything

**Per-spawn model selection was removed.** The `task` tool's per-item fields are
`agent`, `effort`, `outputSchema`, `schemaMode` and `isolated` — there is no
`model`. A spawn always uses the model its agent definition names.

So the mixture is expressed *structurally*: you do not choose a model per call,
you define a specialist whose role pins the model, and route by choosing the
agent. That is closer to a real expert bank than ad-hoc switching, and it means
a badly-routed task is an agent-selection bug, not a model bug.

## 1. Define roles

Roles are `model:effort` pairs and the names are arbitrary — invent what the
graph needs.

```bash
omp config get modelRoles
```

```yaml
modelRoles:
  default:   anthropic/claude-opus-5        # orchestrator
  plan:      anthropic/claude-opus-5:max
  slow:      anthropic/claude-opus-5:max    # judgment
  task:      openai-codex/gpt-5.6-luna:high # general worker
  smol:      google/gemini-3.5-flash-lite:high  # breadth, cheap
  adversary: xai/grok-4.6:xhigh             # vendor-diverse refutation
  designer:  anthropic/claude-opus-5:high
  vision:    openai/gpt-5.6-sol-pro
```

Vendor diversity is the point of the `adversary` role. A second Opus call
agreeing with the first is weak evidence; a Grok node told to refute an Opus
finding catches failure modes redundancy cannot.

Check what a role can actually resolve to before relying on it:

```bash
omp models find <pattern>     # is the model in the catalogue at all?
omp usage                     # which providers are authenticated
```

An unauthenticated provider is the usual reason a role silently misbehaves.

## 2. Define agents

One `.md` per node in `~/.omp/agent/agents/` (or `./.omp/agents` per project):

```yaml
---
name: adversary
description: Refutes findings. Assume the claim is wrong until proven otherwise.
tools: [read, grep, glob, bash, lsp, yield]
model: ["@adversary"]
thinkingLevel: high
output:
  properties:
    refuted: { type: boolean }
    reasoning: { type: string }
---
```

`model` is a **list because it is a fallback chain**, not a set of alternatives
to choose between — the first entry that is available wins. This matters on
subscription plans that ration.

Restrict `tools` deliberately: a read-only node cannot damage a checkout, which
is what makes parallel fan-out safe.

## 3. Turn the graph on

Defaults leave several capabilities disabled. Audit with:

```bash
omp config list --json | python3 -c 'import json,sys
d=json.load(sys.stdin)
def w(o,p=""):
    if isinstance(o,dict) and "value" in o and "type" in o: print(p, o["value"]); return
    if isinstance(o,dict):
        for k,v in o.items(): w(v, f"{p}.{k}" if p else k)
w(d)' | grep -E "^(task|async|retry|advisor|prewalk)"
```

The ones that matter:

| setting | why |
|---|---|
| `task.batch` | one call carries `{context, tasks[]}` — the fan-out primitive |
| `task.enableEffort` | per-item `lo\|med\|hi`; **off by default** |
| `task.isolation.mode` | `worktree` lets parallel writers not collide; **`none` by default** |
| `task.maxConcurrency` | ceiling on simultaneous subagents |
| `task.maxRecursionDepth` | how deep spawns may nest (default 2) |
| `async.enabled` | non-blocking spawns, job IDs, `hub wait` |
| `retry.modelFallback` | traverse the chain when a model is unavailable |
| `retry.usageAwareFallback` | degrade *before* a rationed subscription runs dry |
| `advisor.enabled` | a second model passively reviewing each turn |
| `prewalk.enabled` | downshift to a cheap model at the first edit after planning |

```bash
omp config set task.enableEffort true
omp config set task.isolation.mode worktree
omp config set retry.usageAwareFallback true
```

`retry.usageAwareFallback` deserves attention on subscription-backed setups: it
is the difference between a graph degrading gracefully and one failing outright
when a plan hits its ceiling. It needs `retry.fallbackChains` populated.

## 4. Fan out

The batch shape carries shared context once and one subagent per item:

```
context: "# Goal / # Constraints / # Contract"   ← decided up front, not negotiated
tasks:
  - { agent: scout,     task: "...", outputSchema: {...} }
  - { agent: worker,    task: "...", isolated: true }
  - { agent: adversary, task: "Refute: ..." }
```

Rules that come from omp's own task prompt, worth respecting:

- Concurrent edits to the same files auto-resolve — **never** serialise a batch
  to avoid overlap. Instead: every task skips build/lint/tests (validating
  mid-flight blocks agents on each other), and cross-task contracts are stated
  in `context` up front.
- Subagents start blank, with no conversation history. Pass large payloads as
  `local://<path>` URIs, never inline.
- Read-only research goes to `scout` (cheaper model), not the default worker.

## Choosing what fills a role

Match the model to the node's job, not to a leaderboard:

- **Breadth** (search, discovery, mechanical edits) → cheapest capable model.
  This is most of the token spend, so it is where model choice pays.
- **Judgment** (review, planning, architecture) → strongest available, high effort.
- **Refutation** → a *different vendor* to whatever produced the claim.
- **Long-horizon autonomy** (multi-day migrations) → a model built for it.

On that last point, check for silent rerouting before pinning one. Claude Fable
5, for instance, auto-routes cybersecurity prompts to Opus 4.8 and biology to
Opus 5 — so a `security-reviewer` node pinned to Fable is not running Fable, and
nothing in the output says so. It also carries mandatory 30-day retention, which
matters when nodes read repositories holding credentials.

## Gotchas

**A role that resolves to nothing fails quietly.** `omp models find <name>`
returning nothing usually means the provider was never authenticated, not that
the model does not exist.

**`enabledModels` is separate from roles.** It only controls the Ctrl+P cycle in
the TUI. A model can serve a role without appearing there, and vice versa.

**Effort is per-spawn, model is not.** If a node needs a different model, it
needs to be a different agent.

**Depth is capped.** `task.maxRecursionDepth` defaults to 2, so a three-layer
graph silently stops spawning at the third layer.
