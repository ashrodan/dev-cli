#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/dev-hosts-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/calls"
CLIPBOARD="$TMP/clipboard"
FZF_STATE="$TMP/fzf-state"
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

if [ "${1:-}" = "-G" ]; then
  case "${2:-}" in
    exe-dash|exe-personal) printf 'hostname exe.dev\nuser exedev\nidentityfile ~/.ssh/%s\n' "${2#exe-}" ;;
    dash|ar-general-dev) printf 'hostname ar-general-dev.exe.xyz\nuser exedev\nidentityfile ~/.ssh/dash\n' ;;
    *)        printf 'hostname herdr-1.exe.xyz\nuser exedev\nidentityfile ~/.ssh/default\n' ;;
  esac
  exit 0
fi

if [ "$*" = "exe-dash ls --json" ]; then
  if [ -n "${DEV_TEST_MULTI:-}" ]; then
    printf '%s\n' '{"vms":[{"vm_name":"ar-general-dev","ssh_host":"ar-general-dev.exe.xyz","status":"running","access":{"shell":true}},{"vm_name":"second-box","ssh_host":"second-box.exe.xyz","status":"running","access":{"shell":true}}]}'
  else
    printf '%s\n' '{"vms":[{"vm_name":"ar-general-dev","ssh_host":"ar-general-dev.exe.xyz","status":"running","access":{"shell":true}}]}'
  fi
  exit 0
fi
if [ "$*" = "exe-dash integrations list" ]; then
  if [ -n "${DEV_TEST_INTEGRATION_EXISTS:-}" ]; then
    printf 'sample-github  github  repos=dashlytix/sample\n'
  fi
  exit 0
fi


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
    printf '\n%s\n' "$line"
    exit 0
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
printf '%s\n' '{"number":125,"title":"Fix task workspace","body":"Implement the requested workflow.","headRefName":"feat/pr-125","baseRefName":"main","url":"https://github.com/dashlytix/sample/pull/125"}'
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
chmod +x "$TMP/bin/ssh" "$TMP/bin/code" "$TMP/bin/fzf" "$TMP/bin/gh" "$TMP/bin/linear" "$TMP/bin/pbcopy"

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

run_dev() {
  PATH="$TMP/bin:$PATH" DEV_TEST_LOG="$LOG" DEV_TEST_MULTI="${DEV_TEST_MULTI:-}" \
    DEV_TEST_PICK="${DEV_TEST_PICK:-}" DEV_TEST_PROJECT="${DEV_TEST_PROJECT:-}" \
    DEV_TEST_ALL_PROJECT="${DEV_TEST_ALL_PROJECT:-}" \
    DEV_TEST_REPO_MISSING="${DEV_TEST_REPO_MISSING:-}" DEV_TEST_CLONE_FAIL="${DEV_TEST_CLONE_FAIL:-}" \
    DEV_TEST_INTEGRATION_EXISTS="${DEV_TEST_INTEGRATION_EXISTS:-}" \
    DEV_TEST_DUPLICATE_REPO="${DEV_TEST_DUPLICATE_REPO:-}" \
    DEV_TEST_CROSS_REPO_WORKTREE="${DEV_TEST_CROSS_REPO_WORKTREE:-}" \
    DEV_TEST_EXISTING_WORKTREE="${DEV_TEST_EXISTING_WORKTREE:-}" \
    DEV_TEST_CLIPBOARD="$CLIPBOARD" DEV_TEST_FZF_STATE="$FZF_STATE" \
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
help_output=$(run_dev -H exe-dash --help)
help_calls=$(<"$LOG")
assert_contains "$help_output" "pick an exe.dev SSH profile"
assert_contains "$help_output" "dev task"
[ -z "$help_calls" ] || fail "help should not invoke SSH: $help_calls"

printf 'dev-hosts: all checks passed\n'
