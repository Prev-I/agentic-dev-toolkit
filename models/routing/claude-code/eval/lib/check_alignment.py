"""Installed-vs-bundle alignment for the Claude Code routing bundle.

Asks whether the files Claude Code reads still match this repository. It
makes no model calls and never repairs anything: drift is sometimes
deliberate, so every decision stays with a human.

DRIFT  routing or permission state differs. Fails the check.
STALE  prose differs while routing and permissions match. Informational.

Only what the bundle installs is compared. Every other setting, hook, agent
and rule belongs to the user and is never reported.
"""
import argparse
import json
import os
import sys
from pathlib import Path

from routing import (PERMISSION_FIELDS, ROUTING_FIELDS, FrontmatterError, load_json,
                     normalized, parse_agent, registers_pin_hook)

SETTINGS_KEYS = (("model",), ("effortLevel",), ("env", "ANTHROPIC_DEFAULT_HAIKU_MODEL"))


def dig(data, path):
    for key in path:
        if not isinstance(data, dict) or key not in data:
            return None
        data = data[key]
    return data


def compare(bundle, installed):
    findings = []

    def add(severity, item, detail):
        findings.append({"severity": severity, "item": item, "detail": detail})

    fragment = load_json(bundle / "settings.fragment.json")
    settings_path = installed / "settings.json"
    settings = load_json(settings_path) if settings_path.is_file() else {}
    if not isinstance(settings, dict):
        raise ValueError(f"{settings_path} is not a JSON object")

    for path in SETTINGS_KEYS:
        want, have = dig(fragment, path), dig(settings, path)
        if want != have:
            add("DRIFT", "settings." + ".".join(path), f"bundle={want!r} installed={have!r}")
    if not registers_pin_hook(settings):
        add("DRIFT", "settings.hooks.PreToolUse", "no Agent matcher runs pin-agent-model.sh")

    for agent in sorted((bundle / "agents").glob("*.md")):
        item = f"agents/{agent.name}"
        target = installed / "agents" / agent.name
        if not target.is_file():
            add("DRIFT", item, "not installed")
            continue
        want_fields, want_body = parse_agent(agent)
        try:
            have_fields, have_body = parse_agent(target)
        except FrontmatterError as error:
            add("DRIFT", item, f"unparseable: {error}")
            continue
        for field in ROUTING_FIELDS + PERMISSION_FIELDS:
            want, have = want_fields.get(field), have_fields.get(field)
            if normalized(field, want) != normalized(field, have):
                add("DRIFT", item, f"{field}: bundle={want!r} installed={have!r}")
        if want_body != have_body:
            add("STALE", item, "prompt body differs")

    item = "hooks/pin-agent-model.sh"
    source, target = bundle / item, installed / item
    if not target.is_file():
        add("DRIFT", item, "not installed")
    elif target.read_bytes() != source.read_bytes():
        add("DRIFT", item, "content differs")
    elif not os.access(target, os.X_OK):
        add("DRIFT", item, "not executable")

    target = installed / "rules" / "model-routing.md"
    if not target.is_file():
        add("DRIFT", "rules/model-routing.md", "not installed")
    elif target.read_bytes() != (bundle / "model-routing.md").read_bytes():
        add("STALE", "rules/model-routing.md", "content differs")

    return findings


def main(argv=None):
    parser = argparse.ArgumentParser(prog="check-alignment.sh")
    parser.add_argument("--bundle", required=True, type=Path)
    parser.add_argument("--installed", required=True, type=Path)
    parser.add_argument("--json", dest="json_out", type=Path)
    args = parser.parse_args(argv)

    if not (args.installed / "settings.json").is_file() and not (args.installed / "agents").is_dir():
        print(f"check-alignment: nothing installed under {args.installed}", file=sys.stderr)
        return 2
    try:
        findings = compare(args.bundle, args.installed)
    except json.JSONDecodeError as error:
        print(f"check-alignment: {args.installed / 'settings.json'} is not valid JSON: {error}",
              file=sys.stderr)
        return 2
    except ValueError as error:
        print(f"check-alignment: {error}", file=sys.stderr)
        return 2

    severities = {finding["severity"] for finding in findings}
    status = "DRIFT" if "DRIFT" in severities else "STALE" if findings else "ALIGNED"
    for finding in findings:
        print(f"{finding['severity']}  {finding['item']}  {finding['detail']}")
    print(f"STATUS: {status}")
    if args.json_out:
        report = {"status": status, "bundle": str(args.bundle),
                  "installed": str(args.installed), "findings": findings}
        args.json_out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 1 if status == "DRIFT" else 0


if __name__ == "__main__":
    sys.exit(main())
