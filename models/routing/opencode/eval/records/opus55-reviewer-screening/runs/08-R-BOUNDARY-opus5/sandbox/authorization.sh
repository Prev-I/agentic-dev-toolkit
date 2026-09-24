read_resource() { local caller=$1 owner=$2 value=$3; [[ "$caller" == "$owner" ]] || return 3; printf '%s\n' "$value"; }
