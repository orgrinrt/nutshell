#!/usr/bin/env bash
# =============================================================================
# nutshell/core/validate.sh - Input validation primitives
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): Depends on Layer -1 (log.sh)
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_VALIDATE_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_VALIDATE_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

_NUTSHELL_VALIDATE_DIR="${BASH_SOURCE[0]%/*}"
source "${_NUTSHELL_VALIDATE_DIR}/log.sh"

# -----------------------------------------------------------------------------
# Variable checks
# -----------------------------------------------------------------------------

# Check if variable is set and non-empty
# Usage: is_set "varname" -> returns 0 (true) or 1 (false)
is_set() {
    local varname="${1:-}"
    [[ -z "$varname" ]] && return 1
    [[ -n "${!varname+x}" ]] && [[ -n "${!varname}" ]]
}

# Check if variable is unset or empty
# Usage: is_empty "varname" -> returns 0 (true) or 1 (false)
is_empty() {
    local varname="${1:-}"
    [[ -z "$varname" ]] && return 0
    [[ -z "${!varname+x}" ]] || [[ -z "${!varname}" ]]
}

# -----------------------------------------------------------------------------
# Command availability checks
# -----------------------------------------------------------------------------

# Check if a command is available
# Usage: has_command "git" -> returns 0 (true) or 1 (false)
has_command() {
    command -v "${1:-}" &>/dev/null
}

# -----------------------------------------------------------------------------
# Type checks
# -----------------------------------------------------------------------------

# Check if value is an integer (positive or negative)
# Usage: is_integer "-42" -> returns 0 (true)
is_integer() {
    local val="${1:-}"
    [[ "$val" =~ ^-?[0-9]+$ ]]
}

# Check if value is a positive integer (> 0)
# Usage: is_positive_integer "42" -> returns 0 (true)
is_positive_integer() {
    local val="${1:-}"
    [[ "$val" =~ ^[0-9]+$ ]] && [[ "$val" -gt 0 ]]
}

# Check if value is a non-negative integer (>= 0)
# Usage: is_non_negative_integer "0" -> returns 0 (true)
is_non_negative_integer() {
    local val="${1:-}"
    [[ "$val" =~ ^[0-9]+$ ]]
}

# Check if value is a boolean (true/false/yes/no/1/0/on/off)
# Usage: is_boolean "yes" -> returns 0 (true)
is_boolean() {
    local val="${1:-}"
    local lower="${val,,}"
    case "$lower" in
        true|false|yes|no|1|0|on|off) return 0 ;;
        *) return 1 ;;
    esac
}

# Check if value is truthy (1/true/yes/on/y)
# Usage: is_truthy "yes" -> returns 0 (true)
is_truthy() {
    local val="${1:-}"
    local lower="${val,,}"
    case "$lower" in
        1|true|yes|on|y) return 0 ;;
        *) return 1 ;;
    esac
}

# Check if value is falsy (0/false/no/off/n/empty)
# Usage: is_falsy "no" -> returns 0 (true)
is_falsy() {
    local val="${1:-}"
    local lower="${val,,}"
    case "$lower" in
        0|false|no|off|n|"") return 0 ;;
        *) return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# Format checks
# -----------------------------------------------------------------------------

# Check if value is a valid URL (http/https)
# Usage: is_url "https://example.com" -> returns 0 (true)
is_url() {
    local val="${1:-}"
    [[ "$val" =~ ^https?://[^[:space:]]+$ ]]
}

# Check if value looks like an email address
# Usage: is_email "user@example.com" -> returns 0 (true)
is_email() {
    local val="${1:-}"
    [[ "$val" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]
}

# Check if value is a valid IPv4 address
# Usage: is_ipv4 "192.168.1.1" -> returns 0 (true)
is_ipv4() {
    local val="${1:-}"
    local IFS='.'
    local -a octets
    read -ra octets <<< "$val"
    
    [[ ${#octets[@]} -ne 4 ]] && return 1
    
    local octet
    for octet in "${octets[@]}"; do
        [[ ! "$octet" =~ ^[0-9]+$ ]] && return 1
        [[ "$octet" -lt 0 || "$octet" -gt 255 ]] && return 1
        # Check for leading zeros (invalid in strict IP)
        [[ "${#octet}" -gt 1 && "${octet:0:1}" == "0" ]] && return 1
    done
    return 0
}

# Check if value is a valid IPv6 address (simplified check)
# Usage: is_ipv6 "::1" -> returns 0 (true)
is_ipv6() {
    local val="${1:-}"
    [[ "$val" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]] || \
    [[ "$val" =~ ^::$ ]] || \
    [[ "$val" =~ ^::1$ ]] || \
    [[ "$val" =~ ^[0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4}){7}$ ]]
}

# Check if value is a valid IP address (v4 or v6)
# Usage: is_ip "192.168.1.1" -> returns 0 (true)
is_ip() {
    local val="${1:-}"
    is_ipv4 "$val" || is_ipv6 "$val"
}

# Check if value is a valid port number (1-65535)
# Usage: is_port "8080" -> returns 0 (true)
is_port() {
    local val="${1:-}"
    [[ "$val" =~ ^[0-9]+$ ]] && [[ "$val" -ge 1 ]] && [[ "$val" -le 65535 ]]
}

# Check if value is a valid hostname
# Usage: is_hostname "example.com" -> returns 0 (true)
is_hostname() {
    local val="${1:-}"
    # Allow alphanumeric, hyphens, and dots; no leading/trailing hyphens per label
    [[ "$val" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]
}

# -----------------------------------------------------------------------------
# Require functions (hard fail - exit on failure)
# Use these when the condition is absolutely required and there's no recovery.
# -----------------------------------------------------------------------------

# Require variable to be set, exit with error if not
# Usage: require_set "VAR_NAME" "Error message"
require_set() {
    local varname="${1:-}"
    local msg="${2:-Required variable '$varname' is not set}"
    
    if ! is_set "$varname"; then
        log_fatal "$msg"
    fi
}

# Require file to exist, exit with error if not
# Usage: require_file "/path/to/file" "Error message"
require_file() {
    local path="${1:-}"
    local msg="${2:-Required file '$path' not found}"
    
    if [[ ! -f "$path" ]]; then
        log_fatal "$msg"
    fi
}

# Require directory to exist, exit with error if not
# Usage: require_dir "/path/to/dir" "Error message"
require_dir() {
    local path="${1:-}"
    local msg="${2:-Required directory '$path' not found}"
    
    if [[ ! -d "$path" ]]; then
        log_fatal "$msg"
    fi
}

# Require command to be available, exit with error if not
# Usage: require_command "git" "Git is required"
require_command() {
    local cmd="${1:-}"
    local msg="${2:-Required command '$cmd' not found}"
    
    if ! has_command "$cmd"; then
        log_fatal "$msg"
    fi
}

# Require value to be non-empty, exit with error if empty
# Usage: require_value "$value" "Value cannot be empty"
require_value() {
    local val="${1:-}"
    local msg="${2:-Value cannot be empty}"
    
    if [[ -z "$val" ]]; then
        log_fatal "$msg"
    fi
}

# -----------------------------------------------------------------------------
# Ensure functions (soft fail - log warning, return status)
# Use these when you want to check and handle the failure yourself.
# -----------------------------------------------------------------------------

# Ensure variable is set, return 1 if not (caller handles failure)
# Usage: ensure_set "VAR_NAME" "Error message" || handle_missing_var
ensure_set() {
    local varname="${1:-}"
    local msg="${2:-Variable '$varname' is not set}"
    
    if ! is_set "$varname"; then
        log_warn "$msg"
        return 1
    fi
    return 0
}

# Ensure value is non-empty, return 1 if empty (caller handles failure)
# Usage: ensure_value "$value" "Error message" || handle_empty
ensure_value() {
    local val="${1:-}"
    local msg="${2:-Value is empty}"
    
    if [[ -z "$val" ]]; then
        log_warn "$msg"
        return 1
    fi
    return 0
}

# Ensure file exists, return 1 if not (caller handles failure)
# Usage: ensure_file "/path/to/file" "Error message" || handle_missing
ensure_file() {
    local path="${1:-}"
    local msg="${2:-File '$path' not found}"
    
    if [[ ! -f "$path" ]]; then
        log_warn "$msg"
        return 1
    fi
    return 0
}

# Ensure directory exists, return 1 if not (caller handles failure)
# Usage: ensure_dir "/path/to/dir" "Error message" || handle_missing
ensure_dir() {
    local path="${1:-}"
    local msg="${2:-Directory '$path' not found}"
    
    if [[ ! -d "$path" ]]; then
        log_warn "$msg"
        return 1
    fi
    return 0
}

# Ensure command is available, return 1 if not (caller handles failure)
# Usage: ensure_command "git" "Git not found" || handle_missing
ensure_command() {
    local cmd="${1:-}"
    local msg="${2:-Command '$cmd' not found}"
    
    if ! has_command "$cmd"; then
        log_warn "$msg"
        return 1
    fi
    return 0
}
