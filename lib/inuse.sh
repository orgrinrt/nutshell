#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/inuse.sh - Which cached paths a live process is reading
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The store is shared by every project on the machine, so at any moment one
# process may be reading a directory another has decided to update. Nothing
# coordinated the two, and the failure was not a missing file: a dependency is
# laid out as a git worktree, so removing or rewriting the mirror makes every
# checkout on it read as not-a-repo while its files sit there intact, and the
# next resolver deletes it as wreckage.
#
# What that looked like from outside was a suite reporting a couple of hundred
# failures once in a while, in modules that were on disk the whole time.
#
# So: a path is marked while it is being read, an update waits for the marks to
# clear, and an update marks the path itself while it runs, so the same
# mechanism answers both directions and a half-written directory is never handed
# to a reader.
#
# Usage:
#   use inuse
#
#   inuse_hold "$dir" || return 1     # marks, and arranges its own release
#   inuse_release "$dir"              # or release it early
#
#   inuse_wait "$dir" 30 || return 1  # until nobody else holds it
#   inuse_holders "$dir"              # the live pids, one per line
#
# The mark is a file per holder, named for the pid, under one directory per
# held path. A holder that died leaves its file behind and is ignored: the
# question asked is whether the pid is alive, never whether the file exists.
# That is what makes this safe to leave lying around, and it is why there is no
# separate reaper.
# =============================================================================

[ -n "${_NUTSHELL_INUSE_SH:-}" ] && return 0
_NUTSHELL_INUSE_SH=1

use fs xdg

# Where the marks live. Beside the store rather than inside a cache, because a
# mark surviving a cache wipe is harmless and a mark being wiped mid-read is
# the thing this exists to prevent.
_inuse_root() {
    if [ -n "${NUTSHELL_INUSE_ROOT:-}" ]; then
        printf '%s' "${NUTSHELL_INUSE_ROOT%/}"
        return 0
    fi
    if [ -n "${NUTSHELL_STORE:-}" ]; then
        printf '%s/.inuse' "${NUTSHELL_STORE%/}"
        return 0
    fi
    xdg_set_app_name nutshell
    printf '%s/.inuse' "$(xdg_app_data)"
}

# A path becomes a directory name. Hex rather than a hash, so a mark can be
# read back to the path it is about when somebody is looking at the store by
# hand and wondering what is holding what.
_inuse_key() {
    nut_key "$1" || return 1
    printf '%s' "$_nk"
}

# `$BASHPID`, not `$$`, and expanded in place rather than through a helper.
#
# `$$` in a subshell is the parent's pid, so a mark naming it outlives the
# process that took it: it never clears, and every update then waits out its
# full timeout before proceeding anyway.
#
# And a helper does not work here even with `$BASHPID` in it, which is how this
# was first written. Calling it as `$(_inuse_pid)` runs it in a subshell with a
# `BASHPID` of its own, so the mark was named for a process that was already
# gone by the time the next line read it. The hold reported success and the
# holder list came back empty. So this is a variable, not a function, and it is
# read where it is used.
_inuse_pid_of_this_shell() {
    _INUSE_PID="${BASHPID:-$$}"
}

#[pub]
# The live processes holding that path, one pid per line.
#
# A mark whose pid is gone is swept as it is found. Nothing else sweeps, and
# nothing needs to: the answer is about liveness, so a stale file can only ever
# cost the read that noticed it.
# Usage: inuse_holders <dir> -> prints pids, none when free
inuse_holders() {
    local d k f pid
    k="$(_inuse_key "$1")" || return 1
    d="$(_inuse_root)/$k"
    [ -d "$d" ] || return 0
    for f in "$d"/*; do
        [ -e "$f" ] || continue
        pid="${f##*/}"
        case "$pid" in ''|*[!0-9]*) continue ;; esac
        if kill -0 "$pid" 2>/dev/null; then
            printf '%s\n' "$pid"
        else
            rm -f "$f" 2>/dev/null
        fi
    done
}

#[pub]
# Whether anybody other than this process is holding that path.
# Usage: inuse_held_by_other <dir> -> 0 when somebody else holds it
inuse_held_by_other() {
    local other
    _inuse_pid_of_this_shell
    local mine="$_INUSE_PID"
    while IFS= read -r other; do
        [ -n "$other" ] || continue
        [ "$other" = "$mine" ] || return 0
    done <<EOF
$(inuse_holders "$1")
EOF
    return 1
}

#[pub]
# Mark that path as being read by this process.
#
# The caller does not have to remember to release: an `EXIT` trap is installed
# once per shell and releases everything this process still holds. It composes
# with a trap the caller already set, because it appends rather than replacing,
# which is the one thing a trap helper has to get right.
# Usage: inuse_hold <dir> -> 0 when marked
inuse_hold() {
    local d k
    k="$(_inuse_key "$1")" || return 1
    d="$(_inuse_root)/$k"
    fs_mkdir "$d" 2>/dev/null || return 1
    printf '%s\n' "$1" > "$d/.path" 2>/dev/null
    _inuse_pid_of_this_shell
    : > "$d/$_INUSE_PID" 2>/dev/null || return 1
    _INUSE_HELD="${_INUSE_HELD:-}${_INUSE_HELD:+$'\n'}$1"
    _inuse_arm_trap
    return 0
}

#[pub]
# Mark that path as in use by the whole session, rather than by this shell.
#
# The two are genuinely different marks and the difference is which process is
# still reading when the mutation wants to happen.
#
# A **mutator** holds with `inuse_hold`, which uses `$BASHPID`: the worker doing
# the writing is the thing whose liveness matters, and when it dies the mark
# must clear at once.
#
# A **reader** holds with this, which uses `$$`. Module resolution runs inside a
# command substitution, so `$BASHPID` there names a shell that exits a
# microsecond later while the script that asked goes on sourcing files for
# minutes. `$$` inside a substitution is the parent, which is exactly the
# process that keeps reading.
#
# And this needs no trap. The mark clears when the pid stops being alive, which
# `inuse_holders` checks on every read, so a session that dies in any way at all
# releases without having arranged anything.
# Usage: inuse_hold_session <dir> -> 0 when marked
inuse_hold_session() {
    local d k
    k="$(_inuse_key "$1")" || return 1
    d="$(_inuse_root)/$k"
    fs_mkdir "$d" 2>/dev/null || return 1
    printf '%s\n' "$1" > "$d/.path" 2>/dev/null
    : > "$d/$$" 2>/dev/null || return 1
    return 0
}

#[pub]
# Drop this process's mark on that path.
# Usage: inuse_release <dir>
inuse_release() {
    local d k kept line
    k="$(_inuse_key "$1")" || return 1
    d="$(_inuse_root)/$k"
    _inuse_pid_of_this_shell
    rm -f "$d/$_INUSE_PID" 2>/dev/null
    # Leave the directory when somebody else is still in it, take it away when
    # nobody is. `rmdir` rather than `rm -rf`, so a directory that is not empty
    # because another process just arrived is left alone rather than deleted
    # from under it.
    rm -f "$d/.path" 2>/dev/null
    rmdir "$d" 2>/dev/null || printf '%s\n' "$1" > "$d/.path" 2>/dev/null
    kept=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        [ "$line" = "$1" ] && continue
        kept="${kept}${kept:+$'\n'}${line}"
    done <<EOF
${_INUSE_HELD:-}
EOF
    _INUSE_HELD="$kept"
    return 0
}

_inuse_release_all() {
    local line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        inuse_release "$line"
    done <<EOF
${_INUSE_HELD:-}
EOF
    _INUSE_HELD=""
}

# Appended, never assigned. A helper that overwrites the caller's EXIT trap is
# how a tool loses its own cleanup, and this one is installed from inside a
# library the caller did not think about.
_inuse_arm_trap() {
    [ -n "${_INUSE_TRAP_ARMED:-}" ] && return 0
    _INUSE_TRAP_ARMED=1
    local prev
    prev="$(trap -p EXIT 2>/dev/null | sed "s/^trap -- '//; s/' EXIT\$//")"
    if [ -n "$prev" ]; then
        # shellcheck disable=SC2064
        trap "_inuse_release_all; ${prev}" EXIT
    else
        trap '_inuse_release_all' EXIT
    fi
}

#[pub]
# Wait until nobody else is holding that path.
#
# Returns 1 on timeout rather than proceeding, because proceeding is the thing
# that deletes a directory somebody is reading. A caller that would rather skip
# the update than wait is the ordinary case and should treat 1 as "not now".
# Usage: inuse_wait <dir> [seconds] -> 0 when free, 1 on timeout
inuse_wait() {
    local d="$1" secs="${2:-30}" waited=0
    while inuse_held_by_other "$d"; do
        [ "$waited" -ge "$secs" ] && return 1
        sleep 1
        waited=$(( waited + 1 ))
    done
    return 0
}

#[pub]
# Run a command that mutates that path, with nobody else reading it.
#
# The hold is taken before the wait returns is acted on, so the window between
# "nobody is holding it" and "I am holding it" is closed rather than merely
# narrow. That window is the whole bug: two processes can both see a free path.
# Usage: inuse_mutate <dir> [seconds] -- <command...>
inuse_mutate() {
    local d="$1" secs="$2" rc=0
    shift 2
    [ "${1:-}" = "--" ] && shift
    inuse_hold "$d" || return 1
    if inuse_held_by_other "$d"; then
        # Somebody was already in, or arrived first. Yield rather than race:
        # whoever holds it is reading, and a reader is exactly who must not have
        # the directory rewritten underneath them.
        if ! inuse_wait "$d" "$secs"; then
            inuse_release "$d"
            return 1
        fi
    fi
    "$@" || rc=$?
    inuse_release "$d"
    return "$rc"
}
