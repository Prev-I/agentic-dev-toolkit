public_response() { python3 -c 'import json,sys; print(json.dumps({"name": sys.argv[1]}))' "$1"; }
