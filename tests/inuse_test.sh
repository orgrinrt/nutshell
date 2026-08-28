#!/usr/bin/env bash
# =============================================================================
# nutshell/tests/inuse_test.sh - The marks that keep the shared store sane
# =============================================================================
# Every check here has a control, because the interesting half of this module is
# what it refuses and a mark that never registers refuses nothing while looking
# identical from outside. That is not hypothetical: the first version took the
# pid inside a command substitution, so every hold named a shell that was
# already gone, `inuse_hold` reported success and the holder list came back
# empty.
# =============================================================================

use inuse fs

_iu_dir() { printf '%s/inuse-test-%s-%s' "${TMPDIR:-/tmp}" "$$" "$1"; }

#[test]
it_marks_a_path_and_says_who_holds_it() {
    local d; d="$(_iu_dir marks)"; fs_mkdir "$d"
    assert_ok inuse_hold "$d"
    assert_ne "$(inuse_holders "$d" | grep -c .)" "0"
    inuse_release "$d"
    rm -rf "$d"
}

#[test]
it_reports_nothing_for_a_path_nobody_holds() {
    # The control for the one above. Without it that test passes whether or not
    # holding is what put the pid there.
    local d; d="$(_iu_dir free)"; fs_mkdir "$d"
    assert_eq "$(inuse_holders "$d" | grep -c .)" "0"
    rm -rf "$d"
}

#[test]
it_clears_the_mark_on_release() {
    local d; d="$(_iu_dir cleared)"; fs_mkdir "$d"
    inuse_hold "$d"
    assert_ne "$(inuse_holders "$d" | grep -c .)" "0"
    inuse_release "$d"
    assert_eq "$(inuse_holders "$d" | grep -c .)" "0"
    rm -rf "$d"
}

#[test]
it_does_not_count_its_own_mark_as_somebody_else() {
    # The whole mechanism turns on this. If a process saw its own hold as
    # another's, every mutation would wait out its timeout and then proceed
    # anyway, which is worse than no locking at all because it is slower.
    local d; d="$(_iu_dir mine)"; fs_mkdir "$d"
    inuse_hold "$d"
    assert_fails inuse_held_by_other "$d"
    inuse_release "$d"
    rm -rf "$d"
}

#[test]
it_sees_a_mark_left_by_a_live_process_that_is_not_this_one() {
    # The positive half, and the one the waiting depends on. A background shell
    # that is genuinely alive holds it; this one must see that.
    local d; d="$(_iu_dir other)"; fs_mkdir "$d"
    sleep 20 &
    local other=$!
    local k root
    k="$(nut_key "$d" >/dev/null 2>&1; printf '%s' "$_nk")"
    root="${NUTSHELL_STORE:+${NUTSHELL_STORE%/}/.inuse}"
    [ -n "$root" ] || { xdg_set_app_name nutshell; root="$(xdg_app_data)/.inuse"; }
    fs_mkdir "$root/$k"
    : > "$root/$k/$other"
    assert_ok inuse_held_by_other "$d"
    kill "$other" 2>/dev/null; wait "$other" 2>/dev/null
    # And once it is gone, the mark stops counting without anybody sweeping.
    assert_fails inuse_held_by_other "$d"
    rm -rf "$root/$k" "$d"
}

#[test]
it_ignores_a_mark_whose_process_is_gone() {
    # A holder that died leaves its file behind. The question asked is whether
    # the pid is alive, never whether the file exists, which is what makes the
    # registry safe to leave lying around and why there is no reaper.
    local d; d="$(_iu_dir stale)"; fs_mkdir "$d"
    local k root
    k="$(nut_key "$d" >/dev/null 2>&1; printf '%s' "$_nk")"
    root="${NUTSHELL_STORE:+${NUTSHELL_STORE%/}/.inuse}"
    [ -n "$root" ] || { xdg_set_app_name nutshell; root="$(xdg_app_data)/.inuse"; }
    fs_mkdir "$root/$k"
    # A pid that cannot be running: 4194304 is above the default pid_max on
    # linux and above the darwin ceiling too.
    : > "$root/$k/4194304"
    assert_fails inuse_held_by_other "$d"
    assert_eq "$(inuse_holders "$d" | grep -c .)" "0"
    rm -rf "$root/$k" "$d"
}

#[test]
it_refuses_to_mutate_a_path_somebody_else_is_reading() {
    # The point of all of it. A mutation that proceeds anyway is the deletion
    # this module exists to prevent.
    local d; d="$(_iu_dir busy)"; fs_mkdir "$d"
    sleep 20 &
    local other=$!
    local k root
    k="$(nut_key "$d" >/dev/null 2>&1; printf '%s' "$_nk")"
    root="${NUTSHELL_STORE:+${NUTSHELL_STORE%/}/.inuse}"
    [ -n "$root" ] || { xdg_set_app_name nutshell; root="$(xdg_app_data)/.inuse"; }
    fs_mkdir "$root/$k"; : > "$root/$k/$other"

    local ran=0
    inuse_mutate "$d" 1 -- eval 'ran=1' || true
    assert_eq "$ran" "0"

    kill "$other" 2>/dev/null; wait "$other" 2>/dev/null
    rm -rf "$root/$k" "$d"
}

#[test]
it_runs_a_mutation_when_the_path_is_free() {
    # The control for the one above, and it is the half that would otherwise go
    # unnoticed: a mutate that never runs anything also never mutates anything
    # it should not.
    local d; d="$(_iu_dir idle)"; fs_mkdir "$d"
    inuse_mutate "$d" 1 -- touch "$d/done"
    assert_ok test -f "$d/done"
    # And it let go afterwards.
    assert_eq "$(inuse_holders "$d" | grep -c .)" "0"
    rm -rf "$d"
}

#[test]
it_holds_for_the_session_from_inside_a_command_substitution() {
    # Module resolution runs inside `$( )`, where `$BASHPID` names a shell that
    # exits immediately while the script that asked goes on sourcing files. A
    # reader's mark has to outlive the substitution or it protects nothing, and
    # the first version of this module got exactly that wrong.
    local d; d="$(_iu_dir session)"; fs_mkdir "$d"
    local _ignored
    _ignored="$(inuse_hold_session "$d"; printf ok)"
    assert_eq "$_ignored" "ok"
    # Taken inside the substitution, still held out here.
    assert_ne "$(inuse_holders "$d" | grep -c .)" "0"
    local k root
    k="$(nut_key "$d" >/dev/null 2>&1; printf '%s' "$_nk")"
    root="${NUTSHELL_STORE:+${NUTSHELL_STORE%/}/.inuse}"
    [ -n "$root" ] || { xdg_set_app_name nutshell; root="$(xdg_app_data)/.inuse"; }
    rm -rf "$root/$k" "$d"
}

#[test]
it_would_lose_a_session_mark_taken_with_the_subshell_pid() {
    # The control for the one above, and the reason it is written as a separate
    # mark rather than a flag on the first. This is the defect reproduced: a
    # hold taken with `$BASHPID` inside a substitution is gone by the next line.
    local d; d="$(_iu_dir subshell)"; fs_mkdir "$d"
    local _ignored
    _ignored="$(inuse_hold "$d"; printf ok)"
    assert_eq "$_ignored" "ok"
    assert_eq "$(inuse_holders "$d" | grep -c .)" "0"
    rm -rf "$d"
}
