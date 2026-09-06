#!/usr/bin/env nutshell
# =============================================================================
# nutshell/examples/checks/check_readme_tables.sh - The readme's tables are the whole list
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The readme carries two tables that are lists of things this repository has: a
# module per row under `### Modules`, and a check per row under `### Checks`.
# Both are a second copy of something the tree already answers exactly, and the
# second copy goes stale in the one direction nobody notices: a row is never
# wrong, it is simply absent, so the table reads as complete on every reading.
#
# Measured when this was written: the module table was missing `bench`, `inuse`
# and `key`, and the check table was missing `posix_floor` and
# `resolver_current`. Both had been reviewed.
#
# Absence only. A row naming something that is gone is a different defect and a
# louder one, since the name is right there to look up, and this stays the one
# question it can answer without knowing what a row means.
#
# Usage: ./examples/checks/check_readme_tables.sh
# =============================================================================

use check-runner

README="${NUTSHELL_ROOT}/README.md"

# The rows of one table, by its heading, as the backticked name in the first
# column. Bounded by the next heading at the same depth, so a table further
# down the file is not read as part of this one.
_rows_under() { # <heading>
    awk -v want="$1" '
        $0 == want { inside = 1; next }
        inside && /^### / { exit }
        inside && /^\| `/ {
            line = $0
            sub(/^\| `/, "", line)
            sub(/`.*$/, "", line)
            sub(/::.*$/, "", line)
            print line
        }
    ' "$README" | sort -u
}

# What the tree actually has, one name per line.
_modules() {
    ls "${NUTSHELL_ROOT}/lib" \
        | sed 's/\.sh$//; s/\.bash$//; s/\.posix$//' \
        | sort -u
}

_checks() {
    # The same glob `check --list` reads, so this cannot disagree with it, and
    # no recursion: running `check` from inside a check would run this one.
    for one in "${NUTSHELL_ROOT}"/examples/checks/check_*.sh; do
        [ -e "$one" ] || continue
        one="${one##*/check_}"
        printf '%s\n' "${one%.sh}"
    done | sort -u
}

# Fails naming every absentee, since a count says a table is stale and a name
# says which row to write.
#
# The tree's list arrives in a file rather than on stdin, because `log_pass` and
# `log_fail` increment a counter and the right-hand side of a pipeline is a
# subshell: piped in, every verdict here landed somewhere that went away, and
# the run reported zero tests and passed.
_table_covers() { # <label> <heading> <file of names the tree has>
    local label="$1" heading="$2" have="$3" listed missing
    listed="$(mktemp "${TMPDIR:-/tmp}/nut-readme.XXXXXX")"
    _rows_under "$heading" > "$listed"
    missing="$(comm -23 "$have" "$listed")"
    rm -f "$listed"

    if [ -z "$missing" ]; then
        log_pass "the ${label} table names every one"
        return
    fi
    log_fail "the ${label} table is missing rows"
    printf '%s\n' "$missing" | while IFS= read -r one; do
        [ -n "$one" ] || continue
        log_substep "$one"
    done
}

test_readme_tables() {
    if [ ! -r "$README" ]; then
        log_fail "no readme at ${README}"
        return
    fi
    local have
    have="$(mktemp "${TMPDIR:-/tmp}/nut-have.XXXXXX")"
    _modules > "$have"
    _table_covers modules "### Modules" "$have"
    _checks > "$have"
    _table_covers checks "### Checks" "$have"
    rm -f "$have"
}

main() {
    load_config 2>/dev/null || true
    test_readme_tables
    print_summary "readme tables"
    exit_with_status
}

[[ -n "${NUT_CHECK_LOAD_ONLY:-}" ]] || main "$@"
