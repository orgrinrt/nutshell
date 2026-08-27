#!/usr/bin/env bash
# A fixture for `test_test.sh`. Its one test deliberately checks nothing, so
# the harness's "asserted nothing" guard has something to catch. It is not part
# of the suite and is run by name.
use test

#[test]
it_checks_nothing_at_all() {
    local x=1
    [[ "$x" == 1 ]]
}
