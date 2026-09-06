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
    sudo() { printf 'Value to override user'\''s $PATH with: /opt/bin:/usr/bin\n'; }
    assert_eq "$(_sudo_path)" "/opt/bin:/usr/bin"
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
it_reaches_for_the_system_link_from_exactly_one_place() {
    # The block was pasted twice and the second copy sat inside the failure
    # branch, so an install whose own shebang probe had just failed went on to
    # ask for a password to link a system directory. Both copies read correctly
    # on their own, which is the whole reason nothing caught it, so the check
    # is the count rather than the reading.
    local n
    n="$(grep -c '_ensure_sudo_finds_it "' "${BASH_SOURCE[0]%/*}/../install")"
    assert_eq "$n" "1"
}
