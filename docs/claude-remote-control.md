# Claude Code Remote Control as a Service

Keeping `claude remote-control` running for a project as a systemd **user**
service, so sessions started from claude.ai or the Claude mobile app always find
a server waiting on the workstation. One template unit serves every project:
the instance name selects the directory.

Placeholders used throughout: `<PROJECT>` a Git repository at `~/code/<PROJECT>`,
`<USER>` the Linux account, `<NAME>` and `<PORT>` a shell function name and a
local proxy's port.

Observed with Claude Code 2.1.296, tmux 3.4, direnv 2.32.1 and systemd 255 on
Ubuntu under WSL2.

## Policy

- **No permission bypass.** Never add `--dangerously-skip-permissions` or a
  `bypassPermissions` mode. Remote sessions start in auto mode
  (`--permission-mode auto`): a classifier approves routine actions and blocks
  risky ones, and anything it cannot settle still asks in the client. The
  project's permission rules still apply.
- **One instance per project.** The instance name is the directory name under
  `~/code`, so `claude-rc@<PROJECT>` always serves `~/code/<PROJECT>`. Use plain
  directory names: `%i` is the escaped instance name, so a name that
  `systemd-escape` would alter (spaces, for example) does not map back to the
  directory.
- **Sessions opened from a client get their own Git worktree** (`--spawn
  worktree`), so two remote sessions never share a working tree. The one
  exception is the session the server creates for itself at start, which runs in
  the project's main checkout — the same tree an interactive session there uses.
- **The project's environment comes from its own `.envrc`.** Secrets stay where
  direnv already finds them; nothing secret is written into the unit.

## Prerequisites

Check every item before creating the unit. Each one, when missing, produces a
failure that is easy to misread later.

**A systemd user manager.** `systemctl --user status` must report `running`. On
WSL, systemd must be the init system: `[boot] systemd=true` in `/etc/wsl.conf`.

**tmux, direnv, getent, pgrep and jq.** `command -v tmux direnv getent pgrep jq`.
direnv is needed even for a project without an `.envrc`, because the unit always
launches through it; jq is needed only by the checks below.

**Claude Code, native install, logged in to claude.ai.**

```bash
command -v claude                       # expect: ~/.local/bin/claude
claude --version
claude auth status                      # expect: "authMethod": "claude.ai"
timeout 10 claude remote-control --help | grep -E -- '--(spawn|capacity|remote-control-session-name-prefix)'
```

`claude remote-control --help` can print its help and then stay running, hence the
`timeout`. All three flags must be listed; an older version lacks them.

**No variable that redirects or restricts the API.** Remote Control needs the
first-party claude.ai endpoint and login. None of these may reach the server:

- `ANTHROPIC_BASE_URL`, even set to the default endpoint — leave it unset
- `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_GROWTHBOOK`

The server does not inherit an interactive shell. It sees the user manager's
environment plus whatever the project's `.envrc` exports, and Claude Code then
applies the `env` blocks of its settings files. Check those, not the current
shell:

```bash
blocked='^(ANTHROPIC_(BASE_URL|API_KEY|AUTH_TOKEN)|CLAUDE_CODE_(OAUTH_TOKEN|DISABLE_NONESSENTIAL_TRAFFIC)|DISABLE_GROWTHBOOK)='
systemctl --user show-environment | grep -E "$blocked" | cut -d= -f1
env -i HOME="$HOME" PATH="$PATH" direnv exec ~/code/<PROJECT> env 2>/dev/null | grep -E "$blocked" | cut -d= -f1
for f in ~/.claude/settings.json ~/code/<PROJECT>/.claude/settings*.json; do
  [ -f "$f" ] && jq -r '.env // {} | keys[]' "$f" | sed 's/$/=/' | grep -E "$blocked" | sed "s|^|$f: |"
done
```

All three print names only, and must print nothing. The project's
`settings.local.json` is the easy one to miss: a local proxy wrapper, such as a
token-compression proxy that rewrites project settings, can leave
`ANTHROPIC_BASE_URL` pointing at a loopback port there. Remove it from that file
rather than overriding it in the unit: project settings take precedence over the
process environment.

Interactive sessions in the same project can keep using such a proxy. Set the
variable on those processes only, not in project settings, for example with a
shell function:

```bash
# <NAME> runs Claude Code through the local proxy on <PORT>; plain `claude` does not.
<NAME>() { ANTHROPIC_BASE_URL=http://127.0.0.1:<PORT> claude "$@"; }
```

Sessions started with `<NAME>` go through the proxy, while the Remote Control
server and the sessions it spawns reach the API directly. Pick a name other than
`claude`: the interactive first run below types `claude remote-control` by hand,
and redefining `claude` would hand it the variable.

**Proxy and certificate variables, if the network needs them.** The reverse
holds too: `HTTPS_PROXY`, `NO_PROXY` or `NODE_EXTRA_CA_CERTS` exported only by an
interactive shell never reach the server. Put them in the user manager's
environment (`~/.config/environment.d/`), the project's `.envrc`, or a settings
`env` block.

**A Git repository whose worktree directory is ignored.** `--spawn worktree`
creates worktrees under `.claude/worktrees/`:

```bash
git -C ~/code/<PROJECT> rev-parse --show-toplevel
git -C ~/code/<PROJECT> check-ignore -v .claude/worktrees/x    # must print a rule
```

If nothing is printed, add `.claude/worktrees/` to `.gitignore`, or to
`.git/info/exclude` to keep the rule local.

**An approved `.envrc`, if the project has one.** `direnv status` run in the
project must report `Found RC allowed true`.

## The unit

`~/.config/systemd/user/claude-rc@.service`:

```ini
# >>> claude-rc-unit >>>
[Unit]
Description=Claude Code Remote Control server for ~/code/%i (tmux session rc-%i)
# Ordering only: a user manager cannot see the system's network-online.target.
After=network-online.target

# An immediate failure restarts every RestartSec, so five land within the window
# and the unit ends `failed`. A start that cannot resolve the API name waits out
# TimeoutStartSec instead, so at most one start falls in the window and systemd
# keeps retrying.
StartLimitIntervalSec=120
StartLimitBurst=5

[Service]
Type=forking
WorkingDirectory=%h/code/%i
Environment=PATH=%h/.local/bin:%h/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin

# claude exits at once when it cannot resolve the API name, so wait for it here.
ExecStartPre=/bin/sh -c 'until getent ahosts api.anthropic.com >/dev/null; do sleep 5; done'
# A blocked .envrc makes `direnv exec` exit 1 without running its command. Inside
# tmux that only ends the session cleanly; checking first makes it a unit failure.
ExecStartPre=/usr/bin/direnv exec %h/code/%i /bin/true
ExecStart=/usr/bin/tmux -L rc-%i new-session -d -s rc-%i -c %h/code/%i \
    /usr/bin/direnv exec %h/code/%i %h/.local/bin/claude remote-control --name "%i" --remote-control-session-name-prefix "%i" --spawn worktree --capacity 4 --permission-mode auto
# The server holds one session, so stop it whole. A `-t rc-%i` target would read
# a "." in the instance name as a pane separator. The server is already gone
# whenever claude exited on its own.
ExecStop=-/usr/bin/tmux -L rc-%i kill-server
# tmux runs the pane in its own scope, outside this unit, so systemd neither
# waits for claude nor kills it. Wait here, escalating to TERM and then KILL, or a
# restart starts the new server while the old one is still running. This also
# reaps a claude left behind when the tmux server dies on its own.
ExecStopPost=-/usr/bin/timeout 15 /bin/sh -c 'while pgrep -f "^[^ ]*/claude remote-control --name %i " >/dev/null; do sleep 0.5; done'
ExecStopPost=-/usr/bin/pkill -TERM -f "^[^ ]*/claude remote-control --name %i "
ExecStopPost=-/usr/bin/timeout 5 /bin/sh -c 'while pgrep -f "^[^ ]*/claude remote-control --name %i " >/dev/null; do sleep 0.5; done'
ExecStopPost=-/usr/bin/pkill -KILL -f "^[^ ]*/claude remote-control --name %i "

Restart=always
RestartSec=10
TimeoutStartSec=300
TimeoutStopSec=30

[Install]
WantedBy=default.target
# <<< claude-rc-unit <<<
```

Adjust `/usr/bin/tmux` and `/usr/bin/direnv` to what `command -v` reports. Nothing
goes before `remote-control` on the command line: it is a subcommand, and global
flags placed ahead of it are not Remote Control options.

### Why it is shaped this way

- **A tmux server per instance (`-L rc-%i`).** On the default socket,
  `new-session` joins any tmux server the user already runs. The new session then
  lives outside the unit, the forking client exits, and systemd records the
  service as stopped while the server keeps running untracked, so `Restart=` never
  fires. The reverse is as bad: if the service started the default server first,
  tmux sessions opened later by hand become part of the service and are killed by
  `systemctl --user stop`.
- **No `-t` target anywhere.** Each dedicated server holds exactly one session, so
  tmux commands need only `-L`. A target would break on instance names containing
  `.` or `:`: tmux stores the session as `rc-foo_bar` and reads `-t rc-foo.bar` as
  window `rc-foo`, pane `bar`.
- **`Type=forking`.** `tmux new-session -d` starts the tmux server, which
  daemonizes, and the client returns. systemd tracks the server as the main
  process; the server exits when its only session ends.
- **`Restart=always`, not `on-failure`.** When `claude` exits, for any reason, its
  session closes and the tmux server exits with status 0. To systemd that is a
  clean exit, so `on-failure` would leave the project without a server.
- **Wait for name resolution before starting.** Started without network, `claude
  remote-control` prints `Error: getaddrinfo EAI_AGAIN api.anthropic.com` and
  exits 1 rather than retrying. The first `ExecStartPre` waits for the name to
  resolve, bounded by `TimeoutStartSec`. This matters most at boot, when the
  user manager starts the unit with no network guarantee. It covers only a
  missing name: a network that resolves but cannot connect (a cached resolver
  with the uplink down, a captive portal, a proxy-only network) passes the wait,
  claude fails at once, and that counts as an immediate failure.
- **A start limit sized for both failure speeds.** `StartLimitIntervalSec` and
  `StartLimitBurst` belong in `[Unit]`; systemd ignores the interval in
  `[Service]` with a warning but silently accepts the burst there. A failure
  that happens at once (an untrusted workspace, a blocked variable) restarts every
  10 seconds, so five starts fall inside 120 seconds and the unit ends `failed`
  — visible, instead of restarting for ever. A start that cannot resolve the API
  name spends up to 300 seconds waiting, so the same window never holds a second
  start and systemd keeps retrying until resolution returns.
- **`ExecStop=-…`.** After claude exits, `kill-server` finds no server and returns
  1. The `-` prefix keeps that from marking the unit `failed` on every restart.
- **`ExecStopPost` waits for claude itself, then forces it.** The tmux server
  exits within milliseconds of `kill-server`, but claude, in its own scope, takes
  a second or more to shut down after the hangup. Without the wait a restart
  starts the new server first; it exits at once and the unit only recovers on the
  next automatic restart. If claude is still running after 15 seconds it gets
  `SIGTERM`, and after 5 more `SIGKILL`, all inside `TimeoutStopSec`. The same
  commands run after any stop, so a claude that outlived a crashed tmux server is
  reaped before the next start. When claude has already exited they return at
  once and do not delay the restart.
- **`direnv exec` around `claude`.** The server receives exactly the environment an
  interactive `cd ~/code/<PROJECT> && claude` would see, and every session it
  spawns inherits it — including sessions in worktrees, where git-ignored files
  such as `env.local` do not exist. MCP servers that expand `${VAR}` from the
  environment therefore work in remote sessions too.
- **One project per instance, so no allowlist.** A server shared by every project,
  such as the persistent OpenCode server (see
  [OpenCode as a persistent service](opencode-service.md)), has to merge several
  `.envrc` files and so needs an allowlist and conflict detection. Here one
  `.envrc` is loaded whole, as it would be interactively.
- **The permission mode is set on the server, not left to settings.** Nobody is
  at the workstation to answer a prompt, so a session that waits for approval
  stalls until someone opens it in a client. A project's
  `permissions.defaultMode` does not reliably reach the sessions the server
  starts: with `defaultMode: "auto"` in the project's settings, a new worktree
  session ran in auto mode, while the server's own session resumed after a
  restart ran in `default`. The server passes `--permission-mode` to every
  session it spawns, so the flag covers both. It must follow `remote-control`:
  given before the verb, Remote Control refuses to start. A client can still
  change the mode of a session it has open.
- **mise shims on PATH, not versioned runtime directories.** Shims resolve tools
  against the project's own mise configuration in each working directory.

## First run is interactive

On its first run in a directory, `claude remote-control` asks
`Enable Remote Control? (y/n)` and whether to trust the workspace. Without a
terminal it cannot ask, and exits with `Workspace not trusted`. Answer both once,
by hand, before enabling the unit:

```bash
cd ~/code/<PROJECT> && claude remote-control       # answer y twice, then Ctrl+C
```

## Enable

```bash
systemctl --user daemon-reload
systemd-analyze --user verify claude-rc@<PROJECT>.service    # must print nothing
systemctl --user enable --now claude-rc@<PROJECT>
loginctl enable-linger <USER>
```

`systemd-analyze verify` reports an unknown key as a warning and still exits 0, so
read its output rather than its status. Lingering keeps the user manager, and
with it the service, running without a login session; see
[Lingering](opencode-service.md#lingering).

## Verification

```bash
systemctl --user status claude-rc@<PROJECT> --no-pager
tmux -L rc-<PROJECT> has-session && echo running
tmux -L rc-<PROJECT> capture-pane -p | tail -20
```

The pane should show `Connected · <PROJECT>`, the capacity, and the claude.ai link
for the environment. The environment identifier survives restarts, so the link
stays valid.

`Tasks: 1` in the status output is expected. tmux built with systemd support moves
each pane into its own transient `tmux-spawn-*.scope`, so `claude` and its MCP
servers run outside the service's cgroup; only the tmux server remains inside.
systemd therefore neither waits for nor kills the payload on its own: the
unit's `kill-server` hangs it up and `ExecStopPost` waits for it, forcing it if
needed, and the scope disappears on stop. The unit's resource limits and accounting do not cover the payload.

To confirm that the project environment reached the server, list variable *names*
only — never values:

```bash
pid=$(pgrep -f '^[^ ]*/claude remote-control --name <PROJECT> ')
tr '\0' '\n' < /proc/"$pid"/environ | cut -d= -f1 | sort
```

The pattern is anchored to the first argument because the tmux server's own
command line contains the same words further along, and ends in a space so that
`foo` does not also match `foo-bar`.

## Operations

| Task | Command |
|---|---|
| Watch the TUI | `tmux -L rc-<PROJECT> attach` |
| Detach | `Ctrl+B` then `D` — `Ctrl+C` stops the server, which systemd then restarts |
| Stop | `systemctl --user stop claude-rc@<PROJECT>` |
| Restart | `systemctl --user restart claude-rc@<PROJECT>` |
| Logs | `journalctl --user -u claude-rc@<PROJECT> -f` |
| Recent pane output | `tmux -L rc-<PROJECT> capture-pane -p \| tail -20` |

Every tmux command needs `-L rc-<PROJECT>`; without it tmux looks at the default
server and finds no session.

The environment is read once, at start. After editing `env.local` (or whatever the
`.envrc` sources), restart the unit. After editing `.envrc` itself, run
`direnv allow` in the project first; until then the start check fails. Once five
starts have failed, the unit refuses a restart until the 120-second window passes
or `systemctl --user reset-failed claude-rc@<PROJECT>` clears the counter.

### Another project

Repeat the prerequisites for `~/code/<OTHER>`, run the interactive first run
there, then `systemctl --user enable --now claude-rc@<OTHER>`. A worktree ignore
rule kept in one repository's `.git/info/exclude` does not carry over.

### Sessions and worktrees

The server creates one session in the project directory itself when it starts;
sessions opened from claude.ai or the app go to worktrees. When a session ends
other than cleanly — closing or archiving it from a client is enough — the pane
logs `Session failed: Process exited with error` and `kept worktree … session
crashed`. The server itself is unaffected.

Kept worktrees and their `worktree-*` branches accumulate. Remove one only after
checking it has no uncommitted work and no commits ahead of the default branch.

## Rollback

```bash
systemctl --user disable --now claude-rc@<PROJECT>
rm ~/.config/systemd/user/claude-rc@.service      # once no instance uses it
systemctl --user daemon-reload
```

Lingering, trust and the Remote Control opt-in can stay; they are inert without
the unit.

## Troubleshooting

Both failures below end in `start-limit-hit`. systemd then refuses new starts,
including a manual restart, until the 120-second window passes or the counter is
cleared. After fixing the cause:

```bash
systemctl --user reset-failed claude-rc@<PROJECT>
systemctl --user restart claude-rc@<PROJECT>
```

### The unit is `failed` and the journal shows `direnv: error … is blocked`

The `.envrc` changed or was never approved. Review it, run `direnv allow` in the
project, then reset and restart the unit.

### The unit restarts every 10 seconds, then fails with `start-limit-hit`

`claude` exits as soon as it starts. Run the first-run step by hand.
`Workspace not trusted` in the journal or the pane means the trust prompt was
never answered; a refusal mentioning the API endpoint or login means a variable
from the prerequisites reaches the server.

### The unit stays `activating` for minutes

The first start check is waiting for `api.anthropic.com` to resolve: the machine
has no network or no DNS. The unit starts on its own once the name resolves.
Meanwhile `systemctl --user start`, `restart` and `enable --now` wait for the
start job and appear to hang for up to 300 seconds; add `--no-block` to return
at once.

### The name resolves, but the unit still ends in `start-limit-hit`

The network resolves names but cannot reach the API — a cached resolver with the
uplink down, a captive portal, or a proxy the server does not know about. claude
fails at once on each start, so the limit is reached. Check the proxy and
certificate variables in the prerequisites, then reset and restart the unit.

### `tmux attach` says there is no session

The command is missing `-L rc-<PROJECT>`.
