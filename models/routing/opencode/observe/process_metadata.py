"""Read Linux process identity and start times, never arguments or contents."""
import os
from pathlib import Path


def stale_processes(config_mtime_ms, proc_root=Path("/proc"), ticks=None):
    try:
        boot = next(int(line.split()[1]) for line in (proc_root / "stat").read_text().splitlines() if line.startswith("btime "))
        ticks = ticks or os.sysconf("SC_CLK_TCK")
    except (OSError, ValueError, StopIteration):
        return []
    found = []
    for entry in proc_root.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            name = (entry / "comm").read_text().strip()
            if name not in ("opencode", "opencode-cli"):
                continue
            fields = (entry / "stat").read_text().rsplit(")", 1)[1].split()
            started = int((boot + int(fields[19]) / ticks) * 1000)
            if started < config_mtime_ms:
                found.append({"pid": int(entry.name), "started_ms": started})
        except (OSError, ValueError, IndexError):
            continue
    return found
