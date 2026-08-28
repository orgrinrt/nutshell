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

# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and so
# needs bash. Under a POSIX shell it is not found, the `|| return 0` beside it
# returns from the whole file, and the module defines nothing while reporting
# success.
[ -n "${_NUTSHELL_ATTR_SH:-}" ] && return 0
_NUTSHELL_ATTR_SH=1

# The shape of an attribute line: optional indent, `#[`, a name, an optional
# parenthesised argument, `]`. Anything else is an ordinary comment.
# A newline and a tab, as values. `$'\n'` and `$'\t'` are bash spellings.
_ATTR_NL='
'
_ATTR_TAB="$(printf '\t')"

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
    local l="${1:-}"
    _attr_defines_set_t "${l#"${l%%[![:space:]]*}"}" || return 1
    printf '%s' "$_ATTR_DEF"
}

# The three below set a variable instead of printing, and the printing forms
# are thin over them.
#
# That is the whole reason they exist. A command substitution is a subshell and
# a fork, and these run once per line of every file the checker reads. The
# regex versions could be matched in-process because bash has `=~`; POSIX has
# no regex at all, so the match is `case` and parameter expansion, and the
# result has to come back out of the function some other way than stdout.
_ATTR_NAME=""
_ATTR_ARG=""
_ATTR_DEF=""

# The name of the function a line defines, into `_ATTR_DEF`.
#
# `^[[:space:]]*(function[[:space:]]+(NAME)|(NAME)[[:space:]]*\(\))`, which is
# both spellings bash accepts. `${x%%[!A-Za-z0-9_-]*}` is the longest prefix of
# name characters, which is what the capture group was.
# Takes a line already trimmed of its leading space, which every caller has.
#
# The trimming lives at the call site because the loops trim once and then ask
# several questions of the result, and a helper that trims again makes an
# ordinary line of prose pay for it three times over. Measured: that was the
# whole gap between the regex version and this one. `benches/attr-scan`.
_attr_defines_set_t() {
    _ATTR_DEF=""
    local l="${1:-}" n="" after=""
    case "$l" in
        function[[:space:]]*)
            n="${l#function}"
            n="${n#"${n%%[![:space:]]*}"}"
            n="${n%%[!A-Za-z0-9_-]*}"
            ;;
        *)
            case "$l" in *'('*) ;; *) return 1 ;; esac
            n="${l%%(*}"
            n="${n%"${n##*[![:space:]]}"}"
            case "$n" in *[!A-Za-z0-9_-]*) return 1 ;; esac
            after="${l#*(}"
            case "$after" in ')'*) ;; *) return 1 ;; esac
            ;;
    esac
    case "$n" in ''|[0-9]*|-*) return 1 ;; esac
    _ATTR_DEF="$n"
    return 0
}

# Whether a line is an attribute at all: `#[`, a lowercase name, an optional
# parenthesised argument, `]`, and nothing else on the line.
# Whether a trimmed line is an attribute at all.
_attr_is_attr_t() {
    local l="${1:-}" body nm
    l="${l%"${l##*[![:space:]]}"}"
    case "$l" in '#['*']') ;; *) return 1 ;; esac
    body="${l#\#\[}"; body="${body%]}"
    nm="${body%%(*}"
    case "$nm" in ''|*[!a-z0-9_]*|[0-9]*) return 1 ;; esac
    # An argument opened means it has to close, on this line.
    if [ "$nm" != "$body" ]; then
        case "$body" in *')') ;; *) return 1 ;; esac
    fi
    return 0
}

# The attribute's name, into `_ATTR_NAME`.
# The attribute's name, into `_ATTR_NAME`, from a trimmed line.
_attr_name_set_t() {
    _ATTR_NAME=""
    local l="${1:-}" n
    case "$l" in '#['*) ;; *) return 1 ;; esac
    n="${l#\#\[}"
    n="${n%%[!A-Za-z0-9_]*}"
    case "$n" in ''|[0-9]*) return 1 ;; esac
    _ATTR_NAME="$n"
    return 0
}

# What was inside the parentheses, into `_ATTR_ARG`.
_attr_arg_set() {
    _ATTR_ARG=""
    local l="${1:-}" body nm a
    l="${l#"${l%%[![:space:]]*}"}"
    l="${l%"${l##*[![:space:]]}"}"
    case "$l" in '#['*'('*')]') ;; *) return 1 ;; esac
    body="${l#\#\[}"
    nm="${body%%(*}"
    case "$nm" in ''|*[!a-z0-9_]*|[0-9]*) return 1 ;; esac
    a="${body#*(}"
    a="${a%)]}"
    _ATTR_ARG="$a"
    return 0
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
    local l="${1:-}"
    _attr_name_set_t "${l#"${l%%[![:space:]]*}"}" || return 1
    printf '%s' "$_ATTR_NAME"
}

# _attr_arg <line> -> what was inside the parentheses, or nothing
_attr_arg() {
    _attr_arg_set "${1:-}" || return 1
    printf '%s' "$_ATTR_ARG"
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
    local line pending="" rest one t

    while IFS= read -r line || [ -n "$line" ]; do
        # Trimmed once, here, and handed to everything below already trimmed.
        #
        # The first cut of this called `_attr_is_attr` and then
        # `_attr_defines_set` on every line and each trimmed the line again,
        # so an ordinary line of prose paid three trims to be recognised as
        # prose. Measured on the library, that was the difference between the
        # regex version and this one: `benches/attr-scan`.
        case "$line" in
            [![:space:]]*) t="$line" ;;
            *) t="${line#"${line%%[![:space:]]*}"}" ;;
        esac

        # Blank and prose first, because they are most of every file and the
        # cheapest to recognise. Neither breaks a run of attributes: a
        # documented function has its doc comment between the attributes and
        # itself, and treating that as a break would mean attributes only
        # worked on undocumented code, which is exactly backwards.
        case "$t" in
            '') continue ;;
            '#['*) ;;
            '#'*) continue ;;
        esac

        if _attr_is_attr_t "$t"; then
            # An array held these. One string with a newline between entries
            # holds them as well, because an attribute line cannot contain a
            # newline: `read -r` split on one to produce it.
            pending="${pending}${t}${_ATTR_NL}"
            continue
        fi

        # Set rather than substituted, because a command substitution is a
        # subshell and this runs on every line of the file.
        _attr_defines_set_t "$t"
        if [ -n "$_ATTR_DEF" ]; then
            if [ "$_ATTR_DEF" = "$want" ]; then
                rest="$pending"
                while [ -n "$rest" ]; do
                    one="${rest%%"$_ATTR_NL"*}"
                    rest="${rest#*"$_ATTR_NL"}"
                    _attr_name_set_t "$one"
                    _attr_arg_set "$one"
                    if [ -n "$_ATTR_ARG" ]; then
                        printf '%s\t%s\n' "$_ATTR_NAME" "$_ATTR_ARG"
                    else
                        printf '%s\n' "$_ATTR_NAME"
                    fi
                done
                return 0
            fi
            pending=""
            continue
        fi

        pending=""
    done < "$file"
    return 1
}

# attr_has <file> <function> <attribute>
#
#[pub]
# Usage: attr_has lib/string.sh str_trim pub -> returns 0 when marked
attr_has() {
    local want="$3" out rest one
    # A process substitution fed this loop, and POSIX has none. One command
    # substitution costs the same fork the process substitution did, and the
    # walk over what it returns costs nothing.
    out="$(attr_on "$1" "$2" 2>/dev/null)" || return 1
    rest="$out"
    while [ -n "$rest" ]; do
        case "$rest" in
            *"$_ATTR_NL"*) one="${rest%%"$_ATTR_NL"*}"; rest="${rest#*"$_ATTR_NL"}" ;;
            *) one="$rest"; rest="" ;;
        esac
        [ "${one%%"$_ATTR_TAB"*}" = "$want" ] && return 0
    done
    return 1
}

# attr_arg <file> <function> <attribute>
#
#[pub]
# Usage: attr_arg lib/foo.sh big_fn allow -> prints "loc = 400"
attr_arg() {
    local want="$3" out rest one
    out="$(attr_on "$1" "$2" 2>/dev/null)" || return 1
    rest="$out"
    while [ -n "$rest" ]; do
        case "$rest" in
            *"$_ATTR_NL"*) one="${rest%%"$_ATTR_NL"*}"; rest="${rest#*"$_ATTR_NL"}" ;;
            *) one="$rest"; rest="" ;;
        esac
        if [ "${one%%"$_ATTR_TAB"*}" = "$want" ]; then
            case "$one" in *"$_ATTR_TAB"*) printf '%s' "${one#*"$_ATTR_TAB"}" ;; esac
            return 0
        fi
    done
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
    local line pending=0 t

    # Matched inline for the same reason `attr_on` does: a command substitution
    # is a subshell, and this runs on every line of the file. The test suite
    # calls it once per test file and a checker calls it once per source file.
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            [![:space:]]*) t="$line" ;;
            *) t="${line#"${line%%[![:space:]]*}"}" ;;
        esac

        case "$t" in
            '') continue ;;
            '#['*) ;;
            '#'*) continue ;;
        esac

        if _attr_is_attr_t "$t"; then
            _attr_name_set_t "$t"
            [ "$_ATTR_NAME" = "$want" ] && pending=1
            continue
        fi

        _attr_defines_set_t "$t"
        if [ -n "$_ATTR_DEF" ]; then
            [ "$pending" -eq 1 ] && printf '%s\n' "$_ATTR_DEF"
            pending=0
            continue
        fi

        pending=0
    done < "$file"
}
