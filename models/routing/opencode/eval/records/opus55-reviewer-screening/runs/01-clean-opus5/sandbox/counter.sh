increment_counter() { flock "$1.lock" bash -c 'n=$(<"$1"); printf "%s\n" "$((n+1))" >"$1"' _ "$1"; }
