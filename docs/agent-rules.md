# Working rules

These apply to every task, on any machine, on top of whatever the operator asks
for in the moment. They exist because the failure modes they prevent — a
half-finished change reported as done, an unverified claim, a production write
nobody sanctioned, a day of work lost with a pane — are expensive and quiet.

**Finish the task.** Work it to the end rather than stopping at the first
obstacle or handing back a partial change with a list of leftovers. If one part
is genuinely blocked, complete every other part, then say plainly what is
blocked and why. Scaling the work down is the operator's call, not yours.

**Verify locally.** Never report success from having read the code. Run the
build, run the tests, run the actual command, and quote the result. Where
something cannot be verified, say so explicitly rather than letting it sound as
though it passed. A scripted agent invocation over SSH needs `</dev/null`, or it
blocks on stdin until it times out.

**Production needs permission, and is better avoided.** Deploys, migrations,
writes against a production database, DNS changes, live environment variables
and secret rotation all stop and ask first — naming the exact command you intend
to run. Approval for one production action is not standing approval for the
next. Prefer a branch, a preview deploy, or a scratch database: do all the work
up to the production boundary, then wait there.

**Check in as you go.** Commit at each point the tree is coherent, not once at
the end. Small commits with real messages, pushed regularly, so a dead pane or a
reset context costs one step instead of a day. Check `git status` and
`git check-ignore` before staging — `.env` files and service-account keys must
never enter a commit.

**A dirty branch means a worktree.** Never build on top of uncommitted changes
you did not make, and never stash them: several agents share these repos and
that work belongs to someone. Start a worktree instead.

    git worktree add ../<repo>-<branch> -b <branch>
    herdr worktree create <repo> <branch>     # on the box, so herdr tracks it

**Unfinished work ships as a draft PR.** Open it as a draft, and write the body
for someone who will not read the diff: what is done, what is not, and exactly
what you need from them — which credential, which decision, which approval.
Name each one. The draft PR is the handoff, so a blocker you left unlisted is a
day someone else loses.

**Ready means green.** Take a PR out of draft only when it is genuinely complete,
then watch CI and fix what it catches.

    gh pr ready <n>
    gh pr checks --watch

A red PR marked ready for review is not ready. If a failure is outside your
reach — flaky infrastructure, a secret you cannot hold — put the failing job and
the reason in a PR comment rather than leaving it silent.
