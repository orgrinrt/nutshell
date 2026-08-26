#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/attr.sh - Attributes on shell definitions
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0: depends on nothing but bash.
#
#   #[pub]
#   #[allow(loc = 400)]
#   greet() { ... }
#
# An attribute is a comment, which is the whole reason for the shape. `#` is
# already bash's comment character, so `#[pub]` needs no cooperation from the
# parser: `bash -n`, shellcheck, editors and anything else that reads shell
# keep working, and a file using attributes is still an ordinary shell file.
#
# The alternative considered and rejected was a real keyword, `pub foo() {}`,
# made to parse by defining `pub` as an empty alias with `expand_aliases` set.
# It genuinely works when a file is sourced at runtime. It also breaks every
# static tool, including `bash -n`, because parsing never executes the `shopt`
# and `alias` lines that would make the keyword disappear. For a library whose
# point is portable, checkable bash, losing the checkers to save a line is the
# wrong side of the trade.
#
# Attributes attach downward: they annotate the next definition, and a run of
# them accumulates. A blank line or a plain comment does not break the run,
# since a documented function usually has prose between its attributes and
# itself.
#
# Usage:
#   use attr
#
#   attr_on   lib/string.sh str_trim      # attributes on one definition
#   attr_has  lib/string.sh str_trim pub  # is it marked?
#   attr_arg  lib/foo.sh    big_fn allow  # the argument, `loc = 400`
#   attr_find lib/foo.sh    test          # every definition marked #[test]
# =============================================================================

nut_once || return 0

# The shape of an attribute line: optional indent, `#[`, a name, an optional
# parenthesised argument, `]`. Anything else is an ordinary comment.
readonly ATTR_PATTERN='^[[:space:]]*#\[[a-z_][a-z0-9_]*(\(.*\))?\][[:space:]]*$'

# What a function definition looks like, in one place.
#
# Both spellings bash accepts, and both were being missed. `function name {`
# has no parentheses at all; `name ()` puts a space before them. A `#[pub]` on
# either was invisible, so the public-API check skipped those functions in
# silence rather than reporting them undocumented.
#
# One pattern because there were two, here and in `srcfile`, and they had
# already drifted apart: this one took no hyphen and no `function` keyword,
# that one took both. A definition is one thing and the readers of it agree
# about what it is.
#
# Group 2 is the name after `function`, group 3 the name before `()`. Exactly
# one of them matches.
readonly ATTR_DEFINES_PATTERN='^[[:space:]]*(function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*)|([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*\(\))'

#[pub]
# The function a line defines, or nothing. The one answer both this module and
# `srcfile` use, so a definition means the same thing to each.
# Usage: attr_defines_on "foo() {" -> prints "foo"
attr_defines_on() {
    [[ "${1:-}" =~ $ATTR_DEFINES_PATTERN ]] || return 1
    printf '%s' "${BASH_REMATCH[2]:-${BASH_REMATCH[3]}}"
}

# The three below are matched with bash's own regex rather than by piping each
# line through `sed`.
#
# `attr_on` walks every line of a file and asks `_attr_defines` about each one.
# At a fork per line, times two subshells for the substitution and the pipe,
# times every function a checker looks up, that was a quarter of a million
# processes on one library and it made the QA gate take four minutes. Bash can
# match a line against a pattern without leaving the process, and this needs no
# `sed` and no `awk`, so it also works on a machine that has neither. The two
# readers below were a `cut | grep` and an `awk` over this module's own output
# and are bash for the same reason: a module this low should not need a
# userland to answer a question about a comment.

# _attr_name <line> -> the attribute's name
_attr_name() {
    local l="$1"
    [[ "$l" =~ ^[[:space:]]*#\[([a-zA-Z_][a-zA-Z0-9_]*) ]] || return 1
    printf '%s' "${BASH_REMATCH[1]}"
}

# _attr_arg <line> -> what was inside the parentheses, or nothing
_attr_arg() {
    local l="$1"
    [[ "$l" =~ ^[[:space:]]*#\[[a-z_][a-z0-9_]*\((.*)\)\][[:space:]]*$ ]] || return 1
    printf '%s' "${BASH_REMATCH[1]}"
}

# _attr_defines <line> -> the function name this line defines, or nothing
_attr_defines() { attr_defines_on "${1:-}"; }

# attr_on <file> <function>
#
# Every attribute attached to that definition, one per line, name first and any
# argument after a tab.
#
#[pub]
# Usage: attr_on lib/string.sh str_trim -> prints "pub" or "allow\tloc = 400"
attr_on() {
    local file="$1" want="$2"
    local line pending=() name arg defines

    while IFS= read -r line; do
        if [[ "$line" =~ $ATTR_PATTERN ]]; then
            pending+=("$line")
            continue
        fi

        # Matched here rather than through `_attr_defines`, because a command
        # substitution is a subshell and this runs on every line of the file.
        # The helper stays for callers and for the tests; the loop cannot
        # afford it.
        defines=""
        [[ "$line" =~ $ATTR_DEFINES_PATTERN ]] \
            && defines="${BASH_REMATCH[2]:-${BASH_REMATCH[3]}}"
        if [[ -n "$defines" ]]; then
            if [[ "$defines" == "$want" ]]; then
                for line in "${pending[@]}"; do
                    name=""; arg=""
                    [[ "$line" =~ ^[[:space:]]*#\[([a-zA-Z_][a-zA-Z0-9_]*) ]] \
                        && name="${BASH_REMATCH[1]}"
                    [[ "$line" =~ ^[[:space:]]*#\[[a-z_][a-z0-9_]*\((.*)\)\][[:space:]]*$ ]] \
                        && arg="${BASH_REMATCH[1]}"
                    if [[ -n "$arg" ]]; then
                        printf '%s\t%s\n' "$name" "$arg"
                    else
                        printf '%s\n' "$name"
                    fi
                done
                return 0
            fi
            pending=()
            continue
        fi

        # Prose and blank lines do not break a run. A documented function has
        # its doc comment between the attributes and the definition, and
        # treating that as a break would mean attributes only worked on
        # undocumented code, which is exactly backwards.
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        pending=()
    done < "$file"
    return 1
}

# attr_has <file> <function> <attribute>
#
#[pub]
# Usage: attr_has lib/string.sh str_trim pub -> returns 0 when marked
attr_has() {
    local want="$3" line
    while IFS= read -r line; do
        [[ "${line%%$'\t'*}" == "$want" ]] && return 0
    done < <(attr_on "$1" "$2" 2>/dev/null)
    return 1
}

# attr_arg <file> <function> <attribute>
#
#[pub]
# Usage: attr_arg lib/foo.sh big_fn allow -> prints "loc = 400"
attr_arg() {
    local want="$3" line
    while IFS= read -r line; do
        if [[ "${line%%$'\t'*}" == "$want" ]]; then
            [[ "$line" == *$'\t'* ]] && printf '%s' "${line#*$'\t'}"
            return 0
        fi
    done < <(attr_on "$1" "$2" 2>/dev/null)
    return 1
}

# attr_find <file> <attribute>
#
# Every definition in the file carrying that attribute, one name per line. How
# a test runner finds its tests and a checker finds its exemptions.
#
#[pub]
# Usage: attr_find tests/string_test.sh test -> prints each #[test] function
attr_find() {
    local file="$1" want="$2"
    local line pending=0 defines name

    # Matched inline for the same reason `attr_on` does: a command substitution
    # is a subshell, and this runs on every line of the file. The test suite
    # calls it once per test file and a checker calls it once per source file.
    while IFS= read -r line; do
        if [[ "$line" =~ $ATTR_PATTERN ]]; then
            name=""
            [[ "$line" =~ ^[[:space:]]*#\[([a-zA-Z_][a-zA-Z0-9_]*) ]] \
                && name="${BASH_REMATCH[1]}"
            [[ "$name" == "$want" ]] && pending=1
            continue
        fi

        defines=""
        [[ "$line" =~ $ATTR_DEFINES_PATTERN ]] \
            && defines="${BASH_REMATCH[2]:-${BASH_REMATCH[3]}}"
        if [[ -n "$defines" ]]; then
            [[ "$pending" -eq 1 ]] && printf '%s\n' "$defines"
            pending=0
            continue
        fi

        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        pending=0
    done < "$file"
}
