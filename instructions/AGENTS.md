# Project Name

Instructions for all AI coding agents (Claude Code, Codex, OpenCode).

## Project Overview

Your project description here. Explain what the project does, its primary goals,
and any key constraints that agents should be aware of.

## Repository Structure

```
your-project/
  AGENTS.md                  # This file — source of truth for agent instructions
  CLAUDE.md                  # One-line redirect: @AGENTS.md
  README.md                  # Human-facing documentation
  .mcp.json                  # MCP servers for Claude Code
  .claude/
    settings.json            # Enables MCP servers defined in .mcp.json
  .codex/
    config.toml              # MCP servers for Codex
  opencode.json              # MCP servers for OpenCode
  src/                       # Application source code
  tests/                     # Test suites
  docs/                      # Documentation
```

## Build and Test

```bash
# Replace with your actual build command
npm run build

# Replace with your actual test command
npm test

# Lint / format
npm run lint
```

## MCP Servers

| Server | Purpose |
|---|---|
| `your-server` | Description of what this MCP server provides |

Defined in `.mcp.json` (Claude Code, enabled via `.claude/settings.json`),
`.codex/config.toml` (Codex), and `opencode.json` (OpenCode). Adding a server
means updating all three files. Do not hardcode tool names — agents discover
them from the servers at runtime.

## Git Conventions

- Branch from `main` for all work.
- Use conventional commit messages: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`.
- Keep commits atomic and focused on a single concern.
- Do not commit secrets, tokens, API keys, or connection strings.

## Secrets and Security

- No secrets in any committed file.
- MCP server authentication uses ambient credentials (environment variables,
  CLI login flows, credential providers).
- Audit config files before committing — search for patterns like `Bearer`,
  `password`, `connectionString`, `-----BEGIN`, `sk-`, `pat:`.
