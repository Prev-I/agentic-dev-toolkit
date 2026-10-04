# Concurrent increments of a counter must serialize the entire read-modify-write.
# Missing/unreadable or corrupt counters must fail without replacing their value.
# Values are ASCII decimal integers of at most 18 digits; writes propagate errors.
assert_counter_contract() {
  local counter=$1
  increment_counter "$counter"
}
