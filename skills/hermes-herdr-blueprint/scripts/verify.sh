#!/usr/bin/env bash
set -u

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
CDP_PORT="${HERMES_BROWSER_CDP_PORT:-9222}"
CDP_URL="http://127.0.0.1:${CDP_PORT}"
failures=0

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf '✓ %s\n' "$label"
  else
    printf '✗ %s\n' "$label"
    failures=$((failures + 1))
  fi
}

equals() {
  [[ "$1" == "$2" ]]
}

check "Hermes installed" command -v hermes
check "Browser Use installed" command -v browser-use
check "Chromium service enabled" systemctl is-enabled hermes-browser
check "Chromium service active" systemctl is-active hermes-browser
check "Chromium CDP reachable" curl -fsS "$CDP_URL/json/version"

if command -v hermes >/dev/null 2>&1; then
  check "OpenAI Codex provider selected" equals "$(hermes config get model.provider 2>/dev/null)" "openai-codex"
  check "Browser Use backend selected" equals "$(hermes config get browser.backend 2>/dev/null)" "browser-use"
  check "Tool search enabled" equals "$(hermes config get tools.tool_search.enabled 2>/dev/null)" "true"
  check "Herdr skill installed" test -f "$HERMES_HOME/skills/autonomous-ai-agents/herdr/SKILL.md"
  check "OpenAI Codex authentication present" bash -c "hermes auth status openai-codex 2>/dev/null | grep -q 'logged in'"
fi

if command -v herdr >/dev/null 2>&1; then
  check "Herdr server available" bash -c "herdr status 2>/dev/null | grep -q 'status: running'"
  check "Herdr Hermes integration current" bash -c "herdr integration status 2>/dev/null | grep -q '^hermes: current'"
fi

if command -v browser-use >/dev/null 2>&1 && curl -fsS "$CDP_URL/json/version" >/dev/null 2>&1; then
  if BU_CDP_URL="$CDP_URL" timeout 120 browser-use <<'PY' >/dev/null 2>&1
ensure_real_tab()
goto_url('https://example.com')
assert page_info().get('title') == 'Example Domain'
PY
  then
    printf '✓ Browser navigation test\n'
  else
    printf '✗ Browser navigation test\n'
    failures=$((failures + 1))
  fi
fi

if (( failures > 0 )); then
  printf '\n%d verification check(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nBlueprint verification passed.\n'
