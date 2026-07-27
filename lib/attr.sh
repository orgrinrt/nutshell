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

[[ -n "${_NUTSHELL_LIB_ATTR_SH:-}" ]] && return 0
readonly _NUTSHELL_LIB_ATTR_SH=1

# The shape of an attribute line: optional indent, `#[`, a name, an optional
# parenthesised argument, `]`. Anything else is an ordinary comment.
readonly ATTR_PATTERN='^[[:space:]]*#\[[a-z_][a-z0-9_]*(\(.*\))?\][[:space:]]*$'

# _attr_name <line> -> the attribute's name
_attr_name() {
    printf '%s' "$1" | sed -E 's/^[[:space:]]*#\[//; s/(\(.*\))?\][[:space:]]*$//'
}

# _attr_arg <line> -> what was inside the parentheses, or nothing
_attr_arg() {
    printf '%s' "$1" | sed -nE 's/^[[:space:]]*#\[[a-z_][a-z0-9_]*\((.*)\)\][[:space:]]*$/\1/p'
}

# _attr_defines <line> -> the function name this line defines, or nothing
_attr_defines() {
    printf '%s' "$1" | sed -nE 's/^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\(\).*/\1/p'
}

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

        defines="$(_attr_defines "$line")"
        if [[ -n "$defines" ]]; then
            if [[ "$defines" == "$want" ]]; then
                for line in "${pending[@]}"; do
                    name="$(_attr_name "$line")"
                    arg="$(_attr_arg "$line")"
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
    attr_on "$1" "$2" 2>/dev/null | cut -f1 | grep -qx "$3"
}

# attr_arg <file> <function> <attribute>
#
#[pub]
# Usage: attr_arg lib/foo.sh big_fn allow -> prints "loc = 400"
attr_arg() {
    attr_on "$1" "$2" 2>/dev/null | awk -F'\t' -v a="$3" '$1 == a { print $2; exit }'
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

    while IFS= read -r line; do
        if [[ "$line" =~ $ATTR_PATTERN ]]; then
            name="$(_attr_name "$line")"
            [[ "$name" == "$want" ]] && pending=1
            continue
        fi

        defines="$(_attr_defines "$line")"
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
