# Software Catalog, Script Versions and Install Receipt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `install.sh`'s sixteen third-party pins into a shared data
catalog, give all five shipped scripts a version, and have a successful
install record what it requested and what it got so the doctor can report
drift.

**Architecture:** A new `catalog/software-catalog.env` holds the pins in an
inert `key=value` format called `adt-kv`. `install.sh` loads it through a
pure-Bash reader, validates every effective value before touching the machine,
and after a verified install writes an `adt-kv` receipt to XDG state.
`wsl-toolchain-doctor.sh` reads both files and adds a `TOOLKIT_` finding
domain with three comparisons, one of them behind a new `--probe` flag.

**Tech Stack:** Bash 4.3+ only. No Node, no `jq`, no Python, no TOML parser in
either script. `mise` for runtime probes, coreutils `timeout` for bounding
them.

**Spec:** `docs/superpowers/specs/2026-09-09-software-catalog-design.md` —
read it alongside this plan. Every normative grammar, table and rule lives
there; this plan sequences the work and supplies the tests.

**Repository:** `checkouts/agentic-dev-toolkit` only. The parent workspace's
`scripts/check-catalog-drift.sh` is a separate plan, written after this one
lands, and routed through OpenSpec per the parent's `AGENTS.md`.

## Global Constraints

- **Bash 4.3 minimum.** `declare -n` needs 4.3, `declare -g` needs 4.2.
  Debian/Ubuntu ship 5.x.
- **Pure Bash in `install.sh` and the doctor.** No `node`, `jq`, `python` or
  TOML parser may be added to either.
- **`main "$@"` stays the last line of `install.sh`.** `tests/install.sh`
  asserts it and the whole suite depends on it.
- **The installer body is sourced exactly once per test shell.** A second
  source fails with `readonly variable`.
- **No nested function definitions in any script.** Bash function definitions
  are global; a nested one would replace a caller's function of the same name.
- **No new global helper named `fail`, `error` or `die`.** `tests/install.sh`
  owns `fail`.
- **Installer top-level arrays use `declare -g`.** The body is sourced inside
  `load_installer_functions`, so a plain `declare` is function-local and the
  array is empty after the loader returns. Plain assignments and `readonly`
  are already global and keep their current form.
- **Key grammar:** `^[a-z0-9][a-z0-9.-]*$`
- **Scalar value grammar:** `^[A-Za-z0-9][A-Za-z0-9._:+@/-]*$`
- **List value grammar:** `^$|^[a-z0-9][a-z0-9.-]*(,[a-z0-9][a-z0-9.-]*)*$`,
  for `skipped` and `overridden` only.
- **Canonical order** for every serialized list and every receipt key run is
  catalog declaration order:
  `java-17, java-21, dotnet-10, dotnet-8, python, node, bun, maven,
  dotnet-ef, uv, shellcheck, gitleaks, pyyaml, openspec, superpowers,
  karpathy-ref, karpathy-sha256`
- **Never run the installer for real.** Use `--dry-run`. It mutates the
  machine otherwise.
- **Version bump policy:** bump a script's `SCRIPT_VERSION` in the same commit
  that changes its behaviour — patch for a fix, minor for a new flag or output
  field, major for a removal or breaking output change.
- **Integration:** `.repository-policy.yaml` declares `github-flow` and
  `integration: pull-request`. Work on a branch; open a PR at the end. Never
  commit parent-workspace files here.
- **Conventional commits:** `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`,
  `test:`.

## Full Test Command

Run all of this before every commit. All five suites are reported together.

```bash
bash -n environments/linux/install.sh
bash tests/install.sh
bash tests/repository-policy.sh
bash tests/wsl-toolchain-doctor.sh
bash tests/opencode-service.sh
bash models/routing/opencode/eval/run-tests.sh
shellcheck environments/linux/install.sh tests/install.sh \
  tests/repository-policy.sh repository-policy/validate.sh \
  wsl-toolchain-doctor/wsl-toolchain-doctor.sh tests/wsl-toolchain-doctor.sh \
  opencode-service/opencode-startup-ready.sh \
  opencode-service/opencode-gateway-restart.sh tests/opencode-service.sh
```

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `catalog/software-catalog.env` | create | the seventeen pinned values; data only, never sourced |
| `catalog/README.md` | create | the normative `adt-kv` grammar and how to bump a pin |
| `.gitattributes` | modify | add `*.env text eol=lf` |
| `environments/linux/install.sh` | modify | reader, validator, catalog wiring, input gate, receipt writer, `SCRIPT_VERSION`, `--version` |
| `wsl-toolchain-doctor/wsl-toolchain-doctor.sh` | modify | `SCRIPT_VERSION` 0.4.0, `--probe`, three seams, reader/validator copy, `TOOLKIT_` findings |
| `opencode-service/opencode-gateway-restart.sh` | modify | `SCRIPT_VERSION`, `--version` guard |
| `opencode-service/opencode-startup-ready.sh` | modify | `SCRIPT_VERSION`, `--version` guard |
| `repository-policy/validate.sh` | modify | `SCRIPT_VERSION`, `--version` arm |
| `tests/install.sh` | modify | harness seam, load-integrity gate, catalog/receipt/gate cases |
| `tests/wsl-toolchain-doctor.sh` | modify | seam pinning, version bump, `TOOLKIT_` cases |
| `tests/opencode-service.sh` | modify | version and no-argument cases |
| `tests/repository-policy.sh` | modify | version cases |
| `AGENTS.md` | modify | drop literal pins, add catalog + bump policy + harness note |
| `README.md` | modify | add `catalog/` to the layout |
| `docs/wsl-toolchain-doctor.md` | modify | version, sample JSON, `--probe`, `TOOLKIT_` findings |
| `wsl-toolchain-doctor/README.md` | modify | version, `--probe`, `TOOLKIT_` findings |

## Task Order and Why

Task 1 is independent and small — three scripts nobody else touches. Task 2 is
purely additive: the reader exists and is tested before anything depends on
it. Task 3 is the switch-over, and it is the risky one, which is why the
reader is already proven when it happens. Tasks 4–6 build on a working
catalog. Tasks 7–8 are the doctor, which needs the catalog and receipt formats
settled. Task 9 is documentation, last because it describes what the earlier
tasks actually built.

---

### Task 0: Branch

- [ ] **Step 1: Create the branch**

```bash
cd checkouts/agentic-dev-toolkit
git switch -c feat/software-catalog
git status --short   # expect: clean
```

---

### Task 1: Version the three simple scripts

**Files:**
- Modify: `repository-policy/validate.sh`
- Modify: `opencode-service/opencode-gateway-restart.sh`
- Modify: `opencode-service/opencode-startup-ready.sh`
- Test: `tests/repository-policy.sh`
- Test: `tests/opencode-service.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: `readonly SCRIPT_VERSION="0.1.0"` in each of the three scripts,
  and a `--version` flag on each that prints the bare version and exits 0.
  Later tasks use the same constant name in `install.sh` and the doctor.

- [ ] **Step 1: Write the failing policy-validator tests**

Append to `tests/repository-policy.sh`, before the invocation list at the
bottom:

```bash
test_validator_declares_and_prints_its_version() {
  grep -qE '^readonly SCRIPT_VERSION="[0-9]+\.[0-9]+\.[0-9]+"$' "$VALIDATOR" \
    || fail "validate.sh must declare a semantic SCRIPT_VERSION"

  local output status
  set +e
  output="$("$VALIDATOR" --version 2>&1)"
  status=$?
  set -e

  assert_equal "$status" "0" "--version must exit 0"
  assert_equal "$output" "0.1.0" "--version must print exactly the version"
}

test_validator_version_is_not_swallowed_by_the_unknown_option_arm() {
  local output
  output="$("$VALIDATOR" --version 2>&1)"
  [[ "$output" != *"unknown option"* ]] \
    || fail "--version must be matched before the generic -* arm"
}

test_validator_help_and_unknown_options_still_exit_2() {
  local status
  set +e
  "$VALIDATOR" --help >/dev/null 2>&1
  status=$?
  set -e
  assert_equal "$status" "2" "--help must keep exiting 2"

  set +e
  "$VALIDATOR" --nonsense >/dev/null 2>&1
  status=$?
  set -e
  assert_equal "$status" "2" "an unknown option must keep exiting 2"
}
```

Add the three names to the invocation list at the bottom of the file.

- [ ] **Step 2: Run to verify they fail**

Run: `bash tests/repository-policy.sh`
Expected: FAIL, `validate.sh must declare a semantic SCRIPT_VERSION`

- [ ] **Step 3: Implement in `repository-policy/validate.sh`**

Add near the other `readonly` declarations at the top:

```bash
readonly SCRIPT_VERSION="0.1.0"
```

In `main`'s `for argument in "$@"` loop, add this arm **before** the generic
`-*)` arm:

```bash
      --version)
        printf '%s\n' "$SCRIPT_VERSION"
        exit 0
        ;;
```

- [ ] **Step 4: Run to verify they pass**

Run: `bash tests/repository-policy.sh`
Expected: PASS

- [ ] **Step 5: Write the failing service-helper tests**

Append to `tests/opencode-service.sh`, before its invocation list:

```bash
test_service_helpers_declare_and_print_their_versions() {
  local script
  for script in "$CONSUMER" "$READY"; do
    grep -qE '^readonly SCRIPT_VERSION="[0-9]+\.[0-9]+\.[0-9]+"$' "$script" \
      || fail "$script must declare a semantic SCRIPT_VERSION"

    local output status
    set +e
    output="$(bash "$script" --version 2>&1)"
    status=$?
    set -e

    assert_equal "$status" "0" "$script --version must exit 0"
    assert_equal "$output" "0.1.0" "$script --version must print the version"
  done
}

test_service_helpers_survive_no_arguments_under_set_u() {
  # The systemd units invoke these with no arguments at all. The --version
  # guard must not dereference an unset $1, and its false path must not
  # terminate the script under set -e.
  local script output
  for script in "$CONSUMER" "$READY"; do
    output="$(bash "$script" 2>&1 || true)"
    [[ "$output" != *"unbound variable"* ]] \
      || fail "$script must not dereference an unset \$1"
    [[ "$output" != *"--version"* ]] \
      || fail "$script must not print version output with no arguments"
  done
}
```

Add both names to the invocation list.

- [ ] **Step 6: Run to verify they fail**

Run: `bash tests/opencode-service.sh`
Expected: FAIL, `must declare a semantic SCRIPT_VERSION`

- [ ] **Step 7: Implement in both service helpers**

In each of `opencode-service/opencode-gateway-restart.sh` and
`opencode-service/opencode-startup-ready.sh`, add after the `IFS` line:

```bash
readonly SCRIPT_VERSION="0.1.0"
```

Add this as the **first statement inside `main`** in each. An `if`, never
`[[ … ]] && …`: on the common no-argument path the `&&` list returns 1, and as
the first command of the function that would abort the helper under `set -e`.

```bash
  if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "$SCRIPT_VERSION"
    exit 0
  fi
```

Every other argument keeps today's behaviour of being ignored. Do not add a
parser.

- [ ] **Step 8: Run to verify they pass**

Run: `bash tests/opencode-service.sh`
Expected: PASS

- [ ] **Step 9: Run the full test command and commit**

```bash
git add repository-policy/validate.sh opencode-service/ tests/repository-policy.sh tests/opencode-service.sh
git commit -m "feat: version the policy validator and the service helpers"
```

---

### Task 2: The catalog file and the `adt-kv` reader and validator

Purely additive. The reader and validator exist and are tested; the installer
still uses its literal pins. Nothing changes behaviour yet, which is what
makes Task 3 safe.

**Files:**
- Create: `catalog/software-catalog.env`
- Create: `catalog/README.md`
- Modify: `.gitattributes`
- Modify: `environments/linux/install.sh` (add functions only)
- Test: `tests/install.sh`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `load_kv_file FILE VALUES LINES ORDER ERROR_VARIABLE` → 0 on success with
    the three arrays populated and the error scalar cleared; 1 on failure with
    the message in the error scalar. **Never call it in a subshell.**
  - `validate_kv FILE VALUES LINES ORDER REQUIRED LIST_KEYS MEMBERS` → `die`s
    on the first problem. `MEMBERS` empty means membership is not checked.
  - `declare -gA CATALOG CATALOG_LINES`, `declare -ga CATALOG_ORDER`,
    `CATALOG_ERROR` — globals later tasks read.
  - `catalog_value KEY` → prints the value, `die`s if absent.

- [ ] **Step 1: Create the catalog**

Create `catalog/software-catalog.env` with exactly the seventeen keys from the
spec's Catalog section, in catalog declaration order, values copied from the
current `install.sh` pin block:

```
# agentic-dev-toolkit software catalog - data only. Never sourced.
#
# Claude Code and Codex are deliberately absent: neither is pinned. install.sh
# installs @anthropic-ai/claude-code@latest and takes the Codex vendor script's
# own choice. Pinning them is a separate decision, not a catalog entry.
java-17=temurin-17
java-21=temurin-21
dotnet-10=10
dotnet-8=8
python=3.12
node=24
bun=1
maven=3.9.16
dotnet-ef=latest
uv=latest
shellcheck=latest
gitleaks=latest
pyyaml=latest
openspec=1.9.0
superpowers=v6.3.0
karpathy-ref=2c606141936f1eeef17fa3043a72095b4765b9c2
karpathy-sha256=6e22cc54cb02a5e98ae42d06d9d7292db0c1b43894831b32879beb0166b2aea7
```

Verify the values against the current source before committing:

```bash
sed -n '12,13p;33,50p' environments/linux/install.sh
```

- [ ] **Step 2: Add the `.gitattributes` rule**

Append to `.gitattributes`:

```
*.env text eol=lf
```

- [ ] **Step 3: Write the failing reader tests**

Add to `tests/install.sh`, before the invocation list. These call the reader
directly after the harness has sourced the body.

```bash
readonly CATALOG_FILE="$REPOSITORY_ROOT/catalog/software-catalog.env"

kv_fixture() {
  # kv_fixture NAME CONTENT  -> prints the fixture path
  local path="$TEMP_DIR/kv-$1.env"
  printf '%s' "$2" > "$path"
  printf '%s' "$path"
}

test_reader_loads_a_valid_file_in_source_order() {
  local -A values=() lines=()
  local -a order=()
  local err="sentinel"

  local path
  path="$(kv_fixture valid '# comment
alpha=1

beta=two
')"

  load_kv_file "$path" values lines order err \
    || fail "a valid file must load: $err"

  assert_equal "$err" "" "success must clear the caller error scalar"
  assert_equal "${values[alpha]}" "1" "alpha must load"
  assert_equal "${values[beta]}" "two" "beta must load"
  assert_equal "${lines[beta]}" "4" "beta must record its source line"
  assert_equal "${order[0]}" "alpha" "order must follow the source"
  assert_equal "${order[1]}" "beta" "order must follow the source"
}

test_reader_keeps_a_final_line_with_no_newline() {
  local -A values=() lines=()
  local -a order=()
  local err=""
  local path
  path="$(kv_fixture nonewline 'alpha=1')"

  load_kv_file "$path" values lines order err || fail "must load: $err"
  assert_equal "${values[alpha]}" "1" "an unterminated final line must survive"
}

test_reader_normalizes_crlf() {
  local -A values=() lines=()
  local -a order=()
  local err=""
  local path
  path="$(kv_fixture crlf $'alpha=1\r\nbeta=2\r\n')"

  load_kv_file "$path" values lines order err || fail "must load: $err"
  assert_equal "${values[alpha]}" "1" "CRLF must parse as LF"
  assert_equal "${values[beta]}" "2" "CRLF must parse as LF"
}

test_reader_reports_a_missing_separator_with_a_line_number() {
  local -A values=() lines=()
  local -a order=()
  local err=""
  local path
  path="$(kv_fixture nosep 'alpha=1
garbage
')"

  ! load_kv_file "$path" values lines order err \
    || fail "a line with no '=' must be rejected"
  [[ "$err" == *":2: missing '=' separator" ]] \
    || fail "the diagnostic must name file and line, got: $err"
}

test_reader_reports_a_duplicate_key_with_both_lines() {
  local -A values=() lines=()
  local -a order=()
  local err=""
  local path
  path="$(kv_fixture dup 'alpha=1
alpha=2
')"

  ! load_kv_file "$path" values lines order err \
    || fail "a duplicate key must be rejected"
  [[ "$err" == *":2: duplicate key: alpha (first seen at line 1)" ]] \
    || fail "the diagnostic must name both lines, got: $err"
}

test_reader_reports_an_unreadable_file() {
  local -A values=() lines=()
  local -a order=()
  local err=""

  ! load_kv_file "$TEMP_DIR/does-not-exist.env" values lines order err \
    || fail "a missing file must be rejected"
  [[ "$err" == "cannot read "* ]] || fail "unexpected diagnostic: $err"
}

test_shipped_catalog_satisfies_the_complete_schema() {
  # The fixtures could all pass while the file the installer actually loads
  # is broken. This is the case that notices.
  local -A values=() lines=()
  local -a order=()
  local err=""
  local -A no_lists=() no_members=()
  local -a required=(
    java-17 java-21 dotnet-10 dotnet-8 python node bun maven
    dotnet-ef uv shellcheck gitleaks pyyaml openspec superpowers
    karpathy-ref karpathy-sha256
  )

  load_kv_file "$CATALOG_FILE" values lines order err \
    || fail "the shipped catalog must load: $err"
  assert_equal "${#values[@]}" "17" "the catalog must carry seventeen keys"
  validate_kv "$CATALOG_FILE" values lines order required no_lists no_members
}
```

Add all seven names to the invocation list.

- [ ] **Step 4: Run to verify they fail**

Run: `bash tests/install.sh`
Expected: FAIL with `load_kv_file: command not found`

- [ ] **Step 5: Implement the reader**

Add to `environments/linux/install.sh`, among the function definitions and
**after** `die` is defined. Copy the normative body from the spec's
**Reader** subsection verbatim. Its shape:

```bash
declare -gA CATALOG=() CATALOG_LINES=()
declare -ga CATALOG_ORDER=()
CATALOG_ERROR=""

load_kv_file() {
  local file=$1
  # kv_* prefixes: a nameref whose identifier equals the caller's name is a
  # circular reference. No caller may pass kv_values, kv_lines, kv_order or
  # kv_errname.
  local -n kv_values=$2
  local -n kv_lines=$3
  local -n kv_order=$4
  local kv_errname=$5
  local line key value lineno=0

  printf -v "$kv_errname" '%s' ''

  if [[ ! -r "$file" ]]; then
    printf -v "$kv_errname" '%s' "cannot read $file"
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$(( lineno + 1 ))
    line="${line%$'\r'}"
    if [[ -z "${line//[[:space:]]/}" || "${line#"${line%%[![:space:]]*}"}" == '#'* ]]; then
      continue
    fi
    if [[ "$line" != *=* ]]; then
      printf -v "$kv_errname" '%s' "$file:$lineno: missing '=' separator"
      return 1
    fi
    key="${line%%=*}"
    value="${line#*=}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ ! "$key" =~ ^[a-z0-9][a-z0-9.-]*$ ]]; then
      printf -v "$kv_errname" '%s' "$file:$lineno: malformed key: $key"
      return 1
    fi
    if [[ -n "${kv_values[$key]+set}" ]]; then
      printf -v "$kv_errname" '%s' \
        "$file:$lineno: duplicate key: $key (first seen at line ${kv_lines[$key]})"
      return 1
    fi
    kv_values["$key"]="$value"
    kv_lines["$key"]="$lineno"
    kv_order+=("$key")
  done < "$file"
}
```

**No nested helper.** The error write is inlined at each of the four
rejection sites. A `fail()` defined here would be global and would replace
the test harness's assertion helper.

- [ ] **Step 6: Run to verify the reader tests pass**

Run: `bash tests/install.sh`
Expected: FAIL only on `validate_kv: command not found` in the last test.

- [ ] **Step 7: Write the failing validator tests**

Add to `tests/install.sh`:

```bash
test_validator_rejects_a_missing_required_key_without_a_line_number() {
  local -A values=([alpha]=1) lines=([alpha]=1)
  local -a order=(alpha)
  local -a required=(alpha beta gamma)
  local -A no_lists=() no_members=()
  local output

  output="$( ( validate_kv f values lines order required no_lists no_members ) 2>&1 || true )"
  [[ "$output" == *"f: missing required key: beta"* ]] \
    || fail "must report the FIRST missing key, with no line: $output"
  [[ "$output" != *"gamma"* ]] || fail "must stop at the first missing key"
}

test_validator_rejects_an_empty_and_a_malformed_scalar_with_line_numbers() {
  local -A values=([alpha]="") lines=([alpha]=7)
  local -a order=(alpha)
  local -a required=()
  local -A no_lists=() no_members=()
  local output

  output="$( ( validate_kv f values lines order required no_lists no_members ) 2>&1 || true )"
  [[ "$output" == *"f:7: empty value for key: alpha"* ]] \
    || fail "unexpected empty-value diagnostic: $output"

  values[alpha]="has space"
  output="$( ( validate_kv f values lines order required no_lists no_members ) 2>&1 || true )"
  [[ "$output" == *"f:7: malformed value for key: alpha"* ]] \
    || fail "unexpected malformed-value diagnostic: $output"
}

test_validator_enforces_list_syntax_duplicates_and_membership() {
  local -A values=() lines=([skipped]=3)
  local -a order=(skipped)
  local -a required=()
  local -A lists=([skipped]=1)
  local -A members=([node]=1 [python]=1)
  local -A empty_members=()
  local output

  values[skipped]=""
  validate_kv f values lines order required lists members \
    || fail "an empty list must be valid"

  values[skipped]="node,python"
  validate_kv f values lines order required lists members \
    || fail "a valid list must pass"

  local bad
  for bad in ",node" "node," "node,,python"; do
    values[skipped]="$bad"
    output="$( ( validate_kv f values lines order required lists members ) 2>&1 || true )"
    [[ "$output" == *"f:3: malformed list for key: skipped"* ]] \
      || fail "'$bad' must be rejected as malformed: $output"
  done

  values[skipped]="node,node"
  output="$( ( validate_kv f values lines order required lists members ) 2>&1 || true )"
  [[ "$output" == *"f:3: duplicate element in skipped: node"* ]] \
    || fail "a duplicate element must be rejected: $output"

  values[skipped]="node,nonsense"
  output="$( ( validate_kv f values lines order required lists members ) 2>&1 || true )"
  [[ "$output" == *"f:3: unknown catalog key in skipped: nonsense"* ]] \
    || fail "an unknown member must be rejected: $output"

  # With no catalog in hand, syntax and duplicates still apply, membership
  # does not. This is the doctor's standalone case.
  values[skipped]="node,nonsense"
  validate_kv f values lines order required lists empty_members \
    || fail "membership must be skipped when the member set is empty"

  values[skipped]="node,node"
  output="$( ( validate_kv f values lines order required lists empty_members ) 2>&1 || true )"
  [[ "$output" == *"duplicate element"* ]] \
    || fail "duplicates must still be caught without a member set: $output"
}

test_validator_reports_the_first_defect_in_source_order() {
  # Two defects, and the answer must not move between runs.
  local -A values=([alpha]="bad value" [beta]="also bad") lines=([alpha]=2 [beta]=9)
  local -a order=(alpha beta)
  local -a required=()
  local -A no_lists=() no_members=()
  local first run

  for run in 1 2 3; do
    first="$( ( validate_kv f values lines order required no_lists no_members ) 2>&1 || true )"
    [[ "$first" == *"f:2: malformed value for key: alpha"* ]] \
      || fail "run $run must report the earliest line, got: $first"
  done
}
```

Add the four names to the invocation list.

- [ ] **Step 8: Run to verify they fail**

Run: `bash tests/install.sh`
Expected: FAIL with `validate_kv: command not found`

- [ ] **Step 9: Implement the validator and `catalog_value`**

Add to `environments/linux/install.sh` after `load_kv_file`. Copy the
normative body from the spec's **Validator** subsection verbatim; its shape:

```bash
validate_kv() {
  local file=$1
  local -n v_values=$2 v_lines=$3 v_order=$4
  local -n v_required=$5 v_listkeys=$6 v_members=$7
  local key value element
  local -a elements
  local -A seen

  for key in "${v_required[@]}"; do
    if [[ -z "${v_values[$key]+set}" ]]; then
      die "$file: missing required key: $key"
    fi
  done

  for key in "${v_order[@]}"; do
    value="${v_values[$key]}"

    if [[ -n "${v_listkeys[$key]+set}" ]]; then
      if [[ -z "$value" ]]; then
        continue
      fi
      if [[ ! "$value" =~ ^[a-z0-9][a-z0-9.-]*(,[a-z0-9][a-z0-9.-]*)*$ ]]; then
        die "$file:${v_lines[$key]}: malformed list for key: $key"
      fi
      IFS=, read -ra elements <<<"$value"
      seen=()
      for element in "${elements[@]}"; do
        if [[ -n "${seen[$element]+set}" ]]; then
          die "$file:${v_lines[$key]}: duplicate element in $key: $element"
        fi
        seen["$element"]=1
        if (( ${#v_members[@]} > 0 )) && [[ -z "${v_members[$element]+set}" ]]; then
          die "$file:${v_lines[$key]}: unknown catalog key in $key: $element"
        fi
      done
      continue
    fi

    if [[ -z "$value" ]]; then
      die "$file:${v_lines[$key]}: empty value for key: $key"
    fi
    if [[ ! "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._:+@/-]*$ ]]; then
      die "$file:${v_lines[$key]}: malformed value for key: $key"
    fi
  done
}

catalog_value() {
  printf '%s' "${CATALOG[$1]:?missing catalog key: $1}"
}
```

Every branch is an `if`; every arithmetic test sits inside an `if` condition.
Nothing on the success path returns non-zero.

- [ ] **Step 10: Run to verify they pass**

Run: `bash tests/install.sh`
Expected: PASS

- [ ] **Step 11: Write `catalog/README.md`**

Six sections, per the spec's `catalog/README.md` subsection: what the catalog
is and which components it pins; the normative `adt-kv` grammar; that these
files are never sourced and why the value grammar enforces it; how to bump a
pin, including that `karpathy-ref` and `karpathy-sha256` move together; what a
reader must validate and the diagnostic contract; and that `install.sh`
requires the catalog and ships with it as a bundle. Do not restate the
receipt design or the doctor comparisons.

- [ ] **Step 12: Run the full test command and commit**

```bash
git add catalog/ .gitattributes environments/linux/install.sh tests/install.sh
git commit -m "feat: add the software catalog and its adt-kv reader"
```

---

### Task 3: Switch the pins to the catalog

The risky task, done with a proven reader. Reorders the installer's
top-level, renames the root variable, changes the test harness, and adds the
load-integrity gate.

**Files:**
- Modify: `environments/linux/install.sh`
- Modify: `tests/install.sh`

**Interfaces:**
- Consumes: `load_kv_file`, `validate_kv`, `catalog_value` from Task 2.
- Produces: `ADT_INSTALL_ROOT`, `ADT_CATALOG_FILE`, `readonly SCRIPT_VERSION="0.1.0"`,
  and the sixteen pin globals now sourced from the catalog. `CATALOG` and
  `CATALOG_ORDER` are populated and globally visible after the harness's
  loader returns.

- [ ] **Step 1: Change the harness to set the seam**

In `tests/install.sh`, inside `load_installer_functions`, **before** the
`source`:

```bash
  ADT_CATALOG_FILE="${ADT_CATALOG_FILE:-$REPOSITORY_ROOT/catalog/software-catalog.env}"
  export ADT_CATALOG_FILE
```

Without this every test fails at load: inside the copied body
`${BASH_SOURCE[0]}` is `$TEMP_DIR/install-functions.sh`, so `../..` resolves
into the system temporary tree, not the repository.

- [ ] **Step 2: Add the load-integrity gate to the harness**

In `tests/install.sh`, replace the bare `load_installer_functions` call at the
bottom with the bracketed sequence. Copy it from the spec's **load-integrity
gate** subsection. Its shape — and note that **every check reports with
`printf`/`exit`, never `fail` or `assert_equal`**, because `fail` is the thing
being verified:

```bash
fail_body_before="$(declare -f fail)"
functions_before="$(declare -F | awk '{ print $3 }' | sort)"

load_installer_functions

fail_body_after="$(declare -f fail)"
functions_after="$(declare -F | awk '{ print $3 }' | sort)"

if [[ "$fail_body_after" != "$fail_body_before" ]]; then
  printf 'FAIL: installer loading replaced the test harness fail helper\n' >&2
  exit 1
fi

marker="$TEMP_DIR/fail-fell-through"
set +e
output="$(
  (
    fail "sentinel failure"
    : > "$marker"
  ) 2>&1
)"
status=$?
set -e

if (( status == 0 )); then
  printf 'FAIL: test harness fail helper returned success\n' >&2
  exit 1
fi
if [[ "$output" != FAIL:\ sentinel\ failure* ]]; then
  printf 'FAIL: test harness fail helper lost its diagnostic contract\n' >&2
  exit 1
fi
if [[ -e "$marker" ]]; then
  printf 'FAIL: execution continued after test harness fail helper\n' >&2
  exit 1
fi

if (( ${#CATALOG[@]} == 0 )); then
  printf 'FAIL: catalog values did not survive installer loading\n' >&2
  exit 1
fi
if (( ${#CATALOG_ORDER[@]} == 0 )); then
  printf 'FAIL: catalog order did not survive installer loading\n' >&2
  exit 1
fi

expected_new="$(grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$INSTALLER" |
  tr -d '()' | sort -u)"
actual_new="$(comm -13 \
  <(printf '%s\n' "$functions_before") \
  <(printf '%s\n' "$functions_after"))"
unexpected="$(comm -23 \
  <(printf '%s\n' "$actual_new") \
  <(printf '%s\n' "$expected_new"))"
if [[ -n "$unexpected" ]]; then
  printf 'FAIL: installer loading leaked unexpected function(s): %s\n' \
    "$unexpected" >&2
  exit 1
fi
```

The snapshots bracket the **existing single call**. Do not add a second
`load_installer_functions` anywhere — a second source fails with
`readonly variable`.

- [ ] **Step 3: Run to verify the gate fails**

Run: `bash tests/install.sh`
Expected: FAIL, `catalog values did not survive installer loading` — the
installer does not load a catalog yet.

- [ ] **Step 4: Reorder the installer's top level**

In `environments/linux/install.sh`:

1. Keep `SCRIPT_NAME` and the six upstream source constants where they are.
2. Add `readonly SCRIPT_VERSION="0.1.0"` beside them.
3. **Move the diagnostics and traps up**: `log`, `info`, `warn`, `die`,
   `quote_command`, `run`, `run_sudo`, `cleanup`, `on_error`, and both
   `trap` lines must now precede root resolution. `TEMP_PATHS=()` and
   `DOWNLOADED_INSTALLER=""` must precede the `cleanup` trap.
4. Then resolve the root, **two levels up**, guarded:

```bash
ADT_INSTALL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)" ||
  die "cannot resolve the toolkit root from ${BASH_SOURCE[0]}"
readonly ADT_INSTALL_ROOT
ADT_CATALOG_FILE="${ADT_CATALOG_FILE:-$ADT_INSTALL_ROOT/catalog/software-catalog.env}"
```

**The name must not be `REPOSITORY_ROOT`.** `tests/install.sh` declares
`REPOSITORY_ROOT`, `INSTALLER` and `CLAUDE_TEMPLATE` as `readonly` and sources
the body into that shell; a top-level `REPOSITORY_ROOT=` assignment fails with
`readonly variable` and aborts the whole suite.

- [ ] **Step 5: Load and validate the catalog at top level**

After the reader and validator definitions, before the pin assignments:

```bash
if ! load_kv_file "$ADT_CATALOG_FILE" CATALOG CATALOG_LINES CATALOG_ORDER CATALOG_ERROR; then
  die "$CATALOG_ERROR"
fi

CATALOG_REQUIRED=(
  java-17 java-21 dotnet-10 dotnet-8 python node bun maven
  dotnet-ef uv shellcheck gitleaks pyyaml openspec superpowers
  karpathy-ref karpathy-sha256
)
declare -gA CATALOG_NO_LISTS=() CATALOG_NO_MEMBERS=()
validate_kv "$ADT_CATALOG_FILE" CATALOG CATALOG_LINES CATALOG_ORDER \
  CATALOG_REQUIRED CATALOG_NO_LISTS CATALOG_NO_MEMBERS
```

Call it directly. Never wrap it in `$( )`, a pipeline or a subshell — the
arrays are populated through namerefs and would die with the subshell.

- [ ] **Step 6: Rewire the sixteen pins**

Replace each literal default with a catalog lookup, keeping the precedence
expression identical in shape:

```bash
JAVA_17_VERSION="${ADT_JAVA_17_VERSION:-$(catalog_value java-17)}"
JAVA_21_VERSION="${ADT_JAVA_21_VERSION:-$(catalog_value java-21)}"
DOTNET_10_VERSION="${ADT_DOTNET_10_VERSION:-$(catalog_value dotnet-10)}"
DOTNET_8_VERSION="${ADT_DOTNET_8_VERSION:-$(catalog_value dotnet-8)}"
PYTHON_VERSION="${ADT_PYTHON_VERSION:-$(catalog_value python)}"
NODE_VERSION="${ADT_NODE_VERSION:-$(catalog_value node)}"
BUN_VERSION="${ADT_BUN_VERSION:-$(catalog_value bun)}"
MAVEN_VERSION="${ADT_MAVEN_VERSION:-$(catalog_value maven)}"
DOTNET_EF_VERSION="${ADT_DOTNET_EF_VERSION:-$(catalog_value dotnet-ef)}"
UV_VERSION="${ADT_UV_VERSION:-$(catalog_value uv)}"
SHELLCHECK_VERSION="${ADT_SHELLCHECK_VERSION:-$(catalog_value shellcheck)}"
GITLEAKS_VERSION="${ADT_GITLEAKS_VERSION:-$(catalog_value gitleaks)}"
PYYAML_VERSION="${ADT_PYYAML_VERSION:-$(catalog_value pyyaml)}"
OPENSPEC_VERSION="${ADT_OPENSPEC_VERSION:-$(catalog_value openspec)}"
SUPERPOWERS_REF="${ADT_SUPERPOWERS_REF:-$(catalog_value superpowers)}"

KARPATHY_DEFAULT_REF="$(catalog_value karpathy-ref)"
readonly KARPATHY_DEFAULT_REF
KARPATHY_DEFAULT_SHA256="$(catalog_value karpathy-sha256)"
readonly KARPATHY_DEFAULT_SHA256
KARPATHY_REF="${ADT_KARPATHY_REF:-$KARPATHY_DEFAULT_REF}"
KARPATHY_SHA256="${ADT_KARPATHY_SHA256:-}"
```

**The Karpathy mapping is asymmetric and the asymmetry is the point.** The
catalog digest supplies `KARPATHY_DEFAULT_SHA256` only. `KARPATHY_SHA256` —
the user override — still defaults to **empty**. If the catalog digest became
its default, a custom ref would silently acquire a digest belonging to a
different artefact and the `requires --karpathy-sha256` refusal would never
fire. Delete the old `readonly KARPATHY_DEFAULT_*` literals at lines 12-13.

`OPENSPEC_TOOLS`, `GCM_WINDOWS_PATH` and the rest keep their current form.

- [ ] **Step 7: Retarget the three source-greps**

In `tests/install.sh`, `test_mise_configuration_pins_bun` and
`test_installer_defaults_python_to_312` grep the **installer** for literal
defaults. Point them at the catalog, carrying their comments across — they
exist because `BUN_VERSION` and `PYTHON_VERSION` are globals earlier tests
reassign, so a rendered-output check would pass on inherited state. That
reasoning survives the move.

```bash
  grep -qxE 'bun=1' "$CATALOG_FILE" \
    || fail "the catalog must default bun to the 1 major"
```

```bash
  grep -qxE 'python=3\.12' "$CATALOG_FILE" \
    || fail "the catalog must default python to 3.12"
  grep -qxE 'dotnet-ef=latest' "$CATALOG_FILE" \
    || fail "the catalog must default dotnet-ef to latest"
```

- [ ] **Step 8: Add the catalog-failure tests**

These run the installer as a **program**, not by sourcing:

```bash
run_installer_with_catalog() {
  # run_installer_with_catalog CONTENT -> prints combined output, never fails
  local path="$TEMP_DIR/bad-catalog.env"
  printf '%s' "$1" > "$path"
  ADT_CATALOG_FILE="$path" bash "$INSTALLER" --dry-run 2>&1 || true
}

test_installer_dies_on_a_missing_catalog() {
  local output
  output="$(ADT_CATALOG_FILE="$TEMP_DIR/absent.env" bash "$INSTALLER" --dry-run 2>&1 || true)"
  [[ "$output" == *"cannot read "* ]] || fail "unexpected output: $output"
}

test_installer_dies_on_a_malformed_catalog_key() {
  local output
  output="$(run_installer_with_catalog 'Bad Key=1
')"
  [[ "$output" == *":1: malformed key: Bad Key"* ]] || fail "unexpected: $output"
}

test_installer_dies_on_a_missing_required_catalog_key() {
  local output
  output="$(run_installer_with_catalog 'java-17=temurin-17
')"
  [[ "$output" == *"missing required key: java-21"* ]] || fail "unexpected: $output"
}
```

Add the three names to the invocation list.

- [ ] **Step 9: Run the suite**

Run: `bash tests/install.sh`
Expected: PASS, including the load-integrity gate.

- [ ] **Step 10: Prove the precedence still holds**

```bash
ADT_CATALOG_FILE=catalog/software-catalog.env bash environments/linux/install.sh --dry-run --skip-runtimes --skip-opencode --skip-claude --skip-codex --skip-openspec --skip-superpowers --skip-karpathy --skip-git-credential 2>&1 | head -20
```

Expected: the dry-run banner, no errors, and no attempt to install anything.

- [ ] **Step 11: Run the full test command and commit**

```bash
git add environments/linux/install.sh tests/install.sh
git commit -m "refactor: source the installer pins from the software catalog"
```

---

### Task 4: `install.sh --version` and the effective requested-value gate

**Files:**
- Modify: `environments/linux/install.sh`
- Test: `tests/install.sh`

**Interfaces:**
- Consumes: `catalog_value`, `die`, `SCRIPT_VERSION` from Tasks 2 and 3.
- Produces: `validate_requested_values`, called from `main` between
  `parse_args` and `validate_environment`. Records each value's source layer
  for its diagnostics.

- [ ] **Step 1: Write the failing tests**

```bash
test_installer_version_flag() {
  local output status
  set +e
  output="$(bash "$INSTALLER" --version 2>&1)"
  status=$?
  set -e
  assert_equal "$status" "0" "--version must exit 0"
  assert_equal "$output" "0.1.0" "--version must print exactly the version"
  [[ "$output" != *"Unknown option"* ]] \
    || fail "--version must be parsed before the generic unknown-option arm"
}

test_installer_version_flag_performs_no_installation() {
  local output
  output="$(bash "$INSTALLER" --version 2>&1)"
  [[ "$output" != *"=="* ]] || fail "--version must print no installation log"
}

test_installer_rejects_an_ungrammatical_override() {
  local output bad
  for bad in "24,25" "24 25" "24[0]" ; do
    output="$(bash "$INSTALLER" --node-version="$bad" --dry-run 2>&1 || true)"
    [[ "$output" == *"invalid value for 'node' from --node-version"* ]] \
      || fail "'$bad' must be rejected naming key and source, got: $output"
  done
}

test_installer_rejects_an_empty_inline_override() {
  local output
  output="$(bash "$INSTALLER" --node-version= --dry-run 2>&1 || true)"
  [[ "$output" == *"requires a value"* ]] \
    || fail "an empty inline value must be refused, got: $output"
}

test_installer_rejects_an_ungrammatical_environment_override() {
  local output
  output="$(ADT_MAVEN_VERSION='3.9.16 (rc)' bash "$INSTALLER" --dry-run 2>&1 || true)"
  [[ "$output" == *"invalid value for 'maven' from ADT_MAVEN_VERSION"* ]] \
    || fail "unexpected: $output"
}

test_an_invalid_override_installs_nothing() {
  local output
  output="$(bash "$INSTALLER" --node-version="24,25" --dry-run 2>&1 || true)"
  [[ "$output" != *"Configuring mise runtimes"* ]] \
    || fail "installation must not begin when an input is invalid"
}
```

Add the six names to the invocation list.

- [ ] **Step 2: Run to verify they fail**

Run: `bash tests/install.sh`
Expected: FAIL, `--version must exit 0` (it currently dies as an unknown option)

- [ ] **Step 3: Add the `--version` arm**

In `parse_args`, **before** the generic `*) die "Unknown option: $1"` arm:

```bash
      --version)
        printf '%s\n' "$SCRIPT_VERSION"
        exit 0
        ;;
```

`--version` exits from inside `parse_args`, so it never reaches the gate
added below. That is why the gate is a call in `main` and not a check inside
the parser.

- [ ] **Step 4: Reject empty inline values**

Every `--flag=*` arm currently assigns `${1#*=}` with no check. Add an
emptiness check to each so an empty inline value dies with the same message
the separate form produces, rather than falling through to the catalog. For
example:

```bash
      --node-version=*)
        NODE_VERSION="${1#*=}"
        [[ -n "$NODE_VERSION" ]] || die "--node-version requires a value"
        ;;
```

Apply to all fourteen `=`-form arms that carry a catalog-derived value.

- [ ] **Step 5: Implement the gate**

```bash
validate_requested_values() {
  local key value source
  for key in "${CATALOG_ORDER[@]}"; do
    [[ "$key" != "karpathy-sha256" ]] || continue
    value="$(requested_value_for "$key")"
    source="$(requested_source_for "$key")"
    if [[ -z "$value" ]]; then
      die "invalid value for '$key' from $source: empty"
    fi
    if [[ ! "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._:+@/-]*$ ]]; then
      die "invalid value for '$key' from $source: '$value'"
    fi
  done
}
```

`requested_value_for` and `requested_source_for` read the same per-key
bookkeeping that feeds `OVERRIDDEN_SET` in Task 5 — a `declare -gA
REQUESTED_VALUE` and `declare -gA REQUESTED_SOURCE` populated at steps 5 and 6
of the lifecycle, where `REQUESTED_SOURCE` holds one of `the catalog`,
`ADT_<NAME>` or `--<flag>`.

`karpathy-sha256` is skipped: it is not a `requested.*` value, defaults to
empty by design, and `install_karpathy_skill` already holds it to
`^[0-9a-f]{64}$`.

- [ ] **Step 6: Call it from `main`**

```bash
  parse_args "$@"
  validate_requested_values
  validate_environment
```

Between those two because `parse_args` is the last thing that can change an
effective value and `validate_environment` is the first thing that inspects
the machine.

- [ ] **Step 7: Run to verify they pass**

Run: `bash tests/install.sh`
Expected: PASS

- [ ] **Step 8: Run the full test command and commit**

```bash
git add environments/linux/install.sh tests/install.sh
git commit -m "feat: validate every effective requested value before installing"
```

---

### Task 5: The install receipt

**Files:**
- Modify: `environments/linux/install.sh`
- Test: `tests/install.sh`

**Interfaces:**
- Consumes: `CATALOG_ORDER`, `REQUESTED_VALUE`, `REQUESTED_SOURCE`,
  `catalog_value`, the `SKIP_*` flags.
- Produces: `declare -gA OVERRIDDEN_SET`, `skipped_keys`,
  `write_install_receipt`, and a receipt at
  `${XDG_STATE_HOME:-$HOME/.local/state}/agentic-dev-toolkit/install-receipt.env`.

- [ ] **Step 1: Write the failing override-set tests**

```bash
test_overridden_is_a_set_not_an_append_log() {
  # Both layers name node. One member, never node,node.
  local receipt
  receipt="$(receipt_from_dry_run ADT_NODE_VERSION=22 -- --node-version 23)"
  [[ "$receipt" == *$'\noverridden=node\n'* ]] \
    || fail "both layers naming node must yield one member: $receipt"
  [[ "$receipt" != *"node,node"* ]] || fail "a duplicate member must never be written"
  [[ "$receipt" == *$'\nrequested.node=23\n'* ]] \
    || fail "the CLI must win for the effective value"
}

test_overridden_serializes_in_catalog_order() {
  local receipt
  receipt="$(receipt_from_dry_run -- --node-version 22 --python-version 3.11)"
  [[ "$receipt" == *$'\noverridden=python,node\n'* ]] \
    || fail "members must serialize in catalog order: $receipt"
}

test_an_empty_environment_override_is_not_an_override() {
  local receipt
  receipt="$(receipt_from_dry_run ADT_NODE_VERSION= --)"
  [[ "$receipt" == *$'\noverridden=\n'* ]] \
    || fail "an empty ADT_* must not be recorded: $receipt"
  [[ "$receipt" == *$'\nrequested.node=24\n'* ]] \
    || fail "an empty ADT_* must fall through to the catalog"
}

test_excluded_interfaces_never_enter_overridden() {
  local receipt
  receipt="$(receipt_from_dry_run ADT_OPENSPEC_TOOLS=claude ADT_GCM_PATH=/tmp/x -- --skip-claude --upgrade)"
  [[ "$receipt" == *$'\noverridden=\n'* ]] \
    || fail "non-catalog interfaces must not be recorded: $receipt"
}
```

`receipt_from_dry_run` is a helper you add to the suite: it runs the installer
with `XDG_STATE_HOME` pointed at `$TEMP_DIR`, with the given environment
assignments before `--`, the given flags after it, and `--skip-*` for
everything that would touch the machine, then prints the written receipt.

- [ ] **Step 2: Run to verify they fail**

Run: `bash tests/install.sh`
Expected: FAIL — no receipt is written yet.

- [ ] **Step 3: Implement the override set**

```bash
declare -gA OVERRIDDEN_SET=()
```

At step 5 of the lifecycle, for each catalog-derived component:

```bash
if [[ -n "${ADT_NODE_VERSION:-}" ]]; then
  OVERRIDDEN_SET[node]=1
fi
```

An `if`, not `[[ … ]] && …`: on the common path the variable is unset, the
`&&` list returns 1, and as the function's last command that propagates under
`set -e`.

In each catalog-derived `parse_args` arm, mark the same member —
`OVERRIDDEN_SET[node]=1` — which is idempotent. **Only the sixteen allowlisted
interfaces mark a member.** Not `ADT_OPENSPEC_TOOLS`, not `ADT_GCM_PATH` or
`--gcm-path`, not `ADT_KARPATHY_SHA256` or `--karpathy-sha256`, not
`--project`, `--repair-codex`, `--remove-apt-node`, any `--skip-*`, or any
operational flag. The full table is in the spec's **The allowlist**.

Repeated version flags are last-value-wins, matching today's parser; the
member is still marked once.

- [ ] **Step 4: Implement skip expansion**

```bash
skipped_keys() {
  local -A skipped=()
  local key
  if (( SKIP_RUNTIMES == 1 )); then
    for key in java-17 java-21 dotnet-10 dotnet-8 python node bun maven dotnet-ef uv; do
      skipped["$key"]=1
    done
  fi
  if (( SKIP_RUNTIMES == 1 || SKIP_QUALITY_TOOLS == 1 )); then
    for key in shellcheck gitleaks pyyaml; do
      skipped["$key"]=1
    done
  fi
  (( SKIP_OPENSPEC == 0 ))    || skipped[openspec]=1
  (( SKIP_SUPERPOWERS == 0 )) || skipped[superpowers]=1
  (( SKIP_KARPATHY == 0 ))    || skipped["karpathy-ref"]=1

  serialize_catalog_set skipped
}
```

`--skip-runtimes` includes the quality tools because three separate gates
produce that effect: `configure_runtimes` returns early, so the mise config
including `shellcheck`/`gitleaks` is never written, and
`install_python_quality_libraries` gates on either flag. `--skip-opencode`,
`--skip-claude`, `--skip-codex` and `--skip-git-credential` contribute
nothing — those components have no catalog key.

- [ ] **Step 5: Implement canonical serialization**

```bash
serialize_catalog_set() {
  local -n s_set=$1
  local key out=""
  for key in "${CATALOG_ORDER[@]}"; do
    if [[ -n "${s_set[$key]+set}" ]]; then
      out="${out:+$out,}$key"
    fi
  done
  printf '%s' "$out"
}
```

Walks catalog order, never the set's hash order. `${out:+$out,}` builds the
list with no leading comma.

- [ ] **Step 6: Implement the receipt writer**

Follow the spec's **Writing it** subsection. The shape:

```bash
write_install_receipt() {
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/agentic-dev-toolkit"
  local receipt="$state_dir/install-receipt.env"
  local tmp

  if (( DRY_RUN == 1 )); then
    info "Would write the install receipt to $receipt"
    return 0
  fi

  mkdir -p "$state_dir"
  chmod 0755 "$state_dir"
  tmp="$(mktemp "$state_dir/.install-receipt.XXXXXX")"
  TEMP_PATHS+=("$tmp")
  write_receipt_body > "$tmp"
  chmod 0644 "$tmp"
  mv -f "$tmp" "$receipt"
}
```

Modes are set explicitly so the result is deterministic under `umask 077` as
well as `022`. `mktemp` inside `$state_dir` makes `mv` a same-directory
rename, so a reader sees the old receipt or the new one, never a partial file.
The temporary path joins `TEMP_PATHS` so the existing `cleanup` trap removes
it if the run dies mid-write.

`write_receipt_body` emits, in this order: `script-version`, `installed-at`
(`date -u +%Y-%m-%dT%H:%M:%SZ`), `source-commit` (full 40-character SHA from
`git -C "$ADT_INSTALL_ROOT" rev-parse HEAD`, `-dirty` appended when
`git status --porcelain` produces output, `unknown` outside a checkout),
`catalog-sha256`, `skipped`, `overridden`, then all sixteen `requested.*` in
catalog order, then the `installed.*` keys in catalog order.

- [ ] **Step 7: Implement bounded, guarded, skip-aware probes**

Per the spec's **installer probe contract**. Three rules:

```bash
probe_timeout_bin=""
if ! probe_timeout_bin="$(command -v timeout 2>/dev/null)"; then
  warn "timeout is unavailable; no installed versions will be recorded."
fi
```

- **Skipped components are never probed** — no probe, no key, **no warning**.
  For the shared `dotnet --list-sdks`, run it only if at least one of its two
  components is unskipped, and emit values only for those.
- **Every probe is guarded** so an expected failure cannot trip `errexit` or
  the `ERR` trap:

```bash
  if output="$("$probe_timeout_bin" 10s "$MISE_BIN" exec -- node --version 2>/dev/null)"; then
    candidate="${output%%$'\n'*}"
    candidate="${candidate#v}"
    candidate="${candidate%%[[:space:]]*}"
    if [[ "$candidate" =~ ^[A-Za-z0-9][A-Za-z0-9._:+@/-]*$ ]]; then
      printf 'installed.node=%s\n' "$candidate"
    else
      warn "Could not record installed version for node."
    fi
  else
    warn "Could not record installed version for node."
  fi
```

Every extraction yields **one whitespace-delimited token**, never a line —
that is what keeps banners, `(…)` build metadata and `[/path]` SDK paths out.
The full per-component extraction table is in the spec.

- **If `timeout` could not be resolved**, skip all **probe-derived** capture
  with the one aggregate warning already emitted, run nothing unbounded, and
  still write the receipt. `installed.karpathy-sha256` is **still written**
  when Karpathy was installed: it is zero-invocation provenance, already
  computed and verified before the file was written.

- [ ] **Step 8: Place the call in `main`**

```bash
  verify_installation
  write_install_receipt
  print_summary
```

Between them, so the receipt follows successful verification and the summary
follows successful persistence — a write failure is an installation failure
under the `ERR` trap, not a warning after "Setup complete".
`--verify-only` returns from `main` before the install sequence and never
reaches it.

- [ ] **Step 9: Write the remaining receipt tests**

Cases, all from the spec's testing section: written on success at the
documented path; **not** written on `--dry-run`, `--verify-only` or after a
failure; written atomically with no surviving `.install-receipt.*`; modes
`0644`/`0755` under both umasks; exactly sixteen `requested.*` keys with
`requested.karpathy-sha256` never written; a selective run
(`--skip-runtimes --skip-openspec --skip-karpathy`) still writing all sixteen;
`skipped=` holding expanded catalog keys with `--skip-runtimes` covering the
quality tools; `--skip-claude` alone leaving `skipped=` empty; a skipped
component producing **no** probe and **no** warning; a failing probe not
tripping `ERR`; an unresolvable `timeout` keeping
`installed.karpathy-sha256` while dropping every probe-derived key; and the
written receipt passing `validate_kv` with the receipt's own required set and
`MEMBERS` set to `CATALOG`.

- [ ] **Step 10: Run to verify they pass**

Run: `bash tests/install.sh`
Expected: PASS

- [ ] **Step 11: Run the full test command and commit**

```bash
git add environments/linux/install.sh tests/install.sh
git commit -m "feat: write an install receipt after a verified installation"
```

---

### Task 6: Doctor — version, `--probe`, and the seams

**Files:**
- Modify: `wsl-toolchain-doctor/wsl-toolchain-doctor.sh`
- Test: `tests/wsl-toolchain-doctor.sh`

**Interfaces:**
- Consumes: the `adt-kv` reader and validator (a copy, adapted to report
  rather than `die`), the catalog and receipt formats.
- Produces: `SCRIPT_VERSION="0.4.0"`, `PROBE_MODE`, `parse_audit_args`,
  `openspec_bin()`, `timeout_bin()`, and the seams `WTD_CATALOG_FILE`,
  `WTD_RECEIPT_FILE`, `WTD_MISE_TOOLCHAIN_CONFIG`, `WTD_OPENSPEC_BIN`,
  `WTD_TIMEOUT_BIN`.

- [ ] **Step 1: Update the version tests**

In `tests/wsl-toolchain-doctor.sh`, change the two hardcoded expectations
from `0.3.0` to `0.4.0` — the JSON assertion `'"toolVersion":"0.4.0"'` and
the `--version` regression's expected output. Both keep their exit-status
assertions. These tests do **not** survive unchanged; their intent does.

- [ ] **Step 2: Run to verify they fail**

Run: `bash tests/wsl-toolchain-doctor.sh`
Expected: FAIL, version string is exactly 0.4.0

- [ ] **Step 3: Rename and bump**

Rename `VERSION` to `SCRIPT_VERSION` throughout and set it to `0.4.0`. The
JSON key stays `toolVersion` and `--version` still prints a bare string, so
the rename is unobservable; the number is not.

- [ ] **Step 4: Run to verify they pass**

Run: `bash tests/wsl-toolchain-doctor.sh`
Expected: PASS

- [ ] **Step 5: Write the failing `--probe` parser tests**

```bash
# audit --probe and --json in either order are accepted
run_doctor audit --probe
run_doctor audit --probe --json
run_doctor audit --json --probe
# repeats and unknowns are usage errors
assert_eq "$(run_doctor_status audit --json --json)" "2" "repeated --json exits 2"
assert_eq "$(run_doctor_status audit --probe --probe)" "2" "repeated --probe exits 2"
assert_eq "$(run_doctor_status audit --nonsense)" "2" "an unknown argument exits 2"
```

- [ ] **Step 6: Implement `PROBE_MODE` and the parser**

Declare `PROBE_MODE=0` beside the existing mode globals — unlike the
executable seams, which must stay unassigned. Then replace the `audit` arm's
inline `(( $# > 1 ))` test with the duplicate-aware parser from the spec's
**parse_audit_args**: `seen_json` / `seen_probe` state, arithmetic inside `if`
conditions never as standalone commands, and an explicit `return 0` at the
end. `main` answers a non-zero return with `usage >&2; return 2`, before
`run_audit` — so an argument error runs no audit and invokes no probe.

- [ ] **Step 7: Add the three resolvers**

`mise_bin()` already exists. Add `openspec_bin()` and `timeout_bin()` in the
same shape, from the spec's **Every external executable comes from a seam**:
`${VAR+x}` for set-ness, `printf '%s'`, `command -v … 2>/dev/null` as the
fall-through, plus an `-x` usability check.

**Never assign the seam variables at script scope.** No
`WTD_OPENSPEC_BIN="${WTD_OPENSPEC_BIN:-}"`. Such an assignment makes the
variable set on every run, the `command -v` branch unreachable, and `--probe`
inert in production while every fixture test still passes.

- [ ] **Step 8: Pin the seams in `run_doctor()`**

Add `XDG_STATE_HOME`, `XDG_CONFIG_HOME`, `WTD_CATALOG_FILE`,
`WTD_RECEIPT_FILE`, `WTD_MISE_TOOLCHAIN_CONFIG`, `WTD_OPENSPEC_BIN` and
`WTD_TIMEOUT_BIN` to the `env` list, so no case reads host state or runs a
host binary.

- [ ] **Step 9: Add the seam-state tests**

Four states per seam — **unset** (with fixtures on `PATH`, proving the
production `command -v` path works and a fixture-only suite cannot hide a
dead `--probe`), **injected**, **empty**, and **unusable** (a path that exists
but is not executable). Empty and unusable must perform no `PATH` search,
proven by leaving a working tool on `PATH` and asserting it is never invoked.

- [ ] **Step 10: Port the reader and validator**

Copy `load_kv_file` and `validate_kv`, replacing each `die` with
`printf '%s\n' "$msg" >&2; return 1`. The doctor holds two files at once, so
it passes a different array trio for each. Call the loader **directly** —
never in command substitution — since its arrays are populated through
namerefs.

- [ ] **Step 11: Run the full test command and commit**

```bash
git add wsl-toolchain-doctor/wsl-toolchain-doctor.sh tests/wsl-toolchain-doctor.sh
git commit -m "feat(doctor): add --probe, executable seams and the adt-kv reader"
```

---

### Task 7: Doctor — the three comparisons

**Files:**
- Modify: `wsl-toolchain-doctor/wsl-toolchain-doctor.sh`
- Test: `tests/wsl-toolchain-doctor.sh`

**Interfaces:**
- Consumes: everything from Task 6, plus the receipt written by Task 5.
- Produces: the `TOOLKIT_` finding domain inside `audit`. `SCHEMA_VERSION`
  stays `1` — new codes are data inside the existing `findings[]` array.

- [ ] **Step 1: Write the failing precondition tests**

```bash
# no receipt
run_doctor audit
assert_contains "no receipt is informational" "$LAST_OUT" "TOOLKIT_NOT_PROVISIONED"
[[ "$LAST_OUT" != *"TOOLKIT_INSTALLED_NOT_PROBED"* ]] \
  || fail "no receipt must produce no probe advice"

# unreadable receipt
printf 'garbage\n' > "$TMP_ROOT/receipt.env"
run_doctor audit
assert_contains "an unreadable receipt is informational" "$LAST_OUT" "TOOLKIT_RECEIPT_UNREADABLE"
assert_contains "the audit still completes" "$LAST_OUT" "PATH_"

# readable receipt, no --probe
write_valid_receipt "$TMP_ROOT/receipt.env"
run_doctor audit
assert_contains "a readable receipt advises --probe" "$LAST_OUT" "TOOLKIT_INSTALLED_NOT_PROBED"
```

- [ ] **Step 2: Run to verify they fail**

Run: `bash tests/wsl-toolchain-doctor.sh`
Expected: FAIL, no `TOOLKIT_` findings exist.

- [ ] **Step 3: Implement the preconditions**

Per the spec's **Preconditions**: `TOOLKIT_NOT_PROVISIONED`,
`TOOLKIT_RECEIPT_UNREADABLE`, `TOOLKIT_CATALOG_UNAVAILABLE`,
`TOOLKIT_INSTALLED_NOT_PROBED`, all `INFO`, all non-fatal. Receipt validation
runs the two ordered phases: the six literal keys in declared order, then the
structural predicates in declared order.

- [ ] **Step 4: Implement comparison A**

Reads `${XDG_CONFIG_HOME:-$HOME/.config}/mise/conf.d/agentic-dev-toolkit.toml`
directly, seam `WTD_MISE_TOOLCHAIN_CONFIG`. **Never `mise ls --current`** —
its answer depends on the working directory, and this is a question about the
global toolkit configuration.

Its domain is **exactly twelve keys**: `java-17`, `java-21`, `dotnet-8`,
`dotnet-10`, `python`, `node`, `bun`, `maven`, `uv`, `dotnet-ef`,
`shellcheck`, `gitleaks`. `pyyaml`, `openspec`, `superpowers`,
`karpathy-ref` and `karpathy-sha256` are outside it — they are not installed
through the `[tools]` table. `TOOLKIT_CONFIG_MISSING` is scoped to the twelve.

New parsing, four line forms — scalar, quoted scalar key, and two
two-element arrays where **position carries the mapping**. It cannot reuse
`audit_mise`, which strips the version with `tool="${tool%%@*}"`, dedups on
`seen_tools`, and whose watchlist omits `node` and `bun` entirely.

Findings: `TOOLKIT_CONFIG_DRIFT` (WARN), `TOOLKIT_CONFIG_MISSING` (WARN),
`TOOLKIT_CONFIG_OK` (INFO), `TOOLKIT_CONFIG_UNAVAILABLE` (INFO).

- [ ] **Step 5: Test comparison A**

Agreement; a changed `node`; a **reordered** `java = [...]` array drifting on
both `java-17` and `java-21`; a config missing a key present in the receipt;
a receipt key outside the twelve never producing `TOOLKIT_CONFIG_MISSING`; an
`overridden=` component **still** participating; and a project-local
`mise.toml` in the working directory producing **no** finding.

- [ ] **Step 6: Implement comparison B**

Runs only under `--probe`. Same commands as the receipt writer, with
`$(mise_bin)` for `MISE_BIN` and `$(openspec_bin)` for `openspec`, each
wrapped in `$(timeout_bin) 10s`. Normalize both sides to a concrete version
before comparing; string equality only, never against a `requested.*`.

Skipped components are not probed. A timeout is `TOOLKIT_PROBE_TIMEOUT`, a
failure `TOOLKIT_PROBE_UNAVAILABLE`, both `INFO`, both continuing to the next
component, neither changing the audit's exit status. `latest`-pinned
components **are** compared here — B compares two concrete observations and
needs no declared target.

- [ ] **Step 7: Test comparison B**

Plain `audit` invokes no probe stub at all; `--probe` does; a changed result
is `WARN`; a timeout does not abort; one failure does not suppress later
probes; a `skipped=` component is never probed; no receipt means no probe;
and with all three seams pointing at fixtures and `PATH` emptied of the real
tools, every recorded invocation is a fixture.

- [ ] **Step 8: Implement comparison C**

Iterates the **intersection** of receipt `requested.*` and current catalog
keys, so a catalog key newer than the receipt produces no finding and a
`requested.*` key no longer in the catalog produces none either.
`TOOLKIT_STALE_PIN` fires only when all four hold: not skipped, not
overridden, values differ, and neither side is `latest`. No whole-catalog
checksum fast path — `catalog-sha256` is provenance only.
`karpathy-ref` and `superpowers` participate; `karpathy-sha256` does not.

- [ ] **Step 9: Test comparison C**

A catalog ahead of the receipt; the same component in `overridden=` → no
finding; in `skipped=` → no finding; a `latest` component never stale and
named in `TOOLKIT_NOT_COMPARABLE`; a catalog key absent from an older receipt
→ no finding.

- [ ] **Step 10: Assert no `TOOLKIT_` finding is ever `FAIL`**

```bash
[[ "$LAST_OUT" != *"FAIL  TOOLKIT_"* ]] \
  || fail "toolkit findings are WARN at worst"
```

With and without `--probe`.

- [ ] **Step 11: Run the full test command and commit**

```bash
git add wsl-toolchain-doctor/wsl-toolchain-doctor.sh tests/wsl-toolchain-doctor.sh
git commit -m "feat(doctor): compare requested, installed and catalogued versions"
```

---

### Task 8: Documentation

**Files:**
- Modify: `AGENTS.md`
- Modify: `README.md`
- Modify: `docs/wsl-toolchain-doctor.md`
- Modify: `wsl-toolchain-doctor/README.md`

**Interfaces:**
- Consumes: everything built above.
- Produces: no code.

- [ ] **Step 1: `AGENTS.md` — the pinned-defaults table**

Replace the literal default values with a pointer to
`catalog/software-catalog.env`. Keep the component list and the
pinned-versus-`latest` classification. **Correct the standing claim** that
every pin is "overridable by a CLI flag or an `ADT_*` environment variable of
the same name": every pin has an `ADT_*` variable, but `maven` and
`dotnet-ef` have **no CLI flag**. Leave the Karpathy paragraph as written —
it describes the verification rule, which is unchanged.

- [ ] **Step 2: `AGENTS.md` — the rest**

Add the `catalog/` component; add the `SCRIPT_VERSION` bump policy; note that
`install.sh` and the catalog ship together as a bundle; and note in the test
section that the harness exports `ADT_CATALOG_FILE` before sourcing the
installer body.

- [ ] **Step 3: `README.md`**

Add `catalog/` to the repository-layout tree.

- [ ] **Step 4: The doctor's documentation**

In `wsl-toolchain-doctor/README.md`: version `0.4.0`, the `--probe` flag, and
the `TOOLKIT_*` findings. In `docs/wsl-toolchain-doctor.md`: the version line,
the sample JSON payload, `--probe`, and the findings. Add `--probe` to the
`audit` synopsis in the script's own `usage()`.

- [ ] **Step 5: Verify no stale literals remain**

```bash
grep -nE '(temurin-2?1|3\.9\.16|1\.9\.0|v6\.3\.0)' AGENTS.md README.md docs/*.md
```

Expected: no output outside `catalog/`.

- [ ] **Step 6: Run the full test command and commit**

```bash
git add AGENTS.md README.md docs/wsl-toolchain-doctor.md wsl-toolchain-doctor/
git commit -m "docs: point the pinned defaults at the software catalog"
```

---

### Task 9: Open the pull request

- [ ] **Step 1: Run everything one last time**

Run the full test command from the top of this plan. All five suites must
pass and `shellcheck` must be clean.

- [ ] **Step 2: Confirm no parent-workspace file is staged**

```bash
git status --short
git log --oneline main..HEAD
```

Every path must be inside `checkouts/agentic-dev-toolkit`. A commit mixing
parent files with a child's violates the workspace rule.

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin feat/software-catalog
gh pr create --fill
```

The repository declares `integration: pull-request`; do not merge directly.

---

## Self-Review

**Spec coverage.** Walked the spec section by section. `adt-kv` format → Task
2. Catalog → Task 2. Bundle and lifecycle → Task 3. Test seams → Tasks 3 and
6. Karpathy mapping → Task 3. Script versions → Tasks 1, 3 and 6. Requested
values and the input gate → Task 4. Receipt, probes, skip expansion, override
set → Task 5. Doctor preconditions and comparisons → Tasks 6 and 7. Failure
model → distributed across the tasks that implement each row. Testing →
folded into each task. Documentation → Task 8. Delivery → Tasks 0 and 9.

**Deliberately not in this plan:** the parent workspace's
`scripts/check-catalog-drift.sh`, its fixture tests, and the `AGENTS.md` line
in the parent. Different repository, different policy, different workflow —
its own plan, after this lands.

**Type consistency.** Checked the names used across tasks:
`load_kv_file`/`validate_kv`/`catalog_value` (Task 2) are used unchanged in
Tasks 3, 5 and 6. `CATALOG`, `CATALOG_LINES`, `CATALOG_ORDER`,
`CATALOG_ERROR` are spelled identically in Tasks 2, 3, 5 and the harness
gate. `OVERRIDDEN_SET` and `serialize_catalog_set` (Task 5) are used only
there. `SCRIPT_VERSION` is the same constant name in all five scripts.
`ADT_INSTALL_ROOT` never appears as `REPOSITORY_ROOT`.

**Known judgement call.** Task 5 is the largest and could be split between
the receipt writer and the probes. I kept them together because a receipt
without `installed.*` and probes with nowhere to write are each half a
deliverable; a reviewer gating them separately would be reviewing an
incomplete file twice.
