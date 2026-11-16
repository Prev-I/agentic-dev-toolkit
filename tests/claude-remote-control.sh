#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly RUNBOOK="$REPOSITORY_ROOT/docs/claude-remote-control.md"
# The longest restart delay the unit may back off to. Past it a recovered backend
# stays unused for too long.
readonly MAX_RESTART_DELAY_CAP=600

cleanup() {
  rm -rf "${TEMP_DIR:-}"
}

trap cleanup EXIT

# The helpers are duplicated from tests/install.sh rather than factored into a
# shared library, for the same reason the other suites duplicate them.
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  [[ "$haystack" == *"$needle"* ]] || fail "$message: '$needle' not found"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  [[ "$haystack" != *"$needle"* ]] || fail "$message: '$needle' must not appear"
}

# The runbook is the deliverable, so the suite checks the unit it actually ships
# rather than a second copy that could drift from it.
extract_unit() {
  sed -n '/^# >>> claude-rc-unit >>>$/,/^# <<< claude-rc-unit <<<$/{p;}' "$RUNBOOK"
}

# systemd joins a line ending in a backslash with the next one.
join_continuations() {
  sed -e ':a' -e '/\\$/N; s/\\\n//; ta'
}

directive() {
  local name="$1"
  grep -E "^${name}=" <<< "$UNIT" || true
}

directive_value() {
  local value
  value="$(directive "$1")"
  printf '%s' "${value#"$1"=}"
}

test_the_runbook_ships_exactly_one_unit() {
  local starts ends
  starts="$(grep -c '^# >>> claude-rc-unit >>>$' "$RUNBOOK")"
  ends="$(grep -c '^# <<< claude-rc-unit <<<$' "$RUNBOOK")"
  [[ "$starts" == 1 && "$ends" == 1 ]] || fail "runbook must carry one marked unit, found $starts/$ends markers"
  [[ -n "$UNIT" ]] || fail "marked unit must not be empty"
}

# A shared tmux server either takes the session out of the unit (Restart never
# fires) or pulls hand-opened sessions into it (stop kills them). A `-t` target
# would misread a "." in the instance name as a pane separator.
test_every_tmux_call_uses_the_instance_socket() {
  local line count=0
  while IFS= read -r line; do
    [[ "$line" == Exec*tmux* ]] || continue
    count=$((count + 1))
    assert_contains "$line" 'tmux -L rc-%i ' "unit tmux calls must use the per-instance server"
    assert_not_contains "$line" ' -t ' "unit tmux calls must not target a session by name"
  done <<< "$UNIT"
  [[ "$count" -ge 2 ]] || fail "unit must start and stop tmux, found $count tmux lines"

  # Every documented tmux command, whether or not it names the server.
  local subcommands='attach|has-session|capture-pane|kill-server|kill-session|list-sessions'
  count=0
  while IFS= read -r line; do
    count=$((count + 1))
    assert_contains "$line" 'tmux -L rc-<PROJECT> ' "documented tmux commands must name the instance server"
    [[ ! "$line" =~ \ -[a-zA-Z]*t([\ =\"]|$) ]] || fail "documented tmux commands must not target a session: $line"
  done < <(grep -E "tmux( -[A-Za-z]+( [^ ]+)?)* ($subcommands)" "$RUNBOOK" | grep -vE '^(#|ExecSt)')
  [[ "$count" -ge 4 ]] || fail "runbook must document the tmux commands, found $count"
}

test_the_server_is_kept_alive_and_its_absence_tolerated() {
  [[ "$(directive Type)" == 'Type=forking' ]] || fail "tmux daemonizes, so the unit must be Type=forking"
  # tmux exits 0 when claude exits, so on-failure would never restart it.
  [[ "$(directive Restart)" == 'Restart=always' ]] || fail "unit must use Restart=always"
  local stop
  stop="$(directive ExecStop)"
  [[ "$stop" == ExecStop=-* ]] || fail "ExecStop must tolerate an already exited tmux server: $stop"
}

# A transient backend outage makes claude fail at once on every start, exactly
# like a configuration error, and a server left `failed` cannot be recovered from
# a remote client. So the unit never gives up: the start limit is off, and the
# restart delay grows to a cap short enough that a recovered backend is picked up
# within minutes. The auto-restart counter survives successful runs and `restart`,
# so once it reaches the cap every later crash waits the full cap.
test_restarts_back_off_and_never_exhaust_the_start_limit() {
  local unit_section service_section interval restart_sec max_delay steps timeout_sec sequence
  unit_section="$(sed -n '/^\[Unit\]$/,/^\[/p' <<< "$UNIT")"
  service_section="$(sed -n '/^\[Service\]$/,/^\[/p' <<< "$UNIT")"
  interval="$(sed -n 's/^StartLimitIntervalSec=\(.*\)$/\1/p' <<< "$unit_section")"
  [[ "$interval" == 0 ]] || fail "StartLimitIntervalSec=0 must be in [Unit], found '$interval'"
  ! grep -qE '^StartLimitBurst=' <<< "$unit_section" || fail "StartLimitBurst is meaningless with the limit off"
  ! grep -qE '^StartLimit' <<< "$service_section" || fail "start limits in [Service] are ignored or half-applied"
  restart_sec="$(directive_value RestartSec)"
  max_delay="$(directive_value RestartMaxDelaySec)"
  steps="$(directive_value RestartSteps)"
  timeout_sec="$(directive_value TimeoutStartSec)"
  # Positive and without a leading zero: with no start limit, RestartSec=0 would
  # be a tight loop (systemd skips the backoff), and (( )) reads 08 as octal.
  [[ "$restart_sec" =~ ^[1-9][0-9]*$ && "$max_delay" =~ ^[1-9][0-9]*$ \
    && "$steps" =~ ^[1-9][0-9]*$ && "$timeout_sec" =~ ^[1-9][0-9]*$ ]] \
    || fail "RestartSec, RestartMaxDelaySec, RestartSteps and TimeoutStartSec must be positive integers"
  (( max_delay > restart_sec )) \
    || fail "the restart delay must grow: ${restart_sec}s to ${max_delay}s"
  (( max_delay <= MAX_RESTART_DELAY_CAP )) \
    || fail "a ${max_delay}s cap leaves a recovered backend unused too long; keep it within ${MAX_RESTART_DELAY_CAP}s"

  # The unit's comment states the delays; keep it in step with the directives,
  # and on one line, since UNIT keeps comment line breaks.
  sequence="$(awk -v r="$restart_sec" -v m="$max_delay" -v s="$steps" 'BEGIN {
    for (n = 0; n < s; n++) printf "%.0f, ", r * (m / r) ^ (n / s)
    printf "then %d seconds between starts.", m
  }')"
  assert_contains "$UNIT" "# $sequence" "the unit comment must state the restart delays"
}

# The pane runs in its own scope, so systemd neither waits for nor kills claude.
# The stop must wait for this instance's claude, then force it, inside its timeout.
test_the_stop_waits_for_and_then_forces_the_instance_payload() {
  local pattern='"^[^ ]*/claude remote-control --name %i "'
  local -a post
  mapfile -t post < <(directive ExecStopPost)
  [[ "${#post[@]}" -eq 4 ]] || fail "stop must wait, TERM, wait and KILL, found ${#post[@]} ExecStopPost lines"
  assert_contains "${post[0]}" "while pgrep -f $pattern" "stop must first wait for this instance's claude"
  assert_contains "${post[1]}" "pkill -TERM -f $pattern" "a claude still running must get TERM"
  assert_contains "${post[2]}" "while pgrep -f $pattern" "TERM must get time to work"
  assert_contains "${post[3]}" "pkill -KILL -f $pattern" "a claude that ignores TERM must be killed"
  local line waited=0 limit
  for line in "${post[@]}"; do
    [[ "$line" == ExecStopPost=-* ]] || fail "nothing left to stop must not fail the unit: $line"
    if [[ "$line" =~ timeout\ ([0-9]+)\  ]]; then
      waited=$((waited + BASH_REMATCH[1]))
    elif [[ "$line" == *while* ]]; then
      fail "every wait must carry its own timeout: $line"
    fi
  done
  limit="$(directive TimeoutStopSec)"
  [[ "$limit" =~ ^TimeoutStopSec=([0-9]+)$ ]] || fail "the stop must be bounded"
  (( waited < BASH_REMATCH[1] )) || fail "the ${waited}s of waits must finish inside TimeoutStopSec"
}

# claude exits at once when the name does not resolve; the wait must come before
# anything else and must actually loop.
test_the_start_waits_for_the_api_name() {
  local -a pre
  mapfile -t pre < <(directive ExecStartPre)
  assert_contains "${pre[0]:-}" "until getent ahosts api.anthropic.com" \
    "the first start check must wait for the API name to resolve"
}

test_the_project_environment_is_loaded_and_checked_first() {
  [[ "$(directive WorkingDirectory)" == 'WorkingDirectory=%h/code/%i' ]] \
    || fail "instance name must select ~/code/<instance>"
  assert_contains "$(directive ExecStartPre)" 'direnv exec %h/code/%i ' \
    "a blocked .envrc must fail the unit before tmux hides it"
  assert_contains "$(directive ExecStart)" 'direnv exec %h/code/%i %h/.local/bin/claude remote-control ' \
    "claude must run inside the project's direnv environment"
}

test_remote_control_runs_without_bypass_or_global_flags() {
  local start
  start="$(directive ExecStart)"
  # Nothing may sit between the binary and the subcommand, and the stop and
  # verification patterns expect --name right after it.
  assert_contains "$start" '/claude remote-control --name "%i" ' \
    "remote-control must follow the binary directly, with --name first"
  assert_contains "$start" '--spawn worktree' "remote sessions must get their own worktree"
  # A pre-created session would run in the main checkout, outside any worktree.
  assert_contains "$start" '--no-create-session-in-dir' "the server must not pre-create a session in the project directory"
  # Nobody is at the workstation to answer prompts and the project's defaultMode
  # does not reach every session, so the server sets the mode, after the verb,
  # where Remote Control accepts it.
  [[ "$start " == *'/claude remote-control '*' --permission-mode auto '* ]] \
    || fail "the server must start its sessions in auto mode, after the verb"
  [[ "$(grep -o -- '--permission-mode' <<< "$start" | wc -l)" == 1 ]] \
    || fail "the unit must set the permission mode exactly once"
  assert_not_contains "$UNIT" 'dangerously-skip-permissions' "unit must not bypass permissions"
  assert_not_contains "$UNIT" 'bypassPermissions' "unit must not bypass permissions"
  local settings
  settings="$(grep -vE '^#' <<< "$UNIT")"
  assert_not_contains "$settings" 'ANTHROPIC_' "unit must not redirect or replace API access"
  assert_not_contains "$settings" 'CLAUDE_CODE_OAUTH_TOKEN' "unit must not replace the claude.ai login"
  assert_not_contains "$settings" 'EnvironmentFile=' "the project environment comes from direnv, not the unit"
}

# Unknown keys only warn and still exit 0, so any output is a failure. The
# executables are substituted because a test host need not have tmux or direnv.
test_the_unit_passes_systemd_verify() {
  if ! command -v systemd-analyze >/dev/null 2>&1 \
    || [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "${XDG_RUNTIME_DIR:-/nonexistent}" ]]; then
    printf 'SKIP: systemd-analyze --user verify needs systemd-analyze and a user runtime directory\n' >&2
    return 0
  fi
  local dir="$TEMP_DIR/units" output status=0 true_bin
  true_bin="$(command -v true)"
  mkdir -p "$dir"
  sed -e "s|/usr/bin/tmux|$true_bin|g" -e "s|/usr/bin/direnv|$true_bin|g" \
    <<< "$RAW_UNIT" > "$dir/claude-rc@.service"
  output="$(systemd-analyze --user verify "$dir/claude-rc@fixture.service" 2>&1)" || status=$?
  [[ "$status" == 0 && -z "$output" ]] || fail "systemd-analyze verify must be silent and succeed (status $status): $output"
}

TEMP_DIR="$(mktemp -d)"
RAW_UNIT="$(extract_unit)"
UNIT="$(join_continuations <<< "$RAW_UNIT" | sed -E 's/[[:space:]]+/ /g')"
readonly RAW_UNIT UNIT

test_the_runbook_ships_exactly_one_unit
test_every_tmux_call_uses_the_instance_socket
test_the_server_is_kept_alive_and_its_absence_tolerated
test_restarts_back_off_and_never_exhaust_the_start_limit
test_the_start_waits_for_the_api_name
test_the_stop_waits_for_and_then_forces_the_instance_payload
test_the_project_environment_is_loaded_and_checked_first
test_remote_control_runs_without_bypass_or_global_flags
test_the_unit_passes_systemd_verify

printf 'PASS: claude remote control tests\n'
