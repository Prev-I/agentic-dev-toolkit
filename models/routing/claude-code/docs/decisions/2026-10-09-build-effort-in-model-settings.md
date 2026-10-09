# Build Effort in modelSettings

## Decision

The settings fragment sets Build's effort as
`modelSettings.claude-opus-5-5.effortLevel: "high"` instead of a top-level
`effortLevel: "high"`. Build's model and effort are unchanged; what changes is
that the effort now reaches it.

| Key | Before | After |
|---|---|---|
| `effortLevel` | `"high"` | removed from the fragment |
| `modelSettings.claude-opus-5-5.effortLevel` | not set | `"high"` |

The merge snippet adds the `modelSettings` entry without touching the user's
other models or other fields of the Opus 5.5 entry; the rollback removes only
that `effortLevel`. The alignment check compares
`modelSettings.claude-opus-5-5.effortLevel` instead of `effortLevel`.

## Rationale

- **The top-level key does not reach Opus 5.5 in user settings.** The
  settings reference says that in `~/.claude/settings.json` the top-level
  `effortLevel` "keeps applying where it applied before, on Opus 5, Fable 5.1,
  and earlier models. Opus 5.5 and models released after it ignore it and start
  at their own default until you save a level for them, which `/effort` writes
  under `modelSettings`." [Settings] The bundle installs into exactly that file.
- **Observed.** Evidence E3: the top-level `high` in the user file did not reach
  Sonnet 5.5 or Haiku 5.5 (both sent `medium`), the same key through
  `--settings` reached Opus 5.5, Sonnet 5.5 and Haiku 5.5, and Opus 5.5 with no
  settings sends `medium`. On this workstation Build ran at `high` only because
  the user had saved `modelSettings.claude-opus-5-5.effortLevel: "high"`
  themselves.
- **`modelSettings` is the documented per-model store.** It maps "a model name
  to an object" with an `effortLevel` field, keyed by "the model's canonical
  name, such as `claude-opus-5-5`", and "a model's `effortLevel` here takes
  precedence over the top-level `effortLevel` in the same settings file". It
  requires Claude Code 2.1.251 or later. [Settings]
- **The top-level key is dropped, not kept beside it.** It would apply only to
  Opus 5, Fable 5.1 and earlier, none of which runs as Build in this profile,
  so keeping it would only suggest a control that does nothing for Build.

## Consequences

- A fresh install now gives Build `high` without relying on a value the user
  saved. The earlier fragment silently left it at Opus 5.5's default, `medium`.
- The rollback removes the Opus 5.5 `effortLevel` outright, as it already
  removes `model`: a level the user saved before installing comes back from the
  dated backup, not from the rollback.
- An install made with the earlier fragment keeps its top-level
  `effortLevel: "high"`. Neither snippet removes it, because the current merge
  does not add it; the README says so. It does not reach Opus 5.5, Sonnet 5.5
  or Haiku 5.5. It still applies to Fable 5.1, where Expert's frontmatter
  `xhigh` wins: evidence E1 shows Expert at `xhigh` with that user file loaded.
- An installed profile needs the fragment re-merged. Until then the alignment
  check reports `settings.modelSettings.claude-opus-5-5.effortLevel` as
  `DRIFT`, unless the user had already saved `high` for Opus 5.5.
- `/effort` on Opus 5.5 writes this same key, so a later `/effort` change shows
  as `DRIFT`. That may be a deliberate choice; the check never repairs it.
- Other sources still override the saved level. Within the user file, "a
  model's `effortLevel` here takes precedence over the top-level `effortLevel`
  in the same settings file"; across files, "the highest-precedence settings
  file that sets either an `effortLevel` for that model or a top-level
  `effortLevel` that applies to that model decides, so an `effortLevel` in
  managed settings outranks a level you saved in user settings"; and per
  session, "`--effort` takes precedence over this key for one session, and
  `CLAUDE_CODE_EFFORT_LEVEL` takes precedence over both". [Settings]

## Evidence boundary

Evidence E1 and E3 in
[`../evidence/2026-10-09-capability.md`](../evidence/2026-10-09-capability.md).
The Opus 5.5 row there cannot isolate the top-level key, because the user file
also holds a `modelSettings` entry; the conclusion for Opus 5.5 rests on the
settings reference and on the Sonnet 5.5 and Haiku 5.5 rows. Documentation as
read on 2026-10-09:

- [Settings]

[Settings]: https://code.claude.com/docs/en/settings-reference#effortlevel

Later corrections are appended as dated addenda, never edited in place.
