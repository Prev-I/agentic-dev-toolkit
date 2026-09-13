# Software catalog

`software-catalog.env` is the single source of truth for every third-party
version this toolkit pins: the Java and .NET SDKs, Python, Node.js, Bun,
Maven, `dotnet-ef`, `uv`, `shellcheck`, `gitleaks`, `pyyaml`, OpenSpec,
Superpowers, and the Karpathy guidelines skill's git ref and its SHA-256
digest. Claude Code and Codex are deliberately absent: neither is pinned, so
neither belongs in the catalog. `install.sh` reads this file at startup and
uses its values as the defaults every pin already documents; nothing about
what gets installed changes because the catalog exists.

## The `adt-kv` grammar

A catalog file is plain text in the `adt-kv` format, read one line at a time:

- A line that is empty, all whitespace, or whose first non-whitespace
  character is `#` is a comment and is skipped.
- Every other line must contain a `=`. Everything before the first `=` is the
  key; everything after is the value. Trailing whitespace on the value is
  stripped; nothing else is.
- **Key grammar:** `^[a-z0-9][a-z0-9.-]*$` — lowercase letters, digits, `.`
  and `-`, starting with a letter or digit.
- **Scalar value grammar:** `^[A-Za-z0-9][A-Za-z0-9._:+@/-]*$`.
- **List value grammar** (only for keys a reader has declared as list-typed):
  `^$|^[a-z0-9][a-z0-9.-]*(,[a-z0-9][a-z0-9.-]*)*$` — empty, or comma-joined
  elements each matching the key grammar, with no leading, trailing, or
  doubled commas, and no repeated element.
- A key may appear at most once per file. A second occurrence is a duplicate
  and is rejected, naming both the line it first appeared on and the line of
  the repeat.
- A value may be empty only for a list-typed key (an empty list). Every other
  key requires a non-empty value.
- Every required key must be present. Required keys are checked in the
  order the reader declares them, and the first missing one is reported.
- Lines are read with a loop that treats a final line with no trailing
  newline as a complete line rather than discarding it, and each line has any
  trailing `\r` stripped before the checks above run, so a file saved with
  CRLF line endings parses identically to one saved with LF.

## Never sourced, never evaluated

No reader uses `source`, `.`, `eval`, or command substitution on a catalog
file's content. Every line is parsed as text and every value is checked
against the grammar above before anything reads it. The value grammar is what
makes this safe to guarantee: it excludes shell metacharacters such as `$`,
`` ` ``, `;`, `|`, `&`, quotes, and whitespace, so even a maliciously crafted
catalog file cannot inject a command if some future reader were ever careless
enough to try. Treat the file as inert data, not as configuration to be
executed.

## Bumping a pin

Edit the value on the matching line and leave everything else — key order,
comments, formatting — untouched. Two keys are correlated and must be edited
together: `karpathy-ref` (a git commit) and `karpathy-sha256` (the digest of
the `SKILL.md` at that ref). Changing one without the other leaves the
catalog internally inconsistent — the installer verifies the downloaded
skill against the digest, so a mismatched pair fails every install until both
are corrected. Verify a new ref's digest before committing the change.

## What a reader must validate, and its diagnostics

A conforming reader loads the file into three parallel structures — values by
key, source line by key, and keys in source order — then validates against
whatever schema it cares about: which keys are required, which are lists, and
(where a full catalog is in hand) which values a list may reference. Every
diagnostic follows one contract:

- A problem tied to a specific line is reported as `FILE:LINE: <message>`.
- A missing required key has no line to report, since it was never seen, so
  it is reported as `FILE: <message>` with no line number.

The first problem encountered — walking required keys in their declared
order, then all keys in source order — is the one reported. Diagnostics do
not vary between runs of the same input.

## Install.sh requires the catalog

`install.sh` cannot run without a readable, valid catalog: it is not an
optional enhancement, and there is no fallback to literal defaults. The
catalog file ships as part of this repository and is bundled with
`install.sh` wherever the installer is distributed — the two are not meant to
be separated.
