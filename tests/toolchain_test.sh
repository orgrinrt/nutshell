#!/usr/bin/env bash
# Tests for several versions on one machine at once.
#
# The state this exists for is ordinary, not exceptional: two tools wanting two
# different nutshells, on a machine that has one of them. Failing there is the
# defect. The store keeps every version that has been asked for, the resolver
# takes the newest that satisfies the caller, and a version nobody has fetched
# yet is a download rather than an error.

use test

. "${BASH_SOURCE[0]%/*}/../find-nutshell"

_tc_setup() {
    TCROOT="$(mktemp -d)"
    export NUTSHELL_TOOLCHAINS="$TCROOT/store"
    export NUTSHELL_REMOTE="$TCROOT/remote.git"
    NUTSHELL_INIT=""; NUTSHELL_FROM=""
    unset NUTSHELL_HOME
    # Any directory holding a nutshell comes off PATH, so whatever is installed
    # on the machine running these tests cannot decide their answers. The rest
    # of PATH stays: these tests need git and the ordinary tools.
    _TC_PATH_KEEP="$PATH"
    local d out=""
    while IFS= read -r d; do
        [[ -n "$d" ]] || continue
        [[ -x "$d/nutshell" ]] && continue
        out="${out:+$out:}$d"
    done <<< "${PATH//:/$'\n'}"
    export PATH="$out"
}
_tc_end() {
    rm -rf "$TCROOT"
    unset TCROOT NUTSHELL_TOOLCHAINS NUTSHELL_REMOTE
    NUTSHELL_INIT=""; NUTSHELL_FROM=""
    export PATH="${_TC_PATH_KEEP:-$PATH}"
}

# A version sitting in the store.
_tc_store() {
    local v="$1" name="${2:-$1}"
    mkdir -p "$NUTSHELL_TOOLCHAINS/$name"
    printf 'export NUTSHELL_VERSION="%s"\n' "$v" \
        > "$NUTSHELL_TOOLCHAINS/$name/init"
}

# A remote holding one tagged version, so a fetch has somewhere real to go.
_tc_remote() {
    # Two statements: bash declares every name in one `local` before running
    # any of its assignments, so naming v in work's value reads it while it is
    # still unset and `set -u` stops the test dead.
    local v="$1"
    local work="$TCROOT/work-$v"
    mkdir -p "$work"
    printf 'export NUTSHELL_VERSION="%s"\n' "$v" > "$work/init"
    git -C "$work" init -q -b main
    git -C "$work" config user.email t@example.invalid
    git -C "$work" config user.name t
    git -C "$work" config commit.gpgsign false
    git -C "$work" config tag.gpgsign false
    git -C "$work" add -A
    git -C "$work" commit -qm "$v"
    # Annotated, with a message, because a machine whose git is set to force
    # annotated tags refuses a lightweight one and the error is "no tag
    # message?", which says nothing about tags being the subject.
    git -C "$work" tag -a "$v" -m "$v"
    [[ -d "$NUTSHELL_REMOTE" ]] || git init -q --bare "$NUTSHELL_REMOTE"
    git -C "$work" remote add origin "$NUTSHELL_REMOTE" 2>/dev/null || true
    git -C "$work" push -q origin main --tags 2>/dev/null || \
        git -C "$work" push -q origin "$v"
}

# --- where the store is ------------------------------------------------------

#[test]
it_takes_the_toolchain_directory_from_the_environment() {
    _tc_setup
    assert_eq "$(nutshell_toolchain_dir)" "$TCROOT/store"
    _tc_end
}

#[test]
it_puts_the_toolchains_under_the_store_root() {
    _tc_setup
    unset NUTSHELL_TOOLCHAINS
    assert_eq "$(NUTSHELL_STORE="$TCROOT/s" nutshell_toolchain_dir)" \
        "$TCROOT/s/toolchains"
    assert_eq "$(NUTSHELL_STORE="$TCROOT/s" nutshell_store_root)" "$TCROOT/s"
    _tc_end
}

#[test]
it_falls_back_to_the_data_directory() {
    _tc_setup
    unset NUTSHELL_TOOLCHAINS NUTSHELL_STORE
    assert_eq "$(XDG_DATA_HOME="$TCROOT/data" nutshell_toolchain_dir)" \
        "$TCROOT/data/nutshell/toolchains"
    _tc_end
}

#[test]
it_puts_the_store_where_the_platform_puts_application_data() {
    _tc_setup
    unset NUTSHELL_TOOLCHAINS NUTSHELL_STORE XDG_DATA_HOME
    local root; root="$(HOME="$TCROOT/h" nutshell_store_root)"
    case "$(uname -s)" in
        Darwin) assert_eq "$root" "$TCROOT/h/Library/Application Support/nutshell" ;;
        *)      assert_eq "$root" "$TCROOT/h/.local/share/nutshell" ;;
    esac
    _tc_end
}

#[test]
it_drops_a_trailing_slash_so_the_paths_under_it_are_not_doubled() {
    _tc_setup
    assert_eq "$(NUTSHELL_TOOLCHAINS="$TCROOT/store/" nutshell_toolchain_dir)" \
        "$TCROOT/store"
    unset NUTSHELL_TOOLCHAINS
    assert_eq "$(NUTSHELL_STORE="$TCROOT/s/" nutshell_store_root)" "$TCROOT/s"
    assert_eq "$(NUTSHELL_STORE="$TCROOT/s/" nutshell_toolchain_dir)" \
        "$TCROOT/s/toolchains"
    _tc_end
}

# --- what is in it -----------------------------------------------------------

#[test]
it_lists_nothing_when_the_store_is_not_there() {
    _tc_setup
    assert_empty "$(nutshell_toolchains)"
    _tc_end
}

#[test]
it_lists_nothing_when_the_store_is_empty() {
    _tc_setup
    mkdir -p "$NUTSHELL_TOOLCHAINS"
    assert_empty "$(nutshell_toolchains)"
    _tc_end
}

#[test]
it_lists_what_is_in_the_store_newest_first() {
    _tc_setup
    _tc_store 0.3.0; _tc_store 0.4.0; _tc_store 0.2.0
    assert_eq "$(nutshell_toolchains)" "$(printf '0.4.0\n0.3.0\n0.2.0')"
    _tc_end
}

#[test]
it_orders_by_number_and_not_by_spelling() {
    _tc_setup
    _tc_store 0.9.0; _tc_store 0.10.0; _tc_store 0.10.2
    # Every string comparison puts 0.9.0 above 0.10.0, and every one of them is
    # wrong.
    assert_eq "$(nutshell_toolchains)" "$(printf '0.10.2\n0.10.0\n0.9.0')"
    _tc_end
}

#[test]
it_skips_a_directory_with_no_interpreter_in_it() {
    _tc_setup
    _tc_store 0.4.0
    mkdir -p "$NUTSHELL_TOOLCHAINS/0.5.0"
    assert_eq "$(nutshell_toolchains)" "0.4.0"
    _tc_end
}

#[test]
it_skips_a_directory_whose_contents_disagree_with_its_name() {
    _tc_setup
    _tc_store 0.4.0
    _tc_store 0.1.0 0.9.9      # named 0.9.9, reports 0.1.0
    # The name is what the resolver looks things up by, so a directory that
    # lies about itself would be handed out for a request it cannot satisfy.
    assert_eq "$(nutshell_toolchains)" "0.4.0"
    _tc_end
}

# --- resolving out of it -----------------------------------------------------

#[test]
it_resolves_to_a_toolchain_when_nothing_is_installed() {
    _tc_setup
    _tc_store 0.4.0
    assert_ok nutshell_find "" 0.4.0
    assert_eq "$NUTSHELL_FROM" "toolchain"
    assert_eq "$NUTSHELL_INIT" "$NUTSHELL_TOOLCHAINS/0.4.0/init"
    _tc_end
}

#[test]
it_takes_the_newest_one_that_satisfies_the_caller() {
    _tc_setup
    _tc_store 0.3.0; _tc_store 0.4.0; _tc_store 0.5.0
    assert_ok nutshell_find "" 0.4.0
    assert_eq "$NUTSHELL_INIT" "$NUTSHELL_TOOLCHAINS/0.5.0/init"
    _tc_end
}

#[test]
it_will_not_take_one_older_than_the_caller_needs() {
    _tc_setup
    _tc_store 0.2.0; _tc_store 0.3.0
    # Nothing satisfies, nothing to fetch from: a refusal, not a wrong answer
    # that fails later with a missing function.
    assert_fails nutshell_find "" 0.4.0 2>/dev/null
    _tc_end
}

#[test]
it_takes_any_of_them_when_the_caller_names_no_minimum() {
    _tc_setup
    _tc_store 0.2.0; _tc_store 0.3.0
    assert_ok nutshell_find "" ""
    assert_eq "$NUTSHELL_INIT" "$NUTSHELL_TOOLCHAINS/0.3.0/init"
    _tc_end
}

#[test]
it_prefers_a_satisfying_installed_one_over_the_store() {
    _tc_setup
    _tc_store 0.9.0
    mkdir -p "$TCROOT/installed/bin"
    printf 'export NUTSHELL_VERSION="0.4.0"\n' > "$TCROOT/installed/init"
    printf '#!/usr/bin/env bash\n' > "$TCROOT/installed/bin/nutshell"
    chmod +x "$TCROOT/installed/bin/nutshell"
    export PATH="$TCROOT/installed/bin:$PATH"
    # One shared nutshell that everything uses is the good state. The store is
    # for the tools that cannot use it, not a replacement for it.
    assert_ok nutshell_find "" 0.4.0
    assert_eq "$NUTSHELL_FROM" "installed"
    _tc_end
}

#[test]
it_falls_to_the_store_when_the_installed_one_is_too_old() {
    _tc_setup
    _tc_store 0.4.0
    mkdir -p "$TCROOT/installed/bin"
    printf 'export NUTSHELL_VERSION="0.3.0"\n' > "$TCROOT/installed/init"
    printf '#!/usr/bin/env bash\n' > "$TCROOT/installed/bin/nutshell"
    chmod +x "$TCROOT/installed/bin/nutshell"
    export PATH="$TCROOT/installed/bin:$PATH"
    assert_ok nutshell_find "" 0.4.0 2>/dev/null
    assert_eq "$NUTSHELL_FROM" "toolchain"
    _tc_end
}

#[test]
it_prefers_the_store_over_a_vendored_copy() {
    _tc_setup
    _tc_store 0.4.0
    local root="$TCROOT/project"
    mkdir -p "$root/lib/nutshell"
    printf 'export NUTSHELL_VERSION="0.4.0"\n' > "$root/lib/nutshell/init"
    # The vendored copy is the compromise, kept for a machine with no network.
    assert_ok nutshell_find "$root" 0.4.0
    assert_eq "$NUTSHELL_FROM" "toolchain"
    _tc_end
}

# --- fetching ----------------------------------------------------------------

#[test]
it_fetches_a_version_that_is_not_here_yet() {
    _tc_setup
    _tc_remote 0.4.0
    assert_ok nutshell_find "" 0.4.0 2>/dev/null
    assert_eq "$NUTSHELL_FROM" "fetched"
    assert_eq "$NUTSHELL_INIT" "$NUTSHELL_TOOLCHAINS/0.4.0/init"
    # And it is in the store afterwards, so the next caller does not fetch it
    # again.
    assert_eq "$(nutshell_toolchains)" "0.4.0"
    _tc_end
}

#[test]
it_does_not_fetch_when_the_store_already_answers() {
    _tc_setup
    _tc_store 0.4.0
    # No remote at all. A fetch here would fail loudly, so silence is the
    # assertion.
    assert_ok nutshell_find "" 0.4.0
    assert_eq "$NUTSHELL_FROM" "toolchain"
    _tc_end
}

#[test]
it_refuses_a_fetch_whose_contents_report_another_version() {
    _tc_setup
    # Tagged 0.4.0, but the file inside says 0.1.0: a tag that moved, or a
    # branch name that happens to look like a version. Storing it under the
    # asked-for name would put a lie in the store for every later run.
    local work="$TCROOT/work"
    mkdir -p "$work"
    printf 'export NUTSHELL_VERSION="0.1.0"\n' > "$work/init"
    git -C "$work" init -q -b main
    git -C "$work" config user.email t@example.invalid
    git -C "$work" config user.name t
    git -C "$work" config commit.gpgsign false
    git -C "$work" config tag.gpgsign false
    git -C "$work" add -A; git -C "$work" commit -qm x
    git -C "$work" tag -a 0.4.0 -m 0.4.0
    git init -q --bare "$NUTSHELL_REMOTE"
    git -C "$work" remote add origin "$NUTSHELL_REMOTE"
    git -C "$work" push -q origin main --tags
    assert_fails nutshell_find "" 0.4.0 2>/dev/null
    assert_empty "$(nutshell_toolchains)"
    _tc_end
}

#[test]
it_leaves_no_half_a_toolchain_behind_when_the_fetch_fails() {
    _tc_setup
    export NUTSHELL_REMOTE="$TCROOT/no-such-remote.git"
    assert_fails nutshell_find "" 0.4.0 2>/dev/null
    assert_empty "$(nutshell_toolchains)"
    assert_fails test -e "$NUTSHELL_TOOLCHAINS/0.4.0"
    _tc_end
}

#[test]
it_falls_back_to_the_vendored_copy_when_the_fetch_cannot_happen() {
    _tc_setup
    export NUTSHELL_REMOTE="$TCROOT/no-such-remote.git"
    local root="$TCROOT/project"
    mkdir -p "$root/lib/nutshell"
    printf 'export NUTSHELL_VERSION="0.4.0"\n' > "$root/lib/nutshell/init"
    # The rescue machine: no network, nothing installed, and what is in the
    # tree is all there is.
    assert_ok nutshell_find "$root" 0.4.0 2>/dev/null
    assert_eq "$NUTSHELL_FROM" "vendored"
    _tc_end
}

#[test]
it_does_not_fetch_when_the_caller_names_no_version() {
    _tc_setup
    _tc_remote 0.4.0
    # Nothing to ask the remote for. Guessing at the newest would make an
    # unpinned tool track whatever was tagged last, silently.
    assert_fails nutshell_find "" "" 2>/dev/null
    assert_empty "$(nutshell_toolchains)"
    _tc_end
}

# --- the store is shared, and nothing in it is deleted while it is in use -----
#
# Every project on this machine resolves out of one store and nothing locks it.
# So the two dangerous moves are removing a directory another process is
# sourcing out of, and building a store path out of a name a caller supplied.

#[test]
it_adopts_the_copy_that_got_there_first_instead_of_deleting_it() {
    _tc_setup
    _tc_remote 0.4.0
    # A directory already in place, carrying a mark this test can recognise.
    # A fetch that deletes and replaces loses the mark; one that adopts what is
    # there keeps it, and both answers are the same version, which is the whole
    # reason adopting is allowed.
    mkdir -p "$NUTSHELL_TOOLCHAINS/0.4.0"
    printf 'export NUTSHELL_VERSION="0.4.0"\n' > "$NUTSHELL_TOOLCHAINS/0.4.0/init"
    printf 'in use\n' > "$NUTSHELL_TOOLCHAINS/0.4.0/marker"
    assert_ok _nutshell_fetch 0.4.0 >/dev/null 2>&1
    assert_ok test -f "$NUTSHELL_TOOLCHAINS/0.4.0/marker"
    _tc_end
}

#[test]
it_clears_the_scratch_copy_a_lost_race_left_inside_the_target() {
    _tc_setup
    local dir="$NUTSHELL_TOOLCHAINS/0.4.0" tmp="$NUTSHELL_TOOLCHAINS/0.4.0.fetching.99"
    mkdir -p "$dir"
    printf 'export NUTSHELL_VERSION="0.4.0"\n' > "$dir/init"
    printf 'in use\n' > "$dir/marker"
    mkdir -p "$tmp"
    printf 'export NUTSHELL_VERSION="0.4.0"\n' > "$tmp/init"

    # The state a loser actually reaches. The existence check and the rename
    # are two steps, so a directory that appeared between them turns the
    # rename into a move *inside* it, and `<dir>/<scratch>` is what that
    # leaves. Both the target and the store have to come out of this clean.
    assert_ok _nutshell_adopt "$tmp" "$dir"
    assert_ok test -f "$dir/marker"
    assert_fails test -e "$tmp"
    assert_fails test -e "$dir/0.4.0.fetching.99"
    _tc_end
}

#[test]
it_renames_the_scratch_copy_into_place_when_nothing_is_there() {
    _tc_setup
    local dir="$NUTSHELL_TOOLCHAINS/0.4.0" tmp="$NUTSHELL_TOOLCHAINS/0.4.0.fetching.99"
    mkdir -p "$tmp"
    printf 'export NUTSHELL_VERSION="0.4.0"\n' > "$tmp/init"
    printf 'fetched\n' > "$tmp/marker"

    # The winner's path, and the negative control for the one above: the copy
    # that arrives first is the one kept, not thrown away.
    assert_ok _nutshell_adopt "$tmp" "$dir"
    assert_ok test -f "$dir/marker"
    assert_fails test -e "$tmp"
    _tc_end
}

#[test]
it_refuses_a_version_name_that_would_escape_the_store() {
    _tc_setup
    local outside="$TCROOT/outside"
    mkdir -p "$outside"
    printf 'here\n' > "$outside/keep"
    # The name reaches `rm -rf "${store}/${want}"` in the old shape. It has to
    # be refused before a path is built out of it, not after.
    assert_fails _nutshell_fetch "../outside" 2>/dev/null
    assert_ok test -f "$outside/keep"
    _tc_end
}

#[test]
it_refuses_a_version_name_carrying_a_slash() {
    _tc_setup
    assert_fails _nutshell_fetch "0.4.0/../../etc" 2>/dev/null
    assert_fails _nutshell_fetch "" 2>/dev/null
    _tc_end
}

# --- a fetch that cannot succeed is not repeated on every invocation ----------
#
# The standing case, not a corner: a tool pinned at a version nobody has tagged
# resolves to vendored in the end and pays a network round trip on the way
# there, on every run of every tool on the machine.

#[test]
it_does_not_retry_a_fetch_that_just_failed() {
    _tc_setup
    export NUTSHELL_REMOTE="$TCROOT/no-such-remote.git"
    local root="$TCROOT/project"
    mkdir -p "$root/lib/nutshell"
    printf 'export NUTSHELL_VERSION="0.4.0"\n' > "$root/lib/nutshell/init"

    assert_ok nutshell_find "$root" 0.9.9 2>/dev/null
    assert_eq "$NUTSHELL_FROM" "vendored"
    # The second run says nothing, because it does not go looking again.
    local second; second="$(nutshell_find "$root" 0.9.9 2>&1 >/dev/null)"
    assert_fails grep -q 'could not fetch' <<<"$second"
    _tc_end
}

#[test]
it_tries_again_once_the_window_is_out() {
    _tc_setup
    export NUTSHELL_REMOTE="$TCROOT/no-such-remote.git"
    NUTSHELL_FETCH_RETRY=0 assert_fails _nutshell_fetch 0.9.9 2>/dev/null
    # A zero window is no window: the negative cache must not be a way to
    # never fetch again.
    assert_fails NUTSHELL_FETCH_RETRY=0 _nutshell_fetch_failed_recently 0.9.9
    assert_ok _nutshell_fetch_failed_recently 0.9.9
    _tc_end
}

#[test]
it_remembers_nothing_about_a_fetch_that_worked() {
    _tc_setup
    _tc_remote 0.4.0
    assert_ok _nutshell_fetch 0.4.0 >/dev/null 2>&1
    assert_fails _nutshell_fetch_failed_recently 0.4.0
    _tc_end
}

# --- the store is release-only, and says so -----------------------------------
#
# `_nutshell_num` trims a version field at the first non-digit, and the comment
# on it used to say that made `0.4.0-rc1` sort beside `0.4.0`. It cannot arrive
# to be sorted. These are the two gates that stop it.

#[test]
it_skips_a_directory_whose_name_is_not_the_version_inside_it() {
    _tc_setup
    # The interpreter reports `0.4.0`; the directory claims a prerelease. The
    # name is what the resolver looks up by, so a directory that disagrees with
    # itself would be handed out for a request it does not satisfy.
    _tc_store 0.4.0 "0.4.0-rc1"
    assert_empty "$(nutshell_toolchains)"
    _tc_end
}

#[test]
it_refuses_to_store_a_fetch_whose_version_is_not_the_name_asked_for() {
    _tc_setup
    _tc_remote 0.4.0
    # A tag spelled as a prerelease, holding an interpreter that reports the
    # plain version. There is nowhere in the store for it to go.
    local work="$TCROOT/work-0.4.0"
    git -C "$work" tag -a "0.4.0-rc1" -m rc
    git -C "$work" push -q origin "0.4.0-rc1"
    assert_fails _nutshell_fetch "0.4.0-rc1" 2>/dev/null
    assert_fails test -e "$NUTSHELL_TOOLCHAINS/0.4.0-rc1"
    _tc_end
}

# --- the store root is spelled twice, and only this holds the two together ----

#[test]
it_derives_the_same_store_root_as_the_xdg_module_does() {
    # `find-nutshell` runs before nutshell exists and cannot `use xdg`, so the
    # platform branch is written out in both places. Its own comment says the
    # two are "held together by a test rather than by anybody remembering",
    # and no such test existed: `grep -rn xdg_data_home tests/` returned
    # nothing, and the nearest one restated find-nutshell's own literals back
    # to it without ever calling the module.
    #
    # This calls both and compares, so changing one and not the other fails
    # here rather than on somebody's machine.
    local keep_store="${NUTSHELL_STORE:-}" keep_tc="${NUTSHELL_TOOLCHAINS:-}"
    unset NUTSHELL_STORE NUTSHELL_TOOLCHAINS

    use xdg
    xdg_set_app_name nutshell
    local from_module; from_module="$(xdg_app_data)"
    local from_resolver; from_resolver="$(nutshell_store_root)"

    assert_ne "$from_module" ""
    assert_eq "$from_resolver" "$from_module"

    [[ -n "$keep_store" ]] && export NUTSHELL_STORE="$keep_store"
    [[ -n "$keep_tc" ]] && export NUTSHELL_TOOLCHAINS="$keep_tc"
    return 0
}

#[test]
it_follows_the_data_home_override_the_same_way_the_module_does() {
    # The branch that actually differs between platforms, exercised rather
    # than assumed: with the variable set, both must follow it.
    local keep_store="${NUTSHELL_STORE:-}" keep_tc="${NUTSHELL_TOOLCHAINS:-}"
    unset NUTSHELL_STORE NUTSHELL_TOOLCHAINS

    use xdg
    local probe="/tmp/nut-xdg-probe"
    local from_module from_resolver
    from_module="$(XDG_DATA_HOME="$probe" bash -c '
        . "'"$PWD"'/init" >/dev/null 2>&1
        use xdg; xdg_set_app_name nutshell; xdg_app_data')"
    from_resolver="$(XDG_DATA_HOME="$probe" nutshell_store_root)"

    assert_contains "$from_resolver" "$probe"
    assert_eq "$from_resolver" "$from_module"

    [[ -n "$keep_store" ]] && export NUTSHELL_STORE="$keep_store"
    [[ -n "$keep_tc" ]] && export NUTSHELL_TOOLCHAINS="$keep_tc"
    return 0
}
