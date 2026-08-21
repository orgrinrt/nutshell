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
nut_once || return 0

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

# Declared, not sourced by path. A hand-rolled `source` loads the module and
# hides it from the module-contract check, which reads `use` lines, so the
# dependency was real and unrecorded at once.
use log

# -----------------------------------------------------------------------------
# Variable checks
# -----------------------------------------------------------------------------

#[pub]
# Check if variable is set and non-empty
#
# The NAME of a variable, not its value. `is_set "$x"` asks about a variable
# named after the contents of x, which is almost never set, so it answers no
# whatever x holds. The same goes for `is_empty`.
#
# Usage: is_set "varname" -> returns 0 (true) or 1 (false)
is_set() {
    local varname="${1:-}"
    [[ -z "$varname" ]] && return 1
    [[ -n "${!varname+x}" ]] && [[ -n "${!varname}" ]]
}

#[pub]
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

#[pub]
#[allow(trivial_wrapper)]
# Check if a command is available
# Usage: has_command "git" -> returns 0 (true) or 1 (false)
has_command() {
    command -v "${1:-}" &>/dev/null
}

# -----------------------------------------------------------------------------
# Type checks
# -----------------------------------------------------------------------------

#[pub]
# Check if value is an integer (positive or negative)
# Usage: is_integer "-42" -> returns 0 (true)
is_integer() {
    local val="${1:-}"
    [[ "$val" =~ ^-?[0-9]+$ ]]
}

#[pub]
# Check if value is a positive integer (> 0)
# Usage: is_positive_integer "42" -> returns 0 (true)
is_positive_integer() {
    local val="${1:-}"
    [[ "$val" =~ ^[0-9]+$ ]] && [[ "$val" -gt 0 ]]
}

#[pub]
# Check if value is a non-negative integer (>= 0)
# Usage: is_non_negative_integer "0" -> returns 0 (true)
is_non_negative_integer() {
    local val="${1:-}"
    [[ "$val" =~ ^[0-9]+$ ]]
}

#[pub]
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
#[pub]
is_truthy() {
    local val="${1:-}"
    local lower="${val,,}"
    case "$lower" in
        1|true|yes|on|y) return 0 ;;
        *) return 1 ;;
    esac
}

#[pub]
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

#[pub]
# Check if value is a valid URL (http/https)
# Usage: is_url "https://example.com" -> returns 0 (true)
is_url() {
    local val="${1:-}"
    [[ "$val" =~ ^https?://[^[:space:]]+$ ]]
}

#[pub]
# Check if value looks like an email address
# Usage: is_email "user@example.com" -> returns 0 (true)
is_email() {
    local val="${1:-}"
    [[ "$val" == *@* ]] || return 1

    local local_part="${val%@*}" domain="${val##*@}"

    # More than one @, or nothing on one side of it.
    [[ "$local_part" == *@* ]] && return 1
    [[ -z "$local_part" || -z "$domain" ]] && return 1
    [[ "$local_part" == *[[:space:]]* ]] && return 1

    # The domain is a hostname, judged by the one function that knows what one
    # is. The pattern this replaced matched `[^@[:space:]]+\.[^@[:space:]]+`,
    # which accepts `b..c`: a dot can sit inside either half, so an empty label
    # was invisible to it.
    [[ "$domain" == *.* ]] || return 1
    is_hostname "$domain"
}

#[pub]
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

#[pub]
# Check if value is a valid IPv6 address (simplified check)
# Usage: is_ipv6 "::1" -> returns 0 (true)
is_ipv6() {
    local val="${1:-}"
    [[ -z "$val" ]] && return 1

    # Counted, not pattern-matched. The pattern this replaced allowed a group
    # of zero to four hex digits anywhere, which accepts `:::::` and `1:2:3`:
    # any run of colons matched, because every group between them was allowed
    # to be empty.
    #
    # An address is eight groups. `::` stands for a run of all-zero groups and
    # may appear once, so with it there are at most seven written groups and
    # without it exactly eight.
    # A single colon at either end is not an address. Word splitting drops a
    # trailing empty field while the count keeps it, so `1:2:3:4:5:6:7:` came
    # out as eight groups with seven of them checked, and `::1:` and `1::2:3:`
    # went the same way. Checked here rather than left to the split.
    [[ "$val" == :* && "$val" != ::* ]] && return 1
    [[ "$val" == *: && "$val" != *:: ]] && return 1

    # The IPv4-mapped form, `::ffff:192.168.1.1`. The dotted part is one
    # address occupying the last two groups.
    local mapped=0
    if [[ "$val" == *.* ]]; then
        local quad="${val##*:}"
        is_ipv4 "$quad" || return 1
        val="${val%:*}:"
        mapped=2
        # Trimming left a trailing colon that is not `::`; put the shape back
        # so the rest reads it as a compression or as a separator.
        [[ "$val" == *:: ]] || val="${val%:}"
    fi

    local head tail
    if [[ "$val" == *::* ]]; then
        # Once only. `1::2::3` says nothing about where the zeroes go.
        [[ "${val%%::*}" == *::* || "${val#*::}" == *::* ]] && return 1
        head="${val%%::*}"
        tail="${val#*::}"
    else
        head="$val"
        tail=""
        # No `::`, so every one of the eight has to be written.
        [[ $(( $(_v6_count "$head") + mapped )) -eq 8 ]] || return 1
        _v6_groups_ok "$head"
        return $?
    fi

    local n=$(( $(_v6_count "$head") + $(_v6_count "$tail") + mapped ))
    [[ "$n" -le 7 ]] || return 1
    _v6_groups_ok "$head" || return 1
    _v6_groups_ok "$tail"
}

# _v6_count <segment> -> how many colon-separated groups it holds
_v6_count() {
    [[ -z "$1" ]] && { printf '0'; return 0; }
    local rest="${1//[^:]/}"
    printf '%d' $(( ${#rest} + 1 ))
}

# _v6_groups_ok <segment> -> every group is one to four hex digits
_v6_groups_ok() {
    [[ -z "$1" ]] && return 0
    local group
    local IFS=':'
    for group in $1; do
        [[ "$group" =~ ^[0-9a-fA-F]{1,4}$ ]] || return 1
    done
    return 0
}

#[pub]
# Check if value is a valid IP address (v4 or v6)
# Usage: is_ip "192.168.1.1" -> returns 0 (true)
is_ip() {
    local val="${1:-}"
    is_ipv4 "$val" || is_ipv6 "$val"
}

#[pub]
# Check if value is a valid port number (1-65535)
# Usage: is_port "8080" -> returns 0 (true)
is_port() {
    local val="${1:-}"
    [[ "$val" =~ ^[0-9]+$ ]] && [[ "$val" -ge 1 ]] && [[ "$val" -le 65535 ]]
}

#[pub]
# Check if value is a valid hostname
# Usage: is_hostname "example.com" -> returns 0 (true)
is_hostname() {
    local val="${1:-}"

    # Length first. The pattern alone accepts a single label of any length, so
    # a 300-character name passed, and a name that cannot be resolved is not a
    # hostname whatever it is made of. RFC 1035: 253 for the name, 63 a label.
    [[ -z "$val" || "${#val}" -gt 253 ]] && return 1

    local label
    local IFS='.'
    for label in $val; do
        [[ "${#label}" -ge 1 && "${#label}" -le 63 ]] || return 1
    done

    # Alphanumeric and hyphens, no label starting or ending on a hyphen.
    [[ "$val" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]
}

# -----------------------------------------------------------------------------
# Require functions (hard fail - exit on failure)
# Use these when the condition is absolutely required and there's no recovery.
# -----------------------------------------------------------------------------

# Require variable to be set, exit with error if not
# Usage: require_set "VAR_NAME" "Error message" -> prints nothing; does not return when unset, it exits
#[pub]
require_set() {
    local varname="${1:-}"
    local msg="${2:-Required variable '$varname' is not set}"
    
    if ! is_set "$varname"; then
        log_fatal "$msg"
    fi
}

#[pub]
# Require file to exist, exit with error if not
# Usage: require_file "/path/to/file" "Error message" -> prints nothing; does not return when absent, it exits
require_file() {
    local path="${1:-}"
    local msg="${2:-Required file '$path' not found}"
    
    if [[ ! -f "$path" ]]; then
        log_fatal "$msg"
    fi
}

#[pub]
# Require directory to exist, exit with error if not
# Usage: require_dir "/path/to/dir" "Error message" -> prints nothing; does not return when absent, it exits
require_dir() {
    local path="${1:-}"
    local msg="${2:-Required directory '$path' not found}"
    
    if [[ ! -d "$path" ]]; then
        log_fatal "$msg"
    fi
}

# Require command to be available, exit with error if not
# Usage: require_command "git" "Git is required" -> prints nothing; does not return when the tool is missing, it exits
#[pub]
require_command() {
    local cmd="${1:-}"
    local msg="${2:-Required command '$cmd' not found}"
    
    if ! has_command "$cmd"; then
        log_fatal "$msg"
    fi
}

#[pub]
# Require value to be non-empty, exit with error if empty
# Usage: require_value "$value" "Value cannot be empty" -> prints nothing; does not return when empty, it exits
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
# Usage: ensure_set "VAR_NAME" "Error message" || handle_missing_var -> returns 0 when set, warns and returns 1 when not
#[pub]
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
# Usage: ensure_value "$value" "Error message" || handle_empty -> returns 0 when non-empty, warns and returns 1 when empty
#[pub]
ensure_value() {
    local val="${1:-}"
    local msg="${2:-Value is empty}"
    
    if [[ -z "$val" ]]; then
        log_warn "$msg"
        return 1
    fi
    return 0
}

#[pub]
# Ensure file exists, return 1 if not (caller handles failure)
# Usage: ensure_file "/path/to/file" "Error message" || handle_missing -> returns 0 when the file is there, warns and returns 1 when not
ensure_file() {
    local path="${1:-}"
    local msg="${2:-File '$path' not found}"
    
    if [[ ! -f "$path" ]]; then
        log_warn "$msg"
        return 1
    fi
    return 0
}

#[pub]
# Ensure directory exists, return 1 if not (caller handles failure)
# Usage: ensure_dir "/path/to/dir" "Error message" || handle_missing -> returns 0 when the directory is there, warns and returns 1 when not
ensure_dir() {
    local path="${1:-}"
    local msg="${2:-Directory '$path' not found}"
    
    if [[ ! -d "$path" ]]; then
        log_warn "$msg"
        return 1
    fi
    return 0
}

#[pub]
# Ensure command is available, return 1 if not (caller handles failure)
# Usage: ensure_command "git" "Git not found" || handle_missing -> returns 0 when the tool is on PATH, warns and returns 1 when not
ensure_command() {
    local cmd="${1:-}"
    local msg="${2:-Command '$cmd' not found}"
    
    if ! has_command "$cmd"; then
        log_warn "$msg"
        return 1
    fi
    return 0
}
