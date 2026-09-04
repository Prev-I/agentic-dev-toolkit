assert_public_response_contract() { local response; response=$(public_response "$1"); python3 -c 'import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if "displayName" in d else 1)' "$response"; }
