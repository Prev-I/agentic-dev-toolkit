# Claude Code Adapter

Claude Code loads `CLAUDE.md` natively from the repository root at the start of every session.

## The `@AGENTS.md` Import

Claude Code supports `@`-import syntax: a line like `@AGENTS.md` in `CLAUDE.md` pulls in the full
contents of `AGENTS.md`. This means you can keep a one-line `CLAUDE.md` that points to the canonical
instructions file, avoiding duplication.

## Setup in a Real Project

1. Place `AGENTS.md` at your repository root with all workspace guidance.
2. Place `CLAUDE.md` at the same level with exactly one line: `@AGENTS.md`.
3. Claude Code will load `CLAUDE.md`, follow the import, and read `AGENTS.md`.

## MCP Servers

Define MCP servers in `.mcp.json` at the repository root:

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

Enable them in `.claude/settings.json`:

```json
{
  "enabledMcpjsonServers": ["server-name"]
}
```

Both files should be committed. Machine-specific overrides go in
`.claude/settings.local.json`, which should be git-ignored.
