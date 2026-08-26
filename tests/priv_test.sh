#!/usr/bin/env bash
# Tests for doing one thing as root and then not being root.
#
# The failure this module exists to prevent, from the machine it was written
# on: a tool needed root to mount a partition, got it by being started under
# sudo, and then kept going. It ended with two histories,
# `~/.local/state/<tool>/journal` owned by the person and a second one owned by
# root, and the person could no longer write the second. Nothing was
# misconfigured. It asked for root for a reason and then kept it.

use test
use priv

_priv_reset() { PRIV_USER=""; PRIV_UID=""; PRIV_HOME=""; }

# --- who this is ---------------------------------------------------------------

#[test]
it_knows_who_started_this() {
    _priv_reset
    assert_eq "$(priv_user)" "$(id -un)"
    assert_eq "$(priv_uid)"  "$(id -u)"
    _priv_reset
}

#[test]
it_answers_with_the_person_not_root_when_run_under_sudo() {
    # The case this module is trying to make unnecessary, and the one it still
    # has to answer correctly while it exists.
    _priv_reset
    id() { case "$1" in -u) printf '0' ;; -un) printf 'root' ;; *) builtin command id "$@" ;; esac; }
    SUDO_USER="somebody" SUDO_UID="1234" _priv_learn_user
    local u="$PRIV_USER" i="$PRIV_UID"
    unset -f id
    _priv_reset
    assert_eq "$u" "somebody"
    assert_eq "$i" "1234"
}

#[test]
it_finds_a_home_without_reading_the_environment() {
    # `$HOME` is exactly what is wrong inside something that elevated, so the
    # answer comes from the password database instead.
    local me; me="$(id -un)"
    local h; h="$(_priv_home_of "$me")"
    assert_ne "$h" ""
    assert_eq "$h" "$HOME"
}

#[test]
it_fails_to_find_a_home_for_somebody_who_does_not_exist() {
    # The control. A lookup that answers for every name would answer wrongly
    # for the one that matters.
    assert_fails _priv_home_of "no-such-user-here-at-all"
}

#[test]
it_refuses_to_look_up_an_empty_name() {
    assert_fails _priv_home_of ""
}

# --- how it would ask ----------------------------------------------------------

#[test]
it_says_how_it_would_ask() {
    local how; how="$(priv_how)"
    # On any machine this runs on: already root, or one of the two askers.
    case "$how" in already|sudo|doas) assert_ok true ;; *) assert_ok false ;; esac
}

#[test]
it_says_it_cannot_ask_when_neither_asker_is_there() {
    priv_is_root() { return 1; }
    command() {
        case "$2" in sudo|doas) return 1 ;; esac
        builtin command "$@"
    }
    local rc=0
    priv_how >/dev/null 2>&1 || rc=$?
    unset -f priv_is_root command
    assert_ne "$rc" "0"
}

#[test]
it_prefers_sudo_where_both_are_present() {
    # Not a preference anybody should care about, but it has to be one thing
    # rather than whichever the loop reached first on that machine.
    priv_is_root() { return 1; }
    command() {
        case "$2" in sudo|doas) return 0 ;; esac
        builtin command "$@"
    }
    local how; how="$(priv_how)"
    unset -f priv_is_root command
    assert_eq "$how" "sudo"
}

#[test]
it_needs_no_password_when_it_is_already_root() {
    priv_is_root() { return 0; }
    local rc=0
    priv_needs_password || rc=$?
    unset -f priv_is_root
    assert_ne "$rc" "0"
}

# --- running the one thing -----------------------------------------------------

#[test]
it_runs_the_command_directly_when_already_root() {
    # No asking where nothing needs to be asked, or every step prompts for a
    # password that was never required.
    priv_is_root() { return 0; }
    local asked=0
    sudo() { asked=1; return 0; }
    local out; out="$(priv_run "a thing" printf 'ran')"
    unset -f priv_is_root sudo
    assert_eq "$out" "ran"
    assert_eq "$asked" "0"
}

#[test]
it_passes_the_command_through_without_a_shell() {
    # Arguments, not a string. A path with a space in it is still one path, and
    # a caller must never have to think about quoting to use this.
    priv_is_root() { return 0; }
    local out; out="$(priv_run "a thing" printf '%s|' 'one two' 'three')"
    unset -f priv_is_root
    assert_eq "$out" "one two|three|"
}

#[test]
it_returns_what_the_command_returned() {
    priv_is_root() { return 0; }
    local rc=0
    priv_run "a thing" false || rc=$?
    unset -f priv_is_root
    assert_eq "$rc" "1"
}

#[test]
it_asks_for_one_command_and_not_for_a_shell() {
    # The whole distinction. What is elevated is this command, and the caller
    # is the same user after it as before.
    priv_is_root() { return 1; }
    priv_how() { printf 'sudo'; }
    priv_needs_password() { return 1; }
    local got=""
    sudo() { got="$*"; }
    priv_run "mount the stick" mount /dev/sdz2 /mnt/stick
    unset -f priv_is_root priv_how priv_needs_password sudo
    assert_eq "$got" "-- mount /dev/sdz2 /mnt/stick"
    assert_fails grep -q ' -s\| bash\| sh ' <<<"$got"
}

#[test]
it_refuses_when_there_is_no_way_to_ask() {
    priv_is_root() { return 1; }
    priv_how() { return 1; }
    local rc=0 out
    out="$(priv_run "a thing" true 2>&1)" || rc=$?
    unset -f priv_is_root priv_how
    assert_eq "$rc" "2"
    assert_contains "$out" "a thing"
}

#[test]
it_refuses_rather_than_hanging_on_a_prompt_nobody_can_answer() {
    # These machines are often being fixed over a pipe. A password prompt with
    # no terminal behind it is a program that stops forever.
    priv_is_root() { return 1; }
    priv_how() { printf 'sudo'; }
    priv_needs_password() { return 0; }
    _priv_can_prompt() { return 1; }
    local ran=0
    sudo() { ran=1; }
    local rc=0
    priv_run "a thing" true >/dev/null 2>&1 || rc=$?
    unset -f priv_is_root priv_how priv_needs_password _priv_can_prompt sudo
    assert_eq "$rc" "2"
    assert_eq "$ran" "0"
}

#[test]
it_runs_when_there_is_a_terminal_to_ask_on() {
    # The control for the refusal above.
    priv_is_root() { return 1; }
    priv_how() { printf 'sudo'; }
    priv_needs_password() { return 0; }
    _priv_can_prompt() { return 0; }
    local ran=0
    sudo() { ran=1; }
    priv_run "a thing" true >/dev/null 2>&1
    unset -f priv_is_root priv_how priv_needs_password _priv_can_prompt sudo
    assert_eq "$ran" "1"
}

#[test]
it_says_what_it_is_asking_for_before_the_prompt_appears() {
    # An unexpected password request wants a sentence beside it naming what
    # asked, or somebody types their password into a mystery.
    priv_is_root() { return 1; }
    priv_how() { printf 'sudo'; }
    priv_needs_password() { return 0; }
    _priv_can_prompt() { return 0; }
    sudo() { return 0; }
    local out; out="$(priv_run "mount the stick" true 2>&1)"
    unset -f priv_is_root priv_how priv_needs_password _priv_can_prompt sudo
    assert_contains "$out" "mount the stick"
}

#[test]
it_refuses_a_call_with_nothing_to_run() {
    local rc=0
    priv_run "a thing" >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" "2"
}

# --- giving the file back ------------------------------------------------------

#[test]
it_gives_a_file_back_to_the_person() {
    # The other half of the split. A file root wrote where the person keeps
    # theirs is a file they cannot change, and the symptom arrives much later
    # than the cause.
    priv_is_root() { return 0; }
    priv_user() { printf 'somebody'; }
    local got=""
    chown() { got="$*"; return 0; }
    local d; d="$(mktemp -d)"; : > "$d/f"
    priv_return "$d/f"
    unset -f priv_is_root priv_user chown
    rm -rf "$d"
    assert_contains "$got" "somebody"
}

#[test]
it_does_not_give_anything_back_when_it_was_never_root() {
    priv_is_root() { return 1; }
    priv_user() { printf 'somebody'; }
    local called=0
    chown() { called=1; }
    local d; d="$(mktemp -d)"; : > "$d/f"
    priv_return "$d/f"
    unset -f priv_is_root priv_user chown
    rm -rf "$d"
    assert_eq "$called" "0"
}

#[test]
it_does_not_give_anything_back_to_root() {
    # Nothing to hand over when root is who started it.
    priv_is_root() { return 0; }
    priv_user() { printf 'root'; }
    local called=0
    chown() { called=1; }
    local d; d="$(mktemp -d)"; : > "$d/f"
    priv_return "$d/f"
    unset -f priv_is_root priv_user chown
    rm -rf "$d"
    assert_eq "$called" "0"
}

#[test]
it_ignores_a_path_that_is_not_there() {
    priv_is_root() { return 0; }
    priv_user() { printf 'somebody'; }
    local called=0
    chown() { called=1; }
    priv_return "/no/such/path/at/all"
    unset -f priv_is_root priv_user chown
    assert_eq "$called" "0"
}
