increment_counter() {
  python3 - "$1" <<'PY'
import fcntl
from pathlib import Path
import sys

counter = Path(sys.argv[1])
try:
    with open(str(counter) + ".lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        fcntl.flock(lock, fcntl.LOCK_UN)
        value = counter.read_text().strip()
        if not value.isascii() or not value.isdecimal() or len(value) > 18:
            raise ValueError("invalid counter value")
        counter.write_text(str(int(value, 10) + 1) + "\n")
except (OSError, ValueError) as error:
    print(str(error), file=sys.stderr)
    raise SystemExit(1)
PY
}
