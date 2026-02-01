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
[[ -n "${_NUTSHELL_CORE_LOG_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_LOG_SH=1

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

log_debug() {
    _log_should_emit debug || return 0
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;37m'  # White/gray
        reset='\033[0m'
    fi
    _log_format "DEBUG" "$color" "$reset" "$*" >&2
}

log_info() {
    _log_should_emit info || return 0
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;34m'  # Blue
        reset='\033[0m'
    fi
    _log_format "INFO" "$color" "$reset" "$*"
}

log_warn() {
    _log_should_emit warn || return 0
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;33m'  # Yellow
        reset='\033[0m'
    fi
    _log_format "WARN" "$color" "$reset" "$*" >&2
}

log_error() {
    _log_should_emit error || return 0
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;31m'  # Red
        reset='\033[0m'
    fi
    _log_format "ERROR" "$color" "$reset" "$*" >&2
}

log_success() {
    _log_should_emit info || return 0
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;32m'  # Green
        reset='\033[0m'
    fi
    _log_format "OK" "$color" "$reset" "$*"
}

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

log_substep() {
    _log_should_emit info || return 0
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;35m'  # Magenta
        reset='\033[0m'
    fi
    printf '    %b→%b %s\n' "$color" "$reset" "$*"
}

log_fatal() {
    local color="" reset=""
    if _log_should_color; then
        color='\033[0;31m'  # Red
        reset='\033[0m'
    fi
    _log_format "FATAL" "$color" "$reset" "$*" >&2
    exit 1
}
