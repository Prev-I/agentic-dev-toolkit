#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bundle="$root/../v2"
v1root="$root/.."
helper="$root/runtime/opencode-v2-adapter/v2config.py"
source "$root/tests/test-lib.sh"

assert_file "$helper"
assert_file "$bundle/opencode.jsonc"
assert_file "$bundle/manifests/current-routing-targets.json"
assert_file "$bundle/.opencode/model-routing.md"
for name in reviewer expert scout; do
  assert_file "$bundle/.opencode/agents/$name.md"
done

assert_eq v2 "$(python3 "$helper" shape "$bundle/opencode.jsonc")"

workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT

printf '{"agent":{}}' >"$workspace/v1.json"
assert_eq v1 "$(python3 "$helper" shape "$workspace/v1.json")"
printf '{"agents":{},"plugins":[]}' >"$workspace/v2.json"
assert_eq v2 "$(python3 "$helper" shape "$workspace/v2.json")"
: >"$workspace/empty.json"
assert_eq empty "$(python3 "$helper" shape "$workspace/empty.json")"
printf '{ nope' >"$workspace/bad.json"
rc=0
out=$(python3 "$helper" shape "$workspace/bad.json") || rc=$?
assert_eq 1 "$rc"
assert_eq invalid "$out"

cat >"$workspace/url.jsonc" <<'JSONC'
{
  // comment line
  "url": "https://example.invalid//x", // trailing comment
  /* block */ "other": "a,]b"
}
JSONC
python3 "$helper" load "$workspace/url.jsonc" >"$workspace/url.out"
assert_contains "$(<"$workspace/url.out")" '"https://example.invalid//x"'
assert_contains "$(<"$workspace/url.out")" '"a,]b"'

# md-frontmatter fails closed on YAML outside its subset, and parses plain floats.
mdcase() { printf -- '---\n%s\n---\nbody\n' "$1" >"$workspace/case.md"; }
mdcase 'temperature: 0.1'
assert_eq 0.1 "$(python3 "$helper" md-frontmatter "$workspace/case.md" | python3 -c 'import json,sys; print(json.load(sys.stdin)["temperature"])')"
mdcase 'hidden: true'
python3 "$helper" md-frontmatter "$workspace/case.md" >/dev/null
for bad in 'mode: subagent # primary-only' 'description: a: b' 'hidden: True' 'hidden: TRUE' \
           'x: Null' 'x: ~' 'x: 1e3' 'x: 1.2.3' 'x: "a" # c' 'x: [a, b]'; do
  mdcase "$bad"
  rc=0
  python3 "$helper" md-frontmatter "$workspace/case.md" >/dev/null 2>&1 || rc=$?
  assert_eq 2 "$rc"
done
printf -- '---\npermission:\n  bash:\n    "git status*": allow  # read-only\n---\n' >"$workspace/case.md"
rc=0
python3 "$helper" md-frontmatter "$workspace/case.md" >/dev/null 2>&1 || rc=$?
assert_eq 2 "$rc"

if grep -q '"temperature"' "$bundle/opencode.jsonc"; then fail "temperature in V2 opencode.jsonc"; fi
if grep -rqi 'temperature' "$bundle/.opencode/agents"; then fail "temperature in V2 agent markdown"; fi

python3 - "$helper" "$bundle" "$v1root" <<'PY' || fail "python assertions failed"
import json, subprocess, sys

helper, bundle, v1root = sys.argv[1:4]


def run(*args):
    return json.loads(subprocess.check_output(["python3", helper, *args]))


def action(name):
    return {"bash": "shell", "task": "subagent"}.get(name, name)


def to_perms(permission):
    out = []
    for name, value in permission.items():
        if isinstance(value, dict):
            out += [{"action": action(name), "resource": r, "effect": e} for r, e in value.items()]
        else:
            out.append({"action": action(name), "resource": "*", "effect": value})
    return out


def split(model):
    provider, _, rest = model.partition("/")
    return {"providerID": provider, "model": rest}


config = run("load", f"{bundle}/opencode.jsonc")
v1_manifest = json.load(open(f"{v1root}/eval/manifests/current-routing-targets.json"))
v2_manifest = json.load(open(f"{bundle}/manifests/current-routing-targets.json"))
assert v2_manifest["format"] == "opencode-v2-routing-targets/1"
assert config["model"] == split(v1_manifest["default_model"]), "default model"
assert v2_manifest["default_model"] == split(v1_manifest["default_model"])
assert len(v1_manifest["agents"]) == 11
assert set(v2_manifest["agents"]) == set(v1_manifest["agents"])
assert v2_manifest["breakglass"] == {"agent": "breakglass", "deny_as_subagent": True}
assert v2_manifest["forbidden_model_references"] == v1_manifest["forbidden_model_references"]
for role, target in v1_manifest["agents"].items():
    row = config["agents"][role]
    expected = {**split(target["model"]), "variant": target["variant"]}
    assert row["model"] == expected, f"{role}: {row['model']} != {expected}"
    m = v2_manifest["agents"][role]
    assert (m["providerID"], m["model"], m["variant"], m["mode"]) == (
        row["model"]["providerID"], row["model"]["model"], row["model"]["variant"],
        row.get("mode")), f"manifest mismatch for {role}"
    assert m["mode"] == target["mode"], f"mode drift for {role}"

assert config.get("$schema") == "https://opencode.ai/config.json", "$schema"
for key in ("agent", "permission", "plugin", "provider", "server"):
    assert key not in config, key
assert config["permissions"][-1] == {"action": "subagent", "resource": "breakglass", "effect": "deny"}
assert to_perms({"websearch": "allow", "task": {"*": "allow", "breakglass": "deny"}}) == config["permissions"]

# V1 agent permissions translate to the V2 rows
v1config = run("load", f"{v1root}/opencode.jsonc")
for role, row in config["agents"].items():
    assert "prompt" not in row and "temperature" not in row
    want = v1config["agent"][role].get("permission")
    assert row.get("permissions") == (to_perms(want) if want else None), f"permissions drift: {role}"

for name in ("reviewer", "expert", "scout"):
    v2md = run("md-frontmatter", f"{bundle}/.opencode/agents/{name}.md")
    v1md = run("md-frontmatter", f"{v1root}/.opencode/agents/{name}.md")
    assert "permission" not in v2md and "model" not in v2md, name
    assert v2md["permissions"] == to_perms(v1md["permission"]), name
    for key in ("description", "mode", "steps", "hidden"):
        assert v2md.get(key) == v1md.get(key), f"{name}.{key}"

reviewer = run("md-frontmatter", f"{bundle}/.opencode/agents/reviewer.md")
shell = [(p["resource"], p["effect"]) for p in reviewer["permissions"] if p["action"] == "shell"]
assert shell == [("*", "deny"), ("git status*", "allow"), ("git diff*", "allow"),
                 ("git log*", "allow"), ("git show*", "allow")], shell
PY
printf 'PASS: v2-bundle-test\n'
