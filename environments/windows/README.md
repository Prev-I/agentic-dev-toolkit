# Windows-side environment

WSL is configured from two files, in two different places, with two different
scopes. Everything else under `environments/` runs inside a distribution; this
directory holds the part that does not.

## The two files

| | `/etc/wsl.conf` | `%USERPROFILE%\.wslconfig` |
| --- | --- | --- |
| Lives | inside the distribution | Windows user profile |
| Scope | that distribution only | the WSL2 virtual machine, shared by all distributions |
| Holds | `boot.systemd`, `interop.enabled`, `interop.appendWindowsPath`, `automount` | `memory`, `processors`, `autoMemoryReclaim`, `sparseVhd`, `networkingMode`, `dnsTunneling` |
| In this repository | managed by `wsl-toolchain-doctor` | the template beside this file |
| Applied by | `wsl-toolchain-doctor.sh fix` | copying it by hand |

Getting the two confused is the common mistake: a `memory` setting in
`/etc/wsl.conf` is silently ignored, and an `[interop]` section in `.wslconfig`
is equally inert.

## Applying the template

```powershell
# From Windows, in PowerShell
Copy-Item .\environments\windows\.wslconfig $env:USERPROFILE\.wslconfig
wsl.exe --shutdown
```

Read it before copying. Two settings are enabled and the rest are deliberately
absent, with the reasoning inline — the absences are as considered as the
presences, and a machine with a different problem may want different values.

Then reopen the distribution and confirm the virtual machine restarted:

```bash
uptime -s     # must be later than the moment you copied the file
```

**A `.wslconfig` that is newer than the running virtual machine is doing
nothing.** It is not applied on write, and there is no warning that it has been
ignored — the file simply sits there until the next shutdown. This is the single
easiest thing to get wrong about it.

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
