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
# A short option may be clustered (`-nc`, `-Rs`). An option may stand before or
# after the filter, as jq takes them, and `--` ends the options.
#
# Written with `case` and positional parameters, not arrays, so a shell with
# neither still loads it.
#
# Which tool has an option is read from the tool: `-e`, `--slurpfile` and
# `--rawfile` are not in every version of each (jq has no `--rawfile` before
# 1.6), so the first call that needs one asks the tool for its `--help` and
# looks for the option's long name there, once per process for each tool. The
# rest every jq, gojq and jaq takes. A tool whose help lacks an option is
# passed over for the next that has it, or the call is refused.
# =============================================================================

[ -n "${_NUTSHELL_JSON_QUERY_SH:-}" ] && return 0
_NUTSHELL_JSON_QUERY_SH=1

use deps

# _json_q_help <tool> -> `_jqh`, the tool's `--help`, read once per process
# for each path the tool is found at.
_json_q_help() {
    local p q
    p="$(deps_path "$1")"
    eval "q=\"\${_JSON_Q_P_${1}:-}\" _jqh=\"\${_JSON_Q_H_${1}:-}\""
    [ -n "$q" ] && [ "$q" = "$p" ] && return 0
    _jqh="$(deps_run "$1" --help 2>&1)"
    eval "_JSON_Q_P_${1}=\"\$p\" _JSON_Q_H_${1}=\"\$_jqh\""
}

# _json_q_lacks <tool> <option> -> 0 when the tool's help does not name it
_json_q_lacks() {
    local flag="$2" _jqh
    case "$2" in
        -e) flag="--exit-status" ;;
        --slurpfile | --rawfile) ;;
        *) return 1 ;;
    esac
    _json_q_help "$1"
    case "$_jqh" in
        *"$flag"*) return 1 ;;
    esac
    return 0
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
# The document is the operand after the filter, or stdin when there is none.
# Options, before or after the filter; `--` ends them, so a filter or a
# document that starts with `-` follows a `--`:
#   -r  strings bare (already the default)    --json  strings as JSON text
#   -j  join output, no newline after each    -c      compact (the default)
#   -n  null input        -s  slurp        -R  raw input
#   -e  the status follows the last result (jq's: 1 false or null, 4 none)
#   --arg <name> <text>   --argjson <name> <json>
#   --slurpfile <name> <file>   --rawfile <name> <file>
#   and the long forms --raw-output --join-output --compact-output
#   --null-input --slurp --raw-input --exit-status
# Usage: json_query '.items[] | .name' "$json"
# Usage: curl -s "$url" | json_query '.total'
# Usage: json_query -n --arg k "$key" --argjson v "$val" '{($k): $v}'
# Returns: what the program printed. Status 2 is a refusal: no jq family tool
# is here, or none that has an option the call uses (the refusal names it), an
# option none of them has, or more operands than a filter and a document. 1
# for no filter, and for a query the tool failed, its own status 2 included
# (a file `--slurpfile` cannot open); otherwise the tool's status.
json_query() {
    local raw=1 join="" nullin="" slurp="" rawin="" want_e="" needs="" flags
    local a rest ch u filter="" doc="" havedoc="" nops=0 t tool="" bin nm v rc
    local opts=1
    u=$#
    while [ "$u" -gt 0 ]; do
        a="$1"
        if [ -n "$opts" ]; then
            case "$a" in
                --)
                    opts=""; shift; u=$((u - 1)); continue ;;
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
                --raw-output)     raw=1; a="" ;;
                --json)           raw=0; a="" ;;
                --join-output)    join=1; a="" ;;
                --compact-output) a="" ;;
                --null-input)     nullin=1; a="" ;;
                --slurp)          slurp=1; a="" ;;
                --raw-input)      rawin=1; a="" ;;
                --exit-status)    want_e=1; needs="${needs} -e"; a="" ;;
                --*)
                    echo "json_query: no option ${a} here" >&2
                    return 2 ;;
                -?*)
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
                    done
                    a="" ;;
            esac
            # An option was taken; anything else falls through as an operand.
            if [ -z "$a" ]; then
                shift; u=$((u - 1)); continue
            fi
        fi
        # An operand: the filter, then the document.
        nops=$((nops + 1))
        case "$nops" in
            1) filter="$a" ;;
            2) doc="$a"; havedoc=1 ;;
            *)
                echo "json_query: a filter and a document at most, and ${a} is a third" >&2
                return 2 ;;
        esac
        shift; u=$((u - 1))
    done
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
    # A filter led by `-` would be read as an option. A space before it is
    # skipped by every jq family parser and taken for an option by none.
    case "$filter" in -*) filter=" ${filter}" ;; esac

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
    rc=$?
    # The tool's 2 is a call it could not run, which to a caller is a failed
    # query; 2 from here means json_query refused.
    [ "$rc" -eq 2 ] && return 1
    return "$rc"
}
