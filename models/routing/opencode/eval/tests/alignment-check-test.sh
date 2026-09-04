#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tests/test-lib.sh"
source "$root/runtime/opencode-v1-adapter/check-alignment.sh"

# check-alignment.sh: does the installed configuration still match the
# repository bundle? These cases pin the two properties that make the tool
# trustworthy rather than noisy:
#
#   1. It catches what actually drifted in practice -- a permission value
#      inside an agent row (the 2026-09-04 git-push ask/deny case) and an
#      agent's permission frontmatter (the expert.md missing-denies case).
#   2. It does NOT fire on user-owned configuration keys. activate-profile.sh
#      preserves everything outside `model`, `permission.task` and the
#      declared agent rows; a check that flagged a user's own `plugin` entry
#      would cry wolf and stop being read.

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

bundle="$workdir/bundle"
live="$workdir/live"
mkdir -p "$bundle/agents" "$live/agents"

cat >"$workdir/targets.json" <<'EOF'
{"profile_id": "test", "agents": {"build": {"model": "p/m", "variant": "high", "mode": "primary"}}}
EOF

write_profile() {
  # $1 = destination, $2 = git push action, $3 = extra top-level JSON (or empty)
  cat >"$1" <<EOF
// a comment, which must never itself count as drift
{
  "model": "p/m",
  "permission": { "task": { "*": "allow", "breakglass": "deny" } },
  "agent": {
    "build": {
      "mode": "primary",
      "model": "p/m",
      "variant": "high",
      "permission": {
        "edit": "allow",
        "bash": { "*": "allow", "git push*": "$2" }
      }
    }
  }${3:+,
  $3}
}
EOF
}

write_agent_md() {
  # $1 = destination, $2 = permission body, $3 = prose
  printf -- '---\ndescription: %s\nmode: subagent\npermission:\n%s---\n\n%s\n' \
    "$3" "$2" "$3" >"$1"
}

standard_perm=$'  edit: deny\n  task: deny\n  skill: allow\n'

setup_aligned() {
  write_profile "$bundle/profile.jsonc" ask ""
  write_profile "$live/opencode.jsonc" ask ""
  for name in reviewer expert; do
    write_agent_md "$bundle/agents/$name.md" "$standard_perm" "prose"
    write_agent_md "$live/agents/$name.md" "$standard_perm" "prose"
  done
  printf 'routing policy\n' >"$bundle/model-routing.md"
  printf 'routing policy\n' >"$live/model-routing.md"
}

run_check() {
  set +e
  check_alignment \
    --profile "$bundle/profile.jsonc" \
    --targets "$workdir/targets.json" \
    --bundle-root "$bundle" \
    --live-config "$live/opencode.jsonc" \
    --live-support-root "$live" \
    --json "$workdir/report.json" >"$workdir/out.txt" 2>&1
  local rc=$?
  set -e
  return $rc
}

report_status() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$workdir/report.json"
}

# --- aligned: identical bundles, differing only by a comment --------------
setup_aligned
run_check || fail "identical configurations must be reported ALIGNED (exit 0)"
[[ "$(report_status)" == ALIGNED ]] || fail "expected status ALIGNED, got $(report_status)"

# --- the real 2026-09-04 case: a permission value inside an agent row -----
setup_aligned
write_profile "$live/opencode.jsonc" deny ""
run_check && fail "a git-push permission difference inside an agent row must be DRIFT"
[[ "$(report_status)" == DRIFT ]] || fail "expected status DRIFT, got $(report_status)"
grep -q 'agent.build' "$workdir/out.txt" \
  || fail "drift report must name the differing agent row"
grep -q 'permission' "$workdir/out.txt" \
  || fail "drift report must name the differing sub-key"

# --- routing-owned top-level keys -----------------------------------------
setup_aligned
python3 - "$live/opencode.jsonc" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(text.replace('"model": "p/m"', '"model": "other/model"', 1))
PY
run_check && fail "a changed top-level default model must be DRIFT"

# --- user-owned keys must NEVER be reported (the cry-wolf guard) ----------
setup_aligned
write_profile "$live/opencode.jsonc" ask '"plugin": ["something@1.0.0"], "theme": "dark"'
run_check || fail "user-owned keys (plugin, theme) must not be reported as drift"
[[ "$(report_status)" == ALIGNED ]] \
  || fail "user-owned keys must leave status ALIGNED, got $(report_status)"

# An agent row the targets manifest does not declare is the user's own.
# activate-profile.sh preserves such rows verbatim ("undeclared agent rows
# preserved unchanged"), so flagging one would be a false positive -- and a
# check that flags a user's own custom agent is one they stop running.
setup_aligned
python3 - "$live/opencode.jsonc" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
marker = '  "agent": {\n'
extra = marker + '    "my-own-agent": { "model": "x/y", "variant": "low" },\n'
open(path, "w", encoding="utf-8").write(text.replace(marker, extra, 1))
PY
run_check || fail "an undeclared (user-owned) agent row must not be reported as drift"
[[ "$(report_status)" == ALIGNED ]] \
  || fail "an undeclared agent row must leave status ALIGNED, got $(report_status)"
grep -q 'my-own-agent' "$workdir/out.txt" \
  && fail "an undeclared agent row must not appear in the report at all"

# --- the real expert.md case: permission frontmatter differs -------------
setup_aligned
write_agent_md "$live/agents/expert.md" $'  edit: deny\n  task: deny\n' "prose"
run_check && fail "an agent's differing permission frontmatter must be DRIFT"
grep -q 'security boundary' "$workdir/out.txt" \
  || fail "permission frontmatter drift must be labelled a security boundary"

# --- prose-only differences are STALE, not DRIFT -------------------------
setup_aligned
write_agent_md "$live/agents/reviewer.md" "$standard_perm" "different prose entirely"
run_check || fail "a prose-only difference must NOT fail the check (STALE, not DRIFT)"
[[ "$(report_status)" == STALE ]] || fail "expected status STALE, got $(report_status)"

setup_aligned
printf 'a stale routing policy describing models that are no longer routed\n' >"$live/model-routing.md"
run_check || fail "a differing model-routing.md must be STALE, not DRIFT"
[[ "$(report_status)" == STALE ]] || fail "expected status STALE, got $(report_status)"

# --- an uninstalled support file is DRIFT, not silence -------------------
setup_aligned
rm -f "$live/model-routing.md"
run_check && fail "a missing installed model-routing.md must be DRIFT"

setup_aligned
rm -f "$live/agents/reviewer.md"
run_check && fail "a missing installed agent file must be DRIFT"

# --- a missing installed configuration is an error, not a false ALIGNED --
setup_aligned
rm -f "$live/opencode.jsonc"
set +e
check_alignment \
  --profile "$bundle/profile.jsonc" --targets "$workdir/targets.json" \
  --bundle-root "$bundle" --live-config "$live/opencode.jsonc" \
  --live-support-root "$live" >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" == 2 ]] || fail "a missing installed configuration must exit 2 (usage/environment), got $rc"

# --- never auto-repairs ---------------------------------------------------
setup_aligned
write_profile "$live/opencode.jsonc" deny ""
before=$(sha256sum "$live/opencode.jsonc" | cut -d' ' -f1)
run_check || true
after=$(sha256sum "$live/opencode.jsonc" | cut -d' ' -f1)
[[ "$before" == "$after" ]] || fail "check_alignment must never modify the installed configuration"

printf 'PASS: alignment check (drift vs stale, user-owned keys never flagged)\n'
