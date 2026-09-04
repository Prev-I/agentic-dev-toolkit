validate_page_size() { [[ "$1" =~ ^[0-9]+$ ]] || return 1; (( $1 >= 0 && $1 <= 100 )); }
