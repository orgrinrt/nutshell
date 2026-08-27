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

# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and uses
# `printf -v`. A file on the floor cannot ask a bash-only function whether it
# has been loaded: under a POSIX shell the function is not found, the
# `|| return 0` returns from the whole file, and the module defines nothing
# while reporting success.
[ -n "${_NUTSHELL_CLI_SH:-}" ] && return 0
_NUTSHELL_CLI_SH=1

use string
use list
use map

CLI_EXIT_UNKNOWN="${CLI_EXIT_UNKNOWN:-64}"

# -----------------------------------------------------------------------------
# Registration state
# -----------------------------------------------------------------------------

# Registration order is a list and the two lookups are maps, so this file
# needs no bash array and reads on the floor. Command names go through the
# map's own encoding, so a name holding a dash or a dot is a key like any
# other.
list_new _CLI_ORDER
map_new _CLI_SUMMARY
map_new _CLI_HANDLER
_CLI_NAME="${0##*/}"
_CLI_SUMMARY_LINE=""
_CLI_EPILOGUE=""

# -----------------------------------------------------------------------------
# Declaring the tool
# -----------------------------------------------------------------------------

# cli_name <name>
#[pub]
# Usage: cli_name mytool -> names the tool in usage output
cli_name() { _CLI_NAME="$1"; }

# cli_summary <one line>
#[pub]
# Usage: cli_summary "does the thing" -> one line under the name
cli_summary() { _CLI_SUMMARY_LINE="$1"; }

# cli_epilogue <text>
#
# Printed under the subcommand list. For the sentence a reader needs after
# seeing what the tool can do, which is usually where to look next.
#[pub]
# Usage: cli_epilogue "See https://..." -> a closing line in usage output
cli_epilogue() { _CLI_EPILOGUE="$1"; }

# cli_command <name> <summary> <handler>
#
# Order of registration is order of display. Deliberately not sorted: a tool
# whose subcommands run in a sequence should list them in that sequence, and
# alphabetical order would scatter it.
#[pub]
# Usage: cli_command build "compile everything" do_build -> registers one
cli_command() {
    _cc_name="$1"; _cc_summary="$2"; _cc_handler="$3"
    # Registering a name twice keeps one entry in the order, or the help would
    # list it twice while the second registration silently won the dispatch.
    if ! map_has _CLI_HANDLER "$_cc_name"; then
        list_push _CLI_ORDER "$_cc_name"
    fi
    map_set _CLI_SUMMARY "$_cc_name" "$_cc_summary"
    map_set _CLI_HANDLER "$_cc_name" "$_cc_handler"
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

#[pub]
# Usage: cli_usage -> prints the whole usage text, commands in registration order
cli_usage() {
    printf '%s' "$_CLI_NAME"
    [ -n "$_CLI_SUMMARY_LINE" ] && printf ': %s' "$_CLI_SUMMARY_LINE"
    printf '\n\nusage: %s <command> [options]\n\n' "$_CLI_NAME"

    # Width from the longest name, so the column does not drift as commands
    # are added and nobody has to maintain a magic number.
    _cu_width=0
    _cu_n="$(list_len _CLI_ORDER)"
    _cu_i=0
    while [ "$_cu_i" -lt "$_cu_n" ]; do
        list_read _cu_name _CLI_ORDER "$_cu_i"
        [ "${#_cu_name}" -gt "$_cu_width" ] && _cu_width="${#_cu_name}"
        _cu_i=$(( _cu_i + 1 ))
    done

    # The width goes into the format string rather than through `%-*s`, which
    # is a bash extension: POSIX `printf` has no `*` field width.
    _cu_i=0
    while [ "$_cu_i" -lt "$_cu_n" ]; do
        list_read _cu_name _CLI_ORDER "$_cu_i"
        map_read _cu_sum _CLI_SUMMARY "$_cu_name"
        printf "  %-${_cu_width}s  %s\n" "$_cu_name" "$_cu_sum"
        _cu_i=$(( _cu_i + 1 ))
    done

    if [ -n "$_CLI_EPILOGUE" ]; then
        printf '\n%s\n' "$_CLI_EPILOGUE"
    fi
}

# -----------------------------------------------------------------------------
# Did you mean
# -----------------------------------------------------------------------------

# cli_nearest <input>
#
# The closest registered command, or nothing. The threshold scales with the
# input's length because two edits on a three-character name is most of the
# name, and one edit on a twelve-character name misses obvious typos.
#[pub]
# Usage: cli_nearest buidl -> "build", or nothing when nothing is close
cli_nearest() {
    _cn_input="$1"; _cn_best=""; _cn_best_d=99
    _cn_limit=2
    [ "${#_cn_input}" -le 4 ] && _cn_limit=1

    _cn_n="$(list_len _CLI_ORDER)"
    _cn_i=0
    while [ "$_cn_i" -lt "$_cn_n" ]; do
        list_read _cn_name _CLI_ORDER "$_cn_i"
        _cn_d="$(str_distance "$_cn_input" "$_cn_name")"
        if [ "$_cn_d" -le "$_cn_limit" ] && [ "$_cn_d" -lt "$_cn_best_d" ]; then
            _cn_best_d="$_cn_d"
            _cn_best="$_cn_name"
        fi
        _cn_i=$(( _cn_i + 1 ))
    done
    printf '%s' "$_cn_best"
}

# -----------------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------------

# cli_run "$@"
#
# Returns the handler's own exit code, so a tool that means something by its
# codes keeps meaning it.
#[pub]
# Usage: cli_run "$@" -> dispatches, or explains and exits 64
cli_run() {
    _cr_cmd="${1:-}"

    case "$_cr_cmd" in
        "" | help | -h | --help ) cli_usage; return 0 ;;
    esac

    if map_has _CLI_HANDLER "$_cr_cmd"; then
        map_read _cr_fn _CLI_HANDLER "$_cr_cmd"
        shift
        "$_cr_fn" "$@"
        return $?
    fi

    printf '%s: no command %s\n' "$_CLI_NAME" "'$_cr_cmd'" >&2
    _cr_near="$(cli_nearest "$_cr_cmd")"
    if [ -n "$_cr_near" ]; then
        printf "did you mean '%s'?\n" "$_cr_near" >&2
    else
        printf "try '%s help'\n" "$_CLI_NAME" >&2
    fi
    return "$CLI_EXIT_UNKNOWN"
}
