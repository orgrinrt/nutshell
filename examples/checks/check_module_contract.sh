#!/usr/bin/env nutshell
# =============================================================================
# check_module_contract.sh - Do the modules keep their side of the bargain
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Four questions, all of them queries over the cached module graph:
#
#   cycles        does the declaration graph loop
#   declarations  does every cross-module call have a `use` behind it
#   visibility    is every called function visible from where it is called
#   reachability  is any module used by nothing at all
#
# None of these is enforced by bash, which is the point. Bash has one global
# function table: once a module is sourced, every function it defined is
# callable from everywhere, whether it was meant to be or not, and whether the
# caller declared the dependency or not. That is not a thing to fix, it is a
# property of the language. What can be fixed is not knowing.
#
# The one that has already bitten: `toml.sh` called `str_trim` for its whole
# life without declaring `string`, so `toml_get` worked or silently returned
# nothing depending on load order. Nothing reported it, because from inside
# bash a function that is present is present.
#
# Usage: ./examples/checks/check_module_contract.sh
#
# Exit codes:
#   0 - the contract holds
#   1 - at least one violation
# =============================================================================

set -uo pipefail

use modgraph log

LIB_DIR="${1:-${NUTSHELL_ROOT}/lib}"
QUIET_MODE="${NUTSHELL_CHECK_QUIET:-0}"

violations=0

fail() {
    log_tagged "FAIL" red "$*"
    violations=$((violations + 1))
}

note() { [[ "$QUIET_MODE" == "1" ]] || log_substep "$*"; }

# One walk over the audit's output. The checks used to ask the graph a question
# per call site through command substitution, which forked for each of roughly
# five hundred of them; the audit answers everything in a single pass and this
# only formats what comes back.
report() {
    local kind a b c
    while IFS=$'\t' read -r kind a b c; do
        case "$kind" in
            unused)
                note "${a} declares ${b} and calls nothing from it."
                note "Drop the declaration, unless it is there for a variable"
                note "${b} sets or for something it does when loaded."
                ;;
            cycle)
                fail "the declaration graph has a cycle: ${a}"
                note "Cut one edge. The more general module should not depend on"
                note "the more specific, so the edge to remove usually points away"
                note "from the foundation."
                note "Loading survives a cycle, since a module is marked before it"
                note "is sourced, so this is a design report rather than a crash."
                ;;
            undeclared)
                fail "${a} calls ${b} from ${c}, which it never declares"
                note "Add 'use ${c}' near the top of ${a}.sh. It works today only"
                note "if something else happened to load ${c} first."
                ;;
            private)
                fail "${a} calls ${b}, which ${c} keeps private"
                note "Either mark it in ${c}.sh with #[pub] so anyone may call it,"
                note "#[pub(lib)] for modules in this library only, #[pub(super)]"
                note "for the module above ${c} and what sits under it, or reach"
                note "for something ${c} does export."
                ;;
            super_at_root)
                fail "${c} marks ${b} #[pub(super)] and has no module above it"
                note "There is no super for it to be visible to, so the marker"
                note "reads as public and means private. Use #[pub(lib)] if the"
                note "library may call it, or drop the marker if nothing should."
                ;;
            unreachable)
                fail "nothing declares ${a} and it exports nothing"
                note "No module loads it and no consumer can call into it."
                ;;
        esac
    done < <(modgraph_audit)
}

main() {
    modgraph_build "$LIB_DIR"

    report

    if [[ "$violations" -gt 0 ]]; then
        [[ "$QUIET_MODE" == "1" ]] || printf '\n'
        log_error "module contract: ${violations} violation(s)"
        exit 1
    fi
    [[ "$QUIET_MODE" == "1" ]] || log_success "module contract holds"
    exit 0
}

main "$@"
