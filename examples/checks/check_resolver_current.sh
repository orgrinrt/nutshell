#!/usr/bin/env nutshell
# =============================================================================
# nutshell/examples/checks/check_resolver_current.sh - The map matches its source
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# `resolver` is generated from `lib.nut` by `bin/nut-gen-resolver`. A
# generated file is a second place the same fact lives, and the second place
# goes stale silently: somebody adds a module to the manifest, the resolver
# does not know about it, and the failure arrives as a module that cannot be
# found rather than as anything pointing at the manifest.
#
# So derived has to mean checkable rather than remembered. This regenerates and
# compares. It reads no state and makes no judgement: either the generator
# produces what is committed, or it does not.
#
# Nothing loads `resolver` yet. That is deliberate and it is why this check
# exists now rather than later: a generated file with no consumer is exactly
# the one that rots, and it has to already be correct on the day `use` starts
# reading it.
#
# Usage: ./examples/checks/check_resolver_current.sh
# =============================================================================

use check-runner

GEN="${NUTSHELL_ROOT}/bin/nut-gen-resolver"
OUT="${NUTSHELL_ROOT}/resolver"

test_resolver_current() {
    if [ ! -x "$GEN" ]; then
        log_fail "no generator at ${GEN}"
        return
    fi
    if [ ! -r "$OUT" ]; then
        log_fail "no generated resolver at ${OUT}; run ${GEN##*/} > resolver"
        return
    fi

    local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/nut-res.XXXXXX")"
    if ! "$GEN" "$NUTSHELL_ROOT" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        log_fail "the generator refused the manifest"
        return
    fi

    if diff -q "$tmp" "$OUT" >/dev/null 2>&1; then
        log_test_pass "the resolver matches lib.nut"
    else
        # Named rather than counted. A reader wants to know which row moved,
        # and the diff is the shortest way to say it.
        log_fail "resolver is stale against lib.nut"
        diff "$OUT" "$tmp" 2>/dev/null | head -12 | while IFS= read -r l; do
            log_substep "$l"
        done
        log_substep "regenerate: ${GEN##*/} > resolver"
    fi
    rm -f "$tmp"
}

main() {
    load_config 2>/dev/null || true
    test_resolver_current
    print_summary "resolver currency"
    exit_with_status
}

[[ -n "${NUT_CHECK_LOAD_ONLY:-}" ]] || main "$@"
