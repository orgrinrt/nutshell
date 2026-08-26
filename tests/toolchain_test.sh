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
