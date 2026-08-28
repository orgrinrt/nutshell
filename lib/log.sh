#!/usr/bin/env bash
# =============================================================================
# nutshell/core/log.sh - Logging primitives
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer -1 (Foundation): No dependencies. This is the bedrock.
#
# Environment:
#   LOG_LEVEL - debug|info|warn|error (default: info)
#   LOG_COLOR - auto|always|never (default: auto)
#   LOG_MARKS - auto|icon|text|none (default: auto)
# =============================================================================

# Prevent multiple inclusion
# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and uses
# `printf -v`. A file on the floor cannot ask a bash-only function whether it
# has been loaded.
[ -n "${_NUTSHELL_LOG_SH:-}" ] && return 0
_NUTSHELL_LOG_SH=1

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

LOG_LEVEL="${LOG_LEVEL:-info}"
LOG_COLOR="${LOG_COLOR:-auto}"

# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

_log_should_color() {
    case "$LOG_COLOR" in
        always) return 0 ;;
        never)  return 1 ;;
        auto)   [ -t 2 ] ;;  # Check if stderr is a TTY
    esac
}

_log_level_num() {
    case "$1" in
        debug) echo 0 ;;
        info)  echo 1 ;;
        warn)  echo 2 ;;
        error) echo 3 ;;
        *)     echo 1 ;;
    esac
}

_log_should_emit() {
    local msg_level="$1"
    local current=$(_log_level_num "$LOG_LEVEL")
    local target=$(_log_level_num "$msg_level")
    [ "$target" -ge "$current" ]
}

_log_format() {
    local level="$1"
    local color="$2"
    local reset="$3"
    local message="$4"
    
    if [ -n "$color" ]; then
        printf '%b[%s]%b %s\n' "$color" "$level" "$reset" "$message"
    else
        printf '[%s] %s\n' "$level" "$message"
    fi
}

# -----------------------------------------------------------------------------
# Marks and depth
# -----------------------------------------------------------------------------
#
# A run of forty lines where one went wrong should not need reading forty times
# to find it. Two things make that work, and both are about skimming.
#
# Every line can start with a mark saying what kind of line it is, in one
# column, so the eye scans down rather than across. Icons where the terminal
# can draw them, words where it cannot, and the caller may insist on either.
#
# And a line sits at the depth of the step it belongs to. `log_step` already
# opened a heading and `log_substep` indented one line under it; what was
# missing was nesting past one level and a way to close a step with how it
# went. What produced a message is then a matter of looking left.

LOG_MARKS="${LOG_MARKS:-auto}"

LOG_DEPTH=0
LOG_WARNINGS=0
LOG_FAILURES=0

_LOG_MARKS_SET=0
_LOG_M_OK="+"; _LOG_M_BAD="x"; _LOG_M_WARN="!"; _LOG_M_STEP=">"; _LOG_M_FLAT=" "

# Can this terminal draw a character outside ASCII? A locale that is not UTF-8
# renders one as several bytes of noise, and the linux console before a font is
# loaded is where that happens, which is where a recovery script runs.
_log_unicode_ok() {
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8*|*utf8*|*UTF8*|*utf-8*) ;;
        *) return 1 ;;
    esac
    [ "${TERM:-}" != "linux" ]
}

_log_marks_init() {
    [ "${_LOG_MARKS_SET:-0}" = 1 ] && return 0
    _LOG_MARKS_SET=1
    case "$LOG_MARKS" in
        none) _LOG_M_OK=" "; _LOG_M_BAD=" "; _LOG_M_WARN=" "; _LOG_M_STEP=" " ;;
        text) _LOG_M_OK="+"; _LOG_M_BAD="x"; _LOG_M_WARN="!"; _LOG_M_STEP=">" ;;
        icon) _log_marks_unicode ;;
        *)    _log_unicode_ok && _log_marks_unicode ;;
    esac
}

# The marks as octal UTF-8 rather than `\uXXXX`, which is a bash extension to
# `%b`, and through a substitution rather than `printf -v`, which is bash too.
#
# Four forks, once per process: `_log_marks_init` returns early after the first
# call, and `log_marks` is the only thing that re-arms it. The file stays ASCII,
# which is why these are escapes and not the characters themselves.
_log_marks_unicode() {
    _LOG_M_OK="$(printf '%b' '\342\234\223')"
    _LOG_M_BAD="$(printf '%b' '\342\234\227')"
    _LOG_M_WARN="$(printf '%b' '\342\232\240')"
    _LOG_M_STEP="$(printf '%b' '\342\200\272')"
}

#[pub]
# Choose how lines are marked, overriding what was detected.
# Usage: log_marks icon | text | none | auto
log_marks() { LOG_MARKS="${1:-auto}"; _LOG_MARKS_SET=0; _log_marks_init; }

#[pub]
# Forget the depth and the counts, for a caller starting a fresh run.
# Usage: log_reset
log_reset() { LOG_DEPTH=0; LOG_WARNINGS=0; LOG_FAILURES=0; }

_log_pad() {
    local n=$(( LOG_DEPTH * 2 ))
    [ "$n" -gt 0 ] || return 0
    # A loop rather than `%*s`, which is a bash extension: POSIX `printf` has
    # no `*` field width and the width here is not a constant.
    _lp_i=0
    while [ "$_lp_i" -lt "$n" ]; do printf ' '; _lp_i=$(( _lp_i + 1 )); done
}

# One marked line. The mark sits outside the indent, so every mark in a run is
# in the same column however deep its line is.
_log_marked() {
    local mark="$1" color="$2" text="$3" reset=""
    _log_marks_init
    _log_should_color && reset='\033[0m' || color=""
    printf '%b%s%b %s%s\n' "$color" "$mark" "$reset" "$(_log_pad)" "$text"
}

#[pub]
# Open a step. Everything after it is indented under it until it is ended.
# Unlike log_step, which is a flat heading, these nest.
# Usage: log_open "Partitioning"
log_open() {
    _log_should_emit info || { LOG_DEPTH=$(( LOG_DEPTH + 1 )); return 0; }
    _log_marks_init
    local bold="" reset=""
    if _log_should_color; then bold='\033[1m'; reset='\033[0m'; fi
    _log_marked "$_LOG_M_STEP" '\033[0;36m' "$(printf '%b%s%b' "$bold" "$*" "$reset")"
    LOG_DEPTH=$(( LOG_DEPTH + 1 ))
}

#[pub]
# Close the step, with how it went: ok, warn, fail, or nothing for silence.
# Usage: log_close ok "3 partitions"
log_close() {
    [ "$LOG_DEPTH" -gt 0 ] && LOG_DEPTH=$(( LOG_DEPTH - 1 ))
    local how="${1:-}"; shift 2>/dev/null || true
    case "$how" in
        ok)   log_ok   "$@" ;;
        warn) log_warned "$@" ;;
        fail) log_failed "$@" ;;
        "")   return 0 ;;
        *)    log_flat "$how" "$@" ;;
    esac
}

#[pub]
# It worked. Marked, indented, and counted.
# Usage: log_ok "made an ESP at /dev/sdb1"
log_ok() {
    _log_should_emit info || return 0
    _log_marked "$_LOG_M_OK" '\033[0;32m' "$*"
}

#[pub]
# Worth a look, and the run goes on.
# Usage: log_warned "the free region is tight"
log_warned() {
    LOG_WARNINGS=$(( LOG_WARNINGS + 1 ))
    _log_should_emit warn || return 0
    _log_marked "$_LOG_M_WARN" '\033[0;33m' "$*"
}

#[pub]
# It did not work.
# Usage: log_failed "could not set the esp flag"
log_failed() {
    LOG_FAILURES=$(( LOG_FAILURES + 1 ))
    _log_should_emit error || return 0
    _log_marked "$_LOG_M_BAD" '\033[0;31m' "$*"
}

#[pub]
# Something true that is neither good nor bad. Unmarked, so a run of these does
# not read as a run of results.
# Usage: log_flat "sgdisk: 3 partitions"
log_flat() {
    _log_should_emit info || return 0
    _log_marked "$_LOG_M_FLAT" "" "$*"
}

#[pub]
# Run a command as a step: its output indented under it, and a mark on the end
# saying how it went. Returns what the command returned, which is the reason to
# use it rather than printing around it.
# Usage: log_run "writing the table" sgdisk --zap-all /dev/sdb
log_run() {
    local label="$1"; shift
    log_open "$label"
    local line rc="" sep fifo
    sep="$(printf '\037')"

    # A named pipe rather than `< <(...)`, which is bash. The output has to
    # stream as it arrives and the status has to come back to this shell, and a
    # plain pipeline gives up the second: the loop would run in a subshell and
    # what it counted would not return. A temp file gives up the first.
    #
    # `mkfifo` is POSIX. The command writes into the pipe from a background
    # job, this shell reads it, and `wait` collects the job so the function
    # does not return before the writer is done.
    fifo="$(mktemp -u "${TMPDIR:-/tmp}/nut-run.XXXXXX")" || return 1
    mkfifo "$fifo" || return 1

    { "$@" 2>&1; printf '%s%d\n' "$sep" "$?"; } > "$fifo" &
    while IFS= read -r line; do
        # The status travels in the stream, because a pipeline loses it and a
        # runner that reports success on a failed command is worse than none.
        # Read, never printed: a marker, not output.
        if [ "${line%"${line#?}"}" = "$sep" ]; then rc="${line#?}"; break; fi
        log_flat "$line"
    done < "$fifo"
    wait 2>/dev/null
    rm -f "$fifo"

    case "$rc" in
        '' | *[!0-9]* ) rc=1 ;;
    esac
    if [ "$rc" -eq 0 ]; then log_close ok "$label"
    else log_close fail "${label} (exit ${rc})"; fi
    return "$rc"
}

#[pub]
# How the run went overall: fail if anything failed, warn if anything warned,
# ok otherwise. Counted even when LOG_LEVEL hid the line, because the verdict
# is about what happened rather than about what was displayed.
#
# The counts live in the shell that logged. A run inside `$( )` or one side of
# a pipe is a subshell, and what it counted does not come back; capture the
# text or keep the count, not both from the same call.
# Usage: log_worst -> ok | warn | fail
log_worst() {
    [ "$LOG_FAILURES" -gt 0 ] && { printf 'fail'; return 0; }
    [ "$LOG_WARNINGS" -gt 0 ] && { printf 'warn'; return 0; }
    printf 'ok'
}

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

#[pub]
# Usage: log_debug "probing $path" -> to stderr, only when LOG_LEVEL=debug
log_debug() {
    _log_should_emit debug || return 0
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;37m'  # White/gray
        reset='\033[0m'
    fi
    _log_format "DEBUG" "$color" "$reset" "$*" >&2
}

#[pub]
# Usage: log_info "building" -> to stdout
log_info() {
    _log_should_emit info || return 0
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;34m'  # Blue
        reset='\033[0m'
    fi
    _log_format "INFO" "$color" "$reset" "$*"
}

#[pub]
# Usage: log_warn "falling back to sed" -> to stderr
log_warn() {
    _log_should_emit warn || return 0
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;33m'  # Yellow
        reset='\033[0m'
    fi
    _log_format "WARN" "$color" "$reset" "$*" >&2
}

#[pub]
# Usage: log_error "no such file" -> to stderr
log_error() {
    _log_should_emit error || return 0
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;31m'  # Red
        reset='\033[0m'
    fi
    _log_format "ERROR" "$color" "$reset" "$*" >&2
}

#[pub]
# Usage: log_success "41 passed" -> to stdout
log_success() {
    _log_should_emit info || return 0
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;32m'  # Green
        reset='\033[0m'
    fi
    _log_format "OK" "$color" "$reset" "$*"
}

#[pub]
# Usage: log_step "Building" -> a heading, to stdout
log_step() {
    _log_should_emit info || return 0
    local color="" reset="" bold=""
    if _log_should_color; then
        color='\033[0;36m'  # Cyan
        bold='\033[1m'
        reset='\033[0m'
    fi
    printf '%b==>%b %b%s%b\n' "$color" "$reset" "$bold" "$*" "$reset"
}

#[pub]
# Usage: log_substep "linking" -> an indented line under a step
log_substep() {
    _log_should_emit info || return 0
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;35m'  # Magenta
        reset='\033[0m'
    fi
    printf '    %b→%b %s\n' "$color" "$reset" "$*"
}

# log_tagged <TAG> <colour> <message...>
#
# The house format, `[TAG] message`, for a module that needs a tag of its own
# rather than a severity. Public so that a check reporting BLOCK or a migration
# reporting STEP writes the same shape as everything else: one formatter, so
# the convention cannot drift per script.
#
# `colour` is a name from the palette below, or `none`. Colour is applied only
# when the stream is a terminal, exactly as the level functions do it.
#[pub]
# Usage: log_tagged BLOCK red "unsigned commit" -> "[BLOCK] unsigned commit"
log_tagged() {
    local tag="$1" want="$2"; shift 2
    local color="" reset=""
    if _log_should_color; then
        case "$want" in
            red)     color='\033[0;31m' ;;
            green)   color='\033[0;32m' ;;
            yellow)  color='\033[0;33m' ;;
            blue)    color='\033[0;34m' ;;
            magenta) color='\033[0;35m' ;;
            cyan)    color='\033[0;36m' ;;
            gray)    color='\033[0;37m' ;;
            *)       color='' ;;
        esac
        [ -n "$color" ] && reset='\033[0m'
    fi
    _log_format "$tag" "$color" "$reset" "$*"
}

#[pub]
# Usage: log_fatal "cannot continue" -> to stderr, then exits 1
log_fatal() {
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;31m'  # Red
        reset='\033[0m'
    fi
    _log_format "FATAL" "$color" "$reset" "$*" >&2
    exit 1
}
