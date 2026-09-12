# OpenCode as a Persistent Service

Running OpenCode as a long-lived server on a workstation, instead of starting a
fresh backend per terminal. An optional standalone Telegram client and an
optional HTTPS LAN edge are independent clients of that server.

Two independent halves. Part 1 is the whole story for a single-machine setup and
has no Windows dependency. Part 2 is additive and only worth doing if another
device genuinely needs to reach the server.

Placeholders used throughout: `<USER>` the Linux account, `<PORT>` the server
port (`4096` below), `<HOSTNAME>` the DNS name the LAN resolves to the
workstation, `<LAN_SUBNET>` the home or office subnet in CIDR form,
`<NODE_DIR>` the directory containing the pinned Node binary, and
`<BOT_VERSION>` the pinned `@grinev/opencode-telegram-bot` version.

## Policy

These hold for every step. They are what makes the arrangement safe rather than
merely working.

- **The server binds loopback only.** `127.0.0.1:<PORT>`, never `0.0.0.0`. Every
  widening of reach happens in front of it, never by rebinding it.
- **OpenCode stays the authentication authority.** Its HTTP Basic credentials
  gate every request. A TLS edge in front adds no second auth layer and removes
  none.
- **A client on the same host talks to loopback.** Not to the LAN name. See
  [On-host clients](#on-host-clients-use-loopback).
- **Never disable TLS verification.** No `curl -k` / `--insecure`, no
  `NODE_TLS_REJECT_UNAUTHORIZED=0`. Every legitimate problem below has a fix
  that *adds* trust rather than removing verification.
- **Credentials never reach an interactive shell, a process argument list, a
  config file, or a log.**
- **Exactly one process polls a Telegram bot token.** A second poller, including
  a diagnostic `getUpdates`, displaces the first and produces HTTP 409 conflicts.
- **No port forwarding.** No `netsh portproxy`, no plaintext LAN listener, no
  inbound rule on a network the OS classifies as public.

## Architecture

```text
other LAN device                                this workstation
      |                                               |
      | https://<HOSTNAME>:443                        | TUI / Web UI / local tooling
      v                                               v
 +----------------+                          +-----------------+
 | reverse proxy  |------------------------->| OpenCode server |
 | TLS, internal  |   127.0.0.1:<PORT>       | loopback only   |
 +----------------+                          +-----------------+
                                                      ^
                                                      | OpenCode API
                                             +-----------------+
 Telegram Bot API <--------------------------| Telegram client |
                                             +-----------------+
```

Part 2 adds only the left branch. The right branch is Part 1 and is what local
work uses.

## Part 1 — the persistent server

### The unit

A **user** unit, not a system unit: the server runs as the developer, with their
credentials, tool versions and home directory.

`~/.config/systemd/user/opencode.service`:

```ini
[Unit]
Description=OpenCode persistent server
After=network-online.target
Wants=network-online.target

# These two belong in [Unit], not [Service]. systemd ignores
# StartLimitIntervalSec in [Service] with an "Unknown key name" warning, while
# tolerating StartLimitBurst there — so a template that puts both in [Service]
# keeps a burst with a defaulted 10s window and reads as protected while being
# inert. Check with `systemd-analyze --user verify` rather than by eye.
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
WorkingDirectory=%h
EnvironmentFile=%h/.config/opencode-runtime/secrets.env

ExecStart=%h/.opencode/bin/opencode web --hostname 127.0.0.1 --port 4096
ExecStartPost=%h/.local/libexec/opencode/opencode-startup-ready

Restart=always
RestartSec=3

# Must exceed the readiness probe's own window, or systemd kills the start
# before the probe can report which half failed.
TimeoutStartSec=120
TimeoutStopSec=20

[Install]
WantedBy=default.target
```

`--hostname 127.0.0.1` is the load-bearing argument.

`Restart=always` rather than `on-failure`: a clean exit is still an absent
server, and `on-failure` leaves it stopped.

Bounded restart limits matter, and the window has to be wider than
`RestartSec` × `StartLimitBurst` or it can never be reached. With
`RestartSec=3` and a burst of 5, consecutive starts land at t = 0, 3, 6, 9, 12,
so a 60s window catches the fifth and a persistent failure ends in a visible
`failed` state. systemd's own default is 10s, which the same sequence outruns —
the more dangerous state, because the unit then restarts for ever while
appearing to have a limit configured.

```bash
systemctl --user daemon-reload
systemctl --user enable --now opencode.service
systemctl --user status opencode.service
```

### Credentials

One file, never committed, readable only by its owner:

```bash
install -d -m 700 ~/.config/opencode-runtime
install -m 600 /dev/null ~/.config/opencode-runtime/secrets.env
```

It holds the server's Basic-auth username and password. A sidecar may read the
same file for those credentials and for its own token, but the server does not
need a channel token. `EnvironmentFile` keeps every secret out of `ExecStart` —
a process argument list is world-readable via `/proc`, an environment file is
not.

Verify the file never became readable to others, and that auth is actually on:

```bash
stat -c '%a %U' ~/.config/opencode-runtime/secrets.env   # expect: 600 <USER>
curl -si http://127.0.0.1:4096/global/health | head -2   # expect: 401 + WWW-Authenticate
```

**A `200` from that anonymous call means authentication is not enabled.** Stop
and fix that before going any further; Part 2 would then publish an unauthenticated
server to the LAN.

### Lingering

A user manager normally starts at first login and stops at last logout, which
would stop the server. Lingering decouples it:

```bash
loginctl enable-linger <USER>
loginctl show-user <USER> | grep Linger        # expect: Linger=yes
```

With `Linger=yes` plus `WantedBy=default.target`, the server returns whenever the
OS boots, with no login. On WSL this also requires systemd to be the init
system — `[boot] systemd=true` in `/etc/wsl.conf`, verified with
`ps -p 1 -o comm=` reporting `systemd`.

### Readiness

`ExecStartPost` runs a script that blocks until the server answers and its tool
surface is available, then logs a line per check. Without it, `systemctl
start` returns as soon as the process exists, and the next command in a script
races a server that is listening but not ready. Anything that polls the health
endpoint and one required tool, then exits non-zero on timeout, is sufficient.

`opencode-service/opencode-startup-ready.sh` in this repository is one such
probe. Copy it to the path the unit names:

```bash
install -D -m 755 opencode-service/opencode-startup-ready.sh \
  ~/.local/libexec/opencode/opencode-startup-ready
```

Two things it gets right that are easy to miss. It checks **both** health and
the registered tool surface. The gateway-neutral default is the built-in
`bash` tool; set `READY_TOOL_MARKER` to a plugin-owned tool only when that plugin
is required for the server to count as ready. And it never calls anything
external, so an outage at a message channel cannot fail a start and have systemd
restart a healthy server.

Whatever probe you use, keep `TimeoutStartSec` above its window. Left at the
default the start is killed first, and the probe's own diagnosis — which half
failed — is what you lose.

### Optional standalone Telegram client

Keep Telegram outside the OpenCode process. A sidecar can fail or be upgraded
without replacing the server, while the TUI and Web UI continue to use the same
OpenCode API and native sessions.

Install a pinned release into a versioned directory. Do not use `@latest` in the
unit:

```bash
release="$HOME/.local/share/opencode-telegram-bot/releases/<BOT_VERSION>"
mkdir -p "$release"
npm install --prefix "$release" --omit=dev \
  @grinev/opencode-telegram-bot@<BOT_VERSION>

install -D -m 755 opencode-service/opencode-telegram-ready.sh \
  ~/.local/libexec/opencode/opencode-telegram-ready
install -d -m 700 ~/.config/opencode-telegram-bot
install -m 600 /dev/null \
  ~/.config/opencode-runtime/opencode-telegram-bot.env
```

The common `secrets.env` supplies `TELEGRAM_BOT_TOKEN` and the OpenCode Basic
credentials. The second, non-secret environment file supplies deployment
settings such as `TELEGRAM_ALLOWED_USER_ID`,
`OPENCODE_API_URL=http://127.0.0.1:4096`, and
`OPENCODE_AUTO_RESTART_ENABLED=false`. The last setting is load-bearing:
systemd owns the server, so the bot must not try to replace it. Keep both files
mode `600`; an allowlisted user ID is not a token, but there is no reason to
publish it.

`~/.config/systemd/user/opencode-telegram-bot.service`:

```ini
[Unit]
Description=OpenCode Telegram client
After=network-online.target opencode.service
Wants=network-online.target opencode.service
StartLimitIntervalSec=600
StartLimitBurst=5

[Service]
Type=exec
WorkingDirectory=%h/.config/opencode-telegram-bot
RuntimeDirectory=opencode-telegram-bot
UMask=0077

Environment="PATH=<NODE_DIR>:%h/.opencode/bin:%h/.local/bin:/usr/bin:/bin"
Environment="TELEGRAM_READY_TIMEOUT=60"
EnvironmentFile=%h/.config/opencode-runtime/secrets.env
EnvironmentFile=%h/.config/opencode-runtime/opencode-telegram-bot.env

# The direct entrypoint exits on startup errors. --no-fork keeps Node as MainPID.
ExecStart=/usr/bin/flock --nonblock --no-fork %t/opencode-telegram-bot/instance.lock <NODE_DIR>/node %h/.local/share/opencode-telegram-bot/releases/<BOT_VERSION>/node_modules/@grinev/opencode-telegram-bot/dist/index.js --mode installed
ExecStartPost=%h/.local/libexec/opencode/opencode-telegram-ready

Restart=on-failure
RestartSec=5
TimeoutStartSec=90
TimeoutStopSec=15

[Install]
WantedBy=default.target
```

`Wants=` is deliberately weaker than `Requires=`: an OpenCode failure does not
tear down the bot, and systemd can recover either service independently.
`flock --no-fork` keeps Node as the service's main process and guards starts that
use the same lock. It cannot stop the old gateway or an arbitrary manual client;
operationally, singleton polling still depends on disabling every other poller.
The readiness helper requires both authenticated OpenCode health and a
`Bot @… started!` journal marker from the current systemd invocation. That marker
is vendor output, so verify it when upgrading the bot. A bot or Node upgrade also
requires updating the two pinned paths in the unit.

The bot owns `~/.config/opencode-telegram-bot/settings.json`, including scheduled
tasks and a directory cache. Back it up, but do not use the cache as declarative
configuration: it contains machine-local paths and changes during normal use.

If this replaces another Telegram integration, snapshot that integration first
and stop it before enabling the sidecar. Confirm that no old plugin or service
can still poll the same token. A rollback must reverse that order: stop the
sidecar first, restore the former integration, then start it. Removing only the
new sidecar is otherwise independent of OpenCode:

```bash
systemctl --user disable --now opencode-telegram-bot.service
rm ~/.config/systemd/user/opencode-telegram-bot.service
systemctl --user daemon-reload
```

Keep the versioned release, environment file, settings and readiness helper
until the rollback window closes; they are harmless while the unit is absent
and make restoration deterministic.

```bash
systemctl --user daemon-reload
systemctl --user enable --now opencode-telegram-bot.service
systemctl --user status opencode-telegram-bot.service
journalctl --user -u opencode-telegram-bot.service
```

Verify end to end by sending `/status` from an allowlisted Telegram account and
checking that the reply reports the expected bot and OpenCode versions. Do not
probe the same token with `getUpdates`; that creates a competing poller and is
not a safe health check.

### Restarts requested by a plugin

This is optional and unrelated to the standalone Telegram client. Skip it
unless a plugin offers a restart tool — one that reloads skills,
agents or configuration by replacing the server. The tool cannot do the work
itself: it lives inside the process that has to be replaced. Plugins in that
position write a request into a control directory and rely on whatever
supervises the server to carry it out.

Under `systemd --user` there is no such supervisor. The plugin vendor's own
launcher normally fills that role, but adopting it here would mean giving up
`opencode web` for whatever the launcher spawns, and letting it own the config
directory. So systemd becomes the executor instead, and the missing consumer is
a path-activated unit.

**Do not simply set the plugin's managed flag.** Whatever variable makes the
tool believe a supervisor exists, setting it alone is worse than leaving it
unset: the tool then reports a restart as scheduled and nothing ever performs
one. The flag and the consumer go in together.

For `opencode-gateway`, add all four settings to the server unit; none is
optional when this integration is enabled:

```ini
[Service]
Environment="OPENCODE_GATEWAY_CONFIG=%h/.config/opencode-gateway/opencode/opencode-gateway.toml"
Environment="OPENCODE_GATEWAY_CONTROL_DIR=%h/.config/opencode-gateway/opencode/control"
Environment="OPENCODE_GATEWAY_MANAGED=1"
Environment="READY_TOOL_MARKER=gateway_status"
```

The first two keep the plugin on its intended configuration and control state,
the third advertises a working supervisor, and the fourth makes server readiness
fail if the plugin does not initialise. Install and enable the consumer below
before restarting the server with this drop-in.

The contract is the control directory, and it is the plugin's, not yours:

```text
restart-request.json   {requestedAtMs, requestedBy}      written by the plugin
restart-status.json    {state, requestedAtMs, startedAtMs,
                        completedAtMs, lastError}         the shared record
state ∈ pending | restarting | idle | failed
```

Install the consumer and the pair that triggers it:

```bash
install -D -m 755 opencode-service/opencode-gateway-restart.sh \
  ~/.local/libexec/opencode/opencode-gateway-restart
```

`~/.config/systemd/user/opencode-gateway-restart.service`:

```ini
[Unit]
Description=Consume the plugin's restart request and restart the server

# No dependency on the server unit in either direction, deliberately. This unit
# restarts that one; an edge between them is only a way for the two to deadlock.

[Service]
Type=oneshot
EnvironmentFile=%h/.config/opencode-runtime/secrets.env
Environment="OPENCODE_GATEWAY_CONTROL_DIR=%h/.config/opencode-gateway/opencode/control"
Environment="RESTART_TARGET_UNIT=opencode.service"
ExecStart=%h/.local/libexec/opencode/opencode-gateway-restart

# `systemctl restart` blocks on the target's start job, which runs the readiness
# probe, and the idle wait happens before that.
TimeoutStartSec=600
```

`~/.config/systemd/user/opencode-gateway-restart.path`:

```ini
[Unit]
Description=Watch for a plugin restart request

[Path]
# The plugin's own trigger, written when a queued turn ends. PathExists is
# self-healing: systemd re-checks once the consumer goes inactive, so a request
# arriving mid-restart is not lost.
PathExists=%h/.config/opencode-gateway/opencode/control/restart-request.json

# The interactive case. The tool records the intent immediately but defers the
# request file to the next completed queued turn, which for an attached terminal
# session may never arrive. Edge-triggered, so an intent landing while the
# consumer already runs can be missed; re-asking is one tool call.
PathModified=%h/.config/opencode-gateway/opencode/control/restart-status.json

Unit=opencode-gateway-restart.service

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now opencode-gateway-restart.path
```

Three properties are worth understanding before trusting it.

**It waits for idle.** The request file appearing proves the *asking* turn
ended, not that a concurrent one has, so the server is polled until it reports
no active session — and the target is never restarted while mid-start, which
would cut off a readiness probe already running. An unanswered poll counts as
idle: nothing is in flight through an API that is not answering.

**It writes nothing when it finds no work.** The consumer is path-activated on
files it also writes, so that silence is what stops the trigger chain. Any
change to it has to preserve that.

**It consumes the request even when it refuses.** A request left in place
re-triggers the unit for ever. After the idle wait expires the request is
removed and the reason recorded in `lastError`, where the plugin's own status
tool will show it.

The contract above is read from a specific plugin release, not from a published
specification. Re-read it when the plugin is upgraded — and note that the state
file is shared, so a malformed write surfaces as a broken plugin rather than as
an absent file. That is why the consumer writes it atomically.

### On-host clients use loopback

The client wrapper below attaches to `http://127.0.0.1:<PORT>`. That is
deliberate and it is worth being explicit about, because once Part 2 exists the
LAN name looks like the more "correct" address.

It is not. From this host, using `https://<HOSTNAME>` sends the request out to
the LAN interface, through the proxy, and back to a server that was already
reachable on loopback. It adds a TLS handshake, a firewall traversal and a
certificate-trust dependency, to arrive at the same socket. **Same host means
loopback.** The edge exists for *other* devices.

### The attach wrapper

A shell function that makes the bare command attach to the running server rather
than starting a second backend:

```bash
# >>> opencode-attach-wrapper >>>
opencode() {
    local __oc_secrets="$HOME/.config/opencode-runtime/secrets.env"

    if [ "$#" -eq 0 ]; then
        if ! systemctl --user is-active --quiet opencode.service; then
            echo "OpenCode persistent service is not running." >&2
            echo "Start it with: systemctl --user start opencode.service" >&2
            return 1
        fi

        if [ ! -r "$__oc_secrets" ]; then
            echo "OpenCode server credentials not readable: $__oc_secrets" >&2
            echo "Refusing to attach unauthenticated." >&2
            return 1
        fi

        # Subshell is intentional: the imported credentials live only for the
        # duration of the attached TUI and never reach the interactive shell.
        (
            set -a
            . "$__oc_secrets"
            set +a

            # The attach client does not need any channel tokens.
            unset TELEGRAM_BOT_TOKEN

            command opencode attach http://127.0.0.1:4096
        )
    else
        command opencode "$@"
    fi
}
# <<< opencode-attach-wrapper <<<
```

Four properties are each there for a reason:

- **The subshell.** Credentials exist only for the attached process. Sourcing
  them in the interactive shell would leak them into every later child process
  and into anything that dumps the environment.
- **Arguments are forwarded untouched.** `--version`, `models`, `debug` keep
  their normal behaviour; only the no-argument form is reinterpreted.
- **It refuses rather than degrading.** No credentials means no attach, instead
  of a confusing unauthenticated attempt.
- **`command opencode` is the escape hatch**, and the function relies on it
  internally to avoid recursing.

Place this **outside** any block an installer rewrites wholesale, or the next
install will silently delete it. Mark the boundary with comments, as above.

### Verification

```bash
systemctl --user is-enabled opencode.service          # enabled
systemctl --user is-active  opencode.service          # active
ss -ltn | grep 4096                                   # 127.0.0.1:4096 ONLY
ss -ltn | grep -c '0.0.0.0:4096'                      # 0
curl -so /dev/null -w '%{http_code}\n' http://127.0.0.1:4096/global/health   # 401
```

Then restart the machine (or `systemctl --user restart`) and confirm the server
returns on its own.

If you installed the restart consumer, verify it end to end rather than by
inspection — write a request of the shape the plugin writes, and watch systemd
do the rest:

```bash
CONTROL=~/.config/opencode-gateway/opencode/control
printf '{"requestedAtMs": %s000, "requestedBy": "test"}\n' "$(date +%s)" \
  > "$CONTROL/restart-request.json"

systemctl --user show -p MainPID --value opencode.service   # note it, expect a change
journalctl --user -u opencode-gateway-restart.service -f    # accepted, then restarted
jq . "$CONTROL/restart-status.json"                         # state=idle, lastError=null
ls "$CONTROL"                                               # the request is gone
```

The plugin's own status tool should then report the restart as supported and
managed. If it reports a restart as scheduled but nothing happens, the managed
flag is set and the consumer is not.

## Part 2 — optional TLS LAN edge

Only if another device needs access. A reverse proxy on the host terminates
HTTPS on the LAN interface and forwards to the loopback server. Written for a
Windows host in front of WSL, where the OS forwards `127.0.0.1` into the distro;
the shape is the same for a Linux host with the proxy beside the server.

### Identity: a DNS name, not an address

Use `<HOSTNAME>`, not the current IP. A DHCP lease change otherwise invalidates
the proxy binding, the certificate identity and every client's URL at once. Most
home routers register DHCP clients in their own DNS, which makes the name
self-updating and is exactly the property wanted here.

Prove resolution **before** adopting the name, and stop if it fails rather than
falling back to the address:

```bash
getent hosts <HOSTNAME>          # must return an address on <LAN_SUBNET>
```

> **Trap: multi-homed hosts get multiple A records.** A laptop with both
> Ethernet and Wi-Fi may be registered twice under one name, and the record for
> the currently disconnected interface is stale. Clients that try addresses in
> order and fall back will still connect, with a delay; clients that pick at
> random may fail outright. Check what the name resolves to and remove stale
> reservations at the router.

### The proxy

Install from a package manager, not by fetching a binary by hand, and pin the
version. Then point a Windows service at the **real executable**, not at a shim:

> **Trap: user-scoped package paths cannot back a machine service.** A portable
> or archive-type package installs per-user by default, under the installing
> user's profile. A service running as a machine account cannot depend on that
> path. Install machine-wide (`winget install --scope machine`, or an
> equivalent), then resolve the actual `.exe` — a package manager's `Links`
> entry is often a zero-byte symlink or shim, which is not a valid service
> binary. Record the binary's SHA-256, and re-record it after every upgrade,
> because an upgrade that moves the path silently breaks the service.

Configuration, with Caddy as the example:

```caddyfile
{
	admin off
	auto_https disable_redirects
}

https://<HOSTNAME> {
	tls internal

	reverse_proxy http://127.0.0.1:4096
}
```

- `tls internal` mints a private CA and issues from it. No public DNS, no ACME,
  no public exposure required.
- `auto_https disable_redirects` keeps port 80 closed. There is no plaintext
  listener to redirect *from*, and adding one would violate the policy above.
- `admin off` closes the local admin API, which is unauthenticated by default.
- **No `bind` directive.** See below.
- No auth block, no invented security headers, no access log. The server behind
  handles auth; headers risk breaking the Web UI; a log is one more place an
  `Authorization` value could land.

Validate before starting the service, and assert on the adapted config rather
than trusting the source file:

```powershell
caddy validate --config <CONFIG> --adapter caddyfile
caddy adapt    --config <CONFIG> --adapter caddyfile --pretty
```

Confirm in the adapted output: the site host is `<HOSTNAME>`, the upstream is
`127.0.0.1:4096`, the issuer is `internal`, redirects are disabled, and no IP
literal appears in `listen`.

Give the service bounded failure recovery — restart twice, then stop trying — so
a transient fault self-heals and a permanent one stays visible.

### The firewall is the boundary

Deliberately **no** fixed bind, so the proxy may listen on `:443` on any
interface. A wildcard `0.0.0.0:443` or `[::]:443` listener is therefore expected
and is not a finding. Reachability is decided by firewall rules instead:

```text
profile        Private          (never Public, never Any)
direction      Inbound, Allow
protocol       TCP, local port 443
remote address <LAN_SUBNET>     (an explicit subnet, not "any", not "local subnet")
program        <the real proxy executable>
interface type Wired  -- and a second, identical rule for Wireless
```

Two rules differing only in interface type is what makes the machine portable
across a built-in NIC, a USB dongle and Wi-Fi with no edits. **Do not pin
`InterfaceAlias` or a local address**: an alias ties the rule to one adapter, and
a local address reintroduces the DHCP dependency the DNS name just removed.

Why an explicit subnet rather than the OS's "local subnet" token: that token is
evaluated per receiving interface, so it also matches virtual switches — a
container or VM network on the host satisfies it.

If the interface the LAN arrives on is classified **public**, stop. Do not add a
public-profile rule, and do not silently reclassify the network: a
private-profile rule is inert on a public interface, which looks like success
while nothing can connect, and reclassifying activates every other
private-profile rule on that adapter, not just this one. Reclassifying may be
the right call — but as a decided change, not a side effect.

Order matters when replacing rules: create and verify the replacements, then
remove the old, then restart the proxy. Read the effective rule back from the
firewall API afterwards rather than trusting the creation command.

> **Trap: NAT can defeat remote-address narrowing.** Where the proxy fronts a
> VM or WSL, traffic from *inside* that VM to the host's LAN address may be
> source-translated to the host's own LAN address — landing inside
> `<LAN_SUBNET>` and matching the rule. Narrowing the remote address cannot
> exclude it. This is normally harmless, because a process in that VM already
> reaches the server on loopback and so gains nothing, but it should be a
> recorded decision rather than a surprise. Verify by testing from inside the VM
> and observing which source address the host actually sees.

### Distributing trust

Export **only** the public root certificate — never the root key, an
intermediate key, or the proxy's data directory. The private CA's key stays on
the host that generated it.

Locate the CA belonging to the **service account**, which is not the CA an
interactive `caddy trust` would create. Then prove the file is the one in use,
rather than inferring it from its path, by fetching the live certificate and
chain-building it against that root alone as the only trusted anchor. A
successful build is proof; a matching timestamp is not.

Install the exported root into each client's own trust store, and check the
certificate's identity is a DNS name for `<HOSTNAME>` with no IP entry left over
from an earlier address-based setup.

A normal proxy restart must **not** rotate the CA. Verify by comparing the root
fingerprint before and after, because a rotation invalidates every client's
trust at once and the symptom appears on the clients, not on the host.

### Verification

From a client that trusts the root, with no bypass flag anywhere:

| Request | Expected |
|---|---|
| anonymous | `401` with the Basic realm preserved |
| deliberately wrong password | `401` |
| correct credentials | `200`, healthy payload |
| `http://<HOSTNAME>` (port 80) | refused — nothing listens |
| `http://<HOSTNAME>:<PORT>` direct | refused — server is loopback-only |
| from an untrusted client | certificate validation failure, not bypassed |

Then confirm the negative half on the host: nothing listening on port 80, and
nothing but loopback listening on `<PORT>`.

## Troubleshooting

### `unable to get local issuer certificate` from the OpenCode CLI

The client validates against a **bundled** CA list, not the OS trust store:
OpenCode ships as a Bun single-file executable, which a `/$bunfs/` frame in the
stack trace identifies. So a browser on the same machine validates the edge
happily while the CLI refuses it — a confusing pair of symptoms with one cause.

Point the client at the root explicitly:

```bash
NODE_EXTRA_CA_CERTS=/path/to/root.crt opencode attach https://<HOSTNAME>
```

That **adds** an anchor and keeps verification fully on. It is not
`NODE_TLS_REJECT_UNAUTHORIZED=0`, which switches verification off and must not
be used. Note this applies to a client on **another** device; on the host
itself, attach to loopback and the question does not arise.

### `curl` fails on Windows but browsers succeed

```text
schannel: ... CRYPT_E_NO_REVOCATION_CHECK (0x80092012)
```

Not a trust failure. Windows `curl` uses Schannel, which by default treats "could
not check revocation" as fatal, and a private CA publishes no CRL or OCSP
endpoint — so the check is unsatisfiable by construction. Browsers and .NET do
not hard-require it.

Use `curl --ssl-revoke-best-effort`, which relaxes *only* revocation and still
verifies the chain and hostname. Confirm it is not a bypass by pointing a
deliberately wrong hostname at the same address and watching it still be
rejected. Reaching for `-k` here would trade a satisfiable problem for a real
hole.

### The edge answers `502`

The proxy is healthy and the server behind it is not. Check the unit, then the
loopback health endpoint. On WSL this is also the expected state after the distro
stops: the proxy keeps listening while its upstream is gone, and recovers on its
own once the server returns.

### Everything works until the machine reboots

Lingering brings the server back once the OS is running, but on WSL nothing
starts the *distro* itself — distributions start on demand. After a Windows
reboot the proxy is listening and returns `502` until something touches the
distro. Confirm before assuming: check for a scheduled task, a startup entry or
a run key. Note that a machine-context scheduled task cannot necessarily reach a
particular user's distro, so verify any such fix rather than assuming it works.

### An attach succeeds but shows the wrong sessions

Two backends. Something started a second standalone server instead of attaching
to the persistent one — the exact situation the wrapper prevents. Check for more
than one server process, and confirm only one is listening on `<PORT>`.

## Rollback

Prepare this **before** declaring the edge finished, and archive the current
configuration and firewall rules first so "restore what was there" is a real
option rather than a reconstruction.

Removing the edge, in order: stop the proxy service; remove the inbound rules;
delete the service; confirm nothing listens on 80 or 443 and that `<PORT>` is
loopback-only; confirm the server, its unit and its channels still work
untouched. The server never depended on the edge, so this is not a rollback of
Part 1.

Leave the private CA and any client trust in place unless removing it is
deliberate, and record what else relies on it first. Each client's trust store
must also be cleaned on that client — removing the root on the host does not
reach them.

## Design constraints

- **The server is never rebound to widen reach.** Loopback is the invariant;
  everything else is a front end that can be removed without touching it.
- **Authentication lives in one place.** Adding a second layer at the edge
  splits credential rotation across two systems and buys nothing.
- **Identity is a name, not an address.** Every address-shaped identity —
  bindings, certificates, firewall local addresses, client URLs — is a DHCP
  liability.
- **Reachability is expressed in the firewall, not the bind.** One place to read
  and audit, and it survives changing adapters.
- **Verification never uses a bypass flag.** A check that passes only with
  verification disabled has tested nothing.
- **Credentials pass by environment file, never by argument.**
- **A capability the server advertises has to work.** A restart tool that
  reports success and restarts nothing is worse than one that refuses: the
  refusal is a fact the caller can act on, and the false success is not.

## References

- `environments/windows/README.md` — WSL2 VM settings, including `boot.systemd`,
  which Part 1's lingering step depends on.
- `docs/wsl-toolchain-doctor.md` — PATH and toolchain auditing, for when the
  installed `opencode` is not the one a shell resolves.
- `opencode-service/opencode-startup-ready.sh` — the readiness probe the unit's
  `ExecStartPost` runs.
- `opencode-service/opencode-telegram-ready.sh` — the standalone Telegram
  sidecar's readiness probe.
- `opencode-service/opencode-gateway-restart.sh` — the restart consumer that
  makes systemd the executor for a plugin-requested restart.
- `tests/opencode-service.sh` — the suite for the three scripts, which stubs
  systemd-facing commands and needs neither a user manager nor a server.
