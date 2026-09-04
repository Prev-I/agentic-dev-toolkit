public_response() { python3 -c 'import json,sys; print(json.dumps({"displayName": sys.argv[1]}))' "$1"; }
