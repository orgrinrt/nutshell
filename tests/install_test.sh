#!/usr/bin/env bash
# Tests for the installer, and specifically for the half of it that decides
# where a link has to go for `sudo` to find one.
#
# That half is untestable by reading: every one of the three helpers is a
# decision about somebody's PATH, and the failure they exist to prevent is
# silent and total. `sudo` replaces PATH with its own `secure_path`, which
# never holds a home directory, so a link in `~/.local/bin` alone means every
# `sudo <nutshell script>` dies with `env: 'nutshell': No such file or
# directory` while pointing at a program sitting right there in the user's
# PATH. Reported from a real machine after a clean install said it succeeded.
#
# Sourced rather than run: `install` puts its imperative half in `_main` and
# calls it only when executed, so this reaches the helpers without linking
# anything.

use test

. "${BASH_SOURCE[0]%/*}/../install"

# --- reading sudo's own path -------------------------------------------------

#[test]
it_reads_the_secure_path_sudo_reports() {
    # Not guessed. A machine configured with a different secure_path is exactly
    # the machine where a guess would put the link somewhere root never looks.
    #
    # The stub answers `-l` and not `-V`, and the difference is the whole
    # defect the first version of this shipped: `sudo -V` prints its settings
    # only to root, so a stub that answers it is more capable than the binary
    # and the test passes over code that never ran. Measured on sudo 1.9.17p2
    # as an ordinary user: five version lines and zero matches.
    sudo() {
        [[ "$*" == *-l* ]] || return 1
        printf 'Matching Defaults entries for t on h:\n    env_reset, secure_path=/opt/bin\\:/usr/bin, !log_allowed\n'
    }
    assert_eq "$(_sudo_path)" "/opt/bin:/usr/bin"
    unset -f sudo
}

#[test]
it_reads_nothing_out_of_the_dump_sudo_gives_a_non_root_caller() {
    # The control for the arm above, and the case that shipped broken. This is
    # verbatim what `sudo -V` prints here to a user who is not root; a reader
    # of it finds no secure_path, so the conventional set is the honest answer
    # and a test asserting `/opt/bin` off this input would be asserting a stub.
    sudo() {
        [[ "$*" == *-l* ]] && return 1
        printf 'Sudo version 1.9.17p2\nSudoers policy plugin version 1.9.17p2\n'
    }
    local p; p="$(_sudo_path)"
    assert_contains "$p" "/usr/local/bin"
    assert_not_contains "$p" "/opt/bin"
    unset -f sudo
}

#[test]
it_does_not_prompt_for_a_password_to_find_out_where_root_looks() {
    # `-n` or the installer hangs on a machine with no cached credentials,
    # during a step whose whole purpose is to avoid one surprise.
    # Written to a file rather than to a variable: `_sudo_path` calls sudo
    # inside a command substitution, so an assignment in the stub lands in a
    # subshell and the assertion reads an empty string whatever sudo was given.
    local seen; seen="$(mktemp)"
    sudo() { printf '%s' "$*" > "$seen"; return 1; }
    _sudo_path > /dev/null
    assert_contains "$(cat "$seen")" "-n"
    rm -f "$seen"
    unset -f sudo
}

#[test]
it_falls_back_to_the_conventional_set_when_sudo_says_nothing() {
    # No sudo at all, or a build that does not report one. Refusing to answer
    # would mean the installer skipping the system link on every machine whose
    # sudo is quiet, which is the failure again with better manners.
    sudo() { return 127; }
    local p; p="$(_sudo_path)"
    assert_contains "$p" "/usr/local/bin"
    assert_contains "$p" "/usr/bin"
    unset -f sudo
}

#[test]
it_does_not_take_a_home_directory_from_sudos_answer() {
    # The whole defect in one assertion: whatever sudo reports, a home
    # directory is not on it, so a link there is invisible to root.
    sudo() { return 127; }
    assert_fails grep -q "$HOME" <<< "$(_sudo_path)"
    unset -f sudo
}

# --- can root already see it -------------------------------------------------

#[test]
it_says_root_can_see_an_interpreter_that_is_on_sudos_path() {
    local d; d="$(mktemp -d)"
    printf '#!/bin/sh\n' > "${d}/nutshell"; chmod +x "${d}/nutshell"
    sudo() { printf 'secure_path: %s\n' "$d"; }
    assert_ok _sudo_can_see
    unset -f sudo; rm -rf "$d"
}

#[test]
it_says_root_cannot_see_one_that_is_only_in_a_home_directory() {
    # The reported failure, reproduced: the interpreter exists, it is
    # executable, it is on the user's PATH, and root cannot reach it.
    local d; d="$(mktemp -d)"
    printf '#!/bin/sh\n' > "${d}/nutshell"; chmod +x "${d}/nutshell"
    local empty; empty="$(mktemp -d)"
    sudo() { printf 'secure_path: %s\n' "$empty"; }
    PATH="${d}:${PATH}" assert_fails _sudo_can_see
    unset -f sudo; rm -rf "$d" "$empty"
}

#[test]
it_does_not_count_a_file_that_is_not_executable() {
    # A leftover, a partial copy, or a link to a checkout that moved. Counting
    # one means reporting success and leaving sudo broken.
    local d; d="$(mktemp -d)"
    printf 'not a program\n' > "${d}/nutshell"
    chmod 644 "${d}/nutshell"
    sudo() { printf 'secure_path: %s\n' "$d"; }
    assert_fails _sudo_can_see
    unset -f sudo; rm -rf "$d"
}

#[test]
it_does_not_count_a_directory_that_is_not_there() {
    sudo() { printf 'secure_path: /no/such/dir:/nor/this\n'; }
    assert_fails _sudo_can_see
    unset -f sudo
}

# --- where the system link goes ----------------------------------------------

#[test]
it_links_into_the_first_directory_on_sudos_path_that_exists() {
    local a b; a="$(mktemp -d)"; b="$(mktemp -d)"
    sudo() { printf 'secure_path: /no/such/dir:%s:%s\n' "$a" "$b"; }
    assert_ok _system_link
    assert_ok test -L "${a}/nutshell"
    assert_fails test -e "${b}/nutshell"
    unset -f sudo; rm -rf "$a" "$b"
}

#[test]
it_skips_the_sbin_directories() {
    # `secure_path` leads with `/usr/local/sbin` on most distributions, and an
    # interpreter is not a system binary. A link there works and is wrong, and
    # nothing would ever say so.
    local sb b; sb="$(mktemp -d)/sbin"; mkdir -p "$sb"; b="$(mktemp -d)"
    sudo() { printf 'secure_path: %s:%s\n' "$sb" "$b"; }
    assert_ok _system_link
    assert_fails test -e "${sb}/nutshell"
    assert_ok    test -L "${b}/nutshell"
    unset -f sudo; rm -rf "$sb" "$b"
}

#[test]
it_points_the_link_at_this_checkout() {
    # A link is only worth having if it reaches the interpreter that installed
    # it. Pointing at a checkout that has moved is the stale case the whole
    # script exists to repair.
    local d; d="$(mktemp -d)"
    sudo() { printf 'secure_path: %s\n' "$d"; }
    _system_link
    assert_eq "$(readlink "${d}/nutshell")" "$TARGET"
    unset -f sudo; rm -rf "$d"
}

#[test]
it_does_nothing_when_the_link_is_already_right() {
    local d; d="$(mktemp -d)"
    sudo() { printf 'secure_path: %s\n' "$d"; }
    ln -sfn "$TARGET" "${d}/nutshell"
    local out; out="$(_system_link 2>&1)"
    assert_contains "$out" "already"
    unset -f sudo; rm -rf "$d"
}

#[test]
it_replaces_a_link_pointing_somewhere_else() {
    # The stale case. Refusing would leave the broken one in place, which is
    # the reasoning the user-side link already follows.
    local d; d="$(mktemp -d)"
    sudo() { printf 'secure_path: %s\n' "$d"; }
    ln -sfn /bin/false "${d}/nutshell"
    assert_ok _system_link
    assert_eq "$(readlink "${d}/nutshell")" "$TARGET"
    unset -f sudo; rm -rf "$d"
}

#[test]
it_refuses_to_replace_a_real_file() {
    # Somebody's own program, or a distribution package. Overwriting one
    # because it shares a name is not a thing an installer gets to do.
    local d; d="$(mktemp -d)"
    printf 'somebody else\n' > "${d}/nutshell"
    sudo() { printf 'secure_path: %s\n' "$d"; }
    assert_fails _system_link
    assert_eq "$(cat "${d}/nutshell")" "somebody else"
    unset -f sudo; rm -rf "$d"
}

#[test]
it_reports_rather_than_links_when_nothing_on_the_path_exists() {
    sudo() { printf 'secure_path: /no/such/dir:/nor/this\n'; }
    local out; out="$(_system_link 2>&1)" || true
    assert_fails _system_link
    assert_contains "$out" "nothing on sudo path"
    unset -f sudo
}

# --- taking it back out ------------------------------------------------------

#[test]
it_removes_the_system_link_from_wherever_sudo_says_it_is() {
    # The uninstall used to walk a hardcoded `/usr/local/bin /usr/bin`, which
    # is right on a stock machine and wrong on exactly the configured one the
    # install reads sudo to catch. A directory on neither list held the link
    # the install had just put there, and the uninstall reported success.
    local d; d="$(mktemp -d)"
    sudo() { printf 'secure_path: %s\n' "$d"; }
    _user_dirs() { printf '%s\n' "$(mktemp -d)"; }

    assert_ok _system_link
    assert_ok test -L "${d}/nutshell"
    assert_ok _uninstall
    assert_fails test -e "${d}/nutshell"

    unset -f sudo _user_dirs; rm -rf "$d"
}

#[test]
it_removes_the_user_link_from_the_same_list_the_install_picks_from() {
    # One list, two readers. Stub it and both must move, which is the property
    # that makes the pair above unable to disagree again.
    local u s; u="$(mktemp -d)"; s="$(mktemp -d)"
    sudo() { printf 'secure_path: %s\n' "$s"; }
    _user_dirs() { printf '%s\n' "$u"; }
    PATH="${u}:${PATH}"

    assert_eq "$(_pick_dir)" "$u"
    ln -sfn "$TARGET" "${u}/nutshell"
    assert_ok _uninstall
    assert_fails test -e "${u}/nutshell"

    unset -f sudo _user_dirs; rm -rf "$u" "$s"
}

#[test]
it_leaves_a_real_file_alone_when_uninstalling() {
    # Somebody else's `nutshell` on the path is not ours to delete, and an
    # uninstall that took one would be worse than one that left a link behind.
    local d; d="$(mktemp -d)"
    printf 'somebody else\n' > "${d}/nutshell"
    sudo() { printf 'secure_path: %s\n' "$d"; }
    _user_dirs() { printf '%s\n' "$(mktemp -d)"; }

    assert_ok _uninstall
    assert_eq "$(cat "${d}/nutshell")" "somebody else"

    unset -f sudo _user_dirs; rm -rf "$d"
}

#[test]
it_leaves_a_symlink_that_points_somewhere_else_alone() {
    # The harder half of the arm above, and the one that shipped wrong. A real
    # file was refused; a symlink was not, so any link named `nutshell` on
    # sudo's path was removed, with root behind it where the directory was not
    # writable. Two checkouts on one machine, or a distribution package
    # shipping `/usr/bin/nutshell` into its own tree, and an uninstall from one
    # took the other's.
    local d other; d="$(mktemp -d)"; other="$(mktemp -d)"
    : > "${other}/somebody-elses-thing"
    ln -sfn "${other}/somebody-elses-thing" "${d}/nutshell"
    sudo() { printf 'secure_path: %s\n' "$d"; }
    _user_dirs() { printf '%s\n' "$(mktemp -d)"; }

    local out; out="$(_uninstall 2>&1)"
    assert_ok test -L "${d}/nutshell"
    assert_contains "$out" "points elsewhere"

    # the control: a link that is ours, in the same directory, still goes
    ln -sfn "${other}/bin/nutshell" "${d}/nutshell"
    _uninstall > /dev/null 2>&1
    assert_fails test -L "${d}/nutshell"

    unset -f sudo _user_dirs; rm -rf "$d" "$other"
}

#[test]
it_says_so_rather_than_reporting_success_when_the_user_link_will_not_come_out() {
    # The system half got the writability split and the user half did not, so a
    # root-owned directory on the user list, and `/usr/local/bin` is one on a
    # stock linux, produced `rm: Permission denied` on stderr, a return of 0,
    # and a summary saying the uninstall was done with the link still there.
    # That is the defect this branch is named for, in the half nobody read.
    local d target; d="$(mktemp -d)"; target="$(mktemp -d)"
    ln -sfn "${target}/bin/nutshell" "${d}/nutshell"
    chmod 555 "$d"
    sudo() { printf 'secure_path: %s\n' "$(mktemp -d)"; }
    _user_dirs() { printf '%s\n' "$d"; }
    # elevation refused, which is the case where the link genuinely stays
    priv_run() { return 1; }

    local out; out="$(_uninstall 2>&1)"
    assert_contains "$out" "left ${d}/nutshell in place"
    assert_not_contains "$out" "removed ${d}/nutshell"
    assert_ok test -L "${d}/nutshell"

    unset -f sudo _user_dirs priv_run
    chmod 755 "$d"; rm -rf "$d" "$target"
}

#[test]
it_says_the_same_when_the_system_link_will_not_come_out() {
    # The twin of the arm above, over the other list. The two halves were the
    # same twelve lines written twice and the writability split was in one of
    # them, so this is what says they cannot drift apart again: they are one
    # function now, and both lists reach it.
    local d target; d="$(mktemp -d)"; target="$(mktemp -d)"
    ln -sfn "${target}/bin/nutshell" "${d}/nutshell"
    chmod 555 "$d"
    sudo() { printf 'secure_path: %s\n' "$d"; }
    _user_dirs() { printf '%s\n' "$(mktemp -d)"; }
    priv_run() { return 1; }

    local out; out="$(_uninstall 2>&1)"
    assert_contains "$out" "left ${d}/nutshell in place"
    assert_not_contains "$out" "removed ${d}/nutshell"
    assert_ok test -L "${d}/nutshell"

    unset -f sudo _user_dirs priv_run
    chmod 755 "$d"; rm -rf "$d" "$target"
}

# --- the system step, which is reached from one place ------------------------

#[test]
it_does_not_reach_for_the_system_link_when_the_system_half_was_declined() {
    # `--no-system`. The install has no business asking for a password it was
    # told not to want.
    local d; d="$(mktemp -d)"
    sudo() { printf 'secure_path: %s\n' "$d"; }
    assert_ok _ensure_sudo_finds_it 0
    assert_fails test -e "${d}/nutshell"
    unset -f sudo; rm -rf "$d"
}

#[test]
it_links_for_root_when_root_cannot_already_see_it() {
    local d; d="$(mktemp -d)"
    sudo() { printf 'secure_path: %s\n' "$d"; }
    assert_ok _ensure_sudo_finds_it 1
    assert_ok test -L "${d}/nutshell"
    unset -f sudo; rm -rf "$d"
}

#[test]
it_says_so_and_links_nothing_when_root_can_already_see_it() {
    local d; d="$(mktemp -d)"
    printf '#!/bin/sh\n' > "${d}/nutshell"; chmod +x "${d}/nutshell"
    sudo() { printf 'secure_path: %s\n' "$d"; }
    local out; out="$(_ensure_sudo_finds_it 1 2>&1)"
    assert_contains "$out" "sudo can find it too"
    assert_fails test -L "${d}/nutshell"
    unset -f sudo; rm -rf "$d"
}

#[test]
it_does_not_reach_for_root_after_its_own_probe_has_failed() {
    # The block was pasted twice and the second copy sat inside the failure
    # branch, so an install whose own shebang probe had just failed went on to
    # ask for a password to link a system directory. Both copies read correctly
    # on their own, which is why nothing caught it by reading.
    #
    # Driven rather than counted. The first version of this arm grepped the
    # script for the number of call sites, which is a claim about its text: two
    # calls on one line pass it, an unquoted argument passes it, and moving the
    # single call back inside the failure branch, which is the regression
    # itself, passes it too.
    #
    # `fs_temp_file` is stubbed to a path that cannot be written, so the probe
    # fails for a reason the script already handles, and `TARGET` is left alone,
    # being readonly.
    local marker; marker="$(mktemp)"; rm -f "$marker"
    local d; d="$(mktemp -d)"
    PATH="${d}:${PATH}"
    fs_temp_file() { printf '%s' "/no/such/directory/probe"; }
    _ensure_sudo_finds_it() { : > "$marker"; }

    local rc=0
    _main "$d" > /dev/null 2>&1 || rc=$?

    assert_ne "$rc" "0"
    assert_fails test -e "$marker"

    unset -f fs_temp_file _ensure_sudo_finds_it
    rm -rf "$d"
}

#[test]
it_reaches_for_the_system_link_once_the_probe_has_passed() {
    # The control for the arm above: the same drive with a probe that works,
    # where the system half must be reached. Without it, an install that never
    # reaches root at all passes the arm above and nothing says so.
    local marker; marker="$(mktemp)"; rm -f "$marker"
    local d; d="$(mktemp -d)"
    PATH="${d}:${PATH}"
    _ensure_sudo_finds_it() { : > "$marker"; }

    local rc=0
    _main "$d" > /dev/null 2>&1 || rc=$?

    assert_eq "$rc" "0"
    assert_ok test -e "$marker"

    unset -f _ensure_sudo_finds_it
    rm -f "$marker"; rm -rf "$d"
}

#[test]
it_takes_the_no_system_flag_wherever_it_is_written() {
    # `./install ~/bin --no-system` reads naturally and used to be read as a
    # directory argument plus nothing, so the flag was ignored, the system link
    # went in and a password was asked for. The flag is the whole reason
    # somebody types it.
    local marker; marker="$(mktemp)"; rm -f "$marker"
    local d; d="$(mktemp -d)"
    PATH="${d}:${PATH}"
    _ensure_sudo_finds_it() { [[ "${1:-1}" -eq 1 ]] && : > "$marker"; return 0; }

    _main "$d" --no-system > /dev/null 2>&1
    assert_fails test -e "$marker"

    # and the control, the same call without the flag, which must reach it
    _main "$d" > /dev/null 2>&1
    assert_ok test -e "$marker"

    unset -f _ensure_sudo_finds_it
    rm -f "$marker"; rm -rf "$d"
}
