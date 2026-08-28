#!/usr/bin/env bash
# =============================================================================
# nutshell/core/string.sh - String manipulation primitives
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): No dependencies on other modules
# =============================================================================

# Prevent multiple inclusion
# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE`
# and so needs bash. Under a POSIX shell it is not found, the
# `|| return 0` beside it fires on every load, and the module reports
# success having defined nothing.
[ -n "${_NUTSHELL_STRING_SH:-}" ] && return 0
_NUTSHELL_STRING_SH=1

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

#[allow(trivial_wrapper)]
# Convert string to lowercase
# Usage: str_lower "HELLO" -> "hello"
#[pub]
str_lower() {
    local str="${1:-}"
    echo "${str,,}"
}

#[allow(trivial_wrapper)]
# Convert string to uppercase
# Usage: str_upper "hello" -> "HELLO"
#[pub]
str_upper() {
    local str="${1:-}"
    echo "${str^^}"
}

#[pub]
# Trim whitespace from both ends
# Usage: str_trim "  hello  " -> "hello"
str_trim() {
    local str="${1:-}"
    # Trim leading whitespace
    str="${str#"${str%%[![:space:]]*}"}"
    # Trim trailing whitespace
    str="${str%"${str##*[![:space:]]}"}"
    echo "$str"
}

#[pub]
# Trim whitespace from left side
# Usage: str_ltrim "  hello" -> "hello"
str_ltrim() {
    local str="${1:-}"
    str="${str#"${str%%[![:space:]]*}"}"
    echo "$str"
}

#[pub]
# Trim whitespace from right side
# Usage: str_rtrim "hello  " -> "hello"
str_rtrim() {
    local str="${1:-}"
    str="${str%"${str##*[![:space:]]}"}"
    echo "$str"
}

#[pub]
# Replace all occurrences of a substring
# Usage: str_replace "hello world" "world" "bash" -> "hello bash"
str_replace() {
    local str="${1:-}"
    local from="${2:-}"
    local to="${3:-}"
    local _sr_out="${4:-}"

    # The out-name form, matching the floor half. Both halves have to take the
    # same four arguments or a caller works on one shell and not the other,
    # which is the failure the pair exists to prevent.
    #
    # Validated before either exit, because both reach an assignment through
    # `eval`.
    if [[ -n "$_sr_out" ]]; then
        case "$_sr_out" in ''|*[!A-Za-z0-9_]*|[0-9]*) return 2 ;; esac
    fi
    if [[ -z "$from" ]]; then
        if [[ -n "$_sr_out" ]]; then eval "$_sr_out=\$str"; else echo "$str"; fi
        return 0
    fi
    # The needle is quoted, so it is a literal.
    #
    # Unquoted, `${str//$from/$to}` reads it as a pattern, which is not what
    # "replace all occurrences of a substring" says and not what a caller
    # passing a needle out of a file means. `str_replace 'a*b' '*' '+'`
    # returned `+`, because `*` matched the whole string; `a?c` matched `axc`;
    # and `[b]` matched a bare `b`.
    #
    # Found by writing the POSIX floor beside this and comparing the two over
    # the same inputs. The floor could not have this bug: it has no `${x//}`
    # and cuts at the first literal occurrence instead.
    # **Both** sides quoted. The needle is quoted so it is a literal rather
    # than a pattern, which is the bug the comment above records. The
    # replacement has to be quoted for the same class of reason: unquoted,
    # `$to` goes through quote removal, so a replacement of `\\` collapses to
    # `\` and `str_replace a a '\\'` answers `\` where the floor half answers
    # `\\`. That divergence sat here until three modules stopped keeping their
    # own copy of this loop and started calling it.
    if [[ -n "$_sr_out" ]]; then
        printf -v "$_sr_out" '%s' "${str//"$from"/"$to"}"
    else
        printf '%s\n' "${str//"$from"/"$to"}"
    fi
}

#[pub]
# Check if string contains substring
# Usage: str_contains "hello world" "world" -> returns 0 (true)
str_contains() {
    local str="${1:-}"
    local substr="${2:-}"
    
    [[ -z "$substr" ]] && return 0  # Empty substring always matches
    [[ "$str" == *"$substr"* ]]
}

#[pub]
# Check if string starts with prefix
# Usage: str_starts_with "hello world" "hello" -> returns 0 (true)
str_starts_with() {
    local str="${1:-}"
    local prefix="${2:-}"
    
    [[ -z "$prefix" ]] && return 0
    [[ "$str" == "$prefix"* ]]
}

#[pub]
# Check if string ends with suffix
# Usage: str_ends_with "hello world" "world" -> returns 0 (true)
str_ends_with() {
    local str="${1:-}"
    local suffix="${2:-}"
    
    [[ -z "$suffix" ]] && return 0
    [[ "$str" == *"$suffix" ]]
}

#[pub]
# Split string by delimiter into array
# Usage: str_split ":" "a:b:c" arr -> arr=("a" "b" "c")
str_split() {
    local delim="${1:-}"
    local str="${2:-}"
    local -n _arr="${3:-_str_split_result}"
    
    _arr=()
    [[ -z "$str" ]] && return 0
    
    if [[ -z "$delim" ]]; then
        _arr=("$str")
        return 0
    fi
    
    local IFS="$delim"
    read -ra _arr <<< "$str"
}

#[pub]
# Join array elements with delimiter
# Usage: str_join "," "a" "b" "c" -> "a,b,c"
str_join() {
    local delim="${1:-}"
    shift
    
    local result=""
    local first=true
    
    for item in "$@"; do
        if $first; then
            result="$item"
            first=false
        else
            result="${result}${delim}${item}"
        fi
    done
    
    echo "$result"
}

#[allow(trivial_wrapper)]
# Get string length
# Usage: str_length "hello" -> 5
#[pub]
str_length() {
    local str="${1:-}"
    echo "${#str}"
}

#[pub]
# Extract substring
# Usage: str_substr "hello world" 0 5 -> "hello"
str_substr() {
    local str="${1:-}"
    local start="${2:-0}"
    local length="${3:-}"
    
    if [[ -n "$length" ]]; then
        echo "${str:$start:$length}"
    else
        echo "${str:$start}"
    fi
}

#[pub]
# Repeat string N times
# Usage: str_repeat "-" 5 -> "-----"
str_repeat() {
    local str="${1:-}"
    local count="${2:-1}"
    
    [[ $count -le 0 ]] && return 0
    
    local result=""
    for ((i=0; i<count; i++)); do
        result="${result}${str}"
    done
    echo "$result"
}

# str_distance <a> <b>
#
# Levenshtein distance: how many single-character edits turn one into the
# other. For suggesting what somebody meant, so a caller applies its own
# threshold; this only measures.
#
# One row rather than the full matrix, and no subprocess. There were two of
# these, one here in spirit and one in the check framework, and the other was
# an awk invocation per comparison: a `cli` module offering did-you-mean would
# have had to depend on the QA framework to reach it, which is backwards.
#[pub]
# Usage: str_distance build buidl -> 2
str_distance() {
    local a="$1" b="$2"
    local -i alen=${#a} blen=${#b} i j cost prev tmp
    local -a row=()

    for (( j = 0; j <= blen; j++ )); do row[j]=$j; done

    for (( i = 1; i <= alen; i++ )); do
        prev=${row[0]}
        row[0]=$i
        for (( j = 1; j <= blen; j++ )); do
            tmp=${row[j]}
            cost=1
            [[ "${a:i-1:1}" == "${b:j-1:1}" ]] && cost=0
            local -i del=$(( row[j] + 1 ))
            local -i ins=$(( row[j-1] + 1 ))
            local -i sub=$(( prev + cost ))
            local -i best=$del
            (( ins < best )) && best=$ins
            (( sub < best )) && best=$sub
            row[j]=$best
            prev=$tmp
        done
    done
    printf '%d' "${row[blen]}"
}
