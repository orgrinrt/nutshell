#!/usr/bin/env nutshell
# =============================================================================
# check_posix_floor.sh - How much of this library a POSIX shell can read
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The floor is meant to be POSIX sh, with a predicate selecting a better file
# where a tool or a modern shell earns it. That is a direction rather than a
# state, so it needs a number that moves rather than an opinion that does not.
#
# **What this can and cannot see.** It parses each file with a real POSIX
# shell and reports what will not parse. A parse failure is fatal in a way a
# runtime failure is not: the shell rejects the whole file before running a
# line of it, so no guard inside the file can help and the only fix is to not
# source that file on that shell. That is exactly what a `#[shell(...)]`
# gate is for.
#
# It cannot see a construct that parses and then misbehaves. `declare -A` is
# the standing example: dash parses it as a command and fails at runtime. So a
# clean report here means readable, not portable, and the check says so rather
# than letting a green be read as more than it is.
#
# **It needs a real POSIX shell and refuses without one.** `sh` on macOS is
# bash in POSIX mode and accepts `[[`, arrays and here-strings, so a check
# written against `sh` reports a clean floor on a library that has none. That
# is not hypothetical: the first measurement here was taken that way and was
# worthless.
#
# Usage: ./examples/checks/check_posix_floor.sh
#
# Exit codes:
#   0 - within the configured budget
#   1 - over it, or no POSIX shell to check with
# =============================================================================

set -uo pipefail

use check-runner

POSIX_SHELL=""
POSIX_MAX_UNREADABLE=-1
declare -a POSIX_EXEMPT=()

load_config() {
    if ! cfg_is_true "tests.posix_floor"; then
        log_info "POSIX floor test is disabled in config"
        exit 0
    fi
    POSIX_SHELL="$(cfg_get_or "tests.posix_floor.shell" "")"
    POSIX_MAX_UNREADABLE="$(cfg_get_or "tests.posix_floor.max_unreadable" "-1")"
    cfg_get_array "tests.posix_floor.exempt" POSIX_EXEMPT || POSIX_EXEMPT=()
}

# A shell that is actually POSIX, or nothing.
#
# Verified rather than trusted, because the whole check is worthless run
# against a shell that accepts what it is looking for. The probe is an array
# assignment: POSIX has no arrays, so a shell that parses one is not the
# instrument this needs.
_posix_shell() {
    local cand probe rc
    probe="$(mktemp "${TMPDIR:-/tmp}/nutshell-posix.XXXXXX")" || return 1
    printf 'a=(1 2)\n' > "$probe"

    for cand in ${POSIX_SHELL:+$POSIX_SHELL} dash ash yash posh busybox-sh sh; do
        command -v "$cand" >/dev/null 2>&1 || continue
        "$cand" -n "$probe" >/dev/null 2>&1 && continue   # accepted it: not POSIX enough
        rc=0
        # And it has to accept ordinary POSIX, or it rejects everything and
        # reports a library that cannot be read at all.
        printf 'x=1\necho "${x:-}"\n' > "$probe"
        "$cand" -n "$probe" >/dev/null 2>&1 || rc=1
        printf 'a=(1 2)\n' > "$probe"
        [[ "$rc" -eq 0 ]] && { rm -f "$probe"; printf '%s' "$cand"; return 0; }
    done
    rm -f "$probe"
    return 1
}

_is_exempt() {
    local f="$1" p
    for p in ${POSIX_EXEMPT[@]+"${POSIX_EXEMPT[@]}"}; do
        [[ "$f" == $p ]] && return 0
    done
    return 1
}

# Files the manifest reaches only behind a `shell:` predicate.
#
# The question this check exists to answer is which modules a POSIX shell
# cannot load, not which files it cannot parse. Those stopped being the same
# thing the moment a module could carry a variant: `lib/string.sh` will never
# parse under dash and never has to, because `lib/string.posix.sh` is what a
# POSIX shell is given.
#
# Counting the file would make the number go **up** when a floor is added,
# which is the number moving the wrong way while the library gets better, and
# is the kind of thing people then stop reading.
#
# Only `shell:` counts. A row predicated on `have:` is still sourced on a POSIX
# shell wherever that tool exists, so it has to parse there.
_shell_gated_files() {
    local root="$1" name file rest pending=0
    [[ -r "${root}/lib.nut" ]] || return 0
    while read -r name file rest || [[ -n "$name" ]]; do
        [[ -z "$name" ]] && continue
        # A gate attaches downward to the next declaration and accumulates, so
        # a `#[shell(...)]` seen here marks whatever row comes next.
        if [[ "${name:0:2}" == "#[" ]]; then
            case "$name" in \#\[shell\(*) pending=1 ;; esac
            continue
        fi
        [[ "${name:0:1}" == "#" ]] && { pending=0; continue; }
        [[ -n "$file" ]] || continue
        # Only `shell`. A `has(bin(...))` row is still sourced on a POSIX shell
        # wherever that tool exists, so it has to parse there, and discounting
        # it would hide a real gap.
        [[ "$pending" -eq 1 ]] && printf '%s\n' "$file"
        pending=0
    done < "${root}/lib.nut"
}

# Constructs a POSIX shell parses and then cannot run.
#
# Parsing is not running, and the gap between them is where this check was
# quietly optimistic. `printf -v out ...` is a legal command line anywhere, so
# `dash -n` accepts it; `dash` then reports an illegal option, **carries on**,
# and leaves `out` empty. A frame drawn that way draws nothing and nobody is
# told. `declare -gi x=0` is the same shape: not found, execution continues,
# and the variable is simply not there.
#
# `${x//a/b}` at least fails loudly. The two above do not, which is why a file
# can pass the parse and be broken on the floor in a way no test on a bash
# machine will ever see.
#
# `nut_once` is nutshell's own, and it is the quietest of the lot: it reads
# `BASH_SOURCE` and uses `printf -v`, so under a POSIX shell it is not found,
# the `|| return 0` beside it returns from the whole file, and the module
# defines nothing while reporting success. A caller has no way to tell. The
# floor files carry a guard of their own instead, which is two lines.
#
# `[[` and `((` matter most and are the two a parser cannot see at all. To a
# POSIX shell `[[ -n x ]]` is a command name and three arguments, so it parses
# anywhere and then reports `[[: not found`; `(( x > 1 ))` parses as nested
# subshells and runs `x` as a command. Only the forms carrying bash-only syntax
# inside them, `=~` and a C-style `for`, reach the parser at all. That is how a
# file full of `[[` was counted as reading fine, and it is most of the gap
# between what this check used to report and what actually runs.
#
# Reported beside the parse failures rather than folded into them, because they
# are a different fact about the file: it reads, and it does not work.
_posix_bashisms() {
    local file="$1"
    # Comments stripped first, crudely. A `#` inside a string is taken as one,
    # which loses a real finding now and then; the alternative is parsing shell
    # to run a warning, and this check never blocks.
    sed -e 's/#.*$//' "$file" 2>/dev/null | grep -noE \
        -e '\[\[' \
        -e '(^|[[:space:];&|])\(\(' \
        -e 'printf[[:space:]]+-v' \
        -e '(^|[[:space:];&|(])declare[[:space:]]' \
        -e 'local[[:space:]]+-[aAin]' \
        -e '\$\{[A-Za-z_][A-Za-z0-9_]*//' \
        -e '\$\{[A-Za-z_][A-Za-z0-9_]*(\^\^|,,)' \
        -e '%[-0-9]*\*[sd]' \
        -e "\\$'" \
        -e 'BASH_[A-Z]' \
        -e '(mapfile|readarray)[[:space:]]' \
        -e '(^|[[:space:];&|])nut_once([[:space:]]|$)' \
        -e 'read[[:space:]]+-[a-zA-Z]*[nNdt]([[:space:]]|$)' \
        2>/dev/null | sed -e 's/^\([0-9]*\):[[:space:]]*/\1: /' | head -6
}

test_posix_floor() {
    log_header "POSIX floor"

    local sh
    if ! sh="$(_posix_shell)"; then
        log_fail "no POSIX shell here to check with"
        printf '  dash, ash, yash, posh or busybox. `sh` on macOS is bash in\n'
        printf '  POSIX mode and accepts arrays, so it cannot answer this.\n'
        TESTS_RUN=1; TESTS_FAILED=1
        FAILED_TESTS=("no POSIX shell available")
        return 1
    fi
    log_info "checking with ${sh}"

    local files file rel total=0 unreadable=0 exempt=0 gated=0 why
    declare -a bad=()

    # `get_script_files` honours the project's excludes, and this project
    # excludes `/impl/` from its quality checks: those files are repetitive by
    # design, one per tool, and a duplication or size finding about them says
    # nothing.
    #
    # The POSIX question is not a quality question. An impl module is sourced
    # at run time by the module that chose it, on whatever shell is running,
    # so it has to parse there like anything else. Excluded, twelve of them
    # were invisible and the number read as smaller than it was.
    files="$(get_script_files)"
    local extra
    extra="$(find "$REPO_ROOT/lib" -type f -name '*.sh' -path '*/impl/*' 2>/dev/null)"
    [[ -n "$extra" ]] && files="${files}"$'\n'"${extra}"

    local -A shell_gated=()
    while IFS= read -r rel; do
        [[ -n "$rel" ]] && shell_gated["$rel"]=1
    done < <(_shell_gated_files "$REPO_ROOT")

    while IFS= read -r file; do
        [[ -z "$file" || ! -f "$file" ]] && continue
        rel="${file#$REPO_ROOT/}"
        total=$(( total + 1 ))
        if _is_exempt "$rel"; then exempt=$(( exempt + 1 )); continue; fi
        if [[ -n "${shell_gated[$rel]:-}" ]]; then gated=$(( gated + 1 )); continue; fi

        why="$("$sh" -n "$file" 2>&1 | head -1)"
        if [[ -n "$why" ]]; then
            unreadable=$(( unreadable + 1 ))
            why="${why##*: }"
            bad+=("${rel}: ${why}")
            log_test_warn "${rel} - ${why}"
        fi
    done <<< "$files"

    # A second pass over the files that DID parse. The ones that did not are
    # already counted, and saying they also contain a bashism adds nothing.
    local unrunnable=0 hits
    while IFS= read -r file; do
        [[ -z "$file" || ! -f "$file" ]] && continue
        rel="${file#$REPO_ROOT/}"
        _is_exempt "$rel" && continue
        [[ -n "${shell_gated[$rel]:-}" ]] && continue
        "$sh" -n "$file" 2>/dev/null || continue
        hits="$(_posix_bashisms "$file")"
        [[ -n "$hits" ]] || continue
        unrunnable=$(( unrunnable + 1 ))
        log_test_warn "${rel} - parses, but $(printf '%s' "$hits" | head -1)"
    done <<< "$files"

    echo ""
    log_info "${unreadable} of $(( total - exempt - gated )) cannot be read by ${sh}"
    [[ "$unrunnable" -gt 0 ]] && log_info "${unrunnable} more parse but use something ${sh} cannot run"
    [[ "$gated" -gt 0 ]] && log_info "${gated} behind a shell: predicate, so never sourced there"
    [[ "$exempt" -gt 0 ]] && log_info "${exempt} exempt by config"

    TESTS_RUN=$(( total - exempt - gated ))
    TESTS_PASSED=$(( total - exempt - gated - unreadable ))
    TESTS_WARNED=$unreadable
    WARNED_TESTS=("${bad[@]}")

    # A budget, when one is configured. Without one this reports and never
    # blocks, which is right while the number is still large: a gate that
    # fails every run is one people stop reading.
    if [[ "$POSIX_MAX_UNREADABLE" -ge 0 && "$unreadable" -gt "$POSIX_MAX_UNREADABLE" ]]; then
        TESTS_FAILED=$(( unreadable - POSIX_MAX_UNREADABLE ))
        FAILED_TESTS=("${bad[@]}")
        printf '  over the budget of %s\n' "$POSIX_MAX_UNREADABLE" >&2
        return 1
    fi
    return 0
}

main() {
    # Refuse rather than grade the wrong repository.
    #
    # Through the `#!/usr/bin/env nutshell` shebang, `check-runner` resolves
    # its root from the interpreter's own checkout, so a check run on its own
    # reads the config and the files of whichever nutshell is on PATH. Run
    # standalone here that was somebody else's clone, and it reported warnings
    # about their files under this project's name.
    #
    # That is `check-runner`'s to fix and it is the same class it fixed at
    # 0.4.0, in the one path that does not go through its walk. What this can
    # do is not pretend: `./check` sets the root correctly and everything works
    # there, and anywhere else this says so instead of answering.
    if [[ -f "${PWD}/nut.toml" && -n "${REPO_ROOT:-}" && "${REPO_ROOT}" != "${PWD}" ]]; then
        log_fail "this would read ${REPO_ROOT}, not ${PWD}"
        printf '  run it through `./check`, which resolves the root from the\n' >&2
        printf '  project rather than from the interpreter on PATH.\n' >&2
        TESTS_RUN=1; TESTS_FAILED=1
        FAILED_TESTS=("would have checked the wrong repository")
        print_summary "POSIX floor"
        exit_with_status
    fi
    load_config
    test_posix_floor
    print_summary "POSIX floor"
    exit_with_status
}

# `NUT_CHECK_LOAD_ONLY` is the door a test uses to reach the readers without a
# whole run over a repository.
[[ -n "${NUT_CHECK_LOAD_ONLY:-}" ]] || main "$@"
