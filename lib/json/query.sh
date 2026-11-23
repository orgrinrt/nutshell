#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/json/query.sh - a jq program through jq, gojq or jaq
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# `json_query` and the options it passes on. Loaded by `lib/json.sh`, which is
# where a caller gets it from.
#
# The options are the ones the workspace's scripts call jq with: variables
# (`--arg`, `--argjson`, `--slurpfile`, `--rawfile`), the shape of the input
# (`-n`, `-s`, `-R`) and of the output (`-r`, `-j`, `-c`, `--json`), and `-e`.
# A short option may be clustered (`-nc`, `-Rs`). They go before the filter.
#
# Written with `case` and positional parameters, not arrays, so a shell with
# neither still loads it.
#
# What each tool has, and where this table is not from running the tool:
#   jq    every option here.
#   gojq  every option here (its documentation lists them all).
#   jaq   `-n -s -R -r -j -c --arg --argjson`. `-e`, `--slurpfile` and
#         `--rawfile` are taken as missing: no jaq was run to see, and a call
#         that needs one moves to a tool that has it, or is refused, which
#         costs a caller less than an option a tool then fails to parse.
# =============================================================================

[ -n "${_NUTSHELL_JSON_QUERY_SH:-}" ] && return 0
_NUTSHELL_JSON_QUERY_SH=1

use deps

# _json_q_lacks <tool> <option> -> 0 when the tool cannot take the option
_json_q_lacks() {
    case "$1:$2" in
        jaq:-e | jaq:--slurpfile | jaq:--rawfile) return 0 ;;
    esac
    return 1
}

# _json_q_refuse <option...> -> says why no tool here can make the call
# The first tool here, in order, and the first option it lacks name the refusal;
# with none of the three the refusal says so.
_json_q_refuse() {
    local t a
    for t in jq gojq jaq; do
        deps_has "$t" || continue
        for a in "$@"; do
            _json_q_lacks "$t" "$a" || continue
            echo "json_query: ${a} is not supported by ${t}, and no other tool here takes it" >&2
            return 0
        done
    done
    echo "json_query: needs jq, gojq or jaq, and this machine has none" >&2
}

#[pub]
# Run a jq program over a document, through jq, gojq or jaq, whichever `deps`
# finds first that has every option the call uses. Strings come back bare and
# everything else compact, so `json_query '.a | length' "$doc"` prints `3`.
# The document is the argument after the filter, or stdin when there is none.
# Options, before the filter:
#   -r  strings bare (already the default)    --json  strings as JSON text
#   -j  join output, no newline after each    -c      compact (the default)
#   -n  null input        -s  slurp        -R  raw input
#   -e  the status follows the last result (jq's: 1 false or null, 4 none)
#   --arg <name> <text>   --argjson <name> <json>
#   --slurpfile <name> <file>   --rawfile <name> <file>
# Usage: json_query '.items[] | .name' "$json"
# Usage: curl -s "$url" | json_query '.total'
# Usage: json_query -n --arg k "$key" --argjson v "$val" '{($k): $v}'
# Returns: what the program printed. Status 2 when no jq family tool is here,
# or none that has an option the call uses (the refusal names it), or the call
# has an option none of them has; 1 for no filter.
json_query() {
    local raw=1 join="" nullin="" slurp="" rawin="" want_e="" needs="" flags
    local a rest ch u filter="" doc="" havedoc="" t tool="" bin nm v
    u=$#
    while [ "$u" -gt 0 ]; do
        a="$1"
        case "$a" in
            --arg | --argjson | --slurpfile | --rawfile)
                if [ "$u" -lt 3 ]; then
                    echo "json_query: ${a} needs a name and a value" >&2
                    return 2
                fi
                [ "$a" = --arg ] || [ "$a" = --argjson ] || needs="${needs} ${a}"
                nm="$2"; v="$3"
                shift 3
                set -- "$@" "$a" "$nm" "$v"
                u=$((u - 3))
                continue ;;
            --raw-output)     raw=1 ;;
            --json)           raw=0 ;;
            --join-output)    join=1 ;;
            --compact-output) ;;
            --null-input)     nullin=1 ;;
            --slurp)          slurp=1 ;;
            --raw-input)      rawin=1 ;;
            --exit-status)    want_e=1; needs="${needs} -e" ;;
            -[a-zA-Z]* | --[a-zA-Z]*)
                case "$a" in
                    --*) echo "json_query: no option ${a} here" >&2; return 2 ;;
                esac
                rest="${a#-}"
                while [ -n "$rest" ]; do
                    ch="${rest%"${rest#?}"}"
                    rest="${rest#?}"
                    case "$ch" in
                        r) raw=1 ;;
                        j) join=1 ;;
                        c) ;;
                        n) nullin=1 ;;
                        s) slurp=1 ;;
                        R) rawin=1 ;;
                        e) want_e=1; needs="${needs} -e" ;;
                        *) echo "json_query: no option -${ch} here (in ${a})" >&2; return 2 ;;
                    esac
                done ;;
            *) break ;;
        esac
        shift
        u=$((u - 1))
    done

    # What is left in front of the variable options is the filter, then the
    # document if there is one.
    [ "$u" -ge 1 ] && filter="$1"
    [ "$u" -ge 2 ] && { doc="$2"; havedoc=1; }
    shift "$u"

    for t in jq gojq jaq; do
        deps_has "$t" || continue
        tool="$t"; bin="$(deps_path "$t")"
        [ -z "$needs" ] && break
        # The first tool that has every option the call needs.
        tool=""
        for a in $needs; do
            _json_q_lacks "$t" "$a" && continue 2
        done
        tool="$t"; break
    done
    if [ -z "$tool" ]; then
        _json_q_refuse $needs
        return 2
    fi
    [ -n "$filter" ] || return 1

    flags="-c"
    [ -n "$join" ] && flags="${flags} -j"
    [ -z "$join" ] && [ "$raw" = 1 ] && flags="${flags} -r"
    [ -n "$nullin" ] && flags="${flags} -n"
    [ -n "$slurp" ] && flags="${flags} -s"
    [ -n "$rawin" ] && flags="${flags} -R"
    [ -n "$want_e" ] && flags="${flags} -e"
    # shellcheck disable=SC2086
    set -- $flags "$@" "$filter"
    if [ -n "$havedoc" ]; then
        printf '%s\n' "$doc" | "$bin" "$@"
    else
        "$bin" "$@"
    fi
}
