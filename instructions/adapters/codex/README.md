# Codex Adapter

Codex loads `AGENTS.md` natively from the repository root. No redirect file is needed.

## Setup

1. Place `AGENTS.md` at your repository root. Codex reads it automatically.
2. No `CLAUDE.md` equivalent is required — Codex does not use it.

## MCP Servers

Define MCP servers in `.codex/config.toml`:

```toml
[mcp_servers.server-name]
command = "npx"
args = ["-y", "package-name", "arg1", "arg2"]
```

The server names, commands, and arguments should match those in `.mcp.json` and
`opencode.json` to maintain parity across all three agents.

## Skills

Codex loads skills from `.agents/skills/`. Each skill is a directory containing a
`SKILL.md` file with a frontmatter description and the skill instructions.
