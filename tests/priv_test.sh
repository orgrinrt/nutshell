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

# --- stepping back down --------------------------------------------------------
#
# The other direction, and the one with no way to test it for real without a
# second account. What it does have is a choice between three commands and
# three different ways of handing arguments to them, which is where it can be
# wrong, so the three are stubbed and asked what they were given.

# A directory holding stubs for the step-down commands, first on PATH. Each one
# records that it ran and repeats its arguments one per line, so a test can see
# both which command was picked and what survived the trip.
_priv_stubs() {
    _PRIV_STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-priv.XXXXXX")"
    # Absolute paths, found while PATH is still whole. Once PATH is only the
    # stub directory, `env bash` cannot resolve bash and a test cannot reach
    # `chmod` to write a stub of its own.
    _PRIV_STUB_BASH="$(command -v bash)"
    _PRIV_STUB_SH="$(command -v sh)"
    _PRIV_STUB_CHMOD="$(command -v chmod)"
    local c
    for c in "$@"; do
        _priv_stub_put "$c" "printf '%s\n' \"$c\"" 'printf '"'"'%s\n'"'"' "$@"'
    done
    _PRIV_PATH_KEEP="$PATH"
    # The stub directory and nothing else. Prepending is not enough: a machine
    # with a real `sudo` on it picks that one whenever the stub set leaves it
    # out, so the two tests about falling past `sudo` would have been answered
    # by the host's own sudo failing rather than by the fallback working.
    export PATH="$_PRIV_STUB_DIR"
}
# Write one stub, from lines of bash handed in as arguments. `printf` is a
# builtin and the interpreter and `chmod` are absolute, so this works with the
# stub directory as the whole of PATH.
_priv_stub_put() {
    local name="$1"; shift
    local f="$_PRIV_STUB_DIR/$name" line
    printf '#!%s\n' "$_PRIV_STUB_BASH" > "$f"
    for line in "$@"; do printf '%s\n' "$line" >> "$f"; done
    "$_PRIV_STUB_CHMOD" +x "$f"
}

_priv_stubs_end() {
    export PATH="${_PRIV_PATH_KEEP:-$PATH}"
    [[ -n "${_PRIV_STUB_DIR:-}" ]] && rm -rf "$_PRIV_STUB_DIR"
    unset _PRIV_STUB_DIR _PRIV_PATH_KEEP
}

# Pretend to be root, with somebody else having started this.
_priv_as_root() {
    PRIV_USER="somebody"; PRIV_UID="1234"; PRIV_HOME="/home/somebody"
    priv_is_root() { return 0; }
}
_priv_as_root_end() { unset -f priv_is_root; _priv_reset; }

#[test]
it_runs_the_step_itself_when_it_is_not_root() {
    _priv_reset
    # Nothing to step down from. The step still has to happen, and it has to
    # happen without any of the three commands being involved.
    priv_is_root() { return 1; }
    local out; out="$(priv_as_user "reading" printf 'ran\n')"
    unset -f priv_is_root
    assert_eq "$out" "ran"
}

#[test]
it_runs_the_step_itself_when_the_person_is_root() {
    _priv_reset
    PRIV_USER="root"; PRIV_UID="0"; PRIV_HOME="/root"
    priv_is_root() { return 0; }
    # Stepping down to root from root is the same shell with two more
    # processes in it.
    _priv_stubs runuser sudo su
    local out; out="$(priv_as_user "reading" printf 'ran\n')"
    _priv_stubs_end
    unset -f priv_is_root; _priv_reset
    assert_eq "$out" "ran"
}

#[test]
it_carries_the_status_of_the_step_back_out() {
    _priv_reset
    priv_is_root() { return 1; }
    assert_fails priv_as_user "failing" false
    assert_ok priv_as_user "working" true
    unset -f priv_is_root
}

#[test]
it_prefers_runuser_which_is_the_one_built_for_this() {
    _priv_as_root
    _priv_stubs runuser sudo su
    local out; out="$(priv_as_user "reading" git status)"
    _priv_stubs_end; _priv_as_root_end
    assert_eq "$(head -1 <<<"$out")" "runuser"
    assert_contains "$out" "-u"
    assert_contains "$out" "somebody"
}

#[test]
it_falls_to_sudo_when_there_is_no_runuser() {
    _priv_as_root
    _priv_stubs sudo su
    local out; out="$(priv_as_user "reading" git status)"
    _priv_stubs_end; _priv_as_root_end
    assert_eq "$(head -1 <<<"$out")" "sudo"
    # Non-interactive, because there is nobody at the keyboard inside a step
    # that already elevated, and a prompt there hangs the run.
    assert_contains "$out" "-n"
}

#[test]
it_falls_to_su_last_of_the_three() {
    _priv_as_root
    _priv_stubs su
    local out; out="$(priv_as_user "reading" git status)"
    _priv_stubs_end; _priv_as_root_end
    assert_eq "$(head -1 <<<"$out")" "su"
}

#[test]
it_keeps_the_arguments_apart_through_runuser() {
    _priv_as_root
    _priv_stubs runuser
    # A path with a space in it is the ordinary case, not a corner: people's
    # home directories have spaces in them.
    local out; out="$(priv_as_user "reading" git -C "/home/some body" status)"
    _priv_stubs_end; _priv_as_root_end
    assert_contains "$out" "/home/some body"
    # One line per argument, so a path that was split shows up as two.
    assert_eq "$(grep -c '^/home/some body$' <<<"$out")" "1"
}

#[test]
it_quotes_every_metacharacter_so_any_posix_shell_reads_it_back() {
    # `printf %q` was doing this, and it emits bash's `$'...'` for a tab, a
    # newline or a control character. `dash` is `/bin/sh` on Debian and Ubuntu
    # and reads that as the four characters it is written with, so the path
    # arrived silently wrong. This function writes a person's files as that
    # person; a mangled path is root writing somewhere nobody asked it to.
    #
    # The round trip is through `sh`, and asserts the argument comes back as
    # itself rather than pinning a spelling.
    #
    # It cannot catch the bash-only form on a machine whose `sh` is bash, which
    # macOS is, so it passes there either way. The case below it is the one
    # that holds everywhere; this one is what says the replacement is correct.
    local sh; sh="$(command -v sh)"
    local t q back
    for t in "plain" "/home/some body" "$(printf 'a\tb')" "it's" 'a$b' 'a*b' \
             'a"b' 'a\b' 'a;b' 'a|b' 'a`b`' 'a&b' 'a
b' "" "-x"; do
        q="$(_priv_sq "$t")"
        back="$("$sh" -c "printf %s $q")"
        assert_eq "$back" "$t"
    done
}

#[test]
it_does_not_reach_for_the_bash_only_quoting_form() {
    # The specific thing that was wrong, stated as its own case so a later
    # change back to `printf %q` fails here rather than on somebody's Debian.
    local q; q="$(_priv_sq "$(printf 'a\tb')")"
    assert_fails grep -q "\$'" <<<"$q"
}

#[test]
it_keeps_the_arguments_apart_through_su_which_goes_via_a_shell() {
    _priv_as_root
    _priv_stubs su
    # The one route that has to put the arguments back into a single string,
    # and therefore the one that can lose them. Asserting the spelling of the
    # quoting would pin an implementation; what matters is that a shell reading
    # that string back gets the arguments it started with. So `su` runs its
    # own payload and a stubbed `git` reports what actually arrived.
    _priv_stub_put su \
        'while [[ $# -gt 0 && "$1" != "-c" ]]; do shift; done' \
        'shift' \
        "exec ${_PRIV_STUB_SH} -c \"\$1\""
    _priv_stub_put git 'printf '"'"'%s\n'"'"' "$@"'

    # A path with a space in it is the ordinary case, not a corner: people's
    # home directories have spaces in them.
    local out; out="$(priv_as_user "reading" git -C "/home/some body" status)"
    _priv_stubs_end; _priv_as_root_end
    # One line per argument, so a path the shell split shows up as two.
    assert_eq "$(grep -c '^/home/some body$' <<<"$out")" "1"
    assert_eq "$(wc -l <<<"$out" | tr -d ' ')" "3"
}

#[test]
it_refuses_a_step_with_nothing_in_it() {
    _priv_reset
    assert_fails priv_as_user "nothing" 2>/dev/null
    _priv_reset
}

#[test]
it_says_so_when_there_is_no_way_to_step_down_at_all() {
    _priv_as_root
    # A machine with none of the three. Failing quietly here would run the
    # step as root, which is the whole thing this exists to prevent.
    _priv_stubs
    local rc=0
    priv_as_user "reading" true 2>/dev/null || rc=$?
    _priv_stubs_end; _priv_as_root_end
    assert_ne "$rc" "0"
}

#[test]
it_does_not_pass_su_a_flag_only_one_su_has() {
    _priv_as_root
    _priv_stubs su
    local out; out="$(priv_as_user "reading" true)"
    _priv_stubs_end; _priv_as_root_end
    # `-s` is util-linux. BSD and macOS `su` is `su [-] [-flm] [login [args]]`
    # and refuses it, and this is the branch a busybox rescue console takes.
    assert_fails grep -qx -- "-s" <<<"$out"
    assert_contains "$out" "somebody"
}

#[test]
it_steps_down_with_doas_where_that_is_what_the_machine_has() {
    _priv_as_root
    # `priv_run` already elevates with doas. Without the same here, a machine
    # that can elevate cannot step back down, which is the exact failure this
    # function exists to prevent. OpenBSD and some Alpine installs carry doas
    # and none of the other three.
    _priv_stubs doas
    local out; out="$(priv_as_user "reading" git status)"
    _priv_stubs_end; _priv_as_root_end
    assert_eq "$(head -1 <<<"$out")" "doas"
    assert_contains "$out" "somebody"
}

#[test]
it_prefers_runuser_and_sudo_over_doas() {
    _priv_as_root
    _priv_stubs runuser sudo doas su
    local out; out="$(priv_as_user "reading" git status)"
    _priv_stubs_end; _priv_as_root_end
    assert_eq "$(head -1 <<<"$out")" "runuser"
}

#[test]
it_names_doas_when_it_cannot_step_down_at_all() {
    _priv_as_root
    _priv_stubs
    local err; err="$(priv_as_user "reading" true 2>&1 >/dev/null)"
    _priv_stubs_end; _priv_as_root_end
    # The message lists what it looked for, so a reader knows what to install.
    assert_contains "$err" "doas"
}

# A POSIX shell to check against, or nothing.
_pt_posix_sh() {
    local cand f; f="$(mktemp)"; printf 'declare -A x\n' > "$f"
    for cand in dash ash yash busybox-sh; do
        command -v "$cand" >/dev/null 2>&1 || continue
        "$cand" -c ". '$f'" >/dev/null 2>&1 || { rm -f "$f"; printf '%s' "$cand"; return 0; }
    done
    rm -f "$f"; return 1
}

#[test]
# It runs under a POSIX shell, not merely parses there.
#
# The distinction is the whole point of the floor work: `[[ -n x ]]` is a
# command name and three arguments to a POSIX shell, so it reads anywhere and
# then reports `[[: not found`, and `declare -g` is not found and carries on
# with the variable never set. Neither is a parse error.
#
# So the assertion is that the module answers, and answers the same as it does
# under bash. `priv_user_home` is the one worth asserting: it used to read the
# passwd line into `local -a f=($line)` and take `${f[5]}`, which needs an
# array and a per-command `IFS` a POSIX shell has neither of.
it_runs_under_a_posix_shell() {
    local sh; sh="$(_pt_posix_sh)" || { skip "no strict POSIX shell here"; return 0; }
    local root="${BASH_SOURCE[0]%/*}/.."

    # Not piped. Sourcing through a pipe puts it in a subshell and every
    # function defined dies with it, which reads exactly like the module
    # failing to load.
    local probe='
        use() { return 0; }
        log_error() { :; }
        . "$1"/lib/priv.sh || exit 1
        printf "%s|%s|" "$PRIV_USER" "$(priv_user_home)"
        priv_is_root && printf "root" || printf "notroot"
    '
    local got want
    got="$("$sh" -c "$probe" _ "$root" 2>&1)"
    want="$(bash -c "$probe" _ "$root" 2>&1)"

    assert_not_contains "$got" "not found"
    assert_not_contains "$got" "Bad substitution"
    assert_ne "$got" ""
    assert_eq "$got" "$want"

    # And the field cut actually found a home rather than an empty string.
    assert_not_contains "$got" "||"
}
