load_items_or_fail() { local storage=$1; "$storage" list 2>/dev/null || printf '[]\n'; }
