#!/usr/bin/env bash
# Tests that every module this library loads at run time can be named by
# reading the source.
#
# `nut_reload` picks an implementation at first call. Written literally,
# `nut_reload super::text::impl::grep_match`, anything reading the file can
# tell which modules that call site can reach. Written as
# `nut_reload "super::fs::impl::${impl}"` it cannot, and the name only exists
# once the branch above it has run.
#
# That matters for one specific thing. A pass that keeps only what something
# calls, which is where the load-time win is, has to see every reachable
# module. `fs.sh` had two assembled call sites over a closed set of three, so
# such a pass would have kept one and dropped two, and the failure lands at
# first call on whichever machine has the other `stat`.
#
# Thirteen of the fifteen call sites were already literal. These two were the
# whole of the exception.

use test

ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"

# Every `nut_reload` call site, as written.
# Comment lines are dropped first. Without that this reads the prose in
# `fs.sh` explaining what the assembled form was and reports it as an
# assembled form, which is the test failing on its own documentation.
_dis_sites() {
    grep -rhE 'nut_reload' \
        "$ROOT"/lib/*.sh "$ROOT"/lib/*/*.sh "$ROOT"/lib/*/*/*.sh 2>/dev/null \
        | grep -vE '^[[:space:]]*#' \
        | grep -oE 'nut_reload[[:space:]]+"?[^";]*"?' \
        | sed 's/^nut_reload[[:space:]]*//'
}

# The ones whose argument is built rather than written.
_dis_assembled() {
    _dis_sites | grep -E '\$' || true
}

#[test]
it_finds_dispatch_sites_to_check() {
    # The control. A pattern that matched nothing would make the test below
    # pass over a library full of assembled names.
    local n; n="$(_dis_sites | grep -c . || true)"
    assert_ne "$n" "0"
    assert_ne "$n" ""
    # And it has to be finding the real ones.
    assert_contains "$(_dis_sites)" "super::text::impl::grep_match"
}

#[test]
it_names_every_dispatch_target_literally() {
    local bad; bad="$(_dis_assembled)"
    assert_empty "$bad"
}

#[test]
it_reaches_every_stat_implementation_the_manifest_declares() {
    # The other half: literal is not enough if the set written out is smaller
    # than the set that exists. Every `fs::impl::` module the manifest declares
    # has to appear at a call site, or a machine needing it silently gets the
    # no-tool stub.
    local m missing=""
    while IFS= read -r m; do
        [[ -n "$m" ]] || continue
        grep -q "super::${m}" <<<"$(_dis_sites)" || missing+="${m} "
    done < <(awk '$1 ~ /^fs::impl::/ {print $1}' "$ROOT/lib.nut")
    assert_empty "$missing"
}

#[test]
it_still_answers_for_a_real_file() {
    # The control for the two above. Rewriting the dispatch and breaking it
    # would satisfy both of them, since neither calls anything.
    local size mtime
    size="$(fs_size "$ROOT/init")"
    mtime="$(fs_mtime "$ROOT/init")"
    assert_ok test "$size" -gt 0
    assert_ok test "$mtime" -gt 0
}
