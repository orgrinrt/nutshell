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
# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and so
# needs bash. Under a POSIX shell `nut_once` is not found and the `|| return 0`
# after it fires on every load: the module reports success and defines nothing,
# which is the quietest way a floor module can fail.
[ -n "${_NUTSHELL_VALIDATE_SH:-}" ] && return 0
_NUTSHELL_VALIDATE_SH=1

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
    [ -z "$varname" ] && return 1
    # The name reaches `eval`, so it is checked before it does. `${!name}` did
    # the indirection without one and POSIX has no equivalent; what POSIX has
    # is `eval`, and `eval` will run whatever it is handed. A shell variable
    # name is `[A-Za-z_][A-Za-z0-9_]*` and anything else is a caller passing a
    # command, so it answers no rather than running it.
    case "$varname" in
        ''|*[!A-Za-z0-9_]*|[0-9]*) return 1 ;;
    esac
    eval "[ -n \"\${${varname}+x}\" ] && [ -n \"\${${varname}}\" ]"
}

#[pub]
# Check if variable is unset or empty
# Usage: is_empty "varname" -> returns 0 (true) or 1 (false)
is_empty() {
    local varname="${1:-}"
    [ -z "$varname" ] && return 0
    # Validated for the same reason as `is_set`, and answering yes rather than
    # no: a name that cannot name a variable names no variable, and a variable
    # that does not exist is empty.
    case "$varname" in
        ''|*[!A-Za-z0-9_]*|[0-9]*) return 0 ;;
    esac
    eval "[ -z \"\${${varname}+x}\" ] || [ -z \"\${${varname}}\" ]"
}

# -----------------------------------------------------------------------------
# Command availability checks
# -----------------------------------------------------------------------------

#[pub]
#[allow(trivial_wrapper)]
# Check if a command is available
# Usage: has_command "git" -> returns 0 (true) or 1 (false)
has_command() {
    command -v "${1:-}" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# Type checks
# -----------------------------------------------------------------------------

#[pub]
# Check if value is an integer (positive or negative)
# Usage: is_integer "-42" -> returns 0 (true)
is_integer() {
    local val="${1:-}" d="${1:-}"
    case "$d" in -*) d="${d#-}" ;; esac
    case "$d" in ''|*[!0-9]*) return 1 ;; esac
    return 0
}

#[pub]
# Check if value is a positive integer (> 0)
# Usage: is_positive_integer "42" -> returns 0 (true)
is_positive_integer() {
    local val="${1:-}"
    case "$val" in ''|*[!0-9]*) return 1 ;; esac
    # Positive is "has a digit that is not zero", which needs no arithmetic and
    # so has no upper bound. `[ "$val" -gt 0 ]` on a twenty-digit number writes
    # `integer expected` to stderr and returns 2, and a validator whose whole
    # job is a quiet yes or no should not print on an input a caller handed it
    # precisely to be told about.
    case "$val" in *[1-9]*) return 0 ;; esac
    return 1
}

#[pub]
# Check if value is a non-negative integer (>= 0)
# Usage: is_non_negative_integer "0" -> returns 0 (true)
is_non_negative_integer() {
    local val="${1:-}"
    case "$val" in ''|*[!0-9]*) return 1 ;; esac
    return 0
}

#[pub]
# Check if value is a boolean (true/false/yes/no/1/0/on/off)
# Usage: is_boolean "yes" -> returns 0 (true)
is_boolean() {
    # Matched case-insensitively rather than lowercased first. `${val,,}` is a
    # bash expansion and a POSIX shell does not merely ignore it, it refuses to
    # run the file: `Bad substitution`, fatal, at the point of use. The
    # alternative that keeps one spelling is `tr`, which is a fork per call for
    # a set of eight words.
    case "${1:-}" in
        [Tt][Rr][Uu][Ee]|[Ff][Aa][Ll][Ss][Ee]) return 0 ;;
        [Yy][Ee][Ss]|[Nn][Oo]) return 0 ;;
        [Oo][Nn]|[Oo][Ff][Ff]) return 0 ;;
        1|0) return 0 ;;
        *) return 1 ;;
    esac
}

# Check if value is truthy (1/true/yes/on/y)
# Usage: is_truthy "yes" -> returns 0 (true)
#[pub]
is_truthy() {
    case "${1:-}" in
        1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]|[Yy]) return 0 ;;
        *) return 1 ;;
    esac
}

#[pub]
# Check if value is falsy (0/false/no/off/n/empty)
# Usage: is_falsy "no" -> returns 0 (true)
is_falsy() {
    case "${1:-}" in
        0|[Ff][Aa][Ll][Ss][Ee]|[Nn][Oo]|[Oo][Ff][Ff]|[Nn]|"") return 0 ;;
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
    case "$val" in
        http://?*|https://?*) ;;
        *) return 1 ;;
    esac
    # `[^[:space:]]+` in the old pattern. A tab counts, which is why this is
    # not a test for a plain space.
    case "$val" in *[[:space:]]*) return 1 ;; esac
    return 0
}

#[pub]
# Check if value looks like an email address
# Usage: is_email "user@example.com" -> returns 0 (true)
is_email() {
    local val="${1:-}"
    case "$val" in *@*) ;; *) return 1 ;; esac

    local local_part="${val%@*}" domain="${val##*@}"

    # More than one @, or nothing on one side of it.
    case "$local_part" in *@*) return 1 ;; esac
    [ -z "$local_part" ] && return 1
    [ -z "$domain" ] && return 1
    case "$local_part" in *[[:space:]]*) return 1 ;; esac

    # The domain is a hostname, judged by the one function that knows what one
    # is. The pattern this replaced matched `[^@[:space:]]+\.[^@[:space:]]+`,
    # which accepts `b..c`: a dot can sit inside either half, so an empty label
    # was invisible to it.
    case "$domain" in *.*) ;; *) return 1 ;; esac
    is_hostname "$domain"
}

#[pub]
# Check if value is a valid IPv4 address
# Usage: is_ipv4 "192.168.1.1" -> returns 0 (true)
is_ipv4() {
    local val="${1:-}" rest="${1:-}" octet n=0 more=1
    [ -n "$val" ] || return 1

    # Chopped on the dots rather than read into an array. `read -ra` needs an
    # array and a here-string and POSIX has neither, and splitting on `$IFS`
    # with `for` would also swallow an empty octet, which `1.2..3` needs kept
    # so it can be refused.
    while [ "$more" -eq 1 ]; do
        case "$rest" in
            *.*) octet="${rest%%.*}"; rest="${rest#*.}" ;;
            *)   octet="$rest"; more=0 ;;
        esac
        n=$(( n + 1 ))
        [ "$n" -gt 4 ] && return 1
        case "$octet" in ''|*[!0-9]*) return 1 ;; esac
        [ "$octet" -gt 255 ] && return 1
        # A leading zero is not a strict IP. `0` on its own is fine.
        case "$octet" in 0?*) return 1 ;; esac
    done
    [ "$n" -eq 4 ]
}

#[pub]
# Check if value is a valid IPv6 address (simplified check)
# Usage: is_ipv6 "::1" -> returns 0 (true)
is_ipv6() {
    local val="${1:-}"
    [ -z "$val" ] && return 1

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
    case "$val" in ::*) ;; :*) return 1 ;; esac
    case "$val" in *::) ;; *:) return 1 ;; esac

    # The IPv4-mapped form, `::ffff:192.168.1.1`. The dotted part is one
    # address occupying the last two groups.
    local mapped=0
    case "$val" in *.*)
        local quad="${val##*:}"
        is_ipv4 "$quad" || return 1
        val="${val%:*}:"
        mapped=2
        # Trimming left a trailing colon that is not `::`; put the shape back
        # so the rest reads it as a compression or as a separator.
        case "$val" in *::) ;; *) val="${val%:}" ;; esac
        ;;
    esac

    local head tail
    if case "$val" in *::*) true ;; *) false ;; esac; then
        # Once only. `1::2::3` says nothing about where the zeroes go.
        case "${val%%::*}" in *::*) return 1 ;; esac
        case "${val#*::}"  in *::*) return 1 ;; esac
        head="${val%%::*}"
        tail="${val#*::}"
    else
        head="$val"
        tail=""
        # No `::`, so every one of the eight has to be written.
        [ $(( $(_v6_count "$head") + mapped )) -eq 8 ] || return 1
        _v6_groups_ok "$head"
        return $?
    fi

    local n=$(( $(_v6_count "$head") + $(_v6_count "$tail") + mapped ))
    [ "$n" -le 7 ] || return 1
    _v6_groups_ok "$head" || return 1
    _v6_groups_ok "$tail"
}

# _v6_count <segment> -> how many colon-separated groups it holds
_v6_count() {
    [ -z "$1" ] && { printf '0'; return 0; }
    # Colons counted by walking them off the front. `${1//[^:]/}` deleted every
    # non-colon and measured what was left, which is bash's pattern
    # substitution and is fatal under a POSIX shell rather than ignored.
    local rest="$1" n=1
    while [ "${rest#*:}" != "$rest" ]; do
        n=$(( n + 1 ))
        rest="${rest#*:}"
    done
    printf '%d' "$n"
}

# _v6_groups_ok <segment> -> every group is one to four hex digits
_v6_groups_ok() {
    [ -z "$1" ] && return 0
    local group
    local IFS=':'
    for group in $1; do
        # `^[0-9a-fA-F]{1,4}$`: one to four hex digits, so the charset and the
        # length are two checks rather than one pattern.
        case "$group" in ''|*[!0-9a-fA-F]*) return 1 ;; esac
        [ "${#group}" -le 4 ] || return 1
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
    case "$val" in ''|*[!0-9]*) return 1 ;; esac

    # A leading zero is refused, which is a deliberate change and not what the
    # old code did. `[[ "$val" -ge 1 ]]` read a leading zero as octal, so `007`
    # was seven and passed while `08080` had no valid octal reading and failed
    # with a diagnostic. Neither answer was intended by anybody. Refusing both
    # is one rule, and it is the rule `is_ipv4` in this file already applies to
    # an octet.
    case "$val" in 0?*) return 1 ;; esac

    # Length before arithmetic, for the reason in `is_positive_integer`.
    [ "${#val}" -gt 5 ] && return 1
    [ "$val" -ge 1 ] && [ "$val" -le 65535 ]
}

#[pub]
# Check if value is a valid hostname
# Usage: is_hostname "example.com" -> returns 0 (true)
is_hostname() {
    local val="${1:-}"

    # Length first. The pattern alone accepts a single label of any length, so
    # a 300-character name passed, and a name that cannot be resolved is not a
    # hostname whatever it is made of. RFC 1035: 253 for the name, 63 a label.
    [ -z "$val" ] && return 1
    [ "${#val}" -gt 253 ] && return 1

    # The old pattern said the same thing about the whole name in one line, and
    # said it per label is what it amounts to: alphanumeric and hyphens, and
    # neither end a hyphen. Checked per label because the function was already
    # walking them for the length, and because a pattern that long is read by
    # nobody.
    #
    # `$val` unquoted with `IFS='.'` splits on dots, and a trailing dot yields
    # no final field, so `a.` and `example.com.` pass.
    #
    # That is a change and not an equivalence. The old pattern was anchored at
    # both ends, so a trailing dot failed it whatever the splitting loop saw:
    # `a.`, `a.b.`, `example.com.` and `a.b.c.` all went from no to yes. The
    # new answer is the better one, since a trailing dot is the fully-qualified
    # form and resolvers take it, but it is a decision rather than a tidy-up
    # and the tests below hold it.
    #
    # Everything else agrees. A leading dot, `..`, `a..b` and a bare `.` are
    # refused by both.
    local label first last
    local IFS='.'
    for label in $val; do
        [ "${#label}" -ge 1 ] && [ "${#label}" -le 63 ] || return 1
        case "$label" in *[!a-zA-Z0-9-]*) return 1 ;; esac
        first="${label%"${label#?}"}"
        last="${label#"${label%?}"}"
        case "$first" in *[!a-zA-Z0-9]*) return 1 ;; esac
        case "$last"  in *[!a-zA-Z0-9]*) return 1 ;; esac
    done
    return 0
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
    
    if [ ! -f "$path" ]; then
        log_fatal "$msg"
    fi
}

#[pub]
# Require directory to exist, exit with error if not
# Usage: require_dir "/path/to/dir" "Error message" -> prints nothing; does not return when absent, it exits
require_dir() {
    local path="${1:-}"
    local msg="${2:-Required directory '$path' not found}"
    
    if [ ! -d "$path" ]; then
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
    
    if [ -z "$val" ]; then
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
    
    if [ -z "$val" ]; then
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
    
    if [ ! -f "$path" ]; then
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
    
    if [ ! -d "$path" ]; then
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
