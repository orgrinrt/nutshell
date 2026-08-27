#!/usr/bin/env bash
# Tests for a pin that names a branch rather than a version.
#
# A branch pin is not a floor, it is an identity: `dev` means the head of dev,
# today. That makes it the one pin whose answer changes without anybody
# editing anything, so what it costs to keep current, and what it does when the
# remote cannot be reached, are the whole of it.
#
# It is also the one that shares a directory with every other project on the
# machine while nothing locks it. So the checkouts are keyed by the revision
# they hold and are written once, and none of this may ever delete a tree a
# running interpreter is sourcing out of.

use test

. "${BASH_SOURCE[0]%/*}/../find-nutshell"

_br_setup() {
    BRROOT="$(mktemp -d)"
    export NUTSHELL_TOOLCHAINS="$BRROOT/store"
    export NUTSHELL_REMOTE="$BRROOT/remote.git"
    NUTSHELL_INIT=""; NUTSHELL_FROM=""
    unset NUTSHELL_HOME
    # Whatever is installed on the machine running these must not decide
    # their answers.
    _BR_PATH_KEEP="$PATH"
    local d out=""
    while IFS= read -r d; do
        [[ -n "$d" ]] || continue
        [[ -x "$d/nutshell" ]] && continue
        out="${out:+$out:}$d"
    done <<< "${PATH//:/$'\n'}"
    export PATH="$out"
}
_br_end() {
    rm -rf "$BRROOT"
    unset BRROOT NUTSHELL_TOOLCHAINS NUTSHELL_REMOTE
    NUTSHELL_INIT=""; NUTSHELL_FROM=""
    export PATH="${_BR_PATH_KEEP:-$PATH}"
}

# A remote carrying one branch, and a way to move it.
_br_remote() {
    local branch="${1:-dev}" version="${2:-0.4.0}"
    BRWORK="$BRROOT/work"
    mkdir -p "$BRWORK"
    printf 'export NUTSHELL_VERSION="%s"\n' "$version" > "$BRWORK/init"
    git -C "$BRWORK" init -q -b "$branch"
    git -C "$BRWORK" config user.email t@example.invalid
    git -C "$BRWORK" config user.name t
    git -C "$BRWORK" config commit.gpgsign false
    git -C "$BRWORK" add -A
    git -C "$BRWORK" commit -qm "$version"
    git init -q --bare "$NUTSHELL_REMOTE"
    git -C "$BRWORK" remote add origin "$NUTSHELL_REMOTE"
    git -C "$BRWORK" push -q origin "$branch"
}
_br_move() {
    printf '# %s\n' "${1:-moved}" >> "$BRWORK/init"
    git -C "$BRWORK" commit -qam "${1:-moved}"
    git -C "$BRWORK" push -q origin HEAD
}
_br_head() { git -C "$BRWORK" rev-parse HEAD; }
_br_base() { printf '%s/branches/%s' "$NUTSHELL_TOOLCHAINS" "${1:-dev}"; }

# --- what a branch pin resolves to -------------------------------------------

#[test]
it_resolves_a_branch_pin_to_the_head_of_that_branch() {
    _br_setup; _br_remote dev 0.4.0
    assert_ok nutshell_find "" dev
    assert_eq "$NUTSHELL_FROM" "branch:dev"
    assert_contains "$NUTSHELL_INIT" "$(_br_head)"
    _br_end
}

#[test]
it_keys_the_checkout_by_the_revision_rather_than_by_the_branch_name() {
    _br_setup; _br_remote dev 0.4.0
    nutshell_find "" dev
    # The directory name is what makes the store safe to share: a checkout
    # named for a branch has to be replaced when the branch moves, and
    # replacing it is deleting a tree somebody may be sourcing out of.
    assert_ok test -f "$(_br_base)/$(_br_head)/init"
    assert_fails test -f "$(_br_base)/init"
    _br_end
}

#[test]
it_records_the_revision_the_branch_last_resolved_to() {
    _br_setup; _br_remote dev 0.4.0
    nutshell_find "" dev
    assert_eq "$(_nutshell_branch_head "$(_br_base)")" "$(_br_head)"
    _br_end
}

# --- what it costs to keep current -------------------------------------------

#[test]
it_does_not_ask_the_remote_again_inside_the_window() {
    _br_setup; _br_remote dev 0.4.0
    nutshell_find "" dev
    local first="$NUTSHELL_INIT"
    # The remote is taken away entirely, and the answer has to come back with
    # nothing said. Checking only that the path is unchanged would pass either
    # way: the offline fallback returns that same path, having gone to the
    # network to find out it could not. Silence is what distinguishes them.
    export NUTSHELL_REMOTE="$BRROOT/gone.git"
    local said; said="$(nutshell_find "" dev 2>&1 >/dev/null)"
    assert_eq "$NUTSHELL_INIT" "$first"
    assert_empty "$said"
    _br_end
}

#[test]
it_asks_again_once_the_window_is_out_and_follows_the_branch() {
    _br_setup; _br_remote dev 0.4.0
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev
    local before="$NUTSHELL_INIT"
    _br_move second
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev 2>/dev/null
    assert_ne "$NUTSHELL_INIT" "$before"
    assert_contains "$NUTSHELL_INIT" "$(_br_head)"
    _br_end
}

#[test]
it_leaves_the_old_revision_in_place_when_the_branch_moves() {
    _br_setup; _br_remote dev 0.4.0
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev
    local old; old="$NUTSHELL_INIT"
    _br_move second
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev 2>/dev/null
    # Somebody else's push must not pull the floor out from under a run that
    # already started. The old checkout is still there and still sourceable;
    # it goes when it is a day old, not when it stops being the head.
    assert_ok test -f "$old"
    _br_end
}

#[test]
it_does_not_refetch_a_revision_the_store_already_holds() {
    _br_setup; _br_remote dev 0.4.0
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev
    printf 'in use\n' > "$(_br_base)/$(_br_head)/marker"
    # The window is out and the head has not moved. That is a stamp refresh,
    # not a clone, and certainly not a replacement of the directory.
    local said; said="$(NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev 2>&1 >/dev/null)"
    assert_fails grep -q 'moved, fetching' <<<"$said"
    assert_ok test -f "$(_br_base)/$(_br_head)/marker"
    _br_end
}

# --- when the remote cannot be reached ---------------------------------------

#[test]
it_runs_from_the_last_known_revision_when_the_remote_is_unreachable() {
    _br_setup; _br_remote dev 0.4.0
    nutshell_find "" dev
    local known="$NUTSHELL_INIT"
    export NUTSHELL_REMOTE="$BRROOT/gone.git"
    local said
    said="$(NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev 2>&1 >/dev/null)"
    assert_eq "$NUTSHELL_INIT" "$known"
    # Named rather than pretended about. A stale head that runs beats a
    # refusal, and a reader has to be able to tell which one they got.
    assert_contains "$said" "could not reach"
    _br_end
}

#[test]
it_names_the_revision_it_fell_back_to() {
    _br_setup; _br_remote dev 0.4.0
    nutshell_find "" dev
    local head; head="$(_br_head)"
    export NUTSHELL_REMOTE="$BRROOT/gone.git"
    local said; said="$(NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev 2>&1 >/dev/null)"
    assert_contains "$said" "${head:0:12}"
    _br_end
}

#[test]
it_falls_through_to_a_vendored_copy_when_the_branch_was_never_fetched() {
    _br_setup
    export NUTSHELL_REMOTE="$BRROOT/gone.git"
    local root="$BRROOT/project"
    mkdir -p "$root/lib/nutshell"
    printf 'export NUTSHELL_VERSION="0.4.0"\n' > "$root/lib/nutshell/init"
    assert_ok nutshell_find "$root" dev 2>/dev/null
    assert_eq "$NUTSHELL_FROM" "vendored"
    _br_end
}

#[test]
it_takes_what_the_caller_named_before_asking_the_remote_anything() {
    _br_setup
    export NUTSHELL_REMOTE="$BRROOT/gone.git"
    local d="$BRROOT/named"
    mkdir -p "$d"
    printf 'export NUTSHELL_VERSION="0.4.0"\n' > "$d/init"
    # A suite that exports this must not send every child process it starts to
    # the network.
    NUTSHELL_HOME="$d" assert_ok nutshell_find "" dev
    assert_eq "$NUTSHELL_FROM" "NUTSHELL_HOME"
    _br_end
}

# --- names that are not branch names -----------------------------------------

#[test]
it_refuses_a_ref_that_would_escape_the_store() {
    _br_setup; _br_remote dev 0.4.0
    local outside="$BRROOT/outside"
    mkdir -p "$outside"; printf 'here\n' > "$outside/keep"
    assert_fails _nutshell_branch "../outside" 2>/dev/null
    assert_ok test -f "$outside/keep"
    _br_end
}

#[test]
it_refuses_a_ref_carrying_a_slash() {
    _br_setup
    # `feat/thing` is a legal branch name and is not a legal directory name
    # here. Refusing it is a limit, and it is a stated one rather than a path
    # built out of it.
    assert_fails _nutshell_branch "feat/thing" 2>/dev/null
    _br_end
}

# --- pruning ------------------------------------------------------------------

#[test]
it_keeps_a_revision_that_is_not_a_day_old_yet() {
    _br_setup; _br_remote dev 0.4.0
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev
    local old; old="$(_br_head)"
    _br_move second
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev 2>/dev/null
    assert_ok test -d "$(_br_base)/$old"
    _br_end
}

#[test]
it_drops_a_revision_nothing_has_touched_for_a_day() {
    _br_setup; _br_remote dev 0.4.0
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev
    local old; old="$(_br_head)"
    # Aged deliberately. Two days back, so a machine on either side of a
    # daylight-saving boundary still reads it as older than a day.
    touch -t "$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)" \
        "$(_br_base)/$old"
    _br_move second
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev 2>/dev/null
    assert_fails test -d "$(_br_base)/$old"
    # And the one it just resolved to is still there, which is the half that
    # makes the pruning safe rather than merely tidy.
    assert_ok test -f "$(_br_base)/$(_br_head)/init"
    _br_end
}

#[test]
it_says_a_slashed_ref_is_a_name_problem_and_not_a_network_one() {
    _br_setup; _br_remote dev 0.4.0
    # `feat/toolchains` is a legal branch name and is not a directory name in
    # the store. The limit is real; reporting it as "could not reach" sends the
    # reader to check their connection.
    local said; said="$(nutshell_find "" "feat/toolchains" 2>&1 >/dev/null)"
    assert_contains "$said" "cannot name a toolchain directory"
    assert_fails grep -q "could not reach" <<<"$said"
    _br_end
}

#[test]
it_keeps_a_revision_something_is_still_using() {
    _br_setup; _br_remote dev 0.4.0
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev
    local old; old="$(_br_head)"

    # Aged past the prune's cutoff, as a long-running program's revision would
    # be: modules load lazily through `use`, so a program started three days
    # ago still holds its revision, and reading files inside a directory does
    # not move the directory's mtime.
    touch -t "$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)" \
        "$(_br_base)/$old"

    # Something resolves to it again, which is what a running program does.
    NUTSHELL_BRANCH_TTL=9999 nutshell_find "" dev >/dev/null 2>&1

    # Now somebody else's push moves the head and prunes.
    _br_move second
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev 2>/dev/null

    # The old revision survives, because it was used within the day even though
    # it was fetched days ago. Deleting it pulled the floor out from under a
    # running program and every later `use` in it failed.
    assert_ok test -f "$(_br_base)/$old/init"
    _br_end
}

#[test]
it_still_drops_a_revision_nothing_has_used() {
    # The control for the one above. Touch-on-use must not turn the prune off.
    _br_setup; _br_remote dev 0.4.0
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev
    local old; old="$(_br_head)"
    _br_move second
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev 2>/dev/null
    # Aged after the last resolution, so nothing has used it since.
    touch -t "$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M)" \
        "$(_br_base)/$old"
    _br_move third
    NUTSHELL_BRANCH_TTL=0 nutshell_find "" dev 2>/dev/null
    assert_fails test -d "$(_br_base)/$old"
    _br_end
}
