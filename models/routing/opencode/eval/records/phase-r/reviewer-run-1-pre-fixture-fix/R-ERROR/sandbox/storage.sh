load_items() { local storage=$1; "$storage" list 2>/dev/null || printf '[]\n'; }
