increment_counter() { local n; n=$(<"$1"); printf '%s\n' "$((n+1))" >"$1"; }
