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
# =============================================================================

# Prevent multiple inclusion
nut_once || return 0

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
        auto)   [[ -t 2 ]] ;;  # Check if stderr is a TTY
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
    [[ $target -ge $current ]]
}

_log_format() {
    local level="$1"
    local color="$2"
    local reset="$3"
    local message="$4"
    
    if [[ -n "$color" ]]; then
        printf '%b[%s]%b %s\n' "$color" "$level" "$reset" "$message"
    else
        printf '[%s] %s\n' "$level" "$message"
    fi
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
        [[ -n "$color" ]] && reset='\033[0m'
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
