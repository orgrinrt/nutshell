#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/cli.sh - Subcommand dispatch
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0: depends on log and text for output. Nothing else.
#
# A tool with subcommands is the shape most scripts grow into, and the
# hand-rolled version is always the same: a case statement, a usage function
# that drifts from it, and no suggestion when someone mistypes. This makes the
# registration the single source of both dispatch and help, so a subcommand
# that exists cannot be missing from the usage text.
#
# Usage:
#   use cli
#
#   cli_name    "mytool"
#   cli_summary "does the thing"
#   cli_command "build"  "compile everything"        cmd_build
#   cli_command "check"  "run the checks"            cmd_check
#   cli_run "$@"
#
# Each handler is an ordinary function receiving the remaining arguments.
#
# Environment:
#   CLI_EXIT_UNKNOWN - exit code for an unknown subcommand (default: 64,
#                      which is EX_USAGE from sysexits.h)
# =============================================================================

[[ -n "${_NUTSHELL_LIB_CLI_SH:-}" ]] && return 0
readonly _NUTSHELL_LIB_CLI_SH=1

CLI_EXIT_UNKNOWN="${CLI_EXIT_UNKNOWN:-64}"

# -----------------------------------------------------------------------------
# Registration state
# -----------------------------------------------------------------------------

declare -ga _CLI_ORDER=()
declare -gA _CLI_SUMMARY=()
declare -gA _CLI_HANDLER=()
_CLI_NAME="${0##*/}"
_CLI_SUMMARY_LINE=""
_CLI_EPILOGUE=""

# -----------------------------------------------------------------------------
# Declaring the tool
# -----------------------------------------------------------------------------

# cli_name <name>
#[pub]
cli_name() { _CLI_NAME="$1"; }

# cli_summary <one line>
#[pub]
cli_summary() { _CLI_SUMMARY_LINE="$1"; }

# cli_epilogue <text>
#
# Printed under the subcommand list. For the sentence a reader needs after
# seeing what the tool can do, which is usually where to look next.
#[pub]
cli_epilogue() { _CLI_EPILOGUE="$1"; }

# cli_command <name> <summary> <handler>
#
# Order of registration is order of display. Deliberately not sorted: a tool
# whose subcommands run in a sequence should list them in that sequence, and
# alphabetical order would scatter it.
#[pub]
cli_command() {
    local name="$1" summary="$2" handler="$3"
    _CLI_ORDER+=("$name")
    _CLI_SUMMARY["$name"]="$summary"
    _CLI_HANDLER["$name"]="$handler"
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

#[pub]
cli_usage() {
    printf '%s' "$_CLI_NAME"
    [[ -n "$_CLI_SUMMARY_LINE" ]] && printf ': %s' "$_CLI_SUMMARY_LINE"
    printf '\n\nusage: %s <command> [options]\n\n' "$_CLI_NAME"

    # Width from the longest name, so the column does not drift as commands
    # are added and nobody has to maintain a magic number.
    local width=0 name
    for name in "${_CLI_ORDER[@]}"; do
        (( ${#name} > width )) && width=${#name}
    done

    for name in "${_CLI_ORDER[@]}"; do
        printf '  %-*s  %s\n' "$width" "$name" "${_CLI_SUMMARY[$name]}"
    done

    if [[ -n "$_CLI_EPILOGUE" ]]; then
        printf '\n%s\n' "$_CLI_EPILOGUE"
    fi
}

# -----------------------------------------------------------------------------
# Did you mean
# -----------------------------------------------------------------------------

# _cli_distance <a> <b>
#
# Levenshtein over one row. A misspelling is worth naming and a stranger is
# not, so the caller applies a threshold; this only measures.
_cli_distance() {
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

# cli_nearest <input>
#
# The closest registered command, or nothing. The threshold scales with the
# input's length because two edits on a three-character name is most of the
# name, and one edit on a twelve-character name misses obvious typos.
#[pub]
cli_nearest() {
    local input="$1" name best="" best_d=99 d limit
    limit=2
    (( ${#input} <= 4 )) && limit=1

    for name in "${_CLI_ORDER[@]}"; do
        d=$(_cli_distance "$input" "$name")
        if (( d <= limit && d < best_d )); then
            best_d=$d
            best="$name"
        fi
    done
    printf '%s' "$best"
}

# -----------------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------------

# cli_run "$@"
#
# Returns the handler's own exit code, so a tool that means something by its
# codes keeps meaning it.
#[pub]
cli_run() {
    local cmd="${1:-}"

    if [[ -z "$cmd" || "$cmd" == "help" || "$cmd" == "-h" || "$cmd" == "--help" ]]; then
        cli_usage
        return 0
    fi

    if [[ -n "${_CLI_HANDLER[$cmd]:-}" ]]; then
        shift
        "${_CLI_HANDLER[$cmd]}" "$@"
        return $?
    fi

    printf '%s: no command %s\n' "$_CLI_NAME" "'$cmd'" >&2
    local near
    near="$(cli_nearest "$cmd")"
    if [[ -n "$near" ]]; then
        printf "did you mean '%s'?\n" "$near" >&2
    else
        printf "try '%s help'\n" "$_CLI_NAME" >&2
    fi
    return "$CLI_EXIT_UNKNOWN"
}
