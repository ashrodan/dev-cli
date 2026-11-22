#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/dev-hosts-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/calls"
CLIPBOARD="$TMP/clipboard"
FZF_STATE="$TMP/fzf-state"
NEW_BOX_STATE="$TMP/new-box-state"
mkdir -p "$TMP/bin" "$TMP/ssh/config.d"
mkdir -p "$TMP/projects/sample" "$TMP/projects/sample-worktree" "$TMP/projects/other"
git -C "$TMP/projects/sample" init -q
git -C "$TMP/projects/sample" remote add origin git@github.com:dashlytix/sample.git
git -C "$TMP/projects/other" init -q
git -C "$TMP/projects/other" remote add origin git@github.com:dashlytix/other.git
printf 'gitdir: ../sample/.git/worktrees/sample-worktree\n' > "$TMP/projects/sample-worktree/.git"

cat > "$TMP/ssh/config" <<'SSH'
Include config.d/accounts

Host exe-personal
  HostName exe.dev
  User exedev
  IdentityFile ~/.ssh/personal

Host direct-box
  HostName direct-box.exe.xyz
SSH

cat > "$TMP/ssh/config.d/accounts" <<'SSH'
Host exe-dash
  HostName exe.dev
  User exedev
  IdentityFile ~/.ssh/dash

Host *.exe.xyz
  User exedev
SSH

cat > "$TMP/bin/ssh" <<'SH'
#!/usr/bin/env bash
set -eu
printf 'ssh %s\n' "$*" >> "$DEV_TEST_LOG"

if [ -n "${DEV_TEST_SSH_FAIL:-}" ] && [ "${1:-}" != "-G" ]; then
  printf 'ssh: connect to host failed\n' >&2
  exit 255
fi

if [ "${1:-}" = "-G" ]; then
  case "${2:-}" in
    exe-dash|exe-personal) printf 'hostname exe.dev\nuser exedev\nidentityfile ~/.ssh/%s\n' "${2#exe-}" ;;
    dash|ar-general-dev) printf 'hostname ar-general-dev.exe.xyz\nuser exedev\nidentityfile ~/.ssh/dash\n' ;;
    *)        printf 'hostname herdr-1.exe.xyz\nuser exedev\nidentityfile ~/.ssh/default\n' ;;
  esac
  exit 0
fi

if [ "$*" = "exe-dash ls --json" ]; then
  if [ -e "$DEV_TEST_NEW_BOX_STATE" ]; then
    printf '%s\n' '{"vms":[{"vm_name":"fresh-box","ssh_host":"fresh-box.exe.xyz","status":"running","access":{"shell":true}}]}'
  elif [ -n "${DEV_TEST_MULTI:-}" ]; then
    printf '%s\n' '{"vms":[{"vm_name":"ar-general-dev","ssh_host":"ar-general-dev.exe.xyz","status":"running","access":{"shell":true}},{"vm_name":"second-box","ssh_host":"second-box.exe.xyz","status":"running","access":{"shell":true}}]}'
  else
    printf '%s\n' '{"vms":[{"vm_name":"ar-general-dev","ssh_host":"ar-general-dev.exe.xyz","status":"running","access":{"shell":true}}]}'
  fi
  exit 0
fi
case "$*" in
  "exe-dash new --json --name=fresh-box --tag=tailscale --comment=dev-cli:dashlytix/sample")
    [ -z "${DEV_TEST_NEW_FAIL:-}" ] || exit 3
    : > "$DEV_TEST_NEW_BOX_STATE"
    printf '%s\n' '{"vm_name":"fresh-box"}'
    exit 0
    ;;
esac
case "$*" in
  *"FLEET_AUDIT=1"*)
    cat >/dev/null
    case "$*" in
      *second-box*) printf 'second-box\t95d\t93%%\t0.8.0\tmanual\t2026-11-22\tbudget\n' ;;
      *)            printf 'ar-general-dev\t29d\t70%%\t0.9.5\tsystemd\t2026-11-22\t-\n' ;;
    esac
    exit 0
    ;;
  *"FLEET_HERDR=1"*)
    # Run the real remote script here, with no herdr installed, so the dry
    # run's state logic is exercised. The dry run exits before any change.
    remote=${*: -1}
    remote=${remote/RHOME=\'\/home\/exedev\'/RHOME=\'$DEV_TEST_TMP\/nohome\'}
    PATH="$DEV_TEST_TMP/remote-bin:$PATH" eval "$remote"
    exit $?
    ;;
esac
if [ "$*" = "exe-dash integrations list" ]; then
  if [ -n "${DEV_TEST_INTEGRATION_EXISTS:-}" ]; then
    printf 'sample-github  github  repos=dashlytix/sample\n'
  fi
  exit 0
fi

case "$*" in
  *"HostName=ar-general-dev.exe.xyz"*"RHOME="*"SESSION="*)
    printf 'sample\tw-main\t/home/exedev/sample\tmain\n'
    exit 0
    ;;
  *"HostName=second-box.exe.xyz"*"RHOME="*"SESSION="*)
    exit 0
    ;;
  *"HostName=ar-general-dev.exe.xyz"*"HERDR="*"SESSION="*)
    exit 0
    ;;
  *"HostName=second-box.exe.xyz"*"HERDR="*"SESSION="*)
    printf 'agent\tcodex\t4242\t/home/exedev/sample\tcodex --full-auto\n'
    printf 'shell\tbash\t4343\t/home/exedev\t/dev/pts/4\n'
    printf 'tmux\tbuild\tbuild\t/home/exedev/sample\tdetached, 2 windows\n'
    exit 0
    ;;
esac


case "$*" in
  *"worktree list --cwd "*)
    printf '%s\n' '{"result":{"source":{"source_workspace_id":"w-main"}}}'
    exit 0
    ;;
esac

case "$*" in
  *"rev-parse --path-format=absolute --git-common-dir"*)
    printf '/home/exedev/workspace/sample/.git\n'
    exit 0
    ;;
esac
case "$*" in
  *"remote get-url origin"*"branch --show-current"*)
    printf 'https://github.int.exe.xyz/dashlytix/sample.git\n'
    printf '%s\n' "${DEV_TEST_PR_BRANCH:-feat/pr-125}"
    exit 0
    ;;
esac
case "$*" in
  *"gh api graphql"*)
    printf 'exe-dev-github-integration[bot]\n'
    exit 0
    ;;
esac


case "$*" in
  *"log -1 --format=%s"*)
    printf 'Fix task workspace\n'
    exit 0
    ;;
  *"log --reverse --format="*)
    printf '%s\n' '- Fix task workspace' '' 'Implement the requested workflow.'
    exit 0
    ;;
esac


case "$*" in
  *"git clone "*)
    [ -z "${DEV_TEST_CLONE_FAIL:-}" ] || exit 3
    printf '/home/exedev/sample\n'
    ;;
  *"worktree list --porcelain"*)
    if [ -n "${DEV_TEST_CROSS_REPO_WORKTREE:-}" ]; then
      printf 'worktree /home/exedev/worktrees/sample/cross-existing\n'
      printf 'branch refs/heads/feat/pr-125\n\n'
    elif [ -n "${DEV_TEST_EXISTING_WORKTREE:-}" ]; then
      printf 'worktree /home/exedev/worktrees/sample/existing\n'
      printf 'branch refs/heads/work/%s-fix-login\n\n' "$(date +%Y%m%d)"
    fi
    ;;
  *"symbolic-ref --short refs/remotes/origin/HEAD"*)
    printf 'origin/main\n'
    ;;
  *"worktree create"*)
    printf '%s\n' '{"result":{"worktree":{"path":"/home/exedev/worktrees/sample/task"}}}'
    ;;
  *"worktree open"*)
    printf '%s\n' '{"result":{"already_open":false,"workspace_id":"w-task","root_pane":{"pane_id":"w-task:p1","agent":null}}}'
    ;;
  *"agent start"*)
    printf '%s\n' '{"result":{"agent":"omp","status":"idle"}}'
    ;;
  *"RHOME="*)
    if [ -z "${DEV_TEST_REPO_MISSING:-}" ]; then
      if [ -n "${DEV_TEST_DUPLICATE_REPO:-}" ]; then
        printf 'sample\tmain\t/home/exedev/workspace/sample\t\tmain\t\tdef456\tnow\t0\t0\t0\tmessage\n'
      fi
      if [ -n "${DEV_TEST_CROSS_REPO_WORKTREE:-}" ]; then
        printf 'sample\tfeat/pr-125\t/home/exedev/worktrees/sample/cross-existing\tw-task\tlinked\t\tdef456\tnow\t0\t0\t0\tmessage\n'
      fi
      printf 'sample\tmain\t/home/exedev/sample\t\tmain\t3000\tabc123\tnow\t0\t0\t0\tmessage\n'
    fi
    ;;
esac
SH

cat > "$TMP/bin/code" <<'SH'
#!/usr/bin/env bash
printf 'code %s\n' "$*" >> "$DEV_TEST_LOG"
SH

cat > "$TMP/bin/fzf" <<'SH'
#!/usr/bin/env bash
printf 'fzf %s\n' "$*" >> "$DEV_TEST_LOG"
case "$*" in
  *--version*)
    printf '0.65.2 (stub)\n'
    exit 0
    ;;
  *"box> "*)
    while IFS= read -r line; do
      printf 'box-row %s\n' "$line" >> "$DEV_TEST_LOG"
      box=${line%%	*}
      if [ -z "${DEV_TEST_PICK:-}" ] || [ "$box" = "$DEV_TEST_PICK" ]; then
        printf '%s\n' "$line"
        exit 0
      fi
    done
    exit 1
    ;;
  *"fleet> "*)
    while IFS= read -r line; do
      IFS=$'\t' read -r _ _ _ kind _ <<< "$line"
      if [ -z "${DEV_TEST_FLEET_KIND:-}" ] || [ "$kind" = "$DEV_TEST_FLEET_KIND" ]; then
        printf '\n%s\n' "$line"
        exit 0
      fi
    done
    exit 1
    ;;
  *"project all> "*)
    while IFS= read -r line; do
      printf 'project-all-row %s\n' "$line" >> "$DEV_TEST_LOG"
      project=${line%%	*}
      if [ -z "${DEV_TEST_ALL_PROJECT:-}" ] || [ "$project" = "$DEV_TEST_ALL_PROJECT" ]; then
        printf '%s\n' "$line"
        exit 0
      fi
    done
    exit 1
    ;;
  *"project> "*)
    while IFS= read -r line; do
      printf 'project-row %s\n' "$line" >> "$DEV_TEST_LOG"
      project=${line%%	*}
      if [ -z "${DEV_TEST_PROJECT:-}" ] || [ "$project" = "$DEV_TEST_PROJECT" ]; then
        printf '%s\n' "$line"
        exit 0
      fi
    done
    exit 1
    ;;
  *"task type> "*)
    while IFS= read -r line; do
      case "$line" in
        prompt*) printf '%s\n' "$line"; exit 0 ;;
      esac
    done
    exit 1
    ;;
  *"workspace> "*)
    if [ -e "$DEV_TEST_FZF_STATE" ]; then
      exit 1
    fi
    : > "$DEV_TEST_FZF_STATE"
    IFS= read -r line || exit 1
    printf '%s\n%s\n' "${DEV_TEST_WORKSPACE_KEY:-}" "$line"
    exit 0
    ;;
  *"action> "*)
    while IFS= read -r line; do
      case "$line" in
        "${DEV_TEST_ACTION:-copy}"*) printf '\n%s\n' "$line"; exit 0 ;;
      esac
    done
    exit 1
    ;;
esac
while IFS= read -r line; do
  profile=${line%%	*}
  if [ -z "${DEV_TEST_PICK:-}" ] || [ "$profile" = "$DEV_TEST_PICK" ]; then
    printf '%s\n' "$line"
    exit 0
  fi
done
exit 1
SH

cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$DEV_TEST_LOG"
case "$*" in
  *"repo view "*)
    printf 'main\n'
    ;;
  *"pr list "*)
    [ -z "${DEV_TEST_EXISTING_PR:-}" ] ||
      printf 'https://github.com/dashlytix/sample/pull/125\n'
    ;;
  *"pr create "*)
    printf 'https://github.com/dashlytix/sample/pull/126\n'
    ;;
  *)
    printf '%s\n' '{"number":125,"title":"Fix task workspace","body":"Implement the requested workflow.","headRefName":"feat/pr-125","baseRefName":"main","url":"https://github.com/dashlytix/sample/pull/125"}'
    ;;
esac
SH

cat > "$TMP/bin/open" <<'SH'
#!/usr/bin/env bash
printf 'open %s\n' "$*" >> "$DEV_TEST_LOG"
SH

cat > "$TMP/bin/linear" <<'SH'
#!/usr/bin/env bash
printf 'linear %s\n' "$*" >> "$DEV_TEST_LOG"
printf '%s\n' '{"identifier":"DAS-9","title":"Add task workspace","description":"Create the task workflow.","url":"https://linear.app/example/issue/DAS-9","branchName":"ashley/das-9-task-workspace","attachments":{"nodes":[{"metadata":{"repoLogin":"dashlytix","repoName":"sample","branch":"feat/das-9-pr","targetBranch":"main","url":"https://github.com/dashlytix/sample/pull/9"}}]}}'
SH

cat > "$TMP/bin/pbcopy" <<'SH'
#!/usr/bin/env bash
cat > "$DEV_TEST_CLIPBOARD"
SH
chmod +x "$TMP/bin/ssh" "$TMP/bin/code" "$TMP/bin/fzf" "$TMP/bin/gh" "$TMP/bin/linear" "$TMP/bin/pbcopy" "$TMP/bin/open"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "expected [$2] in [$1]" ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "did not expect [$2] in [$1]" ;;
    *) ;;
  esac
}

# The logged fzf arguments carry the footer's bold/dim attributes.
plain() { printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g'; }

mkdir -p "$TMP/remote-bin" "$TMP/nohome"
printf '#!/bin/sh\nexit 1\n' > "$TMP/remote-bin/systemctl"
printf '#!/bin/sh\nexit 1\n' > "$TMP/remote-bin/pgrep"
chmod +x "$TMP/remote-bin/systemctl" "$TMP/remote-bin/pgrep"
printf '{\n  "version": "0.9.5",\n  "assets": {}\n}\n' > "$TMP/latest.json"

run_dev() {
  PATH="$TMP/bin:$PATH" DEV_TEST_LOG="$LOG" DEV_TEST_MULTI="${DEV_TEST_MULTI:-}" \
    DEV_TEST_TMP="$TMP" DEV_HERDR_MANIFEST_URL="file://$TMP/latest.json" \
    DEV_TEST_PICK="${DEV_TEST_PICK:-}" DEV_TEST_PROJECT="${DEV_TEST_PROJECT:-}" \
    DEV_TEST_ALL_PROJECT="${DEV_TEST_ALL_PROJECT:-}" \
    DEV_TEST_REPO_MISSING="${DEV_TEST_REPO_MISSING:-}" DEV_TEST_CLONE_FAIL="${DEV_TEST_CLONE_FAIL:-}" \
    DEV_TEST_INTEGRATION_EXISTS="${DEV_TEST_INTEGRATION_EXISTS:-}" \
    DEV_TEST_DUPLICATE_REPO="${DEV_TEST_DUPLICATE_REPO:-}" \
    DEV_TEST_CROSS_REPO_WORKTREE="${DEV_TEST_CROSS_REPO_WORKTREE:-}" \
    DEV_TEST_PR_BRANCH="${DEV_TEST_PR_BRANCH:-}" DEV_TEST_EXISTING_PR="${DEV_TEST_EXISTING_PR:-}" \
    DEV_TEST_EXISTING_WORKTREE="${DEV_TEST_EXISTING_WORKTREE:-}" \
    DEV_TEST_SSH_FAIL="${DEV_TEST_SSH_FAIL:-}" DEV_TEST_NEW_FAIL="${DEV_TEST_NEW_FAIL:-}" \
    DEV_TEST_BOX_PICKER="${DEV_TEST_BOX_PICKER:-}" \
    DEV_NEW_BOX_NAME="${DEV_NEW_BOX_NAME:-}" DEV_NEW_BOX_PROJECT="${DEV_NEW_BOX_PROJECT:-}" \
    DEV_NEW_BOX_YES="${DEV_NEW_BOX_YES:-}" DEV_REFRESH_SECS="${DEV_REFRESH_SECS:-}" \
    DEV_TEST_FLEET_KIND="${DEV_TEST_FLEET_KIND:-}" \
    DEV_TEST_WORKSPACE_KEY="${DEV_TEST_WORKSPACE_KEY:-}" DEV_TEST_ACTION="${DEV_TEST_ACTION:-}" \
    DEV_TEST_CLIPBOARD="$CLIPBOARD" DEV_TEST_FZF_STATE="$FZF_STATE" \
    DEV_TEST_NEW_BOX_STATE="$NEW_BOX_STATE" \
    DEV_SSH_CONFIG="$TMP/ssh/config" DEV_PROJECT_ROOT="$TMP/projects" "$ROOT/dev" "$@"
}

: > "$LOG"
direct_output=$(run_dev -H dash ls)
direct_calls=$(<"$LOG")
assert_contains "$direct_output" "/home/exedev/sample"
assert_contains "$direct_calls" "ssh -G dash"
assert_contains "$direct_calls" "ssh dash RHOME="

: > "$LOG"
profile_output=$(run_dev -H exe-dash ls)
profile_calls=$(<"$LOG")
assert_contains "$profile_output" "/home/exedev/sample"
assert_contains "$profile_calls" "ssh exe-dash ls --json"
assert_contains "$profile_calls" "ssh -o HostName=ar-general-dev.exe.xyz exe-dash RHOME="

: > "$LOG"
picked_output=$(DEV_TEST_PICK=exe-dash run_dev --profile ls)
picked_calls=$(<"$LOG")
assert_contains "$picked_output" "/home/exedev/sample"
assert_contains "$picked_calls" "fzf --prompt=profile> "
assert_contains "$picked_calls" "ssh exe-dash ls --json"
assert_contains "$picked_calls" "ssh -o HostName=ar-general-dev.exe.xyz exe-dash RHOME="

: > "$LOG"
code_output=$(run_dev -H exe-dash code sample)
code_calls=$(<"$LOG")
assert_contains "$code_output" "dev: opened /home/exedev/sample in VS Code"
assert_contains "$code_calls" "code --remote ssh-remote+ar-general-dev /home/exedev/sample"

: > "$CLIPBOARD"
copy_output=$(run_dev -H exe-dash copy sample)
copied_command=$(<"$CLIPBOARD")
assert_contains "$copy_output" "dev: copied"
[ "$copied_command" = "dev -H exe-dash -B ar-general-dev herdr -s default /home/exedev/sample" ] ||
  fail "unexpected copied command: $copied_command"

: > "$CLIPBOARD"
: > "$LOG"
rm -f "$FZF_STATE"
browse_output=$(run_dev -H exe-dash)
browse_command=$(<"$CLIPBOARD")
workspace_pickers=$(grep -c 'fzf .*workspace> ' "$LOG" || true)
assert_contains "$browse_output" "dev: copied"
[ "$browse_command" = "$copied_command" ] ||
  fail "Enter should copy the same login command"
[ "$workspace_pickers" -eq 2 ] ||
  fail "workspace picker should reopen after copying"

# The workspace list re-scans on a timer and on ctrl-r, both without leaving fzf.
: > "$LOG"
rm -f "$FZF_STATE"
DEV_REFRESH_SECS=45 run_dev -H exe-dash >/dev/null
refresh_calls=$(plain "$(<"$LOG")")
assert_contains "$refresh_calls" "--bind load:transform("
assert_contains "$refresh_calls" "_focus)+transform-header("
assert_contains "$refresh_calls" "_status)+refresh-preview+reload-sync(sleep 45; "
assert_contains "$refresh_calls" "--bind ctrl-r:reload-sync("
assert_contains "$refresh_calls" "--footer-border=line"
assert_contains "$refresh_calls" "ctrl-r refresh"
assert_contains "$refresh_calls" "--bind resize:transform-footer("
assert_not_contains "$refresh_calls" "ctrl-e,ctrl-r"

# Pressing right opens the action menu, labelled and with its own hint. Its modal
# placement needs a terminal to lay the panel over, so with no tty here it stays
# an inline picker — and must not leave a frame behind, which is what --no-clear
# would do to a script's terminal.
: > "$LOG"
: > "$CLIPBOARD"
rm -f "$FZF_STATE"
menu_output=$(DEV_TEST_WORKSPACE_KEY=right DEV_TEST_ACTION=copy run_dev -H exe-dash)
menu_calls=$(plain "$(<"$LOG")")
assert_contains "$menu_output" "dev: copied"
assert_contains "$menu_calls" "fzf --prompt=action> "
assert_contains "$menu_calls" "--border-label= actions "
assert_contains "$menu_calls" "enter run   ←/esc back"
assert_contains "$menu_calls" "--height=~55%"
assert_not_contains "$menu_calls" "--no-clear"
assert_not_contains "$menu_calls" "--margin="

: > "$LOG"
rm -f "$FZF_STATE"
DEV_REFRESH_SECS=0 run_dev -H exe-dash >/dev/null
manual_calls=$(plain "$(<"$LOG")")
assert_not_contains "$manual_calls" "reload-sync(sleep"
assert_contains "$manual_calls" "--bind ctrl-r:reload-sync("

# A scan replaces the cache; one that cannot reach the box keeps the last list.
CACHE_FIXTURE="$TMP/scan-cache"
printf 'stale\tmain\t/home/exedev/stale\t\tmain\t\t\t\t0\t0\t0\tstale row\n' > "$CACHE_FIXTURE"
scan_output=$(DEV_CACHE="$CACHE_FIXTURE" run_dev -H exe-dash _scan)
assert_contains "$scan_output" "/home/exedev/sample"
assert_not_contains "$scan_output" "/home/exedev/stale"
[ -s "$CACHE_FIXTURE.at" ] || fail "_scan should record when it last scanned"
[ ! -e "$CACHE_FIXTURE.err" ] || fail "_scan should clear the unreachable marker"

status_output=$(plain "$(DEV_BOX=ar-general-dev DEV_CACHE="$CACHE_FIXTURE" run_dev -H exe-dash _status)")
assert_contains "$status_output" "exe-dash/ar-general-dev"
assert_contains "$status_output" "rescans every 30s"
off_status=$(plain "$(DEV_REFRESH_SECS=0 DEV_CACHE="$CACHE_FIXTURE" run_dev -H exe-dash _status)")
assert_contains "$off_status" "auto refresh off"

offline_output=$(DEV_TEST_SSH_FAIL=1 DEV_CACHE="$CACHE_FIXTURE" run_dev -H dash _scan)
assert_contains "$offline_output" "/home/exedev/sample"
[ -e "$CACHE_FIXTURE.err" ] || fail "a failed scan should mark the cache unreachable"
offline_status=$(plain "$(DEV_CACHE="$CACHE_FIXTURE" run_dev -H dash _status)")
assert_contains "$offline_status" "unreachable"

if reach_error=$(DEV_TEST_SSH_FAIL=1 run_dev -H dash ls 2>&1); then
  fail "an unreachable box should fail the listing: $reach_error"
fi
assert_contains "$reach_error" "could not reach dash"

: > "$CLIPBOARD"
task_plan_output=$(run_dev -H exe-dash task plan dashlytix/sample prompt "Fix login")
task_command=$(<"$CLIPBOARD")
assert_contains "$task_plan_output" "copied task bootstrap for Fix login"
[ "$task_command" = 'dev -H exe-dash -B ar-general-dev task run dashlytix/sample prompt Fix\ login' ] ||
  fail "unexpected task bootstrap: $task_command"

: > "$LOG"
: > "$CLIPBOARD"
wizard_output=$(printf 'Fix login\n' | DEV_TEST_PROJECT=dashlytix/sample run_dev -H exe-dash task 2>/dev/null)
wizard_command=$(<"$CLIPBOARD")
assert_contains "$wizard_output" "copied task bootstrap for Fix login"
[ "$wizard_command" = "$task_command" ] ||
  fail "task wizard should copy the explicit plan command"
wizard_calls=$(<"$LOG")
assert_contains "$wizard_calls" "project-row dashlytix/sample"
assert_not_contains "$wizard_calls" "project-row dashlytix/other"

: > "$CLIPBOARD"
: > "$LOG"
expanded_output=$(printf 'Fix other\n' |
  DEV_TEST_PROJECT=+all DEV_TEST_ALL_PROJECT=dashlytix/other run_dev -H exe-dash task 2>/dev/null)
expanded_command=$(<"$CLIPBOARD")
assert_contains "$expanded_output" "copied task bootstrap for Fix other"
assert_contains "$expanded_command" "task run dashlytix/other prompt Fix\\ other"
expanded_calls=$(<"$LOG")
assert_contains "$expanded_calls" "project-all-row dashlytix/other"

: > "$CLIPBOARD"
pr_plan_output=$(run_dev -H exe-dash task plan dashlytix/sample pr 125)
pr_command=$(<"$CLIPBOARD")
assert_contains "$pr_plan_output" "copied task bootstrap for Fix task workspace"
[ "$pr_command" = "dev -H exe-dash -B ar-general-dev task run dashlytix/sample pr 125" ] ||
  fail "unexpected PR bootstrap: $pr_command"

: > "$CLIPBOARD"
linear_plan_output=$(run_dev -H exe-dash task plan dashlytix/sample linear DAS-9)
linear_command=$(<"$CLIPBOARD")
assert_contains "$linear_plan_output" "copied task bootstrap for Add task workspace"
[ "$linear_command" = "dev -H exe-dash -B ar-general-dev task run dashlytix/sample linear DAS-9" ] ||
  fail "unexpected Linear bootstrap: $linear_command"

: > "$CLIPBOARD"
: > "$LOG"
linear_url='https://linear.app/dashlytix/issue/DAS-9/add-task-workspace'
linear_url_output=$(run_dev -H exe-dash task plan dashlytix/sample linear "$linear_url")
linear_url_command=$(<"$CLIPBOARD")
assert_contains "$linear_url_output" "copied task bootstrap for Add task workspace"
assert_contains "$linear_url_command" "$linear_url"
linear_url_calls=$(<"$LOG")
assert_contains "$linear_url_calls" "linear issue view DAS-9 --json --no-comments"

: > "$LOG"
pr_run_output=$(DEV_TEST_DUPLICATE_REPO=1 run_dev -H exe-dash task run dashlytix/sample pr 125)
pr_run_calls=$(<"$LOG")
assert_contains "$pr_run_output" "preparing pr-125"
assert_contains "$pr_run_calls" "fetch origin pull/125/head:refs/heads/feat/pr-125"
assert_contains "$pr_run_calls" "worktree open --workspace w-main"
assert_contains "$pr_run_calls" "git -C /home/exedev/sample show-ref"
assert_not_contains "$pr_run_calls" "git -C /home/exedev/workspace/sample"

: > "$LOG"
cross_reuse_output=$(DEV_TEST_CROSS_REPO_WORKTREE=1 \
  run_dev -H exe-dash task run dashlytix/sample pr 125)
cross_reuse_calls=$(<"$LOG")
assert_contains "$cross_reuse_output" "preparing pr-125"
assert_contains "$cross_reuse_calls" "git -C /home/exedev/worktrees/sample/cross-existing rev-parse"
assert_contains "$cross_reuse_calls" "git -C /home/exedev/workspace/sample worktree list --porcelain"
assert_contains "$cross_reuse_calls" "worktree open --workspace w-main --path /home/exedev/worktrees/sample/cross-existing"
assert_not_contains "$cross_reuse_calls" "worktree create"
assert_contains "$pr_run_calls" "agent start pr-125 --kind omp"
assert_contains "$pr_run_calls" "GH_TOKEN is not expected"
assert_contains "$pr_run_calls" "github.int.exe.xyz"
assert_contains "$pr_run_calls" "dev -H exe-dash -B ar-general-dev pr feat/pr-125"

: > "$LOG"
github_setup_output=$(run_dev -H exe-dash github setup)
github_setup_calls=$(<"$LOG")
assert_contains "$github_setup_output" "installed tokenless gh wrapper"
assert_contains "$github_setup_output" "remote gh actor: exe-dev-github-integration[bot]"
assert_contains "$github_setup_calls" "base64 -d >"
assert_contains "$github_setup_calls" ".local/bin/gh"

: > "$LOG"
github_status_output=$(run_dev -H exe-dash github status)
github_status_calls=$(<"$LOG")
assert_contains "$github_status_output" "remote gh actor: exe-dev-github-integration[bot]"
assert_contains "$github_status_calls" "gh api graphql"

: > "$LOG"
pr_create_output=$(DEV_TEST_CROSS_REPO_WORKTREE=1 DEV_TEST_PR_BRANCH=feat/pr-125 \
  run_dev -H exe-dash pr feat/pr-125)
pr_create_calls=$(<"$LOG")
assert_contains "$pr_create_output" "creating draft PR"
assert_contains "$pr_create_calls" "gh pr list --repo dashlytix/sample --head feat/pr-125 --state open"
assert_contains "$pr_create_calls" "gh pr create --draft --repo dashlytix/sample --head feat/pr-125 --base main --title Fix task workspace --body"
assert_contains "$pr_create_calls" "open https://github.com/dashlytix/sample/pull/126"
: > "$LOG"
pr_existing_output=$(DEV_TEST_CROSS_REPO_WORKTREE=1 DEV_TEST_PR_BRANCH=feat/pr-125 \
  DEV_TEST_EXISTING_PR=1 run_dev -H exe-dash pr feat/pr-125)
pr_existing_calls=$(<"$LOG")
assert_contains "$pr_existing_output" "found existing PR"
assert_not_contains "$pr_existing_calls" "gh pr create"
assert_contains "$pr_existing_calls" "open https://github.com/dashlytix/sample/pull/125"

: > "$LOG"
linear_run_output=$(run_dev -H exe-dash task run dashlytix/sample linear DAS-9)
linear_run_calls=$(<"$LOG")
assert_contains "$linear_run_output" "preparing das-9"
assert_contains "$linear_run_calls" "worktree create --cwd /home/exedev/sample --branch feat/das-9-pr"
assert_contains "$linear_run_calls" "agent start das-9 --kind omp"

: > "$LOG"
task_run_output=$(run_dev -H exe-dash task run dashlytix/sample prompt "Fix login")
task_run_calls=$(<"$LOG")
assert_contains "$task_run_output" "preparing prompt-fix-login"
assert_contains "$task_run_calls" "worktree create --cwd /home/exedev/sample"
assert_contains "$task_run_calls" "agent start prompt-fix-login --kind omp"
assert_contains "$task_run_calls" "ssh -t -o HostName=ar-general-dev.exe.xyz exe-dash"

: > "$LOG"
reuse_output=$(DEV_TEST_EXISTING_WORKTREE=1 \
  run_dev -H exe-dash task run dashlytix/sample prompt "Fix login")
reuse_calls=$(<"$LOG")
assert_contains "$reuse_output" "preparing prompt-fix-login"
assert_contains "$reuse_calls" "worktree open --workspace w-main --path /home/exedev/worktrees/sample/existing"
assert_not_contains "$reuse_calls" "worktree create"

: > "$LOG"
missing_run_output=$(DEV_TEST_REPO_MISSING=1 run_dev -H exe-dash task run dashlytix/sample prompt "Fix login")
missing_run_calls=$(<"$LOG")
assert_contains "$missing_run_output" "preparing prompt-fix-login"
assert_contains "$missing_run_calls" "git clone https://github.int.exe.xyz/dashlytix/sample.git /home/exedev/sample"

if clone_error=$(DEV_TEST_REPO_MISSING=1 DEV_TEST_CLONE_FAIL=1 \
    run_dev -H exe-dash task run dashlytix/sample prompt "Fix login" 2>&1); then
  fail "missing integration should stop task bootstrap"
fi
assert_contains "$clone_error" "integrations add github"

if attach_error=$(DEV_TEST_REPO_MISSING=1 DEV_TEST_CLONE_FAIL=1 \
    DEV_TEST_INTEGRATION_EXISTS=1 \
    run_dev -H exe-dash task run dashlytix/sample prompt "Fix login" 2>&1); then
  fail "unattached integration should stop task bootstrap"
fi
assert_contains "$attach_error" "integrations attach sample-github vm:ar-general-dev"

: > "$LOG"
profile_ps=$(run_dev -H exe-dash ps)
assert_contains "$profile_ps" "https://ar-general-dev.exe.xyz:3000/"

: > "$LOG"
multi_output=$(DEV_TEST_MULTI=1 run_dev -H exe-dash -B second-box ls)
multi_calls=$(<"$LOG")
assert_contains "$multi_output" "/home/exedev/sample"
assert_contains "$multi_calls" "ssh -o HostName=second-box.exe.xyz exe-dash RHOME="

if multi_error=$(DEV_TEST_MULTI=1 run_dev -H exe-dash ls </dev/null 2>&1); then
  fail "multiple lobby boxes should require --box without an interactive terminal"
fi
assert_contains "$multi_error" "select one with --box NAME"

: > "$LOG"
fleet_output=$(DEV_TEST_MULTI=1 run_dev -H exe-dash fleet ls)
fleet_plain=$(plain "$fleet_output")
fleet_calls=$(<"$LOG")
assert_contains "$fleet_output" "ar-general-dev      online"
assert_contains "$fleet_plain" "ar-general-dev      ● herdr"
assert_contains "$fleet_plain" "second-box          online"
assert_contains "$fleet_plain" "second-box          ◆ agent"
assert_contains "$fleet_plain" "second-box          ■ shell"
assert_contains "$fleet_plain" "codex"
assert_contains "$fleet_plain" "second-box          ■ tmux"
assert_contains "$fleet_calls" "HostName=ar-general-dev.exe.xyz"
assert_contains "$fleet_calls" "HostName=second-box.exe.xyz"
assert_not_contains "$fleet_output" "second-box.exe.xyz"

: > "$LOG"
fleet_picker_output=$(DEV_TEST_MULTI=1 DEV_TEST_BOX_PICKER=1 DEV_TEST_PICK=+all \
  run_dev -H exe-dash ls)
fleet_picker_plain=$(plain "$fleet_picker_output")
fleet_picker_calls=$(<"$LOG")
assert_contains "$fleet_picker_plain" "second-box          ◆ agent"

: > "$LOG"
fleet_agent_output=$(DEV_TEST_MULTI=1 DEV_TEST_FLEET_KIND=agent \
  run_dev -H exe-dash fleet)
fleet_agent_calls=$(<"$LOG")
assert_contains "$fleet_agent_output" "codex pid 4242 is running outside Herdr"
assert_contains "$fleet_agent_calls" "ssh -t -o HostName=second-box.exe.xyz exe-dash cd /home/exedev/sample"
assert_contains "$fleet_picker_calls" $'box-row +all\tmonitor Herdr and unmanaged sessions on every box'

rm -f "$NEW_BOX_STATE"
: > "$LOG"
new_box_output=$(run_dev -H exe-dash box new fresh-box dashlytix/sample --yes)
new_box_calls=$(<"$LOG")
assert_contains "$new_box_output" "fresh-box is ready with dashlytix/sample and OMP"
assert_contains "$new_box_calls" "ssh exe-dash new --json --name=fresh-box --tag=tailscale --comment=dev-cli:dashlytix/sample"
assert_contains "$new_box_calls" "ssh -o HostName=fresh-box.exe.xyz exe-dash bash -s"
assert_contains "$new_box_calls" "integrations add github --name=sample --repository=dashlytix/sample --attach=vm:fresh-box"
assert_contains "$new_box_calls" "git clone https://github.int.exe.xyz/dashlytix/sample.git /home/exedev/sample"
assert_contains "$new_box_calls" "agent start sample --kind omp"

: > "$NEW_BOX_STATE"
: > "$LOG"
bootstrap_output=$(DEV_TEST_INTEGRATION_EXISTS=1 \
  run_dev -H exe-dash -B fresh-box box bootstrap dashlytix/sample)
bootstrap_calls=$(<"$LOG")
assert_contains "$bootstrap_output" "fresh-box is ready with dashlytix/sample and OMP"
assert_contains "$bootstrap_calls" "integrations attach sample-github vm:fresh-box"
assert_contains "$bootstrap_calls" "agent start sample --kind omp"

rm -f "$NEW_BOX_STATE"
: > "$LOG"
picker_output=$(DEV_TEST_BOX_PICKER=1 DEV_TEST_PICK=+new \
  DEV_NEW_BOX_NAME=fresh-box DEV_NEW_BOX_PROJECT=dashlytix/sample DEV_NEW_BOX_YES=1 \
  run_dev -H exe-dash ls)
picker_calls=$(<"$LOG")
assert_contains "$picker_calls" $'box-row +new\tcreate a box, clone a repository, and start OMP'
assert_contains "$picker_calls" $'box-row +all\tmonitor Herdr and unmanaged sessions on every box'
assert_contains "$picker_calls" "fzf --prompt=box> "

rm -f "$NEW_BOX_STATE"
: > "$LOG"
if invalid_box_error=$(run_dev -H exe-dash box new 'Bad Box' dashlytix/sample --yes 2>&1); then
  fail "invalid box names should stop before provisioning"
fi
assert_contains "$invalid_box_error" "box name must start"
invalid_box_calls=$(<"$LOG")
assert_not_contains "$invalid_box_calls" " new --json "

rm -f "$NEW_BOX_STATE"
if create_error=$(DEV_TEST_NEW_FAIL=1 \
    run_dev -H exe-dash box new fresh-box dashlytix/sample --yes 2>&1); then
  fail "exe.dev creation failures should stop provisioning"
fi
assert_contains "$create_error" "exe.dev could not create box fresh-box"

: > "$LOG"
audit_output=$(DEV_TEST_MULTI=1 run_dev -H exe-dash fleet audit)
audit_plain=$(plain "$audit_output")
assert_contains "$audit_plain" "ar-general-dev"
assert_contains "$audit_plain" "0.8.0*"
assert_contains "$audit_plain" "manual"
assert_contains "$audit_plain" "latest herdr: 0.9.5"

if herdr_usage=$(run_dev -H exe-dash fleet herdr 2>&1); then
  fail "fleet herdr without boxes should refuse"
fi
assert_contains "$herdr_usage" "--all|BOX..."

: > "$LOG"
herdr_plan=$(DEV_TEST_MULTI=1 run_dev -H exe-dash fleet herdr second-box)
herdr_calls=$(<"$LOG")
assert_contains "$herdr_plan" "dry run: nothing changes"
assert_contains "$herdr_plan" $'second-box\tplan (none): install 0.9.5, install unit, start under systemd'
assert_contains "$herdr_calls" "HostName=second-box.exe.xyz"
assert_contains "$herdr_calls" "APPLY=0"
assert_not_contains "$herdr_calls" "HostName=ar-general-dev.exe.xyz"

: > "$LOG"
help_output=$(run_dev -H exe-dash --help)
help_calls=$(<"$LOG")
assert_contains "$help_output" "pick an exe.dev SSH profile"
assert_contains "$help_output" "dev task"
assert_contains "$help_output" "dev github setup"
assert_contains "$help_output" "dev box new"
assert_contains "$help_output" "dev fleet"
assert_contains "$help_output" "dev fleet herdr"
[ -z "$help_calls" ] || fail "help should not invoke SSH: $help_calls"

printf 'dev-hosts: all checks passed\n'
