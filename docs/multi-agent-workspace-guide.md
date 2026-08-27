# Multi-Agent Workspace Guide

How to make one repository work with Claude Code, Codex, and OpenCode using a single source of truth for instructions and consistent MCP server access.

## The Problem

Each AI coding agent loads instructions and MCP configuration from different files in different formats:

| Concern | Claude Code | Codex | OpenCode |
|---|---|---|---|
| Instructions | `CLAUDE.md` | `AGENTS.md` | `AGENTS.md` (falls back to `CLAUDE.md`) |
| MCP servers | `.mcp.json` | `.codex/config.toml` | `opencode.json` or `opencode.jsonc` |
| Settings | `.claude/settings.json` | (none needed) | `opencode.json` or `opencode.jsonc` |

If you write the same workspace guidance in both `CLAUDE.md` and `AGENTS.md`, they drift apart. If you only configure MCP servers in one format, the other agents cannot reach those external tools.

## The Pattern

**One canonical instructions file, thin redirects, parallel MCP definitions.**

```
your-repo/
  AGENTS.md                  # THE source of truth — all workspace guidance lives here
  CLAUDE.md                  # One line: @AGENTS.md (Claude Code import syntax)
  .mcp.json                  # MCP servers for Claude Code
  .claude/
    settings.json            # Enables the servers defined in .mcp.json
    settings.local.json      # Machine-specific overrides (git-ignored)
  .codex/
    config.toml              # Same MCP servers for Codex
  opencode.json              # Same MCP servers for OpenCode
```

### Why `AGENTS.md` Is the Canonical File

- Both **Codex** and **OpenCode** load `AGENTS.md` natively from the repo root.
- **OpenCode** falls back to `CLAUDE.md` only if no `AGENTS.md` exists, so having both is harmless.
- **Claude Code** loads `CLAUDE.md` natively and supports the `@AGENTS.md` import directive, which injects the full file contents. A one-line `CLAUDE.md` therefore gives Claude Code the identical instructions without maintaining a second copy.

Result: edit `AGENTS.md` once, all three agents see the change.

## How each harness loads nested instruction files

The three harnesses do **not** agree on this, and the difference changes your
configuration rather than just your expectations.

| Harness | How it finds nested `AGENTS.md` | Needs configuration? |
|---|---|---|
| the `agents.md` convention | nested files supported, the one nearest the edited file wins | n/a |
| **Codex** | walks from the project root **down** to the cwd, concatenating each `AGENTS.md` it meets; nearer files win | no — but it sees `docs/AGENTS.md` only if the cwd is inside `docs/` |
| **OpenCode** | walks **up** from the cwd to its parents and does **not** descend into subdirectories | **yes** — monorepo paths must be declared explicitly |
| **Claude Code** | loads a nested file when you touch files in that subtree, and resolves `@AGENTS.md` relative to the file containing the import | no |

OpenCode's is the one that needs action. Declare each nested file the container
owns:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["AGENTS.md", "docs/AGENTS.md"]
}
```

Two details worth keeping:

- **Verify the field name against the schema.** A misspelled key is not an error
  in OpenCode — it is silently inert, so the file looks configured and loads
  nothing.
- **Where a folder holds both `AGENTS.md` and `CLAUDE.md`, OpenCode reads only
  `AGENTS.md`.** That is convenient for the redirect pattern: the eleven-byte
  `CLAUDE.md` is ignored rather than concatenated.

**Declare what the container owns, not its children.** A child repository is
entered directly — you `cd` into it, and every harness then finds its `AGENTS.md`
at the cwd. Declaring `repos/<child>/AGENTS.md` in the container's `instructions`
would load one child's rules permanently, in every session, including while
working on a different child.

## Step-by-Step Setup

### 1. Write `AGENTS.md`

Create `AGENTS.md` at your repo root with all workspace guidance: project overview, repo map, architecture, build/test commands, CI/CD conventions, secrets warnings, git conventions, MCP usage notes.

Use harness-neutral language. Instead of "Claude Code can search ADO with the `mcp__server__search_code` tool", write "the MCP server connects to Azure DevOps" — each agent will discover the tools from the server itself.

### 2. Create the Claude Code Redirect

Create `CLAUDE.md` at your repo root with exactly one line:

```
@AGENTS.md
```

Claude Code's `@`-import syntax pulls in the full file. Do not put any other content in `CLAUDE.md`.

### 3. Define MCP Servers for Claude Code

Create `.mcp.json` at the repo root:

```json
{
  "mcpServers": {
    "server-name": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "package-name", "arg1", "arg2"]
    }
  }
}
```

Enable the servers in `.claude/settings.json`:

```json
{
  "enabledMcpjsonServers": ["server-name"]
}
```

### 4. Define the Same MCP Servers for Codex

Create `.codex/config.toml`:

```toml
[mcp_servers.server-name]
command = "npx"
args = ["-y", "package-name", "arg1", "arg2"]
```

The keys, command, and arguments must match `.mcp.json` exactly. Only the format differs.

### 5. Define the Same MCP Servers for OpenCode

Create `opencode.json` (or `opencode.jsonc`) at the repo root:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "server-name": {
      "type": "local",
      "command": ["npx", "-y", "package-name", "arg1", "arg2"]
    }
  }
}
```

Note the format differences from `.mcp.json`:
- The top-level key is `mcp`, not `mcpServers`.
- The `type` is `"local"` (not `"stdio"`).
- The `command` is an array containing both the executable and all arguments (there is no separate `args` field; the first element is the binary, the rest are arguments).

### 6. Set Up `.gitignore`

Add machine-specific files that should not be committed:

```gitignore
# Claude Code local settings (machine-specific permissions/overrides)
.claude/settings.local.json
```

The following files **should** be committed (they are project configuration, not personal settings):
- `AGENTS.md`
- `CLAUDE.md`
- `.mcp.json`
- `.claude/settings.json`
- `.codex/config.toml`
- `opencode.json`

If the repository hosts child projects that are tracked separately, anchor their entries so the rule
cannot match a same-named directory elsewhere in the tree, and keep the container directory alive:

```gitignore
/repos/*
!/repos/.gitkeep
```

## MCP Server Parity

All three configurations must define the same servers with the same commands and arguments. Here is a concrete example with two servers:

### `.mcp.json` (Claude Code)

```json
{
  "mcpServers": {
    "ado": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@azure-devops/mcp", "your-org"]
    },
    "observability": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp.example.com/"]
    }
  }
}
```

### `.codex/config.toml` (Codex)

```toml
[mcp_servers.ado]
command = "npx"
args = ["-y", "@azure-devops/mcp", "your-org"]

[mcp_servers.observability]
command = "npx"
args = ["-y", "mcp-remote", "https://mcp.example.com/"]
```

### `opencode.json` (OpenCode)

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "ado": {
      "type": "local",
      "command": ["npx", "-y", "@azure-devops/mcp", "your-org"]
    },
    "observability": {
      "type": "local",
      "command": ["npx", "-y", "mcp-remote", "https://mcp.example.com/"]
    }
  }
}
```

### Verification Script

Run this to confirm all three configurations define the same servers with the same commands:

```python
import json, pathlib

# Parse Claude Code config
claude = json.loads(pathlib.Path(".mcp.json").read_text())["mcpServers"]

# Parse Codex config (TOML)
try:
    import tomllib
except ImportError:
    import tomli as tomllib
codex = tomllib.loads(pathlib.Path(".codex/config.toml").read_text())["mcp_servers"]

# Parse OpenCode config
opencode = json.loads(pathlib.Path("opencode.json").read_text())["mcp"]

def normalize_claude(servers):
    """Normalize .mcp.json format to [command, *args]."""
    return {
        name: [s["command"]] + s.get("args", [])
        for name, s in servers.items()
    }

def normalize_codex(servers):
    """Normalize .codex/config.toml format to [command, *args]."""
    return {
        name: [s["command"]] + list(s.get("args", []))
        for name, s in servers.items()
    }

def normalize_opencode(servers):
    """Normalize opencode.json format to [command, *args]."""
    return {
        name: list(s["command"])
        for name, s in servers.items()
    }

c = normalize_claude(claude)
x = normalize_codex(codex)
o = normalize_opencode(opencode)

assert c == x, f"Claude vs Codex mismatch:\n  Claude: {c}\n  Codex:  {x}"
assert c == o, f"Claude vs OpenCode mismatch:\n  Claude:   {c}\n  OpenCode: {o}"
print(f"MCP parity OK: {', '.join(sorted(c))}")
```

## OpenSpec Support Files

If the repository uses OpenSpec, `openspec init` generates a fourth parallel set of files — the
workflow skills, one copy per harness — plus the spec store itself:

```
your-repo/
  openspec/
    config.yaml              # Schema + project context injected into every artifact prompt
    specs/                   # Living specifications
    changes/                 # Active changes; changes/archive/ for completed ones
  .openspec-store/
    store.yaml               # Store identity (version + id)
  .agents/skills/            # OpenSpec skills for Codex (+ .openspec-target marker)
  .claude/skills/            # OpenSpec skills for Claude Code
  .claude/commands/opsx/     # /opsx:* slash commands
  .opencode/skills/          # OpenSpec skills for OpenCode
  .opencode/commands/        # /opsx-* commands
```

The same rule as MCP config applies: the three skill trees are generated copies of one workflow, so
regenerate them together (`openspec update`) rather than hand-editing one harness' copy.

Two things are worth knowing:

- `openspec/config.yaml`'s `context` block is prepended to agent prompts when artifacts are created.
  Treat it as the machine-readable summary of `AGENTS.md`: tech stack, repo model, conventions, and
  what is *out of scope* for this store. Keep the two in sync when either changes.
- `.opencode/` also holds a generated `package.json` / `node_modules` for the OpenCode plugin
  runtime; the generated `.opencode/.gitignore` already excludes them.

## Nested Repositories

A parent workspace that hosts child projects (each destined to become its own Git repository) needs a
clear boundary, or agents will write a child's specs into the parent's store and commits will mix
unrelated trees.

The pattern that works:

1. **Every child carries the full support-file set.** `AGENTS.md`, `CLAUDE.md`, the three MCP config
   files, `.claude/settings.json`, and its own `openspec/` + `.openspec-store/`. A child opened
   directly as a workspace root must be fully self-sufficient — agents load configuration from the
   directory they are started in, not from the parent.
2. **The parent ignores the children.** Anchored `.gitignore` entries (`/repos/*`) keep the child
   trees out of the parent's history while a `.gitkeep` negation preserves the directory in a fresh
   clone.
3. **Each store owns only its own tree.** State this explicitly in the parent's
   `openspec/config.yaml` context ("out of scope: anything under `repos/`") and in `AGENTS.md`, so
   agents propose changes in the owning repository.
4. **MCP definitions are duplicated, not inherited.** There is no config inheritance from a parent
   directory in any of the three agents. Adding a server means touching three files per repository —
   run the parity script in each.

## Hygiene and Safety

### What to Commit

| File | Commit? | Reason |
|---|---|---|
| `AGENTS.md` | Yes | Shared workspace instructions |
| `CLAUDE.md` | Yes | Claude Code entry point |
| `.mcp.json` | Yes | MCP server definitions (no secrets) |
| `.claude/settings.json` | Yes | Shared Claude Code project settings |
| `.codex/config.toml` | Yes | Codex MCP server definitions |
| `opencode.json` | Yes | OpenCode MCP + project config |
| `openspec/` | Yes | Specs, changes, and project context |
| `.openspec-store/store.yaml` | Yes | Store identity, shared by the team |
| `.agents/`, `.claude/skills/`, `.claude/commands/`, `.opencode/skills/`, `.opencode/commands/` | Yes | Generated workflow skills — regenerate, don't hand-edit |
| `.claude/settings.local.json` | **No** | Machine-specific permissions |
| `.opencode/package.json`, `.opencode/node_modules/` | **No** | Generated plugin runtime |

### Secrets

- Never put API keys, connection strings, tokens, or passwords in any of these files.
- MCP server authentication should be handled by each agent's own credential mechanism (Azure Artifacts Credential Provider, `npx` auth, environment variables, etc.), not by committed config.
- If your `AGENTS.md` must reference the *existence* of secrets (e.g., "the backend reads connection strings from Key Vault"), do so without including actual values.
- Audit your config files before committing. Search for patterns like `Bearer`, `password`, `connectionString`, `-----BEGIN`, `sk-`, `pat:`.

### Local-Only Overrides

Each agent has a mechanism for machine-specific settings that should not be committed:

| Agent | Local override file | Notes |
|---|---|---|
| Claude Code | `.claude/settings.local.json` | Permissions, personal MCP servers |
| Codex | User-level `~/.codex/` config | Personal preferences |
| OpenCode | `~/.config/opencode/opencode.json` | Global user preferences, API keys |

## Verification Checklist

Run these checks after setting up multi-agent support:

```bash
# 1. AGENTS.md exists and has content
test -s AGENTS.md && echo "OK: AGENTS.md exists" || echo "FAIL: missing AGENTS.md"

# 2. CLAUDE.md imports AGENTS.md
grep -qx '@AGENTS.md' CLAUDE.md && echo "OK: CLAUDE.md imports AGENTS.md" || echo "FAIL: CLAUDE.md wrong"

# 3. All MCP config files parse without errors
python3 -c "import json; json.load(open('.mcp.json'))" && echo "OK: .mcp.json valid JSON"
python3 -c "import tomllib; tomllib.load(open('.codex/config.toml','rb'))" && echo "OK: config.toml valid TOML"
python3 -c "import json; json.load(open('opencode.json'))" && echo "OK: opencode.json valid JSON"

# 4. No secrets in config files
! grep -riE '(Bearer |-----BEGIN|password|connectionString|sk-)' \
    AGENTS.md CLAUDE.md .mcp.json .codex/config.toml opencode.json \
    .claude/settings.json \
  && echo "OK: no secrets detected" || echo "WARNING: possible secrets found"

# 5. Local settings are git-ignored
git check-ignore .claude/settings.local.json && echo "OK: local settings ignored" || echo "FAIL: add to .gitignore"

# 6. No trailing whitespace issues
git diff --check && echo "OK: no whitespace issues"
```

## Quick Reference

### How Each Agent Discovers Instructions

```
Claude Code:  CLAUDE.md  -->  @AGENTS.md import  -->  reads AGENTS.md
Codex:        AGENTS.md  -->  (direct, native)
OpenCode:     AGENTS.md  -->  (direct, native; CLAUDE.md is fallback)
```

### How Each Agent Discovers MCP Servers

```
Claude Code:  .mcp.json  +  .claude/settings.json (enablement)
Codex:        .codex/config.toml
OpenCode:     opencode.json (or opencode.jsonc)
```

### How Each Agent Discovers OpenSpec Skills

```
Claude Code:  .claude/skills/  +  .claude/commands/opsx/   -->  /opsx:<verb>
Codex:        .agents/skills/                              -->  skill by name
OpenCode:     .opencode/skills/  +  .opencode/commands/    -->  /opsx-<verb>
```

### Adding a New MCP Server

When adding a new MCP server, update all three files:

1. Add the server to `.mcp.json` and list it in `.claude/settings.json`'s `enabledMcpjsonServers` array.
2. Add the equivalent `[mcp_servers.<name>]` table to `.codex/config.toml`.
3. Add the equivalent entry under `mcp` in `opencode.json`.
4. Run the verification script to confirm parity.
5. Document the server's purpose and available tools in `AGENTS.md`.

### Adding a New Agent

To extend this pattern for a new agent (e.g., Cursor, Windsurf, GitHub Copilot):

1. Check how the agent loads instructions. If it reads `AGENTS.md`, nothing to do. If it reads a different file (like `.cursorrules`), create a redirect or symlink.
2. Check how the agent loads MCP servers. Add a config file in the agent's native format with the same server definitions.
3. Run the verification script (extended for the new format).
4. Update the `AGENTS.md` MCP section to mention the new agent's config file.
