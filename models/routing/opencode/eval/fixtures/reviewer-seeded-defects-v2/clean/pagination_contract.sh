# Public contract: page size is a decimal integer in the inclusive range 1..100.
# Zero must be rejected; zero-padding does not change the decimal value.
assert_pagination_contract() {
  validate_page_size 1 && validate_page_size 100 && ! validate_page_size 0
}
