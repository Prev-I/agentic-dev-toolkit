# OpenCode Adapter

OpenCode loads `AGENTS.md` natively from the repository root. If no `AGENTS.md`
exists, it falls back to `CLAUDE.md`.

## MCP Servers

Define MCP servers in `opencode.json` (or `opencode.jsonc`) at the repository root:

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

Key format differences from `.mcp.json` (Claude Code):

- The top-level key is `"mcp"`, not `"mcpServers"`.
- The `"type"` is `"local"`, not `"stdio"`.
- The `"command"` is an array containing the executable and all arguments (there
  is no separate `"args"` field — the first element is the binary, the rest are
  arguments).

## Skills and Commands

- Skills go in `.opencode/skills/`, each as a directory with a `SKILL.md` file.
- Commands go in `.opencode/commands/`, each as a markdown file that becomes a
  `/command-name` slash command.

## Additional Instructions

OpenCode supports an `"instructions"` array in `opencode.json` to load additional
instruction files alongside `AGENTS.md`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": [".opencode/model-routing.md"]
}
```
