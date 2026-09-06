# Windows-side environment

WSL is configured from two files, in two different places, with two different
scopes. Everything else under `environments/` runs inside a distribution; this
directory holds the part that does not.

## The two files

| | `/etc/wsl.conf` | `%USERPROFILE%\.wslconfig` |
| --- | --- | --- |
| Lives | inside the distribution | Windows user profile |
| Scope | that distribution only | the WSL2 virtual machine, shared by all distributions |
| Holds | `boot.systemd`, `interop.enabled`, `interop.appendWindowsPath`, `automount` | `[wsl2]`: `memory`, `processors`, `networkingMode`, `dnsTunneling`. `[experimental]`: `autoMemoryReclaim`, `sparseVhd` |
| In this repository | managed by `wsl-toolchain-doctor` | the template beside this file |
| Applied by | `wsl-toolchain-doctor.sh fix` | copying it by hand |

Getting the two confused is the common mistake: a `memory` setting in
`/etc/wsl.conf` is silently ignored, and an `[interop]` section in `.wslconfig`
is equally inert.

Inside `.wslconfig` the section matters just as much. `autoMemoryReclaim` and
`sparseVhd` belong under `[experimental]`. Placed under `[wsl2]`, each is
reported as an unknown key — named as `wsl2.<key>`, with the file and line — and
WSL then starts normally without it. Observed on WSL 2.7.13.0; check the current
release notes before assuming either key has graduated to `[wsl2]`.

## Applying the template

```powershell
# From Windows, in PowerShell
Copy-Item .\environments\windows\.wslconfig $env:USERPROFILE\.wslconfig
wsl.exe --shutdown
```

Read it before copying. Two settings are enabled and the rest are deliberately
absent, with the reasoning inline — the absences are as considered as the
presences, and a machine with a different problem may want different values.

Then check that WSL accepted every key. Any command that makes WSL read the
file reports the rejected ones, `wsl.exe -l -v` among them:

```powershell
wsl.exe -l -v     # no line naming .wslconfig and a line number
```

A warning there names a key WSL discarded, and that setting is not in force. The
message is localised, so match on the file name and the line number rather than
on its wording.

Then reopen the distribution and confirm the virtual machine restarted:

```bash
uptime -s     # must be later than the moment you copied the file
```

**A `.wslconfig` that is newer than the running virtual machine is doing
nothing.** It is not applied on write, and there is no warning that it has been
ignored — the file simply sits there until the next shutdown. This is the single
easiest thing to get wrong about it.

The second easiest is a key under the wrong section, and that one does warn. The
two failures look identical from inside the distribution — the setting is not in
force either way — so when a `.wslconfig` setting appears to have no effect,
check the restart first and the warnings second.

## Why the installer does not write this file

`environments/linux/install.sh` runs inside the distribution, and every other
asset here is something a Linux script can own. This one is not:

- **It is outside the distribution.** Applying it means writing to
  `/mnt/c/Users/<name>/.wslconfig` across a Windows mount, which requires
  guessing the Windows account name and mutating Windows state from a Linux
  provisioner.
- **It is global.** One distribution's installer would be changing the virtual
  machine for every other distribution on the host, including ones it knows
  nothing about.
- **It cannot take effect where it is applied.** The settings need
  `wsl.exe --shutdown`, which terminates the shell running the installer.

So it ships as a reviewed template with a manual step, and the boundary stays
where it belongs.

## Relationship to the toolchain doctor

`wsl-toolchain-doctor` audits and remediates `/etc/wsl.conf` only. It does not
read `.wslconfig` and is not intended to: a distribution-scoped auditor writing
into the Windows user profile would be changing global state on behalf of one
distribution, which is the same boundary the installer respects above.

The two do share a maintenance window. `interop.appendWindowsPath` in
`/etc/wsl.conf` and everything in `.wslconfig` all wait for the same
`wsl.exe --shutdown`, so apply both together and audit once afterwards rather
than restarting twice.
