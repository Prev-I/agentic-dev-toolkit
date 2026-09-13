# Software Catalog, Script Versions and Install Receipt Design

## Context

`environments/linux/install.sh` declares its third-party pins in one block of
`ADT_*`-overridable assignments near the top of the file, plus a Karpathy ref
and its SHA-256 as `readonly` constants just above them. Between them they carry sixteen pinned components across
seventeen values. Those are the only places the values are *executable* in
this repository, so nothing the installer does can disagree with itself.

There is drift across repositories. The sibling distribution `spec-rivet`
declares `openspecVersion: 1.9.0` and `superpowersVersion: v6.3.0` in
`src/manifest/toolchain.yaml`; this repository declares the same two values
independently in `install.sh`. Bumping one leaves the other stale with nothing
to notice.

They are not, however, the only places the values are *written*. The root
`AGENTS.md` repeats them in prose, in its pinned-defaults table:
Python `3.12`, Node `24`, Maven `3.9.16`, OpenSpec `1.9.0`, Superpowers
`v6.3.0` and the rest. That is documentation duplicating data, and it goes
stale the same way — silently, because no code reads it.

Of the five shipped scripts only `wsl-toolchain-doctor.sh` carries a version.
It emits that version as `toolVersion` in its JSON output, so its version is an
observable interface rather than a label. `install.sh`,
`opencode-service/opencode-gateway-restart.sh`,
`opencode-service/opencode-startup-ready.sh` and `repository-policy/validate.sh`
have none.

Nothing records what a provisioned machine received. `install.sh` writes no
state beyond the shell-rc fence and the mise `conf.d` file, so the doctor can
report what is installed with no idea what was requested.

`spec-rivet` already solves all three problems in its own domain: `src/VERSION`,
a `toolchain.yaml` component catalog, and a `.specrivet-lock.yaml` receipt
written into the target and read back by its update engine. Its manifest reader
parses JSON with `node`, which this repository cannot copy: `install.sh` is the
script that installs Node, and `wsl-toolchain-doctor/README.md` states a
Bash-only constraint.

## Drivers

- One file lists every pinned third-party version this toolkit installs.
- Every shipped script reports a version, on the same convention.
- A provisioned machine carries a record of what it requested and what it got.
- The doctor gains requested-versus-installed comparisons it cannot make today.
- Cross-repository drift with `spec-rivet` becomes detectable.
- Bash-only in the child. No `node`, `jq`, `python` or TOML parser is added to
  `install.sh` or to the doctor.
- Children stay independent: no child reads the workspace or a sibling.
- The existing installer test harness keeps working: it strips the final
  `main "$@"` line, writes the body to a temporary file, and sources it.
- No new failure mode in a systemd service helper.
- The Karpathy verification guarantee is preserved exactly.

## Invariants

1. The catalog is data. No reader ever sources or evaluates it, and its value
   grammar excludes every character that would matter if one did.
2. Precedence is the CLI flag **where the component has one**, then a
   set-and-non-empty `ADT_*` variable, then the catalog value. `maven` and
   `dotnet-ef` have no CLI flag. An `ADT_*` variable set to the empty string
   overrides nothing, because `${ADT_X:-…}` falls through it. Introducing the
   catalog changes no effective default.
3. A missing, malformed, duplicated, empty or incomplete catalog entry fails
   `install.sh` loudly, naming the file, the line, and the key where the line
   has one. Nothing is silently defaulted.
4. `install.sh` and its catalog are one deliverable. The script does not run
   without the catalog.
5. The doctor, the two service helpers and the policy validator remain
   individually copyable. The doctor's use of the catalog is optional.
6. Every shipped script declares `readonly SCRIPT_VERSION="x.y.z"` and prints
   exactly that string, and nothing else, for `--version`, exiting 0.
7. `wsl-toolchain-doctor.sh` keeps emitting `toolVersion` in JSON and keeps
   printing a bare version for `--version`. The internal rename from `VERSION`
   to `SCRIPT_VERSION` is not observable; the version number change from
   `0.3.0` to `0.4.0` is, and its tests change with it.
8. The receipt is written only after a fully successful install. A failed run,
   `--dry-run` and `--verify-only` write nothing.
9. `requested.*` records effective requested values after catalog, environment
   and CLI precedence. `installed.*` records concrete versions observed after
   installation and verification. The two are never conflated.
10. The receipt is written atomically: a temporary file in the destination
    directory, then `mv`.
11. Nothing reads the receipt to decide installer behaviour. The installer's
    correctness never depends on host state.
12. The doctor works with no receipt, with an unreadable receipt, and with no
    catalog. All three are informational, never fatal.
13. Toolkit findings are `WARN` at worst. `FAIL` in this tool means a policy
    violation, and a machine behind on a version is not one.
14. A component recorded in `skipped=` is excluded from all three doctor
    comparisons. A component recorded in `overridden=` is excluded from the
    staleness comparison only: a deliberately chosen version must still be
    checked against the machine's configuration and against what is
    installed.
15. A component whose requested value is `latest` has no declared target and
    is therefore excluded from the staleness comparison. It is still compared
    in the installed-versus-observed comparison, which compares two concrete
    measurements and needs no declared target.
16. The doctor's requested-configuration comparison reads the toolkit-managed
    global mise configuration file directly. It never runs `mise ls --current`,
    whose answer depends on the working directory.
17. The doctor's JSON `schemaVersion` stays `1`. New finding codes are data
    inside the existing `findings[]` shape, not a schema change.
18. The Karpathy catalog digest supplies `KARPATHY_DEFAULT_SHA256` only. The
    user override `KARPATHY_SHA256` still defaults to empty, and a non-default
    ref still requires an explicitly supplied digest.
19. The workspace drift check exits non-zero when it cannot read an input it
    was able to reach. It never passes by failing to look.
20. No commit mixes parent-workspace files with a child's.
21. The installed-versus-observed comparison runs only under `audit --probe`.
    A plain `audit` executes no external probe, and no probe failure or
    timeout can change the audit's exit status.
22. Every reader of an `adt-kv` file — installer, doctor, and the parent's
    drift check — implements the same grammar. A reachable file that violates
    it is an error in every one of them, never a skipped check.
23. Every effective `requested.*` value is validated against the scalar
    grammar **before any installation work begins**. An invalid one aborts
    through `die`, naming the key, the value and its source, having mutated
    nothing and written no receipt. No `requested.*` key is ever silently
    omitted.
24. Installer receipt probes are skip-aware, guarded and bounded. A skipped
    component is never probed and produces no warning; every probe runs
    inside a conditional so it cannot trigger `errexit` or the `ERR` trap;
    every probe is time-bounded, and if no timeout utility can be resolved
    all **probe-derived** capture is skipped rather than run unbounded —
    zero-invocation provenance such as `installed.karpathy-sha256` survives. **No probe
    outcome can turn a verified, successful installation into a failure.**
25. `load_kv_file` is never invoked in a subshell — no command substitution,
    pipeline, process substitution or grouped subshell — when the caller needs
    its arrays. Its diagnostic travels through a named scalar output
    parameter, never a global.

## The `adt-kv` format

The catalog and the receipt share one format. Defining it once means one parser
shape and one set of format tests.

**Encoding and line endings.** UTF-8. Repository files are LF; `.gitattributes`
gains `*.env text eol=lf` alongside the existing `*.sh`, `*.yaml` and `*.yml`
entries. A parser nevertheless tolerates CRLF input, because the receipt is
written on a machine rather than checked out: a trailing carriage return is
stripped with the rest of the trailing whitespace.

**Line kinds.**

- A *blank line* is empty or contains only spaces and tabs. Ignored.
- A *comment* is a line whose first non-whitespace character is `#`. Leading
  whitespace before `#` is permitted. Comments are whole-line only: a `#` that
  appears after a value is an ordinary character in that value.
- A *record* is `key=value`, split at the **first** `=`. No leading whitespace
  is permitted before a key, and no whitespace is permitted on either side of
  the `=`. Trailing spaces, tabs and carriage returns are stripped from the
  value.
- Any other line is malformed. A line with no `=` is reported as
  `missing '=' separator`, distinct from an empty value.

**Key grammar.** `^[a-z0-9][a-z0-9.-]*$`

Lower case, digits, dot and hyphen; must not start with a dot or hyphen. This
admits catalog keys such as `java-21` and `karpathy-sha256`, and receipt keys
such as `requested.node` and `installed.node`.

**Value grammar.** Two rules, because two receipt keys hold lists and a comma
has no business in an ordinary version string.

*Scalar grammar* — every key except the two named below:

```text
^[A-Za-z0-9][A-Za-z0-9._:+@/-]*$
```

Non-empty, no whitespace, no comma, and no character that carries meaning to a
shell: no `$`, backtick, quote, backslash, `;`, `&`, `|`, `(`, `)`, `<`, `>`,
`*`, `?`, `[`, `]`, `{`, `}`, `!`, `~`, `#`. This is what makes invariant 1
more than an intention: the file cannot express a command even if a future
reader made the mistake of sourcing it. The permitted extras cover real values
— `temurin-21`, `v6.3.0`, `3.9.16`, `2026-09-09T14:22:07Z`, `1.0.0+build`, a
full 40-character commit SHA, and `17.0.13`. Note that `@` and `/` are legal
only *after* the first character, which is why an npm scope such as
`@fission-ai/openspec` is **not** a legal value and is never recorded as one;
the catalog stores `openspec=1.9.0`, a version, and the package name lives in
`install_openspec` where it belongs.

*List grammar* — exactly two keys, `skipped` and `overridden`, both in the
receipt and neither in the catalog:

```text
^$|^[a-z0-9][a-z0-9.-]*(,[a-z0-9][a-z0-9.-]*)*$
```

That is: empty, or one or more elements separated by single commas, each
element independently matching the **key grammar**. It rejects a leading
comma, a trailing comma, a doubled comma and an empty element, because each of
those produces an element that fails the key grammar or an empty capture the
alternation cannot match.

Three further rules apply to lists, beyond the regex:

- **Membership.** Every element must name a key that exists in the catalog.
  This is a semantic check, so it runs wherever a catalog is in hand: always
  in the installer and in the parent drift check, and in the doctor only when
  the catalog is readable. With no catalog the doctor treats elements as
  opaque keys, which simply match nothing.
- **Duplicates are rejected**, naming the repeated element — not silently
  normalized. The installer writes these lists itself, so a duplicate means
  the writer is wrong, and deduplicating on read would hide that from the
  tests that should have caught it.
- **Order is deterministic.** The installer writes both lists in **catalog
  declaration order** — the order the keys appear in
  `catalog/software-catalog.env` — so two runs with the same flags produce
  byte-identical receipts and a test can assert the whole line. Readers must
  not depend on order beyond that.

**Empty values** are rejected for every key except those same two. The
allow-empty set and the list-valued set are the same set, deliberately: a list
is the only kind of value that can be legitimately empty, and `skipped=` on a
machine that skipped nothing is exactly that.

**Duplicate keys** are rejected, naming the key, the line of the duplicate and
the line of the first occurrence. Not last-wins: a duplicated pin is exactly
the kind of bad edit that must not resolve silently.

**Missing required keys** are rejected **fail-fast, on the first one, in the
reader's declared required-key order**. Not "each missing key": one policy,
one message, everywhere. The required set is an ordered list, the check walks
it in that order, and the first absent key is reported. Deterministic order is
what makes the message assertable — a set-iteration order would make the same
broken catalog produce different output on different runs. For the catalog the
ordered set is the seventeen keys listed below, in the order they appear
there.

The doctor does not call `die`, but it uses **the same contract**: it walks the
same ordered required set, stops at the same first missing key, and reports it
in the summary of `TOOLKIT_RECEIPT_UNREADABLE` or
`TOOLKIT_CATALOG_UNAVAILABLE`. Not calling `die` changes what happens next, not
what counts as valid.

**Diagnostic contract.** Every rejection that concerns a line present in the
file names `FILE:LINE: <problem>` — missing separator, malformed key,
duplicate key, empty value, malformed value, malformed list, unknown list
element, duplicate list element. A missing required key has no source line and
its diagnostic names `FILE: missing required key: <key>` and nothing more.
**No diagnostic invents a line number.** Retaining the line numbers through
validation is what makes this possible, and is why the reader below fills a
second array.

**Unknown keys** are accepted and retained, and never required. This is what
lets an older doctor read a newer catalog: a key it does not know about is data
it does not use, not an error. Typos are caught by the required-key check
rather than by an unknown-key check, so nothing is lost.

**Never sourced, never evaluated.** No reader uses `source`, `.`, `eval`, or
command substitution on file content.

**Reader.** Signature:

```text
load_kv_file FILE VALUES_ARRAY LINE_NUMBERS_ARRAY KEYS_IN_SOURCE_ORDER_ARRAY ERROR_VARIABLE
```

Three output arrays and one output scalar. The line numbers let validation
name a source line; the **source-order array** makes the *first* reported
problem deterministic, which an associative array cannot do because its
iteration order is a hash order. Both matter: a diagnostic that names a line
but picks an arbitrary key among several bad ones is not reproducible, and a
test cannot assert it.

`ERROR_VARIABLE` exists because **`load_kv_file` must never run in a
subshell.** Its output contract is caller mutation, and a subshell's mutations
die with the subshell:

```bash
if ! problem="$(load_kv_file … 2>&1)"; then   # WRONG — arrays vanish
```

That form loads the file, populates the arrays inside the subshell, and hands
the caller an empty catalog with a clean status. It is not a style preference:
**no caller may wrap the load in command substitution, a pipeline, process
substitution or a grouped subshell** when it needs the arrays. The function
runs in the current shell, always, and returns its diagnostic through a named
scalar written with `printf -v`.

The caller declares all three arrays empty and the scalar, and passes them by
name. The loop below is
the `install.sh` variant; the doctor's differs only in how it reports failure.

```bash
declare -gA CATALOG=() CATALOG_LINES=()
declare -ga CATALOG_ORDER=()

load_kv_file() {
  local file=$1
  # The nameref locals are named kv_* deliberately. A nameref whose own
  # identifier equals the name passed by the caller is a circular reference
  # and bash refuses it, so no caller may pass kv_values, kv_lines, kv_order
  # or kv_errname.
  local -n kv_values=$2
  local -n kv_lines=$3
  local -n kv_order=$4
  local kv_errname=$5
  local line key value lineno=0

  printf -v "$kv_errname" '%s' ''       # success clears the caller's scalar

  if [[ ! -r "$file" ]]; then
    printf -v "$kv_errname" '%s' "cannot read $file"
    return 1
  fi

  # `|| [[ -n "$line" ]]` keeps a final line that has no trailing newline.
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

**No nested helper, deliberately.** An earlier draft factored the four
rejection sites into a `fail()` defined inside `load_kv_file`. **Bash has no
function-local functions**: that definition is global the moment the enclosing
function runs, and `tests/install.sh` already defines a global `fail()` that
prints `FAIL:` and exits 1. The installer loads its catalog at step 3, which
runs while the harness is sourcing the body — so the loader would replace the
suite's assertion helper before the first test, and every later assertion
failure would quietly `return 1` instead of failing the run. **Tests that
cannot fail are worse than no tests.** The error write is therefore inlined at
each of the four sites: two lines, four times, and no name escapes the
function. The same prohibition holds generally — **no snippet in this design
defines a function inside another**, and no helper is introduced under a
generic name such as `fail`, `error` or `die`. Where repetition ever justifies
a helper, it is defined at top level under a uniquely prefixed name with all
its state passed explicitly.

Duplicate **keys** are caught during the load, where both line numbers are in
hand. Everything else waits for validation.

**Callers, all three of them**, use the same shape — a direct call, then a
branch on the status:

```bash
declare -gA CATALOG=() CATALOG_LINES=()
declare -ga CATALOG_ORDER=()
CATALOG_ERROR=""

if ! load_kv_file "$file" CATALOG CATALOG_LINES CATALOG_ORDER CATALOG_ERROR; then
  die "$CATALOG_ERROR"                       # installer
  # add_finding INFO TOOLKIT_CATALOG_UNAVAILABLE "$file" "$CATALOG_ERROR"   (doctor)
  # printf '%s\n' "$CATALOG_ERROR" >&2; exit 2                             (parent)
fi
```

The three consumers differ only in what they do with `$CATALOG_ERROR`; the
**diagnostic text is one contract**, so the same malformed catalog produces
the same sentence whether it aborts an install, becomes a doctor finding, or
fails the parent's drift check.

`ERROR_VARIABLE`'s name obeys the same collision rules as every nameref
argument: the local holding it is `kv_errname`, so no caller may pass a scalar
called `kv_errname`, and the caller initializes the scalar (`CATALOG_ERROR=""`)
before the call so `set -u` cannot trip on it if a caller reads it early.
`printf -v` writes through the name without `eval` and without a subshell.

**`validate_kv` is different and may be captured.** It mutates nothing the
caller can see — its outputs are its exit status and its message — so
`if ! problem="$(validate_kv … 2>&1)"; then` remains correct there. The
prohibition is specific: it applies to any function whose output contract
includes caller mutation, which today is `load_kv_file` alone.

**Validator.** One function, and it is complete: membership is inside it, not
left to a caller poking at its locals.

```text
validate_kv FILE VALUES LINES ORDER REQUIRED LIST_KEYS MEMBERS
```

| Parameter | Kind | Meaning |
|---|---|---|
| `FILE` | string | path, for diagnostics only |
| `VALUES` | associative | key → value, from `load_kv_file` |
| `LINES` | associative | key → source line, from `load_kv_file` |
| `ORDER` | indexed | keys in source order, from `load_kv_file` |
| `REQUIRED` | indexed | required keys **in the order they are checked** |
| `LIST_KEYS` | associative | keys whose value is a list; also the allow-empty set |
| `MEMBERS` | associative | permitted list elements. **Empty means membership cannot be checked and is skipped** |

```bash
validate_kv() {
  local file=$1
  local -n v_values=$2 v_lines=$3 v_order=$4
  local -n v_required=$5 v_listkeys=$6 v_members=$7
  local key value element
  local -a elements
  local -A seen

  # Phase 1: required keys, in the caller's declared order. A key that is
  # absent has no source line, so none is printed.
  for key in "${v_required[@]}"; do
    if [[ -z "${v_values[$key]+set}" ]]; then
      die "$file: missing required key: $key"
    fi
  done

  # Phase 2: per-key syntax, walked in SOURCE order so the first problem
  # reported is the first problem in the file.
  for key in "${v_order[@]}"; do
    value="${v_values[$key]}"

    if [[ -n "${v_listkeys[$key]+set}" ]]; then
      if [[ -z "$value" ]]; then
        continue                                   # an empty list is valid
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
```

Every branch is an `if`, never `cond && action`, and every arithmetic test sits
inside an `if` condition. Nothing on the success path can return non-zero under
`set -e`; the function's last command is the `for` loop, which returns 0.

#### Nameref and empty-array rules

These apply to `load_kv_file`, `validate_kv` and **every** helper that uses
`declare -n`, not just the first one:

- **Every nameref local carries a helper-specific prefix** — `kv_*` in
  `load_kv_file`, `v_*` in `validate_kv`, and a distinct prefix in any helper
  added later.
- **A caller must never pass an array whose variable name equals one of that
  helper's nameref locals.** Bash refuses a circular reference, and the error
  arrives at the callee rather than at the line that caused it. The prefixes
  exist so the constraint is visible at both ends: no caller declares
  `kv_values` or `v_order`, and no helper reuses another's prefix.
- **Every array passed through a nameref is explicitly initialized**, with
  `=()`, before the call. Not a bare `declare -A NAME`, which leaves the
  variable declared-but-unset; under `set -u`, expanding `${#NAME[@]}` on such
  a variable is an error on some supported Bash versions, and `validate_kv`
  does exactly that to decide whether membership can be checked.
- The empty membership map is therefore written
  `declare -A EMPTY_MEMBERS=()`, never `declare -A EMPTY_MEMBERS`.

**Every array the installer declares at its own top level uses `declare -g`.**
This is not stylistic. `tests/install.sh` sources the installer body from
inside the shell function `load_installer_functions`, and a `declare` executed
inside a function is **function-local** — the array is populated during the
source and gone the instant the loader returns. Verified on the reference
platform (bash 5.2):

| Declaration in the sourced body | Survives the loader's return? |
|---|---|
| `PLAIN=value` | **yes** — a plain assignment is global |
| `readonly CONST=value` | **yes** — which is why the installer's existing `readonly` constants already work under the harness |
| `declare -A ARR=()` | **no** — function-local, silently empty afterwards |
| `declare -gA ARR=()` | **yes** |

So only the array declarations change: `CATALOG`, `CATALOG_LINES`,
`CATALOG_ORDER` and `OVERRIDDEN_SET` are declared `-gA`/`-ga`. Plain scalars
and `readonly` constants keep their current form, and `readonly`
initialization still happens exactly once per shell — a second source in the
same shell fails with `readonly variable`, which is precisely the invariant
`load_installer_functions` is called once to preserve.

`declare -g` needs bash 4.2; this design already requires 4.3 for `declare -n`,
and Debian/Ubuntu ship 5.x, so the floor is unchanged. The doctor and the
parent's drift check declare their arrays at true script scope and need no
`-g`; the rule applies to the installer because of how it is sourced.

**`MEMBERS` is the catalog's own values array.** The permitted list elements
are exactly the catalog's keys, so no third structure is built — validating a
receipt passes `CATALOG` in that slot. Two namerefs bound to the same variable
is legal, and it is the whole mechanism:

| Reader | `MEMBERS` argument | Membership enforced? |
|---|---|---|
| `install.sh` | `CATALOG` | **always** — the installer cannot run without a catalog |
| parent drift check | its loaded catalog | **always** — a reachable catalog it cannot read is exit 2 |
| doctor, catalog readable | the loaded catalog | yes |
| doctor, no catalog | `EMPTY_MEMBERS`, declared `declare -A EMPTY_MEMBERS=()` | **no** — syntax and duplicates are still enforced, membership is not |

That last row is the honest limit of a standalone doctor: with no catalog it
cannot know whether `skipped=frobnicate` names a real component, so it checks
the list's shape and its duplicates and says nothing about its meaning.

**The doctor's variant does not `die`.** It must not acquire one under
invariant 12. Each `die "$msg"` becomes `printf '%s\n' "$msg" >&2; return 1`,
and the caller captures the message without any global:

```bash
if ! problem="$(validate_kv … 2>&1)"; then
  add_finding INFO TOOLKIT_RECEIPT_UNREADABLE "$receipt" "$problem"
  return 0
fi
```

The `if !` guard is required: a plain `problem="$(…)"` assignment takes the
command substitution's exit status, which under `set -e` would end the audit
on exactly the input the doctor exists to survive.

The **rules are identical**; only the consequence differs. A file the
installer rejects is a file the doctor reports.

The raw-line read with a manual split is deliberate. `IFS='=' read -r key value`
cannot distinguish a line with no `=` from a line with an empty value, and those
are different mistakes deserving different messages. The `|| [[ -n "$line" ]]`
guard against a dropped unterminated final line is preserved either way.

The reader and validator are duplicated in `install.sh`, the doctor and the
parent's drift check rather than factored into a shared library. That follows
the convention the test suites already state in the header comments of
`tests/opencode-service.sh` and `tests/repository-policy.sh`: this repository
has no shared shell library, and introducing one would mean rewriting
components that have nothing to do with this change. What holds the three
together is this specified contract plus `catalog/README.md`, not shared code.

## Catalog

`catalog/software-catalog.env`, a new top-level component directory beside
`environments/`, `wsl-toolchain-doctor/`, `opencode-service/` and
`repository-policy/`. It sits at the repository root rather than inside
`environments/linux/` because the doctor reads it too, and neither component may
reach into the other.

The `.env` extension exists for editor syntax highlighting and for the
`.gitattributes` rule. The file header states that it is data only and is never
sourced.

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

Seventeen keys, all required. `karpathy-sha256` sits beside its ref because an
integrity pin is meaningless apart from the artefact it pins.

Java is listed 17 before 21, and .NET 10 before 8, matching the order
`render_mise_configuration` emits into the mise `[tools]` arrays. That order is
load-bearing — mise treats the first entry of a multi-version tool as the
default — and the function's own comment says so. The catalog uses explicit
per-version keys rather than an ordered list, so ordering lives in exactly one
place: the renderer.

Deliberately excluded: `OPENSPEC_TOOLS` is a harness list rather than software;
`ADT_GCM_PATH` is a filesystem path; and the six upstream source constants declared
alongside the other `readonly` literals at the top of `install.sh` describe *where* software comes from rather than which
version is wanted. Those six are not six URLs: three are installer URLs
(`MISE_INSTALL_URL`, `OPENCODE_INSTALL_URL`, `CODEX_INSTALL_URL`), one is a
plugin specifier (`SUPERPOWERS_PLUGIN_BASE`), one is a raw-content base URL
(`KARPATHY_RAW_BASE`), and one is a repository-relative file path
(`KARPATHY_SKILL_PATH`). Nothing reads them but the installer, and moving them
into the catalog would churn it every time a vendor moved a URL.

### `install.sh` is now a bundle

`install.sh` requires the catalog. It is shipped, copied and vendored as a
script-plus-catalog pair, and a copy of the script alone does not run.

This is a real loss and is stated rather than minimised. The frozen installer
copies under `models/routing/opencode/eval/records/` are captured evidence and
are not touched; any *new* copy of the installer must carry
`catalog/software-catalog.env` with it, or set `ADT_CATALOG_FILE` to one.

The other four shipped scripts stay individually copyable. The doctor reads the
catalog when it can find one and degrades to an `INFO` when it cannot, so its
dependency is soft in both directions.

### Initialization lifecycle in `install.sh`

Today the file cannot load a catalog, because the pin assignments come before
`die` is defined. The order has to change, and the order is
the design:

1. **Literals, then diagnostics, then the root.** `SCRIPT_NAME`,
   `readonly SCRIPT_VERSION` and the six upstream source constants are pure
   assignments and come first. **Root resolution is not.**
   `cd … && pwd` touches the filesystem and can fail — a deleted working
   directory, a permission change, a path that no longer exists — so it must
   not run before there is a way to report the failure. Two orderings are
   acceptable; this design takes the first:

   **(a) Define `die` and install the traps before resolving the root.** Step
   2's definitions move ahead of this line, and resolution becomes an ordinary
   guarded call:

   ```bash
   ADT_INSTALL_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)" ||
     die "cannot resolve the toolkit root from ${BASH_SOURCE[0]}"
   readonly ADT_INSTALL_ROOT
   ADT_CATALOG_FILE="${ADT_CATALOG_FILE:-$ADT_INSTALL_ROOT/catalog/software-catalog.env}"
   ```

   **(b)** If a future refactor needs the root before `die` exists, the guard
   must inline its own diagnostic — `printf … >&2; exit 1` — rather than
   assume a helper. What is not acceptable is a bare `cd` whose failure
   surfaces as an unexplained non-zero exit under `errexit`.

   **Behaviour when the root cannot be resolved:** the installer exits
   non-zero with a message naming `${BASH_SOURCE[0]}`, before any catalog
   read, any argument parsing and any installation step. It does not guess a
   root, does not fall back to `$PWD`, and does not continue with an unset
   variable that `set -u` would later trip over somewhere less informative.

   **Two levels up, not one**: the production script lives at
   `environments/linux/install.sh`, so the repository root is two directories
   above it.

   **The name is `ADT_INSTALL_ROOT`, and it must not be `REPOSITORY_ROOT`.**
   `tests/install.sh` declares `REPOSITORY_ROOT` — along with `INSTALLER` and
   `CLAUDE_TEMPLATE` — as `readonly`, and then sources the installer body into
   that same shell. A top-level `REPOSITORY_ROOT=` assignment in the body
   fails with `readonly variable`, and under the harness's `set -e` that
   aborts the entire suite before a single test runs. Any global the installer
   gains must avoid those three names; the `ADT_` prefix makes the constraint
   visible instead of remembered.
2. **Diagnostics and parsing functions.** `log`, `info`, `warn`, `die`,
   `quote_command`, `run`, `cleanup`, `on_error`, `load_kv_file`,
   `catalog_value`, `initialize_version_defaults` — and the `trap cleanup EXIT`
   and `trap on_error ERR` installations. Definitions only; nothing runs.
3. **Load and validate the catalog.**
   `load_kv_file "$ADT_CATALOG_FILE" CATALOG CATALOG_LINES CATALOG_ORDER CATALOG_ERROR`,
   called directly in the current shell, then `validate_kv` for the
   required-key, value-grammar and non-empty checks. Every failure is a
   `die` naming the file, the line and the key.
4. **Initialize version defaults from the catalog**, and
5. **apply `ADT_*` overrides**, which are one expression per pin because the
   parameter default does both:

   ```bash
   JAVA_21_VERSION="${ADT_JAVA_21_VERSION:-$(catalog_value java-21)}"
   ```

   Steps 4 and 5 are one block of assignments, listed separately here because
   the precedence they encode is what invariant 2 protects.
6. **Apply CLI overrides during argument parsing.** `parse_args` runs inside
   `main` and assigns over the same globals, exactly as it does today. Each
   assignment **marks the component's catalog key present in the override
   set**; the `ADT_*` layer does the same at step 5 when the variable is set
   and non-empty. That set, serialized in canonical catalog order, becomes the
   receipt's `overridden=`.
7. **Validate the effective requested values.** Every one of the sixteen
   catalog-derived values, after precedence has been applied, must be
   non-empty and must match the scalar `adt-kv` grammar — **before any
   installation work begins**, and before `validate_environment` runs. See
   below.
8. **Continue installation.** `main` proceeds unchanged apart from the receipt
   write described below.

The resulting order is:

```text
catalog load  →  environment/default resolution  →  CLI parsing
              →  effective requested-value validation
              →  environment/platform validation  →  installation
```

Invalid version syntax is therefore rejected before the first mutation, not
discovered when the receipt is written at the end of a successful install.

**Where the installer's existing top-level state belongs.** The seven steps
above describe what changes; the file already carries other globals, and this
is where they sit so that no one has to guess — and so that no unrelated
restructuring is implied:

| Existing initialization | Step | Note |
|---|---|---|
| mode flags — `DRY_RUN`, `UPGRADE`, `VERIFY_ONLY`, `SKIP_PLATFORM_CHECK`, `REMOVE_APT_NODE`, `REPAIR_CODEX`, `PROJECT_PATH` | 1 | pure assignments, no I/O |
| the nine `SKIP_*` flags | 1 | pure assignments |
| `TEMP_PATHS=()`, `DOWNLOADED_INSTALLER=""` | 1 | must exist before the `cleanup` trap can reference them |
| `cleanup`, `on_error`, and `trap cleanup EXIT` / `trap on_error ERR` | 2 | traps install as soon as their functions exist, which is what makes step 1's root guard reportable |
| XDG derivation — `XDG_CONFIG_HOME` and its trailing-slash trim | 1 | parameter expansion only |
| `MISE_BIN`, `MISE_TOOLCHAIN_CONFIG`, `OPENCODE_CONFIG`, `CODEX_HOME`, `CODEX_STANDALONE_ROOT`, `GCM_WINDOWS_PATH`, `GIT_CREDENTIAL_WRAPPER` | 1 | derived paths, no I/O; none is catalog-derived |
| `prepend_path` and its three calls | 2 | a function plus three invocations that test directory existence; they read the filesystem but cannot fail the run |

Only the catalog-derived pins move; everything in that table keeps its current
position relative to the others. The one ordering change the design forces is
that **step 2's diagnostics and traps now precede root resolution**, which
today sits among the literals at the top of the file.

### Effective requested values are validated before anything is installed

The catalog is validated when it is loaded. That is not enough, because the
value that reaches the receipt is the **effective** one, and two of its three
sources are unvalidated today:

- **separate-value CLI flags** go through `require_value`, which rejects an
  empty value and one that looks like another option — and nothing else. It
  accepts spaces, commas, brackets and control characters.
- **`--flag=value` forms never call `require_value` at all.**
  `--node-version=` assigns the empty string and the run continues.
- **`ADT_*` variables** are substituted verbatim when non-empty.

Any of those can produce a value that is fine for `mise` and illegal in a
receipt, and the failure would surface at the very end of a successful
install — or later, as a receipt the doctor refuses to read.

**The gate.** It is a call in `main`, between the two that already sit there:

```bash
  parse_args "$@"
  validate_requested_values
  validate_environment
```

Placed there because `parse_args` is the last thing that can change an
effective value and `validate_environment` is the first thing that inspects
the machine. Each of the sixteen catalog-derived values is checked:

1. non-empty;
2. matches the scalar grammar `^[A-Za-z0-9][A-Za-z0-9._:+@/-]*$`.

A failure goes through the normal `die` path and the message names three
things — the catalog key, the offending value, and **which source it came
from**:

```text
ERROR: invalid value for 'node' from --node-version: '24,25'
ERROR: invalid value for 'maven' from ADT_MAVEN_VERSION: '3.9.16 (rc)'
ERROR: invalid value for 'python' from the catalog: '3.12 '
```

Naming the source is the difference between a message the operator can act on
and one that sends them to the wrong file. The installer therefore records,
alongside each effective value, the layer it came from — the same bookkeeping
that already marks membership in the override set.

**`--flag=` with an empty value fails explicitly.** The `=`-forms gain the
same empty check the separate forms get from `require_value`, dying with the
same `requires a value` message. An empty inline value must never fall
through to the catalog: the operator asked for something and got silence.

**An empty `ADT_*` variable still means "not overridden"** and falls through
to the catalog, exactly as already decided. The two are different states and
stay different: an unset or empty environment variable is an absent opinion,
while `--flag=` is a stated one that is malformed.

**No `requested.*` key is ever silently omitted.** All sixteen are
structurally required by the receipt model, so an invalid value is a fatal
input error, never a dropped key. This is the deliberate opposite of the
`installed.*` rule, where omission is correct — a measurement can legitimately
be unavailable, an input cannot legitimately be malformed.

`KARPATHY_SHA256` is outside this gate. It is not a `requested.*` value, it
defaults to empty by design, and `install_karpathy_skill` already validates it
against `^[0-9a-f]{64}$` before use — a stricter rule than this one, and the
right one for a digest.

Steps 1 to 5 are top-level, in that order, before `main` is called on the final
line. This keeps `--help` working: `usage` interpolates `$SHELLCHECK_VERSION`
and friends into its text, so the defaults must exist before any argument is
parsed.

A consequence worth naming: `--version` and `--help` also require a readable
catalog, because they are parsed after step 3. That is accepted rather than
special-cased. A missing catalog means a broken bundle, and reporting it the
same way for every invocation is simpler to implement, simpler to test, and
never hides the real problem behind a working `--version`.

### Behaviour under `set -Eeuo pipefail`

- **Ordering exists for `set -e`.** Loading before `die` is defined would abort
  with bash's own message and no context. Step 2 before step 3 is what makes
  every catalog failure a named error.
- **`trap on_error ERR` is installed in step 2**, so a failure during catalog
  load reports its line number like any other.
- **`set -u` is why missing keys are validated explicitly.**
  `${CATALOG[node]}` on an absent key aborts with `unbound variable` and no
  useful text. `validate_kv`'s phase 1 runs first and reports
  `missing required key: node`. `catalog_value` also uses
  `${CATALOG[$1]:?missing catalog key: $1}` as a backstop, so a key added to
  the code but not to the required list still fails with a name rather than a
  bash error.
- **The reader's skip condition is an `if`, not `cond && continue`.** A
  trailing `&&` that evaluates false makes the loop body's exit status
  non-zero, which under `set -e` can terminate the enclosing function when it
  is the final command.
- **The line counter is `lineno=$(( lineno + 1 ))`, never `(( lineno++ ))`.**
  A standalone arithmetic command returns status 1 when the expression
  evaluates to zero, and post-increment evaluates to the value *before* the
  increment. With `lineno=0` the first line of every catalog would therefore
  abort the installer. This is not a corner case; it is the first iteration of
  the loop, every time. The assignment form always returns 0. No standalone
  `(( … ))` is used anywhere on a successful path in either reader — where a
  numeric test is needed, it is written `[[ $n -gt 0 ]]`.
- **Every other command on the reader's success path returns 0**: the `[[ … ]] ||
  die` guards succeed when the guard holds, parameter-expansion assignments
  always succeed, an `if` with a false condition and no `else` returns 0, and
  the `while` loop returns 0 when `read` finally fails at EOF. The function's
  last command is the loop itself.
- **`read` returning 1 at EOF is the loop condition**, so it does not trip
  `set -e`; the `|| [[ -n "$line" ]]` guard rescues an unterminated final line.
- **`declare -A` requires bash 4**, already required by the existing
  `mapfile`/`${var,,}` usage.

### Test seams

| Seam | Script | Default |
|---|---|---|
| `ADT_CATALOG_FILE` | `install.sh` | `$ADT_INSTALL_ROOT/catalog/software-catalog.env` |
| `WTD_CATALOG_FILE` | doctor | `$COMPONENT_ROOT/../catalog/software-catalog.env` |
| `WTD_RECEIPT_FILE` | doctor | `${XDG_STATE_HOME:-$HOME/.local/state}/agentic-dev-toolkit/install-receipt.env` |
| `WTD_MISE_TOOLCHAIN_CONFIG` | doctor | `${XDG_CONFIG_HOME:-$HOME/.config}/mise/conf.d/agentic-dev-toolkit.toml` |
| `WTD_MISE_BIN` | doctor | existing seam; `mise_bin()` honours it before falling back to `command -v mise` |
| `WTD_OPENSPEC_BIN` | doctor | new; `openspec_bin()`, same shape, for comparison B's one non-mise probe |
| `WTD_TIMEOUT_BIN` | doctor | new; `timeout_bin()`, same shape, wraps every bounded probe |

`WTD_*` matches the ten seams the doctor already uses — `WTD_MISE_BIN`,
`WTD_WSL_CONF`, `WTD_MOUNTS_FILE` and the rest — and `run_doctor()` in
`tests/wsl-toolchain-doctor.sh` already threads that style of variable through
`env`. `WTD_MISE_BIN` is listed above because comparison B depends on it, not because
it is new; `WTD_OPENSPEC_BIN` and `WTD_TIMEOUT_BIN` are new, and exist so that
a test never reaches the developer's real `openspec` or `timeout` through
ambient `PATH`.

**The installer's default is unusable inside the test harness, and the harness
must therefore set the seam.** `load_installer_functions` reads the installer,
asserts the last line is `main "$@"`, drops it, writes the remainder to
`$TEMP_DIR/install-functions.sh`, and sources that. Inside the copy
`${BASH_SOURCE[0]}` is the temporary file, so `../..` resolves to two
directories above `$TEMP_DIR` — somewhere in the system temporary tree, not
the repository — and the load in step 3 would die on every test.

**The precise required harness change** is two lines in
`load_installer_functions`, before the `source`:

```bash
ADT_CATALOG_FILE="${ADT_CATALOG_FILE:-$REPOSITORY_ROOT/catalog/software-catalog.env}"
export ADT_CATALOG_FILE
```

It is not accurate to say every existing test then works unchanged: **the
harness itself changes**, and without that change every test in the suite
fails at load. What is accurate is that no individual *test function* needs
editing, because with the seam set the sourced body populates the same globals
it populated before. That distinction is the difference between a two-line
diff and a mystery.

Tests that need a *different* catalog do not re-source. They run the installer
as a program with the seam set:
`ADT_CATALOG_FILE=<fixture> bash "$INSTALLER" --dry-run`. That is how the
missing-catalog, malformed-key, duplicate-key, empty-value, CRLF and
no-trailing-newline cases are exercised, and it keeps `readonly` intact on the
constants described next.

### Karpathy: what the catalog supplies, and what it must not

The verification property in `install_karpathy_skill` is precise and must
survive untouched:

- `KARPATHY_REF == KARPATHY_DEFAULT_REF` — the built-in digest applies, and a
  user-supplied digest that contradicts it is refused.
- `KARPATHY_REF != KARPATHY_DEFAULT_REF` — a user-supplied digest is
  **required**; without it the step dies with `requires --karpathy-sha256`.

The mapping is therefore asymmetric, and the asymmetry is the whole point:

| Catalog key | Supplies | Not |
|---|---|---|
| `karpathy-ref` | `KARPATHY_DEFAULT_REF` | `KARPATHY_REF` |
| `karpathy-sha256` | `KARPATHY_DEFAULT_SHA256` | `KARPATHY_SHA256` |

`KARPATHY_REF="${ADT_KARPATHY_REF:-$KARPATHY_DEFAULT_REF}"` and
`KARPATHY_SHA256="${ADT_KARPATHY_SHA256:-}"` keep their current definitions.
**`KARPATHY_SHA256` still defaults to empty.** If the catalog digest became its
default, a custom ref would silently acquire a digest belonging to a different
artefact, and the `requires --karpathy-sha256` refusal — the thing standing
between this machine and an unverified file of standing agent instructions —
would never fire.

`KARPATHY_DEFAULT_REF` and `KARPATHY_DEFAULT_SHA256` remain `readonly`. They
move from literal assignment at the top of the file to assignment from the
catalog in
step 4, and are marked `readonly` immediately after. This is safe because
step 4 executes exactly once per shell: the production script runs it at load,
and tests that vary the catalog run the installer as a program rather than
re-sourcing the body.

Three existing tests are mandatory regressions and must keep passing unchanged:
`test_karpathy_skill_refuses_a_custom_ref_with_no_digest`,
`test_karpathy_skill_refuses_a_digest_that_contradicts_the_pin` and
`test_karpathy_skill_always_verifies_the_pinned_ref_against_the_builtin_digest`,
all in `tests/install.sh`.

## Script versions

| Script | Today | This change |
|---|---|---|
| `wsl-toolchain-doctor/wsl-toolchain-doctor.sh` | `VERSION="0.3.0"` | `SCRIPT_VERSION="0.4.0"` |
| `environments/linux/install.sh` | none | `SCRIPT_VERSION="0.1.0"` |
| `opencode-service/opencode-gateway-restart.sh` | none | `SCRIPT_VERSION="0.1.0"` |
| `opencode-service/opencode-startup-ready.sh` | none | `SCRIPT_VERSION="0.1.0"` |
| `repository-policy/validate.sh` | none | `SCRIPT_VERSION="0.1.0"` |

**`install.sh` starts at `0.1.0`, and that is settled.** A version orders
releases; it does not grade maturity, so the script's 1455 lines and daily use
argue for neither number. What decides it is that pre-1.0 says the newly
versioned interface is not frozen — and this change is the worst possible
moment to claim otherwise, because it *adds a required catalog dependency*.
Declaring `1.0.0` in the same commit that makes the script unable to run alone
would be publishing a stability promise about an interface that just changed
shape. `0.1.0` also matches the doctor's series and `spec-rivet`'s
`src/VERSION`. The patch/minor/major bump policy below applies unchanged from
`0.1.0` onward.

The name is `SCRIPT_VERSION` in all five so tests have one thing to look for. In
`install.sh` it also avoids collision with the fourteen `*_VERSION` tool pins.

`--version` prints the bare string and exits **0**.

### The doctor's version tests change

The rename from `VERSION` to `SCRIPT_VERSION` is invisible, but the bump from
`0.3.0` to `0.4.0` is not, and the existing tests hardcode the old number:

- the JSON assertion `'"toolVersion":"0.3.0"'` becomes
  `'"toolVersion":"0.4.0"'`.
- the `--version` regression, which asserts exit `0` and output `0.3.0`, keeps
  the exit assertion and expects `0.4.0`.

Those tests do not survive unchanged. Their *intent* survives: both continue to
assert that the emitted version is exactly the declared one.

### Per-script flag placement

- `install.sh` parses `--version` inside `parse_args`, **before the generic
  `*) die "Unknown option: $1"` arm**, or it is reported as an unknown option:

  ```bash
  --version)
    printf '%s\n' "$SCRIPT_VERSION"
    exit 0
    ;;
  ```

  It prints the bare version and nothing else, exits `0`, and performs no
  installation — `exit 0` inside `parse_args` returns from the script before
  `main` reaches its first install step. Note the installer's `--help` also
  exits `0`, unlike `validate.sh`'s.

  **Both `install.sh --version` and `install.sh --help` require a readable,
  valid catalog**, because catalog loading is step 3 and argument parsing is
  step 6. It does **not** reach step 7: `--version` exits from inside
  `parse_args`, so the effective-value gate never runs for it, which is why
  that gate is a call in `main` rather than a check inside the parser. This
  catalog dependency is unusual and it is deliberate, not an oversight: the
  script
  and its catalog are one deliverable, `usage` interpolates catalog-derived
  defaults into its text, and a `--version` that succeeds on a machine where
  the bundle is broken would report health the installer does not have.
- `repository-policy/validate.sh` has an option loop in `main` with an
  `-h|--help` arm **and a generic `-*` arm** that prints `unknown option` and
  exits 2. The `--version` arm must be added **before** the `-*` arm, or it is
  swallowed by it. Note the deliberate asymmetry: `--help` exits `2` here,
  while `--version` exits `0`.
- `wsl-toolchain-doctor.sh` already has the arm in `main`. Only the rename and
  the number change.
- The two `opencode-service` scripts have no argument parsing at all. Their
  `main` ignores `"$@"`, and under `set -u` a bare `$1` is an unbound variable
  when the script is invoked with no arguments — which is how the systemd units
  invoke them. The guard is therefore an **`if`**, as the first statement of
  `main`:

  ```bash
  if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' "$SCRIPT_VERSION"
    exit 0
  fi
  ```

  Not `[[ … ]] && { … }`: as the first command of a function under `set -e`, a
  bare `&&` whose left side is false yields status 1, and on the overwhelmingly
  common path — no arguments at all — that would abort the very service helper
  it was meant to leave untouched. **Every other argument keeps today's
  behaviour of being ignored.** They are invoked by units recorded verbatim in
  the parent workspace; a strict parser would be a regression, not a feature.

### Bump policy

To be written into the root `AGENTS.md`: bump a script's `SCRIPT_VERSION` in
the same commit that changes its behaviour. Patch for a fix, minor for a new
flag or output field, major for a removal or a breaking output change.

## Install receipt

Path: `${XDG_STATE_HOME:-$HOME/.local/state}/agentic-dev-toolkit/install-receipt.env`.
State rather than config: `install.sh` already derives `XDG_CONFIG_HOME` for
files the user may edit, and this is a record the user should not.
`validate_environment` refuses to run as root, so `$HOME` is the provisioned
user's.

Format is `adt-kv`, with `skipped` and `overridden` declared allow-empty.

**Abridged** — the first six of the sixteen mandatory `requested.*` keys are
shown, as a contiguous run in catalog declaration order. A real receipt
carries all sixteen, always; see the complete key set below.

```
script-version=0.1.0
installed-at=2026-09-09T14:22:07Z
source-commit=1fcbb1c9a4e2b7d0f3a18c65b2e94d7f0a1c3e58
catalog-sha256=9c2f41a7be05d38e6114cc7a0d52f9b83e7a16d4c0985fb27e3a1d640c8b7f52
skipped=shellcheck,gitleaks,pyyaml
overridden=python,node
requested.java-17=temurin-17
requested.java-21=temurin-21
requested.dotnet-10=10
requested.dotnet-8=8
requested.python=3.11
requested.node=22
# … the remaining ten requested.* keys, in catalog declaration order …
installed.java-17=17.0.13
installed.java-21=21.0.5
installed.dotnet-10=10.0.100
installed.dotnet-8=8.0.404
installed.python=3.11.9
installed.node=22.14.0
# … the remaining installed.* measurements, in the same order …
```

Four things in that sample are load-bearing rather than decorative.

- `overridden=python,node` is in **catalog declaration order**, where `python`
  precedes `node` — not the order the flags were typed.
- `skipped=shellcheck,gitleaks,pyyaml` is in that same order, which is why it
  is not alphabetical.
- `requested.python=3.11` and `requested.node=22` **differ from the catalog's
  `3.12` and `24`**, which is what being overridden means. A receipt listing a
  component as overridden while echoing the catalog value would contradict
  itself.
- The `requested.*` and `installed.*` runs are **contiguous prefixes** of the
  catalog order — `java-17`, `java-21`, `dotnet-10`, `dotnet-8`, `python`,
  `node` — not a selection. `dotnet-10` and `dotnet-8` precede `python`, so a
  sample that skipped them while claiming catalog order would be teaching the
  wrong order.

### `requested.*` versus `installed.*`

`requested.<catalog-key>` is the effective requested value after catalog,
`ADT_*` and CLI precedence. It is a **constraint**, and it is frequently not a
version: `24`, `1`, `temurin-17`, `latest`. A machine provisioned with
`--node-version 22` records `requested.node=22`.

`installed.<catalog-key>` is a **concrete version observed on the machine**
after installation and after `verify_installation` has succeeded. `24.8.1`,
not `24`.

Never compare one against the other. `node=24` and `24.8.1` are different kinds
of value, and treating a constraint as a version is the mistake this split
exists to prevent.

### Observing installed versions

`verify_installation` already runs almost every probe needed, through
`"$MISE_BIN" exec`. The receipt writer reuses the same commands and captures
what verification currently only prints. `MISE_BIN` below is the
installer's own global; the doctor runs the same commands through `$(mise_bin)`
instead, as comparison B sets out.

**Every extraction yields exactly one whitespace-delimited token**, never a
line and never raw output. That single rule is what keeps banners, file paths,
build metadata in parentheses and SDK paths in brackets out of the receipt —
none of them can survive being reduced to one field.

| Catalog key | Probe | Extraction — one token |
|---|---|---|
| `node` | `"$MISE_BIN" exec -- node --version` | first line, first field, leading `v` stripped |
| `bun` | `"$MISE_BIN" exec -- bun --version` | first line, first field |
| `python` | `"$MISE_BIN" exec -- python --version` | first line, second field of `Python X.Y.Z` |
| `java-17` | `"$MISE_BIN" exec "java@$JAVA_17_VERSION" -- java -version` | first double-quoted token on stderr, quotes removed |
| `java-21` | `"$MISE_BIN" exec "java@$JAVA_21_VERSION" -- java -version` | first double-quoted token on stderr, quotes removed |
| `maven` | `"$MISE_BIN" exec -- mvn -version` | first line, third field of `Apache Maven X.Y.Z (…)` — the trailing `(…)` is a later field and is discarded |
| `dotnet-10` | `"$MISE_BIN" exec -- dotnet --list-sdks` | first field of the first line whose first field has major `10`; the `[/path]` is a later field and is discarded |
| `dotnet-8` | `"$MISE_BIN" exec -- dotnet --list-sdks` | same, major `8` |
| `dotnet-ef` | `"$MISE_BIN" exec -- dotnet-ef --version` | last non-empty line, first field — the command prints an ASCII-art banner first |
| `uv` | `"$MISE_BIN" exec -- uv --version` | first line, second field |
| `shellcheck` | `"$MISE_BIN" exec -- shellcheck --version` | the field after `version:` |
| `gitleaks` | `"$MISE_BIN" exec -- gitleaks version` | first line, first field, leading `v` stripped |
| `pyyaml` | `"$MISE_BIN" exec -- python -c 'import yaml; print(yaml.__version__)'` | first line, first field |
| `openspec` | `openspec --version` | first `X.Y.Z` match, as `install_openspec` does |

#### Nothing enters the receipt unvalidated

A probe result becomes a *candidate*, and the candidate must clear the same
normative scalar grammar every other receipt value clears. In order:

1. run the probe and capture its output;
2. extract the single token named above;
3. the candidate must be **non-empty**;
4. the candidate must match `^[A-Za-z0-9][A-Za-z0-9._:+@/-]*$`.

If step 1, 2, 3 or 4 fails, **that `installed.<key>` is omitted** and the
installer emits a `warn` naming the component and the reason. It is not
written blank, not written quoted, and not written with whatever the probe
happened to print.

Three consequences, all deliberate:

- **A failed measurement costs one optional key, nothing else.** The other
  thirteen measurements, every `requested.*`, and the whole receipt remain
  valid. A missing `installed.*` is an ordinary state the doctor already
  handles.
- **The receipt is never written invalid.** No value containing a space, a
  parenthesis, a bracket, a control character or a newline can reach it,
  because such a value fails step 4 and is dropped rather than escaped.
- **The written receipt satisfies the same validator the doctor runs.** That
  is a test, not an aspiration: the installer's own suite loads the receipt it
  just wrote and validates it with the receipt's required-key and structural
  rules.

Java and .NET need one probe per requested version — `mise exec java@…` — which
is exactly what `verify_installation` already does for both JDKs. `dotnet` is
the exception: one `--list-sdks` call yields both, selected by major.

**No reliable probe exists for two components**, and they get no `installed.*`
key:

- `superpowers` — a git ref installed into a harness plugin directory, with no
  command that reports it back.
- `karpathy-ref` — a `SKILL.md` file, with no version of any kind. What *is*
  observable is the digest that was verified before writing, so the receipt
  records `installed.karpathy-sha256` with the digest actually checked.

`installed.karpathy-sha256` is **not** a suffix exception — `karpathy-sha256`
is an ordinary catalog key. What is special about it is narrower and worth
stating exactly:

- it is permitted as `installed.*`, carrying **integrity provenance**: the
  digest of the content this machine actually received;
- `requested.karpathy-sha256` is **forbidden**, because the catalog digest
  reaches `KARPATHY_DEFAULT_SHA256` rather than any requested value;
- it **participates in no installed-version comparison**, because a digest is
  not a version and comparison B compares versions;
- it *is* usable to verify **what content was installed** — the question
  "is the skill on this machine the bytes the pin promised" is answerable from
  it, by comparison against the catalog's digest;
- it therefore stays distinct from a component version everywhere: written as
  `installed.*`, never as `requested.*`, never compared in B, and never a
  `skipped=` or `overridden=` member.

**`latest` constraints still get an `installed.*` value.** `uv`, `shellcheck`,
`gitleaks`, `pyyaml` and `dotnet-ef` are pinned to `latest`, so their
*staleness* is meaningless — but the concrete version that landed is exactly
the thing worth recording, and it is what makes "this machine's shellcheck went
backwards" observable later. What `latest` excludes is the staleness
comparison, not the record.

#### The installer's probe contract

Probing is best-effort and **never fails the install**. Three properties make
that true rather than hopeful, and each needs stating because the installer
runs under `set -Eeuo pipefail` with `trap on_error ERR` — an environment
where a bare failing command substitution aborts the run.

**Skipped components are never probed.** Before each probe the writer
consults the canonical expanded `skipped=` set. A skipped component gets no
probe, no `installed.*` key, and **no warning** — its tool is absent because
the operator said so, and reporting that as a problem trains people to ignore
warnings. For the one shared probe, `dotnet --list-sdks`, the rule is: run it
if **at least one** of the components it supplies is unskipped, and emit
values only for the unskipped ones. A run that skipped `dotnet-8` but not
`dotnet-10` invokes it once and writes one key.

**Every probe is guarded.** No bare `output="$(probe)"` for an optional
observation:

```bash
if output="$(run_bounded_probe "$component")"; then
  # extract the single token, then validate it against the scalar grammar
else
  warn "Could not record installed version for $component."
fi
```

The `if` makes the failure expected, which suppresses both `errexit` and the
`ERR` trap. A failed probe omits **only** that component's key: it does not
abort the install, does not discard measurements already captured, does not
write malformed data, and leaves the `requested.*` and provenance portion of
the receipt untouched and complete.

**Every probe is bounded.** `run_bounded_probe` wraps its command in
`timeout 10s`, using the system `timeout` from coreutils, which is present on
every supported Debian/Ubuntu system — but presence is verified, not assumed.
The installer resolves it once, before the first probe, with
`command -v timeout`. If it cannot be resolved:

- **all probe-derived `installed.*` capture is skipped** — every key in the
  probe table, and only those;
- **`installed.karpathy-sha256` is still written** when Karpathy was
  installed. It is **zero-invocation integrity provenance**: the digest was
  already computed and verified by `install_karpathy_skill` before the file
  was written, so recording it runs no command, needs no bound, and has
  nothing to time out. Dropping it would discard evidence the run already
  holds in a variable;
- **one aggregate warning** is emitted, not one per component;
- the receipt is still written, with every `requested.*` key, `skipped=`,
  `overridden=` and all provenance fields intact and valid;
- **no unbounded probe runs.** There is no fallback to running the command
  bare;
- the installation still succeeds.

The distinction is between a *measurement* and a *record*. Every other
`installed.*` value is a measurement — it requires running something, so it
requires a bound. `installed.karpathy-sha256` is a record of what the
installer itself already did. It is the only such key today, and any future
zero-invocation key must be named explicitly here before it may survive a
missing timeout; nothing acquires the exemption by resembling it.

A timed-out probe is treated exactly like any other unavailable observation:
warn, omit that key, continue to the next component.

**What verification does and does not prove.** An earlier draft claimed every
probe target is known to work because `verify_installation` succeeded. That is
wrong: verification is itself skip-aware — it gates the mise block on
`SKIP_RUNTIMES`, OpenSpec on `SKIP_OPENSPEC`, and the quality tools on both —
so a successful verification says nothing about a component that was skipped.
The accurate statement is narrower:

- a **non-skipped** component has already passed whatever verification exists
  for it, which is why probe failure there is unexpected rather than routine;
- a **skipped** component is never probed at all, so verification's silence
  about it never matters;
- receipt probes stay **observational and guarded regardless**, because
  "already verified" is not "cannot fail a second later";
- **no probe outcome can turn a verified, successful installation into a
  failed one.**

Three different numbers get confused here, so all three are stated:

| Quantity | Count |
|---|---|
| catalog components (`karpathy-sha256` is not one) | 16 |
| components yielding a concrete `installed.*` measurement | 14 |
| external command invocations | **13** |

Fourteen measurements from thirteen invocations, because one
`dotnet --list-sdks` call supplies both `installed.dotnet-10` and
`installed.dotnet-8`. Of the thirteen, twelve are `mise exec` and one is
`openspec --version`.

The two components with no measurement are `superpowers` and `karpathy-ref`.
Karpathy still contributes `installed.karpathy-sha256`, at a cost of **zero
invocations**: the digest was already computed and checked before the file was
written, and the receipt records the value rather than recomputing it.

Thirteen short invocations, on a run that has just installed a toolchain, is
not a hot path.

### `skipped=` and `overridden=`

Both hold **catalog keys**, never installer flag names. One namespace across
the catalog, the receipt and every doctor comparison.

| Flag | Expands to |
|---|---|
| `--skip-runtimes` | `java-17,java-21,dotnet-10,dotnet-8,python,node,bun,maven,dotnet-ef,uv` **and** everything `--skip-quality-tools` expands to |
| `--skip-quality-tools` | `shellcheck,gitleaks,pyyaml` |
| `--skip-openspec` | `openspec` |
| `--skip-superpowers` | `superpowers` |
| `--skip-karpathy` | `karpathy-ref` |
| `--skip-opencode`, `--skip-claude`, `--skip-codex`, `--skip-git-credential`, `--skip-platform-check` | nothing |

`--skip-runtimes` includes the quality tools because it effectively implies
them, though not through a single condition. Three separate gates produce that
effect, and the receipt has to record the outcome rather than any one of them:

- `configure_runtimes` returns immediately when `SKIP_RUNTIMES` is set, so the
  whole mise configuration — including the `shellcheck` and `gitleaks` entries
  — is never written at all.
- `render_mise_configuration` gates only those two entries, and only on
  `SKIP_QUALITY_TOOLS`. It knows nothing about `SKIP_RUNTIMES`; it is simply
  never called.
- `install_python_quality_libraries` gates on
  `SKIP_RUNTIMES == 1 || SKIP_QUALITY_TOOLS == 1`, and installs PyYAML through
  `pip` into the mise-managed interpreter. **PyYAML is never a mise `[tools]`
  entry**, which is why it is also outside comparison A.

`README.md`'s quality-tools section and the `--skip-quality-tools` entry in
`usage()` both state the implication in prose. The receipt records the effective skip, not the literal flag.

The last row matters: four skip flags touch components that have no catalog key
at all. They contribute nothing to `skipped=` and can never produce a catalog
drift finding, which is why no example here uses Claude Code or Codex.

`karpathy-sha256` never appears in `skipped=`. Only keys that participate in a
comparison do, and the digest is provenance.

**A mapping table defines membership; it never defines order.** The rows above
say *which* catalog keys a flag contributes, and they are written in catalog
declaration order only because that reads well. Serialization is governed
separately and absolutely: both lists are written in **canonical catalog
declaration order**, whatever order the flags arrived in and whatever order a
table happens to show. Every expansion shown anywhere in this document — the
table above, the receipt sample, the test expectations, the prose — is written
in that same order, so no reader can mistake a table's layout for the wire
format.

`overridden=` holds catalog keys whose effective value came from a CLI flag or
an `ADT_*` variable rather than the catalog. It is what stops a deliberate
choice from being reported back as staleness.

**Override detection must match value selection exactly.** The effective
default is `${ADT_X:-<catalog>}`, and `:-` substitutes the catalog value when
the variable is unset **or set to the empty string**. So an environment
variable that is present but empty does **not** override anything, and must
not be recorded as one. The test is therefore *set and non-empty*:

**Override tracking is set membership, not append history.** Both layers can
identify the same component — `ADT_NODE_VERSION=22 install.sh --node-version 23`
names `node` twice — and appending twice would emit `overridden=node,node`,
which the receipt's own list grammar rejects as a duplicate element. The
writer would produce a receipt no reader accepts.

The structure is therefore an associative set, and marking a key that is
already marked is a no-op:

```bash
declare -gA OVERRIDDEN_SET=()

# step 5, the environment layer
if [[ -n "${ADT_NODE_VERSION:-}" ]]; then
  OVERRIDDEN_SET[node]=1
fi

# step 6, the CLI layer — the same member, idempotently
OVERRIDDEN_SET[node]=1
```

An `if`, not `[[ … ]] && …`: on the common path the variable is unset, the
`&&` list returns 1, and as the last command of the function that records
overrides it would propagate under `set -e`.

Serialization walks the **canonical catalog-order array**, never the set's own
hash order, and emits each present key exactly once:

```bash
overridden=""
for key in "${CATALOG_ORDER[@]}"; do
  if [[ -n "${OVERRIDDEN_SET[$key]+set}" ]]; then
    overridden="${overridden:+$overridden,}$key"
  fi
done
```

`${OVERRIDDEN_SET[$key]+set}` is the `set -u`-safe existence test, and
`${overridden:+$overridden,}` builds the list without a leading comma — the
exact defect the list grammar rejects. An empty `overridden=` is the natural
result when nothing was marked, and remains valid.

**CLI still wins for the effective value.** Set membership records *that* a
component was overridden; precedence — CLI flag where one exists, then a
set-and-non-empty `ADT_*`, then the catalog — decides *what* the value is.
The two are independent, which is why observing an override twice cannot
change either answer.

**A repeated version flag is last-value-wins**, matching what `parse_args`
does today: its `while`/`case` loop simply assigns again. This design does not
add duplicate detection for version flags — that would be a behaviour change
to an existing interface for no benefit here. `--node-version 22
--node-version 23` yields `23`, and `node` appears in `overridden=` exactly
once. (This is deliberately unlike `parse_audit_args` in the doctor, where a
repeated flag *is* a usage error, because that preserves the strictness
`audit` already had.)

**Reader-side duplicate rejection is unchanged.** `validate_kv` still rejects
a duplicate list element, and it should: with the writer emitting a set in
canonical order, a duplicate in a receipt means either a writer bug or a hand
edit, and both deserve to fail loudly.

A CLI flag is unconditional: `require_value` already refuses an empty one, so
any flag that parsed is an override.

#### The allowlist

**`overridden=` is built from an explicit allowlist, never mechanically from
every environment variable or every flag the run happened to carry.** Only an
interface that *replaces a catalog-derived component value* contributes, and
each contributes exactly the catalog key it replaces:

| Environment variable | CLI flag | Catalog key |
|---|---|---|
| `ADT_JAVA_17_VERSION` | `--java-17-version` | `java-17` |
| `ADT_JAVA_21_VERSION` | `--java-21-version` | `java-21` |
| `ADT_DOTNET_8_VERSION` | `--dotnet-8-version` | `dotnet-8` |
| `ADT_DOTNET_10_VERSION` | `--dotnet-10-version` | `dotnet-10` |
| `ADT_PYTHON_VERSION` | `--python-version` | `python` |
| `ADT_NODE_VERSION` | `--node-version` | `node` |
| `ADT_BUN_VERSION` | `--bun-version` | `bun` |
| `ADT_MAVEN_VERSION` | *(none)* | `maven` |
| `ADT_DOTNET_EF_VERSION` | *(none)* | `dotnet-ef` |
| `ADT_UV_VERSION` | `--uv-version` | `uv` |
| `ADT_SHELLCHECK_VERSION` | `--shellcheck-version` | `shellcheck` |
| `ADT_GITLEAKS_VERSION` | `--gitleaks-version` | `gitleaks` |
| `ADT_PYYAML_VERSION` | `--pyyaml-version` | `pyyaml` |
| `ADT_OPENSPEC_VERSION` | `--openspec-version` | `openspec` |
| `ADT_SUPERPOWERS_REF` | `--superpowers-ref` | `superpowers` |
| `ADT_KARPATHY_REF` | `--karpathy-ref` | `karpathy-ref` |

Sixteen rows for sixteen components. `maven` and `dotnet-ef` are the two whose
only override path is the environment.

**Everything else contributes nothing**, and the list is worth writing out
because "it came from the environment" is the wrong test:

| Excluded | Why |
|---|---|
| `ADT_OPENSPEC_TOOLS` | a harness list, not a catalog key |
| `ADT_GCM_PATH`, `--gcm-path` | a filesystem path, not a catalog key |
| `ADT_KARPATHY_SHA256`, `--karpathy-sha256` | see below |
| `--project`, `--repair-codex`, `--remove-apt-node` | operations, not values |
| every `--skip-*` | recorded in `skipped=`, which is a different question |
| `--dry-run`, `--upgrade`, `--verify-only`, `--skip-platform-check` | operational modes |
| `ADT_FORCE_WSL`, `ADT_SETUP_ALLOW_ROOT_FOR_TESTS` | test seams |
| `MISE_BIN`, `CODEX_HOME`, `XDG_CONFIG_HOME`, … | environment plumbing |

**The Karpathy checksum is the interesting exclusion**, and it is excluded on
purpose rather than by omission. `ADT_KARPATHY_SHA256` and
`--karpathy-sha256` set `KARPATHY_SHA256`, which **defaults to empty** and
never takes a catalog value: the catalog's digest reaches
`KARPATHY_DEFAULT_SHA256` instead. Supplying one is providing *integrity
evidence for a custom ref*, not replacing a catalog-derived default the way a
version override does — and since `requested.karpathy-sha256` is never
written, there is no requested value for a staleness comparison to be
suppressed against. Recording it in `overridden=` would name a key that has no
`requested.*` entry, which phase 2 of receipt validation would then have to
special-case. `--karpathy-ref` *is* on the allowlist; its digest is not.

**Every member of `overridden=` is therefore a real catalog key by
construction**, which is what lets `validate_kv`'s membership check treat the
list exactly like `skipped=`.

The precedence is: the CLI flag **where that component has one**, then a
set-and-non-empty `ADT_*` variable, then the catalog.

**Both keys are always written, empty when nothing was skipped or overridden.**
An always-present key lets a reader distinguish "nothing skipped" from "written
by an installer too old to record it"; the latter is a missing required key and
becomes `TOOLKIT_RECEIPT_UNREADABLE`.

`skipped=` distinguishes deliberate omission from successful installation. It
says nothing about failure, and cannot: **a failed install writes no receipt at
all**, so no receipt ever describes a component that was attempted and failed.

### Writing it

Atomic, in the destination directory so the rename cannot cross a filesystem:

```bash
mkdir -p "$state_dir"
chmod 0755 "$state_dir"
tmp="$(mktemp "$state_dir/.install-receipt.XXXXXX")"
TEMP_PATHS+=("$tmp")          # removed by the existing EXIT trap on failure
write_receipt_body > "$tmp"
chmod 0644 "$tmp"
mv -f "$tmp" "$state_dir/install-receipt.env"
```

Modes are set explicitly rather than left to `umask`, so the result is
deterministic and testable on a machine with `umask 077` as well as `022`.
Nothing in the file is secret — every value is a public version string — so
`0644` and `0755` are correct.

`mktemp` inside `$state_dir` is what makes `mv` a same-directory rename: a
reader either sees the previous receipt or the new one, never a partial file.
The temporary path joins the existing `TEMP_PATHS` array so the script's
`cleanup` trap removes it if the run dies mid-write.

**Exact placement in `main()`.** Today the tail is `verify_installation` then
`print_summary`. It becomes three calls:

```bash
  verify_installation
  write_install_receipt
  print_summary
```

Between them, not after them, and the position carries four guarantees:

- the receipt is written **only after verification succeeds**, so it never
  claims a state the machine did not reach;
- the summary prints **only after the receipt has persisted**, so "Setup
  complete" is never shown for a run whose record failed to write;
- a receipt-write failure is therefore an **installation failure** — non-zero,
  under the `ERR` trap, with no completion summary — rather than a warning
  buried after a success message nobody reads past;
- because the write is atomic, that failure leaves any **earlier receipt
  intact**; the machine keeps its last accurate record rather than acquiring a
  truncated one.

The two non-installing paths bypass it by construction rather than by a flag
check inside the writer: `--verify-only` returns from `main` before the
install sequence is reached, and so never calls it; `--dry-run` reaches
`write_install_receipt`, which returns immediately after printing what it
would have written. Both are asserted.

`--upgrade` replaces the file. A previous receipt survives a failed run
untouched, which is deliberate: it still describes the last state the machine
actually reached.

`installed-at` is `date -u +%Y-%m-%dT%H:%M:%SZ`.

`source-commit` is the **full 40-character SHA** from
`git -C "$ADT_INSTALL_ROOT" rev-parse HEAD`, with `-dirty` appended when
`git -C "$ADT_INSTALL_ROOT" status --porcelain` produces output. A full SHA is
unambiguous where a short one is merely probably unambiguous, and the dirty
marker records the case that matters most for support: a machine provisioned
from a working tree that does not match any commit. Outside a checkout, or with
no `git` on `PATH`, the value is `unknown`.

`catalog-sha256` is the digest of the catalog file that was actually loaded. It
is **provenance only** — a record of which catalog produced this receipt. It is
not a correctness shortcut, and no comparison is skipped on the strength of it;
see the doctor's staleness rules below.

The receipt is a snapshot, not a history. A per-run append log would answer
"when did this machine last change" across upgrades, but it needs rotation, a
size bound and its own format decision, and none of that serves the doctor
check. Out of scope.

### The complete key set

The installer writes exactly this, on every successful run:

- `script-version`, `installed-at`, `source-commit`, `catalog-sha256` — always.
- `skipped` and `overridden` — **always**, with an empty value when nothing was
  skipped or overridden. They are the two allow-empty keys of the format.
- `requested.<key>` for **every catalog key except `karpathy-sha256`** —
  sixteen keys — **regardless of whether the component was skipped**. A run
  with `--skip-runtimes --skip-openspec` still writes all sixteen.
- `installed.<key>` only where a probe produced a value.
- `installed.karpathy-sha256` whenever the skill was installed and verified —
  **independently of probing**. It is zero-invocation provenance, so it is
  present even when every probe was skipped or the timeout utility could not
  be resolved, and absent only when Karpathy itself was skipped.
- `requested.karpathy-sha256` is **never written**. The digest is not a
  requested version; it is integrity provenance, and it is recorded once, as
  `installed.karpathy-sha256`, holding the digest actually verified before the
  file was written.

Writing `requested.*` unconditionally is what keeps a highly selective install
structurally valid. The alternative — omitting skipped components — makes
"deliberately skipped" and "written by an older installer" indistinguishable,
and makes the required-key set depend on the flags of the run that produced
the file. Skipping is recorded in exactly one place, `skipped=`, and every
comparison consults it before acting.

### Receipt validation: two ordered phases

"At least one `requested.*`" is not a key and cannot live in a required-key
loop. Receipt validation is therefore two phases, each with its own declared
order, and neither depending on hash order.

**Phase 1 — literal required keys**, checked in exactly this order, failing on
the first absent one:

1. `script-version`
2. `installed-at`
3. `source-commit`
4. `catalog-sha256`
5. `skipped`
6. `overridden`

That is the complete literal set. It is the `REQUIRED` array passed to
`validate_kv`, and `validate_kv`'s own per-key syntax pass then runs over the
source-order array, so a malformed value is reported for the earliest such
line in the file.

**Phase 2 — structural predicates**, numbered here for reference:

1. at least one key matches `requested.*`;
2. every `requested.*` suffix is a catalog key — walked in **source order**,
   reporting the earliest offender;
3. `requested.karpathy-sha256` is **absent**; its presence is an error;
4. every `installed.*` suffix is a catalog key — walked in source order.
   `installed.karpathy-sha256` satisfies this like any other: **`karpathy-sha256`
   is a catalog key**, so it needs no exception and none is granted;
5. every element of `skipped` and of `overridden` is a catalog key. This is
   `validate_kv`'s `MEMBERS` check.

Predicates 2, 4 and 5 need a catalog. A doctor with none reports
`TOOLKIT_CATALOG_UNAVAILABLE` and evaluates only 1 and 3.

**The numbering above is conceptual, and does not match execution order.**
Predicate 5 does not run where the list above places it. `load_receipt` makes
one call to `validate_kv` passing the six phase-1 literal keys as `REQUIRED`
and `skipped`/`overridden` as `LISTKEYS` with the catalog as `MEMBERS`; inside
that single call, `validate_kv` checks phase 1's required keys and then walks
every key in **source order** doing its per-key syntax pass, which for a list
key also checks membership — this is predicate 5. All of that happens before
`load_receipt` returns from `validate_kv` at all. Only once `validate_kv`
reports clean does `load_receipt` evaluate predicates 1 through 4 itself, in
that order. The actual, deterministic execution order is therefore:

1. phase 1's six literal required keys, then `validate_kv`'s list syntax and
   membership check (predicate 5), together in one call;
2. then predicate 1 (at least one `requested.*`);
3. then predicate 2 (`requested.*` suffixes are catalog keys);
4. then predicate 3 (`requested.karpathy-sha256` absent);
5. then predicate 4 (`installed.*` suffixes are catalog keys).

A receipt violating both predicate 5 and predicate 1 at once — a
`skipped=` member that is not a catalog key, and no `requested.*` key at all —
reports predicate 5's message (`unknown catalog key in skipped: ...`), never
predicate 1's. `tests/wsl-toolchain-doctor.sh` pins exactly this with a
combined-violation test, asserting the predicate-5 message is present and
predicate 1's is not.

The outcome for a caller is unaffected by this reordering: either way the
receipt is rejected as `TOOLKIT_RECEIPT_UNREADABLE`, and only the reported
message differs. The implemented order is fully deterministic — it falls out
of `validate_kv` and `load_receipt` being two ordinary, unconditional sequences
of checks — so this document is amended to describe it rather than to invert
the implementation to match the originally declared 1→2→3→4→5 order.

**"The same order the installer uses" means the order this document declares**,
not an order one program discovers by reading the other's output. The installer
*writes* keys in a canonical order — the six literals above, then `requested.*`
in catalog declaration order, then `installed.*` in catalog declaration order.
The doctor *validates* in the two orders above. The installer never reads its
own receipt in production; both sides take their ordering from these explicit
lists, so a writer change and a reader change are each visible in this
document rather than inferred from a hash.

## Doctor: three comparisons

A `TOOLKIT_` finding domain inside the existing `audit` action. No new action,
one new flag, and the existing `add_finding <SEVERITY> <CODE> <subject>
<message>` model is unchanged.

The three comparisons answer different questions and have different inputs.
Conflating them is the mistake this section exists to prevent.

| # | Question | Inputs | When |
|---|---|---|---|
| A | Does the global mise configuration still request what the install requested? | receipt `requested.*` + the toolkit's global mise config | every `audit` |
| B | Is the machine still running the versions the install produced? | receipt `installed.*` + live probes | `audit --probe` only |
| C | Has the toolkit's catalog moved ahead of this machine? | catalog + receipt `requested.*` | every `audit` |

A and C read files and cost nothing. B launches subprocesses and is opt-in;
see below.

### Preconditions

- **No receipt** — `TOOLKIT_NOT_PROVISIONED` `INFO`. All three skipped. This is
  a normal state: the doctor runs on any WSL machine.
- **Unreadable receipt** — any `adt-kv` violation, a missing required key, or a
  truncated file: `TOOLKIT_RECEIPT_UNREADABLE` `INFO`, naming the file and the
  first problem found. All three skipped. **The doctor does not terminate**, and
  the rest of the audit runs.
- **No catalog** — `TOOLKIT_CATALOG_UNAVAILABLE` `INFO`. C is skipped; A runs,
  and B runs if `--probe` was given, because neither needs the catalog. The
  doctor locates the catalog from a `BASH_SOURCE`-derived component root, the
  way `validate.sh` derives `COMPONENT_ROOT` from `${BASH_SOURCE[0]}`, and a
  copy of the doctor outside the repository simply takes this path.
- **Receipt readable, no `--probe`** — `TOOLKIT_INSTALLED_NOT_PROBED` `INFO`.
  A and C run as usual.
- Every component in `skipped=` is excluded from all three comparisons, and is
  never probed. Every component in `overridden=` is excluded from C only: a
  deliberately chosen version must still be checked against the machine's
  configuration and, when probing, against what is installed.

### A — requested-configuration drift

Compares receipt `requested.*` against the **toolkit-managed global mise
configuration file**, `${XDG_CONFIG_HOME:-$HOME/.config}/mise/conf.d/agentic-dev-toolkit.toml`
— the file `configure_runtimes` writes, named by `MISE_TOOLCHAIN_CONFIG`. Seam:
`WTD_MISE_TOOLCHAIN_CONFIG`.

**It must not use `mise ls --current`.** That is what `audit_mise` uses at line
634, and its answer depends on the working directory: run the doctor from
inside a project with its own `mise.toml` and the project's versions are what
comes back. Requested-configuration drift is a question about the global
toolkit configuration, so the global file is read directly. Reading a file also
means the comparison needs no mise binary and no activation.

The file's `[tools]` table is generated by `render_mise_configuration` and has a
fixed, narrow shape. The parser recognises exactly four line forms:

| Form | Example | Maps to |
|---|---|---|
| scalar | `node = "24"` | `python`, `node`, `bun`, `maven`, `uv`, `shellcheck`, `gitleaks` |
| quoted scalar key | `"dotnet:dotnet-ef" = "latest"` | `dotnet-ef` |
| two-element array | `java = ["temurin-17", "temurin-21"]` | `java-17` = element 1, `java-21` = element 2 |
| two-element array | `dotnet = ["10", "8"]` | `dotnet-10` = element 1, `dotnet-8` = element 2 |

Array position carries the mapping because it carries the meaning: mise treats
the first entry as the default, and `render_mise_configuration` documents that
17-before-21 and 10-before-8 are deliberate. A parser that matched by value
instead of position would silently accept a reordered file, which is exactly
the change that must be reported.

This is **new parsing logic**. It does not and cannot reuse `audit_mise`:

- `audit_mise` strips the version outright — `tool="${tool%%@*}"` —
  because every question it asks is about binding, not version.
- It then deduplicates on `seen_tools`, collapsing a multi-version tool to one
  row. Its own comment says so. Java's two versions are precisely what
  comparison A needs to see.
- Its watchlist, `primary_binary_for_mise_tool`, covers only `java`, `maven`,
  `python`, `uv` and `dotnet`. **`node` and `bun` are absent** and are skipped
  by the `[[ -n "$primary" ]] || continue` guard. Nothing existing supports
  them; both need new handling here.

#### A's domain is exactly twelve keys

Comparison A can only speak about components the generated `[tools]` table is
able to express. Its domain is fixed at those twelve:

`java-17`, `java-21`, `dotnet-8`, `dotnet-10`, `python`, `node`, `bun`,
`maven`, `uv`, `dotnet-ef`, `shellcheck`, `gitleaks`.

Five catalog keys are **outside A entirely**, because mise is not how they are
installed or configured:

| Key | Installed by |
|---|---|
| `pyyaml` | `install_python_quality_libraries`, via `pip` into the mise-managed interpreter — never a `[tools]` entry |
| `openspec` | `npm install -g @fission-ai/openspec@<version>` |
| `superpowers` | a harness plugin specifier, written into harness configuration |
| `karpathy-ref` | a `SKILL.md` downloaded and verified, then written to two directories |
| `karpathy-sha256` | not a component; integrity provenance |

`TOOLKIT_CONFIG_MISSING` is **scoped to the twelve**. A receipt key outside the
domain can never produce it. Absence of `openspec` from a mise `[tools]` table
is the correct and expected state, and reporting it as missing configuration
would be a false finding generated by the check's own blind spot.

Findings, per component within the domain, comparing **exact strings** because
both sides are constraints written by the same renderer:

- values differ → `WARN` `TOOLKIT_CONFIG_DRIFT`, subject the catalog key,
  message naming both values.
- receipt has the key, the config does not, **and the key is one of the
  twelve** → `WARN` `TOOLKIT_CONFIG_MISSING`.
- all compared components agree → one `INFO` `TOOLKIT_CONFIG_OK` naming the
  count.
- the config file is absent or does not parse → `INFO`
  `TOOLKIT_CONFIG_UNAVAILABLE`, A skipped.

### B — installed-machine drift, opt-in

Compares receipt `installed.*` against a fresh probe, using the same commands
the receipt writer used. Both sides are concrete versions, so this is the only
comparison where equality on a version string is meaningful.

#### Every external executable comes from a seam

Comparison B reaches exactly three executables, and each has an explicit,
injectable source. Nothing is taken from ambient `PATH` at the point of use.

| Executable | Resolution | Default |
|---|---|---|
| `mise` | the existing `mise_bin()` | `WTD_MISE_BIN` when set, else `command -v mise` |
| `openspec` | `openspec_bin()`, new, same shape | `WTD_OPENSPEC_BIN` when **set**, else `command -v openspec` |
| `timeout` | `timeout_bin()`, new, same shape | `WTD_TIMEOUT_BIN` when **set**, else `command -v timeout` |

**The seam variables are never assigned at script scope.** Not with
`WTD_X="${WTD_X:-}"`, not with `declare WTD_X`, not with anything. Such an
assignment makes the variable *set* on every run, so `${WTD_X+x}` is always
true, the `command -v` branch becomes unreachable, and `--probe` is inert in
production while every fixture test still passes. That failure mode is silent
in exactly the place tests cannot see it, which is why the rule is absolute:
**an unset seam must stay genuinely unset.**

Three distinct states follow, and the resolvers must preserve all three:

| Seam state | Meaning | Resolver |
|---|---|---|
| **unset** | production | falls through to `command -v` |
| **set, non-empty** | injected | uses exactly that path, and only it |
| **set, empty** | deliberately absent | returns non-zero, searches nothing |

```bash
openspec_bin() {
  if [[ ${WTD_OPENSPEC_BIN+x} ]]; then
    [[ -n "$WTD_OPENSPEC_BIN" && -x "$WTD_OPENSPEC_BIN" ]] || return 1
    printf '%s' "$WTD_OPENSPEC_BIN"
    return 0
  fi
  command -v openspec 2>/dev/null
}

timeout_bin() {
  if [[ ${WTD_TIMEOUT_BIN+x} ]]; then
    [[ -n "$WTD_TIMEOUT_BIN" && -x "$WTD_TIMEOUT_BIN" ]] || return 1
    printf '%s' "$WTD_TIMEOUT_BIN"
    return 0
  fi
  command -v timeout 2>/dev/null
}
```

These follow the existing `mise_bin()` verbatim in shape — `${VAR+x}` for
set-ness, `printf '%s'` without a newline, `command -v … 2>/dev/null` as the
fall-through — and add one thing `mise_bin()` does not check: `-x`. A seam
pointing at a path that is not executable is **unusable**, and treating it as
usable would hand `timeout` a fixture that cannot run. An unusable explicit
seam returns non-zero exactly like an empty one; it never widens into a
`PATH` search.

Under `set -Eeuo pipefail`: `"$WTD_OPENSPEC_BIN"` is only expanded inside the
branch that already proved it set, so `set -u` is satisfied; `[[ … ]] ||
return 1` returns deliberately; and `command -v` as the final command makes
the function's status the resolution result, which every caller consumes as
`if ! bin="$(openspec_bin)"; then …`.

Resolution happens once per audit, at the point comparison B begins, and never
again.

**`MISE_BIN` is an installer global.** The doctor has no such variable and must
not acquire one. The probe table in the receipt section is written in the
installer's terms; comparison B runs the same commands with `$(mise_bin)`
substituted for `"$MISE_BIN"`, and wraps each in `$(timeout_bin) 10s`.

**No probe searches for an alternative after its seam fails.** No
`$HOME/.local/bin/mise`, no second candidate, no widening of the search. A
host-dependent hunt for an executable is precisely the class of behaviour this
tool exists to detect in others.

Failure of each seam is scoped to what depends on it:

| Seam unresolvable | Effect |
|---|---|
| `timeout` | **Comparison B does not run at all.** Unbounded probing is forbidden, so with no way to bound a probe there is nothing safe to run. One `INFO` `TOOLKIT_PROBE_UNAVAILABLE` says so. |
| `mise` | No mise-backed probe is attempted. **One** `INFO` `TOOLKIT_PROBE_UNAVAILABLE` naming mise, not one per component. The OpenSpec probe still runs, because it does not depend on mise. |
| `openspec` | Only `installed.openspec` is not measured. One `INFO` `TOOLKIT_PROBE_UNAVAILABLE` naming it. Every mise-backed probe still runs. |

None of these is a `FAIL`, and none changes the audit's exit status.

**Plain `audit` resolves none of the three.** Resolution is inside comparison
B, and B runs only under `--probe`. So is the receipt check: **with no
receipt, `audit --probe` invokes nothing either**, because there is no
`installed.*` to compare against.

**B does not run by default.** A and C read files; B executes up to thirteen
external commands, and an audit is something people run when something is
already wrong. Turning a diagnostic into a dozen subprocess launches — any of
which can hang on a broken toolchain, which is exactly when the doctor is
reached for — is the wrong default. The interface becomes:

```
wsl-toolchain-doctor.sh audit [--json] [--probe]
```

- plain `audit` runs the existing diagnostics plus comparisons A and C;
- `audit --probe` additionally runs B;
- `--probe` is valid with and without `--json`, in either order;
- when a **readable receipt exists** and B was omitted, plain `audit` emits one
  `INFO` `TOOLKIT_INSTALLED_NOT_PROBED` naming `--probe` as the way to run it.
  With no receipt, or an unreadable one, nothing probe-related is emitted
  beyond the existing precondition finding — a machine this toolkit never
  provisioned should not be told about a flag that would tell it nothing.

The `audit` arm currently accepts at most one argument and only `--json`, as an
inline `(( $# > 1 ))` test. It gains a `parse_audit_args` helper. It is *not*
merely "shaped like `parse_fix_args`": that one tolerates a repeated flag,
while `audit` today rejects a second argument outright, and that strictness is
kept. The helper therefore tracks what it has already seen:

`PROBE_MODE` is a **mode global, and it is declared as one**, beside the
doctor's existing `JSON_MODE` and `DRY_RUN` at script scope:

```bash
PROBE_MODE=0
```

That is deliberately unlike the executable seams, which must stay unassigned:
a mode flag is the doctor's own state and always has a value, while a seam's
absence is information the resolver has to read. Declaring `PROBE_MODE`
guarantees no later code can reach an unset one under `set -u`, whatever path
the command line took.

```bash
parse_audit_args() {
  local arg
  local seen_json=0
  local seen_probe=0

  JSON_MODE=0
  PROBE_MODE=0

  for arg in "$@"; do
    case "$arg" in
      --json)
        if (( seen_json == 1 )); then
          return 1
        fi
        seen_json=1
        JSON_MODE=1
        ;;
      --probe)
        if (( seen_probe == 1 )); then
          return 1
        fi
        seen_probe=1
        PROBE_MODE=1
        ;;
      *)
        return 1
        ;;
    esac
  done

  return 0
}
```

Two `set -e` details are load-bearing. The arithmetic appears **inside `if`
conditions**, never as a standalone `(( … ))` command, because a standalone
arithmetic command returns 1 when its expression evaluates to zero — the same
trap as the line counter. And the function **ends with an explicit
`return 0`**, because the `for` loop's last iteration would otherwise decide
the return value; `case` with no matching pattern returns 0, but relying on
that in a function whose caller tests its status is how a parser starts
failing on its own success.

The contract:

- either flag may appear first: `audit --json --probe` and
  `audit --probe --json` are both valid;
- each may appear **at most once**; a repeated `--json` and a repeated
  `--probe` each return 1;
- any other argument returns 1;
- the parser **resets `JSON_MODE` and `PROBE_MODE` to 0 before parsing**, so a
  run never inherits a previous value;
- `main` answers a non-zero return with `usage >&2; return 2`, and **no audit
  runs and no probe is invoked** — the parse happens before `run_audit` is
  called, so an argument error costs nothing and measures nothing;
- a rejected command line may leave a **partial** assignment behind:
  `audit --probe --probe` sets `PROBE_MODE=1` before detecting the repeat.
  That is harmless precisely because the caller exits with status 2 without
  running anything, and because the next invocation resets both flags. No
  code path reads `PROBE_MODE` after a rejected parse.

#### Probe bounds

Every probe runs under `$(timeout_bin) 10s`. Ten seconds is far beyond a
healthy `mise exec … --version` and far below the patience of someone watching
an audit. The utility itself comes from a seam, described below.

- **A probe that times out** is reported `INFO` `TOOLKIT_PROBE_TIMEOUT`,
  naming the component. It is an inability to compare, never a `FAIL`, and
  never a drift claim.
- **A probe that fails or returns something unparseable** is reported `INFO`
  `TOOLKIT_PROBE_UNAVAILABLE`.
- **Either outcome continues to the next component.** One dead toolchain entry
  must not suppress the twelve invocations that would have worked. The probe
  loop therefore captures each probe's status rather than letting it propagate,
  which under `set -e` means each call is guarded (`if ! out="$(timeout …)"`).
- **B never changes the audit's exit status by itself.** An optional
  observational check that can fail an audit is a check people stop passing
  `--probe` to.
- If the timeout utility cannot be resolved, **B does not run at all** and
  reports one collective `TOOLKIT_PROBE_UNAVAILABLE`. Unbounded probing is not
  an acceptable fallback, so with no way to bound a probe there is nothing
  safe to run.

**Normalization before comparison**, applied to both sides:

| Component | Normalized form |
|---|---|
| `node` | strip a leading `v`; compare `X.Y.Z` |
| `bun`, `uv`, `python`, `maven`, `dotnet-ef`, `pyyaml` | `X.Y.Z` as printed |
| `java-17`, `java-21` | the quoted version token from `java -version`, e.g. `17.0.13` |
| `dotnet-10`, `dotnet-8` | the SDK version whose major matches the key |
| `shellcheck` | the token after `version:` |
| `gitleaks` | `X.Y.Z` as printed |
| `openspec` | first `X.Y.Z` match |

Comparison is string equality **after** normalization, never a range or prefix
test, and never against a `requested.*` value.

- differs → `WARN` `TOOLKIT_DRIFT_INSTALLED`, naming both.
- probe unavailable, unparseable or timed out → `INFO`
  `TOOLKIT_PROBE_UNAVAILABLE` or `TOOLKIT_PROBE_TIMEOUT`. No drift is claimed
  from a failed measurement.
- receipt has no `installed.*` for a component → nothing to compare, silently
  outside B.
- a component listed in `skipped=` is **not probed at all**. There is nothing
  installed to measure, and launching a subprocess to confirm that is waste.
- all compared components agree → one `INFO` `TOOLKIT_INSTALLED_OK`.

Components whose requested value is `latest` **are** compared in B. This is not
a contradiction of invariant 15: `latest` defeats *staleness*, which needs a
declared target, but B compares two concrete observations — what the install
recorded and what is on the machine now — and `shellcheck` moving underneath a
machine is exactly the kind of thing worth seeing.

Even with `--probe`, B does nothing when the receipt carries no `installed.*`
keys, so a machine this toolkit never provisioned pays nothing for it.

### C — catalog staleness

Compares the catalog's current value against the receipt's `requested.*`.

**Iteration is over the intersection**: the keys that appear as `requested.*`
in the receipt *and* as keys in the current catalog. That direction of
iteration is what makes the comparison forward-compatible:

- a catalog key the receipt predates — a component added since this machine
  was provisioned — is **outside C and produces no finding**. The machine is
  not stale on a pin it was never offered; that is a case for reprovisioning,
  not a warning, and the receipt has nothing to compare against.
- a `requested.*` key no longer in the catalog — a component since removed —
  is likewise outside C in principle, since it falls outside the intersection.
  **In practice this case is unreachable**: receipt validation's phase-2
  predicate 2 already rejects any receipt carrying a `requested.*` suffix that
  is not a catalog key, so such a receipt never survives `load_receipt` and C
  never runs against it at all. The bullet above records the intended
  direction of forward-compatibility should predicate 2 ever be relaxed; it is
  not describing a case C has to handle today.

`TOOLKIT_STALE_PIN` is emitted for a component in that intersection **only when
all four hold**:

1. the component is not in `skipped=`;
2. the component is not in `overridden=`;
3. the catalog's current value differs from `requested.<key>`;
4. the value is concrete — neither side is `latest`.

Condition 2 is the one with teeth. A machine provisioned with
`--node-version 22` has `requested.node=22` and `overridden=…,node,…`; without
that exclusion it would report stale against `node=24` forever, and the warning
people cannot act on is the warning they learn to ignore.

**There is no whole-catalog checksum fast path.** An earlier draft skipped C
entirely when `catalog-sha256` still matched the file on disk. That is removed.
It made one component's reported result depend on unrelated bytes elsewhere in
the file — a comment edit changes the digest and changes which findings appear,
while a value that never changed reports differently depending on its
neighbours. The saving was seventeen string comparisons. `catalog-sha256`
remains in the receipt as provenance only.

Multi-version Java and .NET need nothing special here: `java-17`, `java-21`,
`dotnet-10` and `dotnet-8` are ordinary keys compared one at a time. Arrays
exist only in the mise TOML, and only comparison A reads that.

**`karpathy-ref` participates in C**, unless skipped or overridden. A moved
commit pin is precisely the staleness worth reporting, and the comparison is a
plain string equality on two refs. **`karpathy-sha256` does not participate**,
in C or anywhere else: it is never written as `requested.*`, it is provenance
rather than a requested version, and a digest that differs from the catalog's
means the ref differs — which C already reports against `karpathy-ref`, once,
in terms a reader can act on. `superpowers` participates in C for the same
reason as `karpathy-ref`: it has no probe, but it has a declared ref.

- all compared components current → one `INFO` `TOOLKIT_PINS_CURRENT`.
- components excluded by conditions 1, 2 or 4 → one `INFO`
  `TOOLKIT_NOT_COMPARABLE`, naming them and why. One finding rather than a
  dozen: `uv`, `shellcheck`, `gitleaks`, `pyyaml` and `dotnet-ef` are always in
  it, and five identical notices per audit is how a check gets muted.

### Severity

`WARN` at worst, for every code in the domain. `FAIL` in this tool means a
policy violation — a Windows PE on `PATH`, interop disabled — and a machine
behind on a version is not one. Agreement emits `INFO` so the audit shows the
check ran rather than staying silent.

### Version and schema

`SCRIPT_VERSION` becomes `0.4.0`. Under the bump policy this is a **minor**
bump, and adding `--probe` does not change that: a new optional flag and new
finding codes are additive, every existing invocation behaves exactly as it
did, and `audit` without `--probe` runs no command it did not run before. A
major bump would be claiming a break that has not happened.

`SCHEMA_VERSION` stays `1`. The JSON shape is unchanged; new codes are data
inside the existing `findings[]` array, and `--probe` adds findings rather than
fields. This keeps faith with the existing doctor design document, whose
invariant list treats that number as a contract about shape.

## Workspace drift check

`scripts/check-catalog-drift.sh` in the parent workspace, beside `check-env.sh`,
`checkout-repos.sh` and `update-repos.sh`. The parent may reference children
freely; reconciling them is what a parent is for. No child gains a reference to
the workspace or to a sibling.

### `jq` is required

Not preferred — required. If `jq` is absent the check exits 2 with an install
hint. The earlier draft's `grep -oE` fallback is removed: a regular expression
over JSON silently returns the wrong value when formatting changes, and a
reconciliation check that can be wrong without saying so is worse than one that
refuses to run. The parent workspace has no Bash-only constraint; that
constraint belongs to the child's installer and doctor.

### Inputs and exact paths

| Input | Location |
|---|---|
| ADT catalog | `checkouts/agentic-dev-toolkit/catalog/software-catalog.env`, override `DRIFT_ADT_CATALOG` |
| spec-rivet manifest | `checkouts/spec-rivet/src/manifest/toolchain.yaml`, override `DRIFT_SPECRIVET_MANIFEST` |

The manifest is valid JSON despite the `.yaml` name. Extraction is by exact
path, never by recursive key search:

| Pair | ADT catalog key | `jq` filter | Relation |
|---|---|---|---|
| 1 | `openspec` | `.components.openspec.openspecVersion` | equal |
| 2 | `superpowers` | `.components.superpowers.superpowersVersion` | equal |
| 3 | `node` | `.components.openspec.minimumNodeVersion` | satisfies |

Filters use `jq -er` so a missing path is an error rather than the string
`null`. Pairs are hardcoded, so adding an overlap is a deliberate edit.

### Comparison semantics

**Equality (pairs 1 and 2)** is exact string equality after stripping trailing
whitespace. No `v`-prefix normalization: `superpowers=v6.3.0` and
`superpowersVersion: "v6.3.0"` are both written with the prefix today, and
teaching the check to ignore a prefix difference would hide a real
inconsistency in how the two repositories name the same ref.

**Satisfies (pair 3)** is a lower-bound test, because the two values are
different kinds. `spec-rivet` declares a minimum of `20.19.0`; the toolkit pins
a major, `24`. The algorithm:

1. Parse the minimum as `MAJOR.MINOR.PATCH`. A minimum that is not three
   numeric components is an unreadable input: exit 2.
2. Parse the catalog's `node` value. `latest` is not comparable — count it as
   an uncomparable pair, not as drift. Otherwise accept `N`, `N.M` or
   `N.M.P`, all numeric, and expand missing components with zero. `24` becomes
   `24.0.0`, which is the **lowest** version the constraint admits and
   therefore the right value to test.
3. Compare numerically, component by component, major then minor then patch.
4. Satisfied when the expanded catalog value is greater than or equal to the
   minimum. Otherwise drift.

Anything else in the catalog's `node` value — a range, a codename, a
non-numeric component — is unreadable input: exit 2.

### Reading the catalog

The parent does **not** get an ad hoc `grep | cut` reader. `adt-kv` is a
normative contract, and a second, laxer implementation of it is how the two
sides quietly stop agreeing on what a valid catalog is.

The drift check therefore validates the catalog against the full contract
before using any value: raw-line reading with the unterminated-final-line
guard, split at the first `=`, the key grammar `^[a-z0-9][a-z0-9.-]*$`, the
value grammar `^[A-Za-z0-9][A-Za-z0-9._:+@/-]*$`, duplicate-key rejection,
empty-value rejection with no allow-empty keys, trailing-`\r` stripping so a
CRLF catalog is normalized exactly as the child normalizes it, and
required-key validation for the keys the check actually uses — `openspec`,
`superpowers` and `node`.

It also inherits the **ordering** rules, not only the grammar: keys are
validated in source order and required keys in the declared required-key
order, so the first problem it reports in a broken catalog is the same
problem the installer would report. A reconciliation check whose error message
depends on hash order is a check whose failures cannot be triaged.

The catalog is the only `adt-kv` file the parent reads, so it needs no list
keys and no membership set: it passes an empty `LIST_KEYS` and an empty
`MEMBERS`, and the catalog has neither.

The parent has no pure-Bash constraint; that one belongs to the child's
installer and doctor. Bash or `awk` are both acceptable here. What is not
acceptable is a different grammar or a different order: whichever is chosen
must implement the contract above, and its fixtures must prove it.

**A reachable catalog that is unreadable, malformed, duplicated or incomplete
is exit 2.** It is not a reason to skip a pair and report success.

### Exit codes and accounting

Every configured pair reaches **exactly one** of five terminal categories, on
every exit path including a preflight failure:

| Category | Meaning |
|---|---|
| `agreed` | compared, and equal or satisfying |
| `drifted` | compared, and disagreeing |
| `skipped` | a child the pair needs is genuinely not checked out |
| `uncomparable` | every input was reachable and valid, and the pair still could not be decided — today only a `node` pin of `latest` against a numeric minimum |
| `failed` | evaluation stopped by a fatal dependency or a malformed reachable input |

`compared` is not a sixth category; it is the roll-up of the first two. Two
identities hold on **every** outcome:

```text
agreed + drifted           == compared
compared + skipped + uncomparable + failed == configured
```

Stating both is what keeps the total honest without double-counting `agreed`
and `drifted` inside it.

**The summary line, one format, printed on every outcome** — agreement, drift,
all children absent, and every exit-2 path including a preflight failure:

```
3 pairs configured, 0 compared, 0 agreed, 0 drifted, 0 skipped, 0 uncomparable, 3 failed
```

Tests assert this line verbatim on exit 0, exit 1 and exit 2.

The decision procedure, in order:

1. **Preflight.** If `jq` is missing, every configured pair is `failed` and the
   check exits 2 — **regardless of whether any child is checked out**. `jq` is
   a required dependency, not an input: without it no pair could have been
   evaluated even had every child been present, so reporting those pairs as
   `skipped` and exiting 0 would be a false clean bill.
2. **Presence.** For each pair, are all children it needs checked out? If not,
   print `skipped: <child> not checked out` once per absent child and mark
   every pair needing it `skipped`.
3. **Read and validate** the inputs of each remaining pair: the ADT catalog
   against the full `adt-kv` contract, the `spec-rivet` manifest against its
   exact JSON paths. Any failure — unreadable file, `adt-kv` violation, missing
   required key, missing JSON path, unparseable version — marks every pair
   depending on that input `failed`.
4. **Evaluate** the pairs that survive, into `agreed`, `drifted` or
   `uncomparable`.
5. **Exit**, in this precedence:
   1. `failed > 0` → **2**;
   2. else `drifted > 0` → **1**;
   3. else `compared == 0 && skipped == 0` → **2**;
   4. else → **0**.

Rule 5.1 outranks 5.2 deliberately: a run that could not read one of its
inputs cannot claim its verdict is complete, so "cannot run" beats "found
drift". Rule 5.3 is the silent-pass guard — everything was reachable, nothing
was absent, and still nothing was decided.

Behaviour, case by case:

| Case | Accounting | Exit |
|---|---|---|
| all three pairs agree | 3 compared, 3 agreed | 0 |
| `openspec` mismatch | 3 compared, 2 agreed, 1 drifted | 1 |
| `node` pin below the minimum | 3 compared, 2 agreed, 1 drifted | 1 |
| `node` pinned `latest` | 2 compared, 2 agreed, 1 uncomparable | 0 |
| `jq` missing | 3 failed | 2 |
| catalog malformed (reachable) | 3 failed | 2 |
| `spec-rivet` manifest malformed | 3 failed | 2 |
| required JSON path missing | 3 failed | 2 |
| both children absent | 3 skipped | 0 |
| one child present, one absent | 3 skipped | 0 |
| drift in one pair and a failure in another | mixed, `failed > 0` | 2 |

Absent versus unreadable is the distinction underneath all of it:

- **A child directory that does not exist** is `skipped`. Children are
  git-ignored and cloned on demand by `checkout-repos.sh`, so absence is a
  normal state of a fresh workspace, not a fault.
- **A child that is checked out but whose input is missing, unreadable,
  malformed, incomplete, or yields no value at the expected JSON path** is
  `failed`. The repository is there; failing to read it is a fault.

The mixed case deserves its own sentence, because the arithmetic is not
obvious. All three pairs need the `spec-rivet` manifest as well as the ADT
catalog. With `agentic-dev-toolkit` present and `spec-rivet` absent, all three
are `skipped`, none is `failed`, nothing is compared, and the check **exits
0** — a present child does not make an absent one's data readable.

The exit codes match the convention stated at the top of
`repository-policy/validate.sh`: 0 agree, 1 disagree, 2 cannot run.

### Tests

`scripts/check-catalog-drift-test.sh`, beside the script. Fixture-driven
through `DRIFT_ADT_CATALOG` and `DRIFT_SPECRIVET_MANIFEST`, so no case touches
a real checkout. Helpers are duplicated into the file rather than shared,
following the convention the child's suites state.

Comparison and exit-code cases: agreement across all three pairs (exit 0); an
`openspec` mismatch (exit 1); a `superpowers` mismatch (exit 1); a node pin
below the minimum (exit 1); a node pin above it (exit 0); a `latest` node pin
counted uncomparable, not drift; a malformed minimum (exit 2); a manifest
missing the expected JSON path (exit 2); both children absent (exit 0);
**one child absent and one present (exit 0)**; `jq` unavailable (exit 2).

Catalog-validation cases, each on a reachable catalog and each expecting
**exit 2**: a duplicate catalog key; a malformed line with no `=`; a malformed
key; a malformed value; an empty value; a missing required key (`node`,
`openspec` or `superpowers`); an unreadable catalog file. Plus one **exit 0**
case: a valid catalog whose final line has no trailing newline, proving the
parent's reader keeps the last key.

Summary-line cases: the seven-field line is printed and asserted **verbatim**
on an agreeing run (exit 0), a drifting run (exit 1), an all-absent run
(exit 0) and each exit-2 run, and in every case its categories satisfy
`compared + skipped + uncomparable + failed == configured` and
`agreed + drifted == compared`. The `jq`-missing case is included explicitly,
because it is the one that reports all three pairs as `failed` without ever
looking at a child.

This is a new test script in a workspace that has no test harness. It is
self-contained and adds no framework — the alternative, an untested
reconciliation check, is the thing that quietly stops reconciling.

It gains a line in the parent's "Checking it" section in `AGENTS.md`, beside
the independence loops.

## Failure model

| Condition | Behaviour |
|---|---|
| catalog missing or unreadable | `install.sh` dies at step 3, before any work |
| catalog key malformed, duplicated, empty, or required-and-missing | `install.sh` dies naming file, line and key |
| catalog value violates the value grammar | `install.sh` dies naming file, line and key |
| catalog missing a required key | `install.sh` dies naming the file and the key, with no line number |
| effective requested value empty or ungrammatical | `install.sh` dies naming key, value and source; nothing installed, no receipt written |
| `--flag=` with an empty inline value | `install.sh` dies with `requires a value`; never falls through to the catalog |
| `ADT_*` set but empty | not an override; the catalog value is used and the key does not appear in `overridden=` |
| installer probe fails or is unparseable | `warn`; that `installed.*` omitted; `ERR` trap not triggered; install succeeds |
| installer probe times out | identical to a failed probe |
| installer cannot resolve `timeout` | all **probe-derived** `installed.*` capture skipped; `installed.karpathy-sha256` still written when Karpathy was installed; one aggregate warning; valid receipt; no unbounded probe; install succeeds |
| a component is in `skipped=` | never probed; no `installed.*` key; **no warning** |
| `load_kv_file` fails | returns non-zero with the message in the caller's error scalar; installer `die`s with it, doctor turns it into an `INFO` finding, parent prints it and exits 2 |
| catalog missing, doctor | `TOOLKIT_CATALOG_UNAVAILABLE` `INFO`; C skipped, A runs, B runs if `--probe` |
| receipt missing, doctor | `TOOLKIT_NOT_PROVISIONED` `INFO`; A, B and C skipped; no probe advice |
| receipt malformed or truncated, doctor | `TOOLKIT_RECEIPT_UNREADABLE` `INFO`; A, B and C skipped; audit continues |
| receipt readable, `--probe` not given | `TOOLKIT_INSTALLED_NOT_PROBED` `INFO`; A and C run |
| global mise config missing or unparseable | `TOOLKIT_CONFIG_UNAVAILABLE` `INFO`; A skipped |
| a probe fails or is unparseable | `TOOLKIT_PROBE_UNAVAILABLE` `INFO`; remaining probes still run |
| a probe exceeds `timeout 10s` | `TOOLKIT_PROBE_TIMEOUT` `INFO`; remaining probes still run |
| timeout seam unresolvable — unset and not on `PATH`, or set empty, or set to a non-executable path | B does not run; one collective `TOOLKIT_PROBE_UNAVAILABLE`; no `PATH` fallback |
| openspec seam unresolvable, same three ways | only `installed.openspec` is not measured; every mise-backed probe still runs |
| mise seam unresolvable | no mise-backed probe; one `TOOLKIT_PROBE_UNAVAILABLE` naming mise; the OpenSpec probe still runs |
| installer cannot resolve `ADT_INSTALL_ROOT` | exits non-zero naming the script path, before any catalog read or argument parsing |
| receipt write fails | run exits non-zero under the `ERR` trap; **no completion summary**; any earlier receipt left byte-identical |
| unknown or repeated `audit` argument | `usage` to stderr, exit 2, as today |
| install fails part-way | no receipt written; a previous receipt is left untouched |
| install dies mid-write of the receipt | temporary file removed by the existing `cleanup` trap; previous receipt intact |
| `--dry-run` / `--verify-only` | no receipt written, and `--dry-run` says so |
| no `.git`, or no `git` on `PATH` | `source-commit=unknown`, not an error |
| worktree dirty at install time | `source-commit=<sha>-dirty` |
| drift check: `jq` absent | exit 2 |
| drift check: child absent | pairs needing it skipped; exit 0 if nothing else failed |
| drift check: child present, input unreadable or malformed | exit 2 |
| drift check: catalog violates `adt-kv` | exit 2 |
| drift check: zero comparisons, a child was absent, nothing failed | exit 0 |
| drift check: zero comparisons, every child present, nothing failed | exit 2 |
| drift check: drift in one pair and a failure in another | exit 2; cannot-run outranks disagreement |
| drift check: `jq` absent, children present or not | all pairs `failed`, exit 2 |

## Testing

### `tests/install.sh`

**The harness change, and its regression.** `load_installer_functions` sets and
exports `ADT_CATALOG_FILE` before sourcing. One test proves that change is both
sufficient and safe: after `load_installer_functions` returns, the harness's
own `readonly` globals are intact — `REPOSITORY_ROOT` still names the
repository root, `INSTALLER` and `CLAUDE_TEMPLATE` are unchanged — and sourcing
emitted no `readonly variable` diagnostic. That is the regression guarding the
`ADT_INSTALL_ROOT` naming decision, and it fails loudly the day a new installer
global takes a harness name.

**The shipped catalog validates.** One test runs the real
`catalog/software-catalog.env` through the validator and asserts it satisfies
the complete schema: all seventeen required keys present, every key matching
the key grammar, every value matching the scalar grammar, no duplicates, no
empty values. Without it every fixture could pass while the file the installer
actually loads is broken.

Format and loading, run by invoking the installer as a program with
`ADT_CATALOG_FILE` pointed at a fixture:

- missing catalog dies, naming the path;
- malformed key dies, naming key and line;
- malformed scalar value dies, naming the key;
- empty scalar value dies, naming the key;
- missing required key dies, naming the file and the key;
- duplicate key dies, naming both lines;
- a CRLF catalog parses identically to the LF original;
- a catalog whose final line has no newline still yields that key;
- a comment with leading whitespace, and a `#` inside a value, both behave as
  specified;
- a catalog whose first line is a valid record loads without aborting — the
  regression for the `set -e` line-counter bug, which would otherwise fail
  every catalog at line 1.

List values, exercised by validating receipt fixtures:

- `skipped=` empty is valid, and so is `overridden=` empty;
- a single element is valid;
- several elements are valid;
- a **leading** comma is rejected;
- a **trailing** comma is rejected;
- a **doubled** comma is rejected;
- an element that is not a catalog key is rejected, naming the element, **when
  a catalog is available** — the installer always has one;
- with an **explicitly initialized empty membership map** —
  `declare -A EMPTY_MEMBERS=()`, standing in for the doctor with no readable
  catalog — list syntax and duplicate elements are still rejected, membership
  is not checked, and `${#EMPTY_MEMBERS[@]}` does not trip `set -u`;
- membership validation **runs without an unbound-variable abort** under
  `set -u`: the case exists because an earlier draft had the caller reach into
  `validate_kv`'s locals, which fails exactly there;
- a **repeated** element is rejected, naming the element — not deduplicated;
- a bad element's diagnostic carries the line number of the `skipped=` or
  `overridden=` line it appeared on, not the line of some other key;
- a comma in a *scalar* value, such as `requested.node=24,25`, is rejected:
  the scalar grammar admits no comma.

Wiring and precedence:

- the catalog reaches the installer's defaults — the three deliberate
  source-greps in `test_mise_configuration_pins_bun` and
  `test_installer_defaults_python_to_312` are retargeted from the installer to
  the catalog file, carrying their comments across. They exist because
  `BUN_VERSION` and `PYTHON_VERSION` are globals earlier tests reassign, so a
  rendered-output check would pass on inherited state. That reasoning survives
  the move;
- a CLI flag beats `ADT_*` beats catalog, asserted at all three layers;
- **`ADT_NODE_VERSION=""` uses the catalog value and does not add `node` to
  `overridden=`** — the empty-variable case `${ADT_X:-…}` falls straight
  through, and recording it as an override would make the doctor suppress a
  staleness finding nobody asked to suppress;
- `--maven-version` and `--dotnet-ef-version` are rejected as unknown options,
  documenting that those two components are overridable only through `ADT_*`;
- **the `overridden=` allowlist is exact.** A catalog-derived override
  (`--node-version 22`) enters the list; an environment-only override
  (`ADT_MAVEN_VERSION`, `ADT_DOTNET_EF_VERSION`) enters it; and none of
  `ADT_OPENSPEC_TOOLS`, `ADT_GCM_PATH`, `--gcm-path`, `ADT_KARPATHY_SHA256`,
  `--karpathy-sha256`, any `--skip-*`, `--project`, `--repair-codex`,
  `--dry-run`, `--upgrade` or `--verify-only` enters it;
- **every member emitted in `overridden=` is a real catalog key**, asserted by
  validating the written receipt with `MEMBERS` set to the catalog;
- **`overridden=` is a set, not an append log.** An environment override alone
  produces one member; a CLI override alone produces one member; and
  `ADT_NODE_VERSION=22 … --node-version 23` — both layers naming `node` —
  produces `node` **once**, never `node,node`;
- in that same case the **effective value is the CLI's**:
  `requested.node=23`;
- **a repeated version flag is last-value-wins**: `--node-version 22
  --node-version 23` yields `requested.node=23` and one `node` member;
- **two overridden components serialize in canonical catalog order**:
  overriding `node` and `python` yields `overridden=python,node`, whichever
  order the flags were given;
- the written receipt **passes the doctor's duplicate-list validation**, and
  a hand-edited receipt containing `overridden=node,node` is still
  **rejected** on read;
- `--dry-run` output reflects the catalog value for a component with no
  override.

Effective requested-value validation — the gate that runs before any
installation work:

- accepted: a catalog-derived value; a non-empty `ADT_*` override; a
  separate-value CLI override (`--node-version 22`); an inline override
  (`--node-version=22`);
- rejected, with `die` naming key, value and source: a separate-value override
  containing a space; an override containing a comma
  (`--node-version=24,25`); an override containing brackets or a control
  character; a non-empty `ADT_*` value that violates the scalar grammar; a
  catalog value that violates it, caught at load;
- **`--node-version=` with an empty inline value dies with
  `requires a value`** and does not fall through to the catalog;
- **`ADT_NODE_VERSION=""` falls through to the catalog and does not appear in
  `overridden=`** — the settled distinction between an absent opinion and a
  malformed one;
- an invalid requested value causes **no installation action**: with `run`
  and `run_sudo` stubbed to record, nothing is recorded;
- an invalid requested value **writes no receipt**, and leaves any earlier
  receipt byte-identical;
- the error message names the source, asserted for all three layers — CLI
  flag, environment variable, catalog.

`--version`:

- with a valid catalog, `install.sh --version` prints exactly `0.1.0` and
  exits 0;
- it performs no mutating operation: run with `run` and `run_sudo` stubbed to
  record invocations, nothing is recorded and no file is written;
- with the catalog missing, `--version` fails under the catalog failure
  contract — dies naming the path, non-zero;
- with a malformed catalog, `--version` fails under the same contract;
- `--version` never produces `Unknown option: --version`, which is what
  placing its arm after the generic `*)` would cause.

Karpathy, mandatory regressions kept and re-asserted against the
catalog-sourced defaults:

- a custom ref with no digest is refused;
- a digest contradicting the pin is refused;
- the pinned ref always verifies against the built-in digest;
- `KARPATHY_SHA256` is empty by default even though the catalog carries a
  digest — the regression that guards the mapping in this design.

Receipt:

- written on success, at the documented path;
- **not** written on `--dry-run`, on `--verify-only`, or after a failure;
- written atomically — a pre-existing receipt is either the old content or the
  new one, and no `.install-receipt.*` temporary survives;
- file mode `0644` and directory mode `0755` under both `umask 022` and
  `umask 077`;
- `requested.*` records constraints and `installed.*` records concrete
  versions, and a `--node-version 22` run records `requested.node=22`;
- the receipt carries **exactly sixteen `requested.*` keys** — every catalog
  key except `karpathy-sha256` — on a default run, and
  **`requested.karpathy-sha256` is never written** on any run;
- a heavily selective run (`--skip-runtimes --skip-openspec --skip-karpathy`)
  still writes all sixteen, still passes required-key validation, and records
  the omissions only in `skipped=`;
- `skipped=` holds expanded catalog keys, with `--skip-runtimes` expanding to
  the runtimes **and** the three quality tools, and `--skip-claude` alone
  leaving it empty because Claude Code has no catalog key;
- both list keys are written in **catalog declaration order**, so two runs with
  the same flags produce byte-identical lists;
- multi-version Java and .NET each produce two `requested.*` and two
  `installed.*` keys, from a single `dotnet --list-sdks` invocation in the
  .NET case;
- `latest`-pinned components still get an `installed.*` value;
- **every `installed.*` value is validated before it is written.** A stubbed
  probe returning a clean token is recorded; one returning an empty string, a
  value with spaces, a value containing `(…)` or `[…]`, or several lines is
  **omitted** with a `warn`, never written raw and never written quoted;
- **one invalid probe result does not suppress the others**: with a single
  component's probe stubbed to return garbage, every other `installed.*` is
  still written and the receipt is still complete in every other respect;
- **skipped components are never probed**: with `--skip-runtimes`, no runtime
  probe stub is invoked; with `--skip-openspec`, no OpenSpec probe; with
  `--skip-quality-tools`, none of the three quality probes. In each case no
  `installed.*` key appears **and no missing-tool warning is emitted**;
- **the shared .NET probe runs only when needed**: skipping both .NET
  components invokes `dotnet --list-sdks` zero times; skipping one invokes it
  once and writes exactly one key;
- **a failing probe does not trigger the `ERR` trap**: with a probe stubbed to
  exit non-zero, the run completes successfully and `on_error` never fires;
- **a timed-out probe does not abort**: with a probe stubbed to outlive the
  bound, the run warns, omits that key and completes;
- **an unresolvable `timeout` skips all probe-derived capture with one
  aggregate warning**: no probe-table `installed.*` key is written, exactly
  one warning is emitted, **no probe runs unbounded**, and the receipt is
  still written and still valid;
- **an unresolvable `timeout` with Karpathy installed still writes
  `installed.karpathy-sha256`**, holding the digest that was verified during
  installation, while every probe-derived key is absent; all sixteen
  `requested.*` keys and every provenance field remain present, and the
  receipt validates;
- **an unresolvable `timeout` with Karpathy skipped writes no
  `installed.karpathy-sha256`** and no missing-tool warning about it; the
  receipt still validates;
- `installed.karpathy-sha256` is never compared in comparison B in either
  case;
- **one failed probe does not suppress later probes**: with the first
  component's probe failing, the last component's still runs and is recorded;
- **requested values and provenance survive total probe failure**: with every
  probe failing, the receipt still carries all sixteen `requested.*` keys,
  `skipped=`, `overridden=`, `script-version`, `installed-at`,
  `source-commit` and `catalog-sha256`, and still validates;
- **the receipt the installer just wrote passes the doctor's own validator** —
  loaded back and run through the receipt's phase 1 and phase 2 rules;
- `superpowers` gets `requested.*` and no `installed.*`; Karpathy gets
  `installed.karpathy-sha256`;
- `source-commit` is a full 40-character SHA, gains `-dirty` on a modified
  worktree, and is `unknown` outside a checkout.

Lifecycle and sequencing:

- **`die` and the `ERR` trap are defined before root resolution.** Asserted
  against the installer source, in the same style as the existing default
  greps: the line defining `die` precedes the line assigning
  `ADT_INSTALL_ROOT`. This is the regression for the ordering fix — a bare
  `cd` before diagnostics exist reports nothing useful when it fails;
- an unresolvable root exits non-zero with a message naming the script path,
  before any catalog read or argument parsing;
- **`write_install_receipt` runs between `verify_installation` and
  `print_summary`**, asserted on call order with all three stubbed;
- **a receipt-write failure prevents the completion summary**: with the state
  directory made unwritable, the run exits non-zero and `print_summary`'s
  text never appears;
- a failed receipt write leaves a pre-existing receipt byte-identical;
- `--verify-only` returns before `write_install_receipt` is reached at all,
  and `--dry-run` reaches it and writes nothing.

Receipt validation phases, exercised against hand-written receipt fixtures:

- phase 1 fails on the **first** absent literal key in the declared order —
  a receipt missing both `installed-at` and `overridden` names `installed-at`;
- phase 2 predicate 1: a receipt with the six literals and no `requested.*`
  key is invalid;
- phase 2 predicate 2: a `requested.*` whose suffix is not a catalog key is
  invalid, naming the earliest such key in source order;
- phase 2 predicate 3: `requested.karpathy-sha256` present is invalid;
- phase 2 predicate 4: `installed.karpathy-sha256` is accepted, while an
  `installed.*` with a non-catalog suffix is not;
- the phases run in order: a receipt with both a missing literal key and a
  structural defect reports the literal key.

Diagnostics, asserted on message text so the contract cannot rot:

- a duplicate key names both the duplicate's line and the first occurrence's;
- an empty value, a malformed value, a malformed key, a malformed list and a
  bad list element each name `FILE:LINE:`;
- a **missing required key names the file and the key, contains no line
  number, and reports only the first missing key in declared required-key
  order** — the same broken catalog naming the same key on every run;
- **a successful load populates all three caller arrays and clears the error
  scalar**; a failed load returns non-zero, sets the diagnostic in the
  caller's scalar, and introduces no global;

##### The load-integrity gate

This one needs specifying carefully, because the obvious checks do not work
and because the ordinary way of reporting a failure is itself unavailable
here.

**It cannot report through `fail` or `assert_equal`.** `assert_equal`
delegates to `fail`, and `fail` is the object under test. If a replacement
`fail` returns success, every assertion *about* `fail` also returns success
and the suite reports a clean run. **This is the one place in the suite that
deliberately bypasses the ordinary assertion helpers**: each check is an `if`,
reports with `printf … >&2`, and terminates with `exit 1`. Nothing in the gate
calls `fail`, `assert_equal`, or anything that delegates to them.

**`declare -F fail` and `type -t fail` cannot detect a replacement.** The
first prints the function's *name*, the second prints `function`; both are
byte-identical before and after the body changes. A comparison of the *set* of
global function names is equally blind, because replacing a function adds no
name and removes none. No claim may rest on any of the three alone.

**It uses the harness's existing single load.** `tests/install.sh` calls
`load_installer_functions` exactly once, between
`test_claude_template_resolves_after_copying_to_project_root` and the first
installer-dependent test. Sourcing the body twice in one shell fails —
`readonly variable` on the second pass — so the gate must not call the loader
itself. It brackets the existing call:

```bash
TEMP_DIR="$(mktemp -d)"
test_claude_template_resolves_after_copying_to_project_root

fail_body_before="$(declare -f fail)"
functions_before="$(declare -F | awk '{ print $3 }' | sort)"

load_installer_functions          # the existing single call, unmoved

fail_body_after="$(declare -f fail)"
functions_after="$(declare -F | awk '{ print $3 }' | sort)"

# … the four integrity checks below …

test_lttng_selector_prefers_time64_package_when_available
# … the existing invocation sequence, unchanged …
```

The *before* snapshots must be taken **before** that call, because step 3's
catalog load runs during the source; snapshotting twice afterwards compares a
corrupted state with itself and proves nothing. No test function anywhere
calls `load_installer_functions`.

**Check 1 — body identity.** `declare -f`, lower-case, because it emits the
body, which is the only thing that changes under replacement:

```bash
if [[ "$fail_body_after" != "$fail_body_before" ]]; then
  printf 'FAIL: installer loading replaced the test harness fail helper\n' >&2
  exit 1
fi
```

**Check 2 — behaviour.** Body identity proves the text is unchanged; this
proves the helper still works. The call runs in an isolated subshell so the
expected exit does not take the suite with it, and a marker file proves
unreachability rather than assuming it:

```bash
marker="$TEMP_DIR/fail-fell-through"
err_trap="$(trap -p ERR)"
trap - ERR
set +e
output="$(
  (
    fail "sentinel failure"
    : > "$marker"
  ) 2>&1
)"
status=$?
set -e
eval "$err_trap"

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
```

`set +e` around the capture is necessary but **not sufficient on its own**.
Sourcing the installer body arms `trap on_error ERR` in the current shell, and
`set +e` does not disarm an ERR trap — it only stops a failing *simple
command* from aborting the script under `errexit`. `fail`'s `exit 1`, run
inside the command substitution above, still fires the armed trap, and the
trap's own handling then propagates the failure outward and takes the whole
suite down before a single test runs, `set +e` notwithstanding. The gate must
therefore disarm the trap for the duration of the capture and restore it
afterwards: `trap -p ERR` prints the trap currently installed as a re-runnable
`trap ... ERR` command, `trap - ERR` clears it, and `eval "$err_trap"` restores
exactly what was there — whatever `on_error` was armed with, unchanged — once
the capture is over. `set +e` still matters alongside this: the assignment
takes the subshell's status, and a non-zero one is the *expected* outcome; it
also means a replacement that merely `return`s does not abort the subshell, so
`: > $marker` runs — which is exactly what the marker is there to catch.

**Check 3 — catalog arrays survived the loader's scope.** The body is sourced
inside a function, so a `declare` without `-g` is function-local and vanishes
on return. This check fails if that regression is ever reintroduced, and it
uses the same independent path because function integrity is only just
established:

```bash
if (( ${#CATALOG[@]} == 0 )); then
  printf 'FAIL: catalog values did not survive installer loading\n' >&2
  exit 1
fi

if (( ${#CATALOG_ORDER[@]} == 0 )); then
  printf 'FAIL: catalog order did not survive installer loading\n' >&2
  exit 1
fi

if ! declare -p OVERRIDDEN_SET >/dev/null 2>&1; then
  printf 'FAIL: override set did not survive installer loading\n' >&2
  exit 1
fi
```

`OVERRIDDEN_SET` is tested for existence rather than size, because an empty
override set is the normal state of a run with no overrides.

**Check 4 — no leaked function names.** This is the only check that catches a
nested helper under a *new* name, and its expected set is derived
mechanically rather than maintained by hand:

```bash
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

Three properties make this precise rather than hand-waved. The matcher is
**anchored to column zero**, so a nested declaration — which is indented — is
never admitted to the expected set; deriving the allowlist from *all*
declarations would admit the very thing the check exists to detect.
Pre-existing harness functions are subtracted by the `comm -13` against the
before-snapshot, so the delta is only what loading introduced. And the
snapshot is taken **immediately after the load, before any installer test
runs** — which matters concretely: `install.sh` legitimately defines
`verify_command` inside `verify_installation`, and that definition does not
exist until a test calls it. Snapshotting later would flag a real, intended
nested function as a leak.

Detection is not interchangeable, and each mutation is caught by a specific
check:

| Mutation | What actually happens | Caught by |
|---|---|---|
| nested `fail()` that **returns 0** | subshell's last command is `: > $marker`, so `status` is 0 and the marker exists | body identity; status check; marker check |
| nested `fail()` that **`return 1`s** without exiting | `set +e` lets execution continue, `: > $marker` runs and succeeds, so the subshell's status is **0**, not 1 | body identity; status check; marker check |
| replacement that **exits non-zero with a different prefix** | subshell exits 1, marker absent, output wrong | body identity; **prefix check** |
| a **differently named** leaked helper, e.g. `kv_fail()` | `fail` is untouched; a new name appears | **only** check 4 |

The second row is the one worth reading twice: a `return`-based replacement
does **not** leave the status non-zero, because the marker command becomes
the subshell's final, successful command. Body identity, the status check and
the marker check all fire; claiming the status stays correct would have been
wrong.

Once the gate passes, the suite returns to normal: **later tests use the
ordinary `fail` and `assert_equal`**, the existing invocation sequence is
unchanged, no individual test sources the installer again, tests needing a
different catalog run the installer as a separate process as already decided,
and no `readonly` initialization runs twice in one shell.

- **duplicate-key and malformed-line diagnostics keep their exact text** —
  `FILE:LINE: duplicate key: KEY (first seen at line N)` and
  `FILE:LINE: missing '=' separator` — asserted verbatim, since inlining the
  writes is where wording most easily drifts;
- **the loader is called directly, never through command substitution.**
  Asserted two ways: against the installer source, that no `load_kv_file`
  call site is preceded by `$(` on the same line; and behaviourally, that
  after a successful load the caller's arrays are non-empty — the assertion
  that fails immediately if anyone reintroduces a subshell, because the arrays
  would come back empty with a zero status;
- **the installer, the doctor and the parent receive the same diagnostic
  text** for the same malformed file: one contract, three consumers;
- **two simultaneous defects report the same first error, deterministically.**
  Two cases: a catalog with a malformed value on an early line and another on
  a later line always names the earlier line, because syntax validation walks
  the source-order array rather than the associative array; and a catalog
  missing two required keys always names the earlier of the two in declared
  required-key order. Both are run repeatedly in one test to prove the answer
  does not move between invocations.

### `tests/wsl-toolchain-doctor.sh`

`run_doctor()` pins every path and every executable comparison B can reach, so
no case can read host state or run a host binary:

- `XDG_STATE_HOME`, `XDG_CONFIG_HOME` — new. `HOME` is already pinned, but a
  developer machine that exports `XDG_STATE_HOME` would otherwise leak a real
  receipt into the suite;
- `WTD_CATALOG_FILE`, `WTD_RECEIPT_FILE`, `WTD_MISE_TOOLCHAIN_CONFIG` — new;
- `WTD_MISE_BIN` — already threaded through `run_doctor()`, reused as-is;
- `WTD_OPENSPEC_BIN`, `WTD_TIMEOUT_BIN` — new, so that no test reaches the
  developer's real `openspec` or `timeout`.

Version and preconditions:

- `SCRIPT_VERSION` is declared; `--version` exits 0 and prints exactly `0.4.0`;
  the JSON carries `"toolVersion":"0.4.0"` — both existing assertions updated
  from `0.3.0`;
- no receipt → `TOOLKIT_NOT_PROVISIONED` `INFO`, exit status unchanged;
- a malformed receipt, and separately a truncated one →
  `TOOLKIT_RECEIPT_UNREADABLE` `INFO`, the audit still completes and later
  findings still appear;
- a receipt missing a required key reports **the first** missing key, in the
  same declared order the installer uses;
- a **duplicate-key** load failure reaches `TOOLKIT_RECEIPT_UNREADABLE` with
  the loader's own message text, proving the diagnostic survives the
  direct-call path;
- a **valid** receipt gives the doctor both populated arrays and an empty
  error scalar;
- no catalog → `TOOLKIT_CATALOG_UNAVAILABLE` `INFO`; A still runs, and B runs
  only if `--probe` was given.

Comparison A:

- agreement → `TOOLKIT_CONFIG_OK`; a changed `node` in the global config →
  `TOOLKIT_CONFIG_DRIFT`; a reordered `java = [...]` array → drift on both
  `java-17` and `java-21`; a config missing a key present in the receipt →
  `TOOLKIT_CONFIG_MISSING`;
- a receipt key outside the twelve mise-managed keys — `openspec`, say — never
  produces `TOOLKIT_CONFIG_MISSING`, however absent it is from the `[tools]`
  table;
- **a component in `overridden=` still participates in A**: change it in the
  global config and `TOOLKIT_CONFIG_DRIFT` still fires. `overridden=` excludes
  a component from C alone;
- **a project-local mise configuration in the working directory produces no
  finding** — the case that proves A reads the global file;
- `node` and `bun` are compared in A, which the existing collision watchlist
  cannot do.

Comparison B and `--probe`:

- B is **not** executed by plain `audit`: with a receipt present and a probe
  command stubbed to record its invocation, the stub is never called;
- plain `audit` with a readable receipt emits `TOOLKIT_INSTALLED_NOT_PROBED`;
- plain `audit` with **no** receipt emits no probe-related finding at all;
- **with no receipt, `audit --probe` executes no probe either**;
- `audit --probe` executes B; `audit --probe --json` does too and the JSON
  stays valid; `--json --probe` is accepted in either order;
- an unknown `audit` argument exits 2 with usage; **`audit --json --json` and
  `audit --probe --probe` each exit 2**, preserving today's strictness;
- an argument error runs **no audit and no probe**: with all three seam
  fixtures in place, their logs are empty after a rejected command line;
- agreement → `TOOLKIT_INSTALLED_OK`; a changed probe result → `WARN`
  `TOOLKIT_DRIFT_INSTALLED`; a failing probe → `TOOLKIT_PROBE_UNAVAILABLE` and
  no drift;
- **the seams behave differently when unset, injected, empty and unusable**,
  one case each:
  - **unset** — with `WTD_OPENSPEC_BIN` and `WTD_TIMEOUT_BIN` *not exported at
    all* and fixture directories placed on `PATH`, the resolvers fall through
    to `command -v` and find them. **This is the production path**, and the
    case exists so that a suite made entirely of injected fixtures cannot
    conceal a `--probe` that is inert in production — precisely the failure a
    top-level `WTD_X="${WTD_X:-}"` assignment would have caused;
  - **injected** — set to a fixture path, that fixture is used;
  - **empty** — set to `""`, the resolver returns non-zero and **no `PATH`
    search happens**, proven by leaving a working tool on `PATH` and asserting
    it is never invoked;
  - **unusable** — set to a path that exists but is not executable, treated
    exactly like empty, again with no `PATH` fallback;
- **the injected timeout fixture wraps every probe**: with `WTD_TIMEOUT_BIN`
  pointing at a recording fixture, every probe B runs appears in its log, and
  the count matches the number of components probed;
- **`WTD_TIMEOUT_BIN=""` — no resolvable timeout**: **B does not run at all**,
  one collective `TOOLKIT_PROBE_UNAVAILABLE` is emitted, neither the mise
  fixture nor the openspec fixture is invoked, and nothing is `FAIL`;
- **`WTD_MISE_BIN=""` — no resolvable mise**: no mise-backed probe is
  attempted, exactly **one** `TOOLKIT_PROBE_UNAVAILABLE` naming mise is
  emitted rather than one per component, the OpenSpec probe still runs,
  nothing is `FAIL`, and the audit's exit status is unchanged;
- **`WTD_MISE_BIN` pointing at a fixture script**: every mise-backed probe
  runs through that fixture. The assertion is that B reaches **only the three
  injected fixtures** — mise, openspec, timeout — not that it reaches no other
  executable at all, which would contradict needing a timeout and an openspec
  in the first place;
- **`WTD_OPENSPEC_BIN` pointing at a fixture**: `installed.openspec` is
  measured through it;
- **`WTD_OPENSPEC_BIN=""` — no resolvable openspec**: only that one
  measurement is lost, every mise-backed probe still runs, one
  `TOOLKIT_PROBE_UNAVAILABLE` names openspec;
- **a mise-backed probe failing does not suppress the injected OpenSpec
  probe**: with the mise fixture failing, the openspec fixture is still
  invoked and still reports;
- **nothing resolves from ambient host `PATH`**: with all three seams pointing
  at fixtures in the temporary directory and `PATH` emptied of the real tools,
  the audit still completes and every recorded invocation is a fixture;
- **no receipt invokes none of the three seams**: with `--probe` and no
  receipt, all three fixture logs are empty;
- one probe timing out yields `TOOLKIT_PROBE_TIMEOUT`, does not abort the
  audit, and leaves later findings intact;
- one probe failing does not suppress later probes: with the first component's
  probe stubbed to fail, the last component's probe still runs;
- a component in `skipped=` is never probed — its stub is never invoked;
- a `latest`-pinned component **is** probed and compared concretely in B,
  while never appearing as a stale pin in C.

Comparison C:

- a catalog ahead of the receipt → `TOOLKIT_STALE_PIN`; the same component in
  `overridden=` → no finding; the same component in `skipped=` → no finding; a
  `latest` component → never a stale pin, and named in
  `TOOLKIT_NOT_COMPARABLE`;
- a catalog key absent from an older receipt produces no finding, and a
  `requested.*` key absent from the current catalog produces none either.

Across the whole domain: **no `TOOLKIT_*` finding is ever `FAIL`**, with or
without `--probe`.

### `tests/opencode-service.sh`

- `SCRIPT_VERSION` declared; `--version` exits 0 and prints it;
- **invocation with no arguments completes normally under `set -e`** — the
  `--version` guard's false path must not terminate the script, which is the
  regression for using `if` rather than a bare `&&`;
- an unknown argument behaves exactly as today — ignored, not rejected. This is
  the case that protects the systemd units.

### `tests/repository-policy.sh`

- `SCRIPT_VERSION` declared; `--version` exits **0** and prints it;
- `--version` is not swallowed by the generic `-*` arm;
- `--help` still exits 2, and an unknown option still exits 2.

### Parent workspace

`scripts/check-catalog-drift-test.sh`, with the comparison, catalog-validation
and summary cases listed under the drift check above. Two requirements bear
repeating because they are what make the accounting model testable rather than
decorative:

- the summary line is asserted **verbatim** on an exit 0, an exit 1 and an
  exit 2 run;
- **every exit-2 path** — missing `jq`, malformed catalog, malformed manifest,
  missing JSON path — still prints a complete summary whose categories satisfy
  `compared + skipped + uncomparable + failed == configured` and
  `agreed + drifted == compared`.

## Documentation

| File | Change |
|---|---|
| root `AGENTS.md`, pinned-defaults table | replace the literal default values with a pointer to `catalog/software-catalog.env`; keep the component list and the pinned-versus-`latest` classification. The current claim that every pin is "overridable by a CLI flag or an `ADT_*` environment variable of the same name" must be corrected while the table is being edited: every pin has an `ADT_*` variable, but `maven` and `dotnet-ef` have no CLI flag |
| root `AGENTS.md` | add the `catalog/` component; add the `SCRIPT_VERSION` bump policy; note that `install.sh` and the catalog ship together |
| root `AGENTS.md` test section | the harness now exports `ADT_CATALOG_FILE` before sourcing the installer body |
| `README.md` repository layout | add `catalog/` |
| `catalog/README.md` | new; scope fixed below |
| `wsl-toolchain-doctor/README.md` | version `0.4.0`; document the `TOOLKIT_*` findings and the `--probe` flag |
| `wsl-toolchain-doctor.sh` `usage()` | add `--probe` to the `audit` synopsis |
| `docs/wsl-toolchain-doctor.md` | the version line, the sample JSON payload, and the `--probe` flag |
| `.gitattributes` | add `*.env text eol=lf` |
| parent `AGENTS.md` | one line for `check-catalog-drift.sh` in "Checking it" |

The `AGENTS.md` table keeps its rationale and loses its data. The Karpathy
paragraph below it stays as written: it describes the verification rule, not a
value, and that rule is unchanged.

### `catalog/README.md`

It is created, and the reason is not that other component directories have
READMEs — several do not.

`adt-kv` is a **maintained contract with three independent implementations**:
the installer, the doctor, and the parent workspace's drift checker. Those
readers span two repositories and deliberately share no executable parser, so
the only thing keeping them in agreement is a written grammar. This design
document cannot be that: it is dated, it records how the decision was reached,
and it will be historically accurate rather than current the moment the format
changes. `catalog/README.md` is the normative reference the three
implementations are maintained against.

It stays short, and covers exactly six things:

1. what the catalog is and which components it pins;
2. the normative `adt-kv` grammar — line kinds, key grammar, value grammar,
   duplicates, empty values, required keys, CRLF, unterminated final line;
3. that these files are never sourced or evaluated, and why the value grammar
   is what enforces it;
4. how to bump a pin, including that `karpathy-ref` and `karpathy-sha256` move
   together;
5. what a reader must validate, and the diagnostic contract — `FILE:LINE:` for
   anything with a line, `FILE:` for a missing required key;
6. that `install.sh` requires the catalog and ships with it as a bundle.

It does not restate the receipt design, the doctor comparisons or the
rationale for any individual pin.

## Out of scope

- Pinning Claude Code and Codex. They float on `latest` today; the catalog notes
  their absence and the behaviour is unchanged.
- An append-only install history log.
- Reshaping `spec-rivet`'s `toolchain.yaml`, or any change inside `spec-rivet`.
- The six upstream source constants at the top of `install.sh` — three
  installer URLs, a plugin specifier, a raw-content base and a
  repository-relative path.
- Any *installed-version* comparison for `superpowers` or `karpathy-ref`,
  neither of which has a local version probe. Both still participate in the
  staleness comparison, which needs only their declared refs.
- Re-versioning or otherwise touching the frozen installer copies under
  `models/routing/opencode/eval/records/`.

## Delivery

Two repositories. No commit mixes them.

**`agentic-dev-toolkit`** declares `workflow: github-flow` and
`integration: pull-request`, so its side lands on a branch and through a pull
request: the catalog, the five script versions, the receipt, the doctor's
three comparisons and its new `--probe` flag, the tests and the
documentation.

**The parent workspace** side is `scripts/check-catalog-drift.sh`, its test
script, and one line in `AGENTS.md`.

Its integration policy declares `workflow: trunk` and `integration: direct`.
That governs **how a change reaches the stable branch** — a direct commit on
`main` rather than a pull request — and nothing else. It is not a workflow
exemption. The parent's `AGENTS.md` states that work in this workspace runs
through OpenSpec, using the six `/opsx:*` commands against the `spec-driven`
schema, and that statement is unqualified.

So the parent-workspace changes go through OpenSpec, and are then integrated as
direct commits on `main`. An earlier draft inferred an exemption from the
integration mode; that inference was wrong and is withdrawn. Skipping OpenSpec
here would need the user to change the parent instructions, not a reading of
the policy file.
