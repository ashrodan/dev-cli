#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/dev-hosts-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/calls"
mkdir -p "$TMP/bin" "$TMP/ssh/config.d"

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

case "$*" in
  *"RHOME="*)
    printf 'sample\tmain\t/home/exedev/sample\t\tmain\t3000\tabc123\tnow\t0\t0\t0\tmessage\n'
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
while IFS= read -r line; do
  profile=${line%%	*}
  if [ -z "${DEV_TEST_PICK:-}" ] || [ "$profile" = "$DEV_TEST_PICK" ]; then
    printf '%s\n' "$line"
    exit 0
  fi
done
exit 1
SH
chmod +x "$TMP/bin/ssh" "$TMP/bin/code" "$TMP/bin/fzf"

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

run_dev() {
  PATH="$TMP/bin:$PATH" DEV_TEST_LOG="$LOG" DEV_TEST_MULTI="${DEV_TEST_MULTI:-}" \
    DEV_TEST_PICK="${DEV_TEST_PICK:-}" DEV_SSH_CONFIG="$TMP/ssh/config" \
    "$ROOT/dev" "$@"
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
[ -z "$help_calls" ] || fail "help should not invoke SSH: $help_calls"

printf 'dev-hosts: all checks passed\n'
