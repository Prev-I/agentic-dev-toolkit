"""Shared parsing for the Claude Code routing bundle.

Agent files are Markdown with a flat `key: value` frontmatter block. The
bundle never uses nested YAML, so a strict line parser is enough and keeps the
suite free of a PyYAML dependency. Anything it does not understand is an
error, never a silent skip: a lenient parser would let a malformed installed
agent compare as equal to the bundle.
"""
import json
import os
import shlex
from pathlib import Path

ROUTING_FIELDS = ("model", "effort")
PERMISSION_FIELDS = ("tools", "disallowedTools", "maxTurns", "permissionMode")
LIST_FIELDS = frozenset({"tools", "disallowedTools"})
PIN_HOOK_NAME = "pin-agent-model.sh"


class FrontmatterError(ValueError):
    """An agent file whose frontmatter is not the flat form the bundle uses."""


def parse_agent(path):
    """Return (fields, body) for an agent Markdown file."""
    lines = Path(path).read_text(encoding="utf-8").split("\n")
    if lines[0] != "---":
        raise FrontmatterError(f"{path}: missing opening '---'")
    try:
        end = lines.index("---", 1)
    except ValueError:
        raise FrontmatterError(f"{path}: missing closing '---'") from None
    fields = {}
    for number, line in enumerate(lines[1:end], start=2):
        if not line.strip():
            continue
        key, separator, value = line.partition(":")
        if not separator or not key or key != key.strip() or " " in key:
            raise FrontmatterError(f"{path}:{number}: not a flat 'key: value' line")
        if key in fields:
            raise FrontmatterError(f"{path}:{number}: duplicate key '{key}'")
        fields[key] = value.strip()
    return fields, "\n".join(lines[end + 1:])


def normalized(field, value):
    """Comparable form of a frontmatter value. Tool-list order carries no meaning."""
    if value is None:
        return None
    if field in LIST_FIELDS:
        return tuple(sorted(item.strip() for item in value.split(",") if item.strip()))
    return value


def load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def pin_hook_commands(settings):
    """Commands of Agent-matcher PreToolUse hooks that run pin-agent-model.sh."""
    hooks = settings.get("hooks") if isinstance(settings, dict) else None
    entries = hooks.get("PreToolUse") if isinstance(hooks, dict) else None
    if not isinstance(entries, list):
        return []
    commands = []
    for entry in entries:
        if not isinstance(entry, dict) or entry.get("matcher") != "Agent":
            continue
        for hook in entry.get("hooks") or []:
            if isinstance(hook, dict) and str(hook.get("command", "")).rstrip('"\'').endswith(PIN_HOOK_NAME):
                commands.append(str(hook["command"]))
    return commands


def registers_pin_hook(settings):
    """True when settings route Agent calls through pin-agent-model.sh."""
    return bool(pin_hook_commands(settings))


def hook_command_target(command):
    """The file a hook command runs, with quotes, ~ and $VARS resolved; None if unparseable."""
    try:
        words = shlex.split(command)
    except ValueError:
        return None
    if not words:
        return None
    return Path(os.path.expandvars(os.path.expanduser(words[0]))).resolve()
