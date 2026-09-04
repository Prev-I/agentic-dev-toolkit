#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

classify_capability_failure() {
  python3 - "$1" <<'PY'
import json
import sys

record = json.load(open(sys.argv[1], encoding="utf-8"))
message = str(record.get("error_text") or "").lower()
status = record.get("status_code")

RESOLUTION = ("providermodelnotfounderror", "model not found", "unknown model",
              "no such model", "not found")
UNAVAILABLE = ("not available", "unavailable for", "model is disabled",
               "model has been retired")
POLICY = ("organization policy", "policy denied", "blocked by policy",
          "disabled by your organization")
QUOTA = ("usage limit", "rate limit", "quota", "too many requests")
AUTH = ("unauthorized", "invalid_api_key", "authentication", "forbidden")
NETWORK = ("timeout", "network", "connection", "dns", "econnreset")
PROVIDER = ("service unavailable", "provider unavailable", "bad gateway",
            "internal server error")

def hit(markers):
    return any(marker in message for marker in markers)

if hit(RESOLUTION):
    result = "MODEL_UNRESOLVABLE"
elif hit(UNAVAILABLE):
    result = "MODEL_UNAVAILABLE"
elif hit(POLICY):
    result = "POLICY_DENIED"
elif hit(QUOTA) or status == 429:
    result = "QUOTA_FAILURE"
elif hit(AUTH) or status in (401, 403):
    result = "AUTH_FAILURE"
elif hit(NETWORK):
    result = "NETWORK_FAILURE"
elif hit(PROVIDER) or status in (500, 502, 503, 504):
    result = "PROVIDER_FAILURE"
else:
    result = "UNCLASSIFIED"
print(result)
PY
}

capability_stop_class() {
  case "$1" in
    MODEL_UNRESOLVABLE|MODEL_UNAVAILABLE) printf 'CAPABILITY_REGRESSION\n' ;;
    *) printf 'TRANSIENT_OR_EXTERNAL\n' ;;
  esac
}
