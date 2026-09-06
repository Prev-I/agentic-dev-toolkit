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
| Enabled here | — | `autoMemoryReclaim` only; see below for why not `sparseVhd` |
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

Read it before copying. One setting is enabled and the rest are deliberately
absent, with the reasoning inline — the absences are as considered as the
presence, and a machine with a different problem may want different values.

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

## Why `sparseVhd` is not enabled

It is the setting most likely to be reached for, and on a machine that already
has the problem it solves nothing. Two independent reasons, both worth knowing
before overriding this.

**It never retrofits an existing disk.** The key governs virtual disks created
after it is set. An `ext4.vhdx` that has already grown keeps every byte it has
committed. On one host with the key correctly placed and in force, all three
distributions still reported as not sparse:

```
rancher-desktop         0.96 GB   not sparse
Ubuntu                 31.79 GB   not sparse
rancher-desktop-data   64.59 GB   not sparse   (distribution stopped)
```

97 GB committed, none of it recoverable by the setting that was supposed to
recover it.

**The feature is gated off, for data corruption.** Converting an existing disk
by hand does not work either. Its release notes put the gate in WSL 2.5.6, and
the service refuses:

```powershell
wsl.exe --manage rancher-desktop --set-sparse true
# reports that sparse VHD support is disabled due to potential data corruption,
# directs you to --allow-unsafe, and exits with
# Error code: Wsl/Service/E_INVALIDARG
```

Observed on WSL 2.7.13.0. The message is localised; the error code is not.

`--allow-unsafe` exists and does force it. Whether to point it at a disk you
care about is a decision with a real downside, and not one a template should
make on someone's behalf — which is why the key is documented here and left
unset in the file.

**To actually reclaim space from an existing `ext4.vhdx`**, compact it — see
below. Note that this is also the path a sparse disk closes off: `Optimize-VHD`
refuses files that are sparse.

## Reclaiming space from an existing `ext4.vhdx`

Compaction is the part everyone reaches for, and on its own it recovers almost
nothing. `diskpart` can only drop blocks the filesystem has declared free, and
ext4 does not declare them by deleting a file. **Discard the free blocks first,
with `fstrim`.** Skipping that step is the likeliest reason for the widespread
impression that compacting a WSL disk does not work.

Measured on one host, on the `rancher-desktop-data` disk listed above (64.08 GB
by the time the run started, having drifted down a little across the restarts in
between):

| Step | Result |
| --- | --- |
| `fstrim` on the mounted filesystem | 973.7 GiB of free blocks discarded |
| `diskpart` compact, 28 s | **64.08 GB → 35.00 GB** |
| `e2fsck -fn` afterwards | clean, no corrections, 710,653 files |

35.00 GB against 33 GiB of real data: no meaningful slack left.

### The procedure

Everything must be stopped first — `wsl.exe --shutdown`, and quit any desktop
application that owns a distribution, or it will restart one underneath you.

```powershell
wsl.exe --mount --vhd "<path>\ext4.vhdx" --name work
wsl.exe -d <other-distro> -u root -- fstrim -v /mnt/wsl/work
wsl.exe --shutdown
```

Then compact, with the distribution still down:

```
diskpart
  select vdisk file="<path>\ext4.vhdx"
  attach vdisk readonly
  compact vdisk
  detach vdisk
```

Three things about this are not obvious and each one costs a run to discover.

**A data-only distribution may have no userland to run `fstrim` in.** Container
storage distributions can ship little more than `/bin/sh` — no `ls`, no `df`.
Mounting the disk from a distribution that does have tools, as above, sidesteps
that entirely.

**`wsl --mount` mounts are lost when the virtual machine idles out.** The VM
stops once no distribution is running, and takes every manual mount with it. Do
the mount and the `fstrim` in one invocation; run them as separate steps and the
second one silently operates on an empty directory on `/mnt/wsl` instead — and
`fstrim` will report `the discard operation is not supported` rather than
anything that names the real problem.

**`wsl -d <distro> -u root` is root without `sudo`**, which is what makes
`fstrim` and `e2fsck` runnable non-interactively on a machine whose `sudo` asks
for a password.

### Verifying

Check the filesystem before trusting the result. Attach the disk without
mounting it, so `e2fsck` sees it offline:

```powershell
wsl.exe --shutdown
wsl.exe --mount --vhd "<path>\ext4.vhdx" --bare
wsl.exe -d <other-distro> -u root -- e2fsck -fn /dev/sdX
```

Copy the `.vhdx` aside before compacting if the contents are expensive to
rebuild. On the run above the copy took 45 s for 64 GB, which is a cheap way to
make the whole operation reversible.

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
