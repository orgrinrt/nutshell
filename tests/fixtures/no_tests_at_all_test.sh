#!/usr/bin/env bash
# A test file with no #[test] in it, which the harness must refuse.
#
# The shape is not somebody forgetting to write tests. It is what every file
# in the suite becomes when discovery itself breaks: `attr_find` is what finds
# the tests, and `attr_find` is in the library under test.

use test

# Marked with something else, so the file is not empty and the attribute
# reader is definitely running. It just finds nothing it was asked for.
#[helper]
it_looks_like_a_test_but_is_not_marked_as_one() {
    assert_eq "1" "1"
}
