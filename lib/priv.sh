#!/usr/bin/env bash
# =============================================================================
# nutshell/priv.sh - Doing one thing as root, and then not being root
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Elevation is a step, not a mode. `priv_run` takes one command, runs that as
# root, and returns with the caller unchanged. Nothing else in the process
# becomes root and nothing after it is.
#
# The failure this exists to prevent is quiet and it is not one tool's. A
# program that needs root for one thing, gets it by being started under `sudo`,
# and then keeps going writes the user's own files as root: their state
# directory, their cache, their config, their history. It happened here. One
# tool ended up with two journals, `~/.local/state/<tool>/journal` owned by the
# person and a second one owned by root, and the person could no longer write
# the second.
#
# Running a whole program under `sudo` is `su` with extra steps. This is the
# other thing, the one the name always meant: do this, as root, now.
#
# Usage:
#   use priv
#
#   priv_run "mount the stick" mount /dev/sda2 /mnt/stick || return 1
#
#   # Where a path belongs to the person, ask rather than reading $HOME.
#   printf '%s/.local/state\n' "$(priv_user_home)"
# =============================================================================

nut_once || return 0

use log

# Who this actually is, worked out once and before anything elevates.
#
# Read at load time on purpose. A caller asking later, from inside something
# that has already elevated, would be told about root, and the whole point is
# to answer about the person.
declare -g PRIV_USER="${PRIV_USER:-}"
declare -g PRIV_HOME="${PRIV_HOME:-}"
declare -g PRIV_UID="${PRIV_UID:-}"

_priv_learn_user() {
    [[ -z "$PRIV_UID" ]] || return 0

    # `SUDO_USER` is set when this process was itself started under sudo, and
    # then it names the person rather than root. That case is the one this
    # module is trying to make unnecessary, and it still has to be answered
    # correctly while it exists.
    if [[ "$(id -u 2>/dev/null)" == "0" && -n "${SUDO_USER:-}" ]]; then
        PRIV_USER="$SUDO_USER"
        PRIV_UID="${SUDO_UID:-}"
        [[ -n "$PRIV_UID" ]] || PRIV_UID="$(id -u "$PRIV_USER" 2>/dev/null)"
        PRIV_HOME="$(_priv_home_of "$PRIV_USER")"
        return 0
    fi

    PRIV_USER="$(id -un 2>/dev/null)"
    PRIV_UID="$(id -u 2>/dev/null)"
    PRIV_HOME="${HOME:-$(_priv_home_of "$PRIV_USER")}"
}

# A user's home from the password database rather than from the environment,
# because the environment is what is wrong in the case this is for.
_priv_home_of() {
    # Initialised, not merely declared: `local x` leaves it unset, and a caller
    # running under `set -u` gets an error rather than an empty string.
    local u="$1" line=""
    [[ -n "$u" ]] || return 1
    if command -v getent >/dev/null 2>&1; then
        line="$(getent passwd "$u" 2>/dev/null)" || line=""
    fi
    if [[ -z "$line" && -r /etc/passwd ]]; then
        while IFS= read -r line; do
            [[ "$line" == "${u}:"* ]] && break
            line=""
        done < /etc/passwd
    fi
    if [[ -n "$line" ]]; then
        # name:passwd:uid:gid:gecos:home:shell
        local IFS=:
        # shellcheck disable=SC2206
        local -a f=($line)
        [[ -n "${f[5]:-}" ]] && { printf '%s' "${f[5]}"; return 0; }
    fi
    # A mac keeps its users elsewhere, and `dscl` is how you ask.
    if command -v dscl >/dev/null 2>&1; then
        local h; h="$(dscl . -read "/Users/${u}" NFSHomeDirectory 2>/dev/null)" || h=""
        h="${h#*: }"
        [[ -n "$h" ]] && { printf '%s' "$h"; return 0; }
    fi
    return 1
}

_priv_learn_user

#[pub]
# The person who started this, whatever has elevated since.
# Usage: priv_user -> a name
priv_user() { _priv_learn_user; printf '%s' "$PRIV_USER"; }
#[pub]
# Usage: priv_uid -> a number
priv_uid()  { _priv_learn_user; printf '%s' "$PRIV_UID"; }
#[pub]
# Their home, from the password database rather than from `$HOME`.
#
# `$HOME` is exactly what is wrong inside something that elevated, so anything
# building a path the person will look for asks this instead.
# Usage: priv_user_home -> a path
priv_user_home() { _priv_learn_user; printf '%s' "$PRIV_HOME"; }

# One argument, quoted so any POSIX shell reads it back as itself.
#
# Not `printf %q`. That emits bash's ANSI-C form for anything holding a tab, a
# newline or a control character, and `$'...'` is a bashism: dash, which is
# `/bin/sh` on Debian and Ubuntu, reads `$'\t'` as the four characters and the
# path arrives silently wrong. This function's whole job is writing a person's
# files as that person, so a mangled path is root writing somewhere nobody
# asked it to.
#
# Single quotes take everything literally, so the only character needing work
# is the single quote itself: close, escape it outside the quotes, reopen.
_priv_sq() {
    local s="${1:-}"
    printf "'%s'" "${s//\'/\'\\\'\'}"
}

#[pub]
# Run one step as the person, from inside something that elevated.
#
# The other direction from `priv_run`, and the half that stops root's
# fingerprints ending up on a person's files. `priv_return` repairs ownership
# after the fact; this never creates the problem. Prefer it: a chown pass has
# to be told every path, and the one it was not told about is the one nobody
# notices.
#
# The cases that need it are the ones where the tool is root because some other
# step needed root, and this step does not: git in somebody's checkout, a file
# written into their home, anything reading their configuration.
#
# A no-op when not root, and a no-op when the person is root, so a caller does
# not have to ask which it is.
# Usage: priv_as_user "reading your checkout" git -C "$d" status
priv_as_user() {
    local what="${1:-a step}"; shift || true
    (( $# > 0 )) || { log_error "priv_as_user: nothing to run"; return 2; }

    local u; u="$(priv_user)"
    if ! priv_is_root || [[ -z "$u" || "$u" == "root" ]]; then
        "$@"
        return $?
    fi

    local c
    for c in runuser sudo su; do
        command -v "$c" >/dev/null 2>&1 || continue
        case "$c" in
            # runuser is the one built for this: root to another user, no
            # password, no login shell in the way.
            runuser) runuser -u "$u" -- "$@"; return $? ;;
            sudo)    sudo -n -u "$u" -- "$@"; return $? ;;
            # Last, and through a shell, so the arguments have to be quoted
            # back into one string. Every other route avoids that.
            su)
                local q="" a
                for a in "$@"; do q+="${q:+ }$(_priv_sq "$a")"; done
                # No `-s`. That flag is util-linux; BSD and macOS `su` is
                # `su [-] [-flm] [login [args]]` and refuses it, and this is
                # the branch a busybox rescue console actually takes.
                su "$u" -c "$q"
                return $?
                ;;
        esac
    done

    log_error "${what}: cannot step down to ${u}; there is no runuser, sudo or su"
    return 2
}

#[pub]
# Is this already root?
# Usage: priv_is_root
priv_is_root() { [[ "$(id -u 2>/dev/null)" == "0" ]]; }

#[pub]
# Can this ask for root at all, and how?
#
# Prints the command that would do it, or nothing. `doas` as well as `sudo`,
# because a machine that has chosen one usually does not have the other.
# Usage: priv_how -> "sudo", "doas", or nothing
priv_how() {
    priv_is_root && { printf 'already'; return 0; }
    local c
    for c in sudo doas; do
        command -v "$c" >/dev/null 2>&1 && { printf '%s' "$c"; return 0; }
    done
    return 1
}

#[pub]
# Would asking for root need a password right now?
#
# Answers without asking for one. A caller that wants to warn before a prompt
# appears, or to decide whether an unattended run can proceed, asks this.
# Usage: priv_needs_password
priv_needs_password() {
    priv_is_root && return 1
    local how; how="$(priv_how)" || return 0
    case "$how" in
        sudo) sudo -n true 2>/dev/null && return 1 ;;
        doas) doas -n true 2>/dev/null && return 1 ;;
    esac
    return 0
}

#[pub]
# Run one command as root, then return.
#
# The first argument says what it is for, in words, so the log and the prompt
# both name the thing rather than the mechanism. Everything after it is the
# command and its arguments, passed through without a shell, so nothing here
# has to think about quoting and a caller cannot accidentally build one string
# out of a path with a space in it.
#
# Returns whatever the command returned. Refuses, without running anything,
# when there is no way to elevate, or when a password would be needed and
# there is no terminal to type it on: a prompt nobody can answer is a program
# that hangs, and the machines this runs on are often being fixed over a pipe.
# Usage: priv_run "mount the stick" mount /dev/sda2 /mnt
priv_run() {
    local what="${1:-a privileged step}"; shift || true
    (( $# > 0 )) || { log_error "priv_run: nothing to run"; return 2; }

    if priv_is_root; then
        "$@"
        return $?
    fi

    local how
    how="$(priv_how)" || {
        log_error "${what}: this needs root and there is no sudo or doas here"
        return 2
    }

    if priv_needs_password && ! _priv_can_prompt; then
        log_error "${what}: this needs root, and there is no terminal to ask for a password on"
        return 2
    fi

    # Said before the prompt appears, so an unexpected password request has a
    # sentence beside it explaining what asked for it.
    if priv_needs_password; then
        log_info "${what}: asking for your password for this one step"
    fi

    case "$how" in
        sudo) sudo -- "$@" ;;
        doas) doas -- "$@" ;;
        *)    "$@" ;;
    esac
}

# Is there a terminal a password could be typed on?
_priv_can_prompt() {
    [[ -t 0 || -t 1 || -t 2 ]] && return 0
    # An askpass helper is a terminal by another name.
    [[ -n "${SUDO_ASKPASS:-}" ]] && return 0
    return 1
}

#[pub]
# Give a file back to the person after something elevated made it.
#
# The other half of the split this module is about. A file root wrote into a
# place the person owns is a file they cannot change afterwards, and the
# symptom arrives much later than the cause.
# Usage: priv_return <path>...
priv_return() {
    local u; u="$(priv_user)"
    [[ -n "$u" && "$u" != "root" ]] || return 0
    priv_is_root || return 0
    local p
    for p in "$@"; do
        [[ -e "$p" ]] || continue
        chown -R "$u" "$p" 2>/dev/null || true
    done
}
