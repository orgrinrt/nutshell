#!/usr/bin/env bash
# Tests for keeping a check's answer until it can change.
#
# A cache that is wrong is worse than a check that is slow, so most of this is
# about what has to invalidate it. Three things can: the file, the check that
# read it, and the config the thresholds came from. op's point, and the one an
# obvious implementation misses: the checker counts. A cache over the file
# alone keeps answering with the old check's opinion after the check changes,
# and nothing says so.

use test
use checkcache

_cc_setup() {
    CCROOT="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-cc.XXXXXX")"
    export NUT_CACHE_DIR="$CCROOT/cache"
    export NUT_CACHE_ENABLED=1
    export NUT_CACHE_CHECKER="$CCROOT/checker.sh"
    printf 'a checker\n' > "$NUT_CACHE_CHECKER"
    printf 'some source\n' > "$CCROOT/src.sh"
    CONFIG_FILE="$CCROOT/nut.toml"; printf 'threshold = 1\n' > "$CONFIG_FILE"
    # Everything below wants the entry to be newer than its inputs, and a
    # filesystem with one-second stamps cannot tell two writes apart.
    sleep 1
}
_cc_end() {
    rm -rf "$CCROOT"
    unset CCROOT NUT_CACHE_DIR NUT_CACHE_ENABLED NUT_CACHE_CHECKER CONFIG_FILE
}

#[test]
it_has_nothing_before_anything_is_written() {
    _cc_setup
    assert_fails nut_cache_hit probe "$CCROOT/src.sh"
    _cc_end
}

#[test]
it_gives_back_what_was_kept() {
    _cc_setup
    nut_cache_write probe "$CCROOT/src.sh" 'two findings here'
    assert_ok nut_cache_hit probe "$CCROOT/src.sh"
    assert_eq "$(nut_cache_read probe "$CCROOT/src.sh")" "two findings here"
    _cc_end
}

#[test]
it_forgets_when_the_file_changes() {
    _cc_setup
    nut_cache_write probe "$CCROOT/src.sh" 'old answer'
    sleep 1
    printf 'edited\n' > "$CCROOT/src.sh"
    assert_fails nut_cache_hit probe "$CCROOT/src.sh"
    _cc_end
}

#[test]
it_forgets_when_the_check_itself_changes() {
    _cc_setup
    nut_cache_write probe "$CCROOT/src.sh" 'old answer'
    sleep 1
    # The one an obvious cache misses. The file is untouched and the answer is
    # still wrong, because a different check is asking.
    printf 'a checker, with another step\n' > "$NUT_CACHE_CHECKER"
    assert_fails nut_cache_hit probe "$CCROOT/src.sh"
    _cc_end
}

#[test]
it_forgets_when_the_thresholds_change() {
    _cc_setup
    nut_cache_write probe "$CCROOT/src.sh" 'old answer'
    sleep 1
    printf 'threshold = 2\n' > "$CONFIG_FILE"
    assert_fails nut_cache_hit probe "$CCROOT/src.sh"
    _cc_end
}

#[test]
it_keeps_one_answer_per_check_for_the_same_file() {
    _cc_setup
    nut_cache_write one "$CCROOT/src.sh" 'what one thinks'
    nut_cache_write two "$CCROOT/src.sh" 'what two thinks'
    assert_eq "$(nut_cache_read one "$CCROOT/src.sh")" "what one thinks"
    assert_eq "$(nut_cache_read two "$CCROOT/src.sh")" "what two thinks"
    _cc_end
}

#[test]
it_answers_nothing_when_the_checker_is_not_named() {
    _cc_setup
    nut_cache_write probe "$CCROOT/src.sh" 'answer'
    unset NUT_CACHE_CHECKER
    # A check that will not say which file it is cannot be cached, because
    # there is no way to notice it changing.
    assert_fails nut_cache_hit probe "$CCROOT/src.sh"
    _cc_end
}

#[test]
it_stays_out_of_the_way_until_it_is_turned_on() {
    _cc_setup
    NUT_CACHE_ENABLED=0
    nut_cache_write probe "$CCROOT/src.sh" 'answer'
    assert_fails nut_cache_hit probe "$CCROOT/src.sh"
    # And nothing was written, so turning it on later does not find a stale one.
    NUT_CACHE_ENABLED=1
    assert_fails nut_cache_hit probe "$CCROOT/src.sh"
    _cc_end
}

#[test]
it_forgets_a_file_that_is_no_longer_there() {
    _cc_setup
    nut_cache_write probe "$CCROOT/src.sh" 'answer'
    rm -f "$CCROOT/src.sh"
    assert_fails nut_cache_hit probe "$CCROOT/src.sh"
    _cc_end
}

#[test]
it_can_be_thrown_away() {
    _cc_setup
    nut_cache_write one "$CCROOT/src.sh" 'a'
    nut_cache_write two "$CCROOT/src.sh" 'b'
    nut_cache_clear one
    assert_fails nut_cache_hit one "$CCROOT/src.sh"
    assert_ok    nut_cache_hit two "$CCROOT/src.sh"
    nut_cache_clear
    assert_fails nut_cache_hit two "$CCROOT/src.sh"
    _cc_end
}

#[test]
it_keeps_every_computed_entry_inside_the_cache_directory() {
    _cc_setup
    local root; root="$(_nut_cache_root)"
    local name entry
    # The old version of this asserted a file outside was not overwritten,
    # which held for every possible argument because the substitution had
    # already removed every `/`. It read as a security test and restated a
    # substitution. This asserts the computed path instead, over names chosen
    # to escape if anything could.
    for name in '../../etc/passwd' '/etc/passwd' '..' '.' '-rf' \
                'a/b/../../../c' "$(printf 'new\nline')" '$(touch /tmp/nut-pwn)' \
                '~/x' 'a b' "*"; do
        entry="$(_nut_cache_path probe "$name")" || continue
        assert_contains "$entry" "$root"
        assert_fails grep -q '/\.\./' <<<"$entry"
    done
    assert_fails test -e /tmp/nut-pwn
    _cc_end
}

#[test]
it_does_not_give_one_file_the_answer_meant_for_another() {
    _cc_setup
    # Flattening every separator to `_` mapped `lib/toml/json.sh` and
    # `lib/toml_json.sh` onto one entry, so the answer for one was served for
    # the other. Both exist in this repository.
    printf 'one\n' > "$CCROOT/a.sh"; printf 'two\n' > "$CCROOT/b.sh"
    sleep 1
    nut_cache_write probe "$CCROOT/a.sh" "answer for a"
    assert_ne "$(_nut_cache_path probe 'lib/toml/json.sh')" \
              "$(_nut_cache_path probe 'lib/toml_json.sh')"
    assert_fails nut_cache_hit probe "$CCROOT/b.sh"
    _cc_end
}

#[test]
it_forgets_when_a_file_changes_without_its_time_moving_forward() {
    _cc_setup
    nut_cache_write probe "$CCROOT/src.sh" 'FINDING: none'
    # `tar -x`, `rsync -a`, `cp -p` and `touch -t` all move mtime backwards,
    # and `-nt` only sees it move forward. Reproduced before this was fixed:
    # the cache served "no findings" for a file whose contents had been
    # replaced wholesale, which is the one direction a cache must not be wrong.
    printf 'COMPLETELY DIFFERENT AND LONGER\n' > "$CCROOT/src.sh"
    touch -t 200001010000 "$CCROOT/src.sh"
    assert_fails nut_cache_hit probe "$CCROOT/src.sh"
    _cc_end
}

#[test]
it_forgets_when_the_content_changes_and_the_time_does_not() {
    _cc_setup
    # A reference whose mtime the file is restored to, so the only thing that
    # moves is the content and its size. Two `git checkout`s inside one second
    # do this, and so does `touch -r` and any build step that restores times.
    #
    # The previous version of this test moved the mtime *backward*, which is
    # what the test above it already covers, so it passed on a key the size was
    # not actually in. The size was stat'd and then discarded by a `${v##* }`
    # that took the path.
    local ref="$CCROOT/ref"; printf 'r\n' > "$ref"
    touch -r "$ref" "$CCROOT/src.sh"
    nut_cache_write probe "$CCROOT/src.sh" 'answer'
    assert_ok nut_cache_hit probe "$CCROOT/src.sh"

    printf 'a much longer line than before\n' > "$CCROOT/src.sh"
    touch -r "$ref" "$CCROOT/src.sh"

    # Same mtime, different size.
    assert_fails nut_cache_hit probe "$CCROOT/src.sh"
    _cc_end
}

#[test]
it_forgets_when_a_module_the_check_uses_is_edited_in_place() {
    _cc_setup
    # A check is not one file. `check_trivial_wrappers` gets its behaviour from
    # `lib/srcfile.sh`, so editing that changes what it reports while touching
    # neither the check nor the config, and op's ruling is that a check gaining
    # a step reads everything again.
    #
    # A real edit, under a scratch interpreter root. The previous version of
    # this test hand-set `_NUT_CACHE_BASE` and asserted a miss, which restated
    # the string comparison in `nut_cache_hit` and never entered the function
    # that computes it. The defect it was named for survived that test: the
    # computation stat'd the `lib` directory, whose mtime moves when an entry
    # is added or removed and not when a file inside it is edited.
    local fake="$CCROOT/fakenut"
    mkdir -p "$fake/lib"
    printf 'a module\n' > "$fake/lib/srcfile.sh"
    printf 'an init\n' > "$fake/init"

    local keep="${NUTSHELL_ROOT:-}"
    export NUTSHELL_ROOT="$fake"
    _NUT_CACHE_BASE=""

    nut_cache_write probe "$CCROOT/src.sh" 'answer'
    assert_ok nut_cache_hit probe "$CCROOT/src.sh"

    sleep 1
    printf 'a module, with another step\n' > "$fake/lib/srcfile.sh"
    _NUT_CACHE_BASE=""

    assert_fails nut_cache_hit probe "$CCROOT/src.sh"

    export NUTSHELL_ROOT="$keep"
    _NUT_CACHE_BASE=""
    _cc_end
}

#[test]
it_refuses_a_hit_when_the_config_is_not_named_at_all() {
    _cc_setup
    nut_cache_write probe "$CCROOT/src.sh" 'answer'
    unset CONFIG_FILE
    # The config test used to sit inside `if [[ -n "$CONFIG_FILE" ]]`, so an
    # unset one skipped it and the entry hit anyway, while the header said
    # freshness meant newer than the config.
    assert_fails nut_cache_hit probe "$CCROOT/src.sh"
    _cc_end
}

#[test]
it_refuses_an_entry_written_in_an_older_format() {
    _cc_setup
    nut_cache_write probe "$CCROOT/src.sh" 'answer'
    local entry; entry="$(_nut_cache_path probe "$CCROOT/src.sh")"
    # The store is shared by every nutshell on the machine. An entry from a
    # version that meant something else by its stamp is a miss, not a lie.
    { printf 'f1:whatever|0 0|0 0|0 0\n'; printf 'stale answer'; } > "$entry"
    assert_fails nut_cache_hit probe "$CCROOT/src.sh"
    _cc_end
}

# --- which stat this machine has ---------------------------------------------
#
# The flavour is decided by what `stat` prints, not by what it returns, and
# the difference only shows on the platform this was not developed on.
#
# BSD spells the format `-f`. GNU spells it `-c`, and its own `-f` asks for
# file-system status and does not know `%m`. A chooser written as
# `stat -f … || stat -c …` therefore reads the wrong thing on Linux while
# exiting 0, so the fallback never fires and every stamp is garbage that
# compares equal to itself. Invalidation stops with nothing to show for it.
#
# GNU is unavailable here, so it is planted: a `stat` that owns the whole PATH
# and behaves the way GNU's does. Prepending would let the machine's real one
# answer, which is how a stub test comes to prove nothing.

_stat_stub() {
    local dir="$1" kind="$2"
    mkdir -p "$dir"
    case "$kind" in
        gnu)
            # `-c` works and expands directives the way GNU does. `-f` exits 0
            # and prints filesystem noise, which is the whole hazard: written
            # against exit status, the chooser picks `-f` here and every stamp
            # on Linux is garbage that compares equal to itself.
            cat > "$dir/stat" <<'STUB'
#!/bin/sh
if [ "$1" = "-c" ]; then
    shift; fmt="$1"; shift
    for f do
        m=$(/usr/bin/stat -f '%m' "$f" 2>/dev/null) || exit 1
        z=$(/usr/bin/stat -f '%z' "$f" 2>/dev/null) || exit 1
        out=$fmt
        out=$(printf '%s' "$out" | sed -e "s|%Y|$m|g" -e "s|%s|$z|g" -e "s|%n|$f|g")
        printf '%s\n' "$out"
    done
    exit 0
fi
if [ "$1" = "-f" ]; then
    shift; shift
    for f do printf 'Blocks: Total: 1000 Free: 500\n'; done
    exit 0
fi
exit 1
STUB
            ;;
        bsd)
            cat > "$dir/stat" <<'STUB'
#!/bin/sh
[ "$1" = "-f" ] || exit 1
shift; fmt="$1"; shift
exec /usr/bin/stat -f "$fmt" "$@"
STUB
            ;;
        gnu-numeric)
            # The premise the digit test rested on, denied. A `stat` whose
            # wrong-flag output *starts with a number* passes any "first field
            # looks numeric" probe, and the chooser then picks `-f` on a
            # machine where `-f` is not a format flag at all. Nothing here can
            # rule such a `stat` out, so the detection stops depending on it.
            cat > "$dir/stat" <<'STUB'
#!/bin/sh
if [ "$1" = "-c" ]; then
    shift; fmt="$1"; shift
    for f do
        m=$(/usr/bin/stat -f '%m' "$f" 2>/dev/null) || exit 1
        z=$(/usr/bin/stat -f '%z' "$f" 2>/dev/null) || exit 1
        out=$(printf '%s' "$fmt" | sed -e "s|%Y|$m|g" -e "s|%s|$z|g" -e "s|%n|$f|g")
        printf '%s\n' "$out"
    done
    exit 0
fi
if [ "$1" = "-f" ]; then
    shift; shift
    for f do printf '4096 1000000 500000\n'; done
    exit 0
fi
exit 1
STUB
            ;;
        none)
            printf '#!/bin/sh\nexit 127\n' > "$dir/stat"
            ;;
    esac
    chmod +x "$dir/stat"

    # The stub owns the whole PATH. Prepending leaves the real one reachable
    # by anything that resolves a second time, and then the test is about the
    # machine rather than about the stub.
    for t in find sort head printf mktemp rm cat chmod sh sed grep; do
        [[ -e "$dir/$t" ]] && continue
        local real; real="$(command -v "$t" 2>/dev/null)" || continue
        ln -sf "$real" "$dir/$t"
    done
}

_stat_flag_under() {
    local dir="$1"
    bash -c '
        PATH="$1"; export PATH
        . "$2"/init || exit 1
        use checkcache
        _nut_cache_stat_flag || printf "NONE"
    ' _ "$dir" "$NUTSHELL_ROOT" 2>/dev/null
}

#[test]
it_picks_the_format_a_gnu_stat_understands() {
    local d; d="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-stat.XXXXXX")"
    _stat_stub "$d" gnu
    assert_eq "$(_stat_flag_under "$d")" "-c"
    rm -rf "$d"
}

#[test]
it_picks_the_format_a_bsd_stat_understands() {
    # The control. A probe that always answered `-c` would pass the one above
    # and be just as wrong, in the other direction.
    local d; d="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-stat.XXXXXX")"
    _stat_stub "$d" bsd
    assert_eq "$(_stat_flag_under "$d")" "-f"
    rm -rf "$d"
}

#[test]
it_says_so_rather_than_guessing_when_there_is_no_stat() {
    # A machine with neither has no stamps, and no stamps has to mean every
    # entry misses. Answering with a flag that does not work would mean every
    # entry hits on a stamp that never changes.
    local d; d="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-stat.XXXXXX")"
    _stat_stub "$d" none
    assert_eq "$(_stat_flag_under "$d")" "NONE"
    rm -rf "$d"
}

#[test]
it_reads_a_real_mtime_and_size_through_whichever_stat_it_picked() {
    # The flag being right is not the claim. The claim is that the numbers
    # coming back are this file's mtime and size, and a probe that accepted a
    # format printing `?` would satisfy the three above and fail this.
    local d; d="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-stat.XXXXXX")"
    _stat_stub "$d" gnu
    printf '0123456789' > "$d/probe.txt"

    local got
    got="$(bash -c '
        PATH="$1"; export PATH
        . "$2"/init || exit 1
        use checkcache
        _nut_cache_stat_into "$3"
        printf "%s" "${_NUT_CACHE_STAMP[$3]:-}"
    ' _ "$d" "$NUTSHELL_ROOT" "$d/probe.txt" 2>/dev/null)"

    assert_ne "$got" ""
    assert_eq "${got#* }" "10"
    [[ "${got%% *}" =~ ^[0-9]+$ ]] || _test_failed "mtime is not a number: [${got%% *}]"
    rm -rf "$d"
}

#[test]
it_is_not_fooled_by_a_stat_whose_wrong_flag_prints_numbers() {
    # The control for the two picks above, and the reason the detection writes
    # a file of known size rather than looking for a leading digit.
    #
    # This `stat` is GNU: `-c` is the format flag and `-f` asks about the file
    # system. Its `-f` output happens to begin with a block size. A probe that
    # accepted "the first field is a number" picks `-f` here and is wrong about
    # every stamp afterwards, on the platform where it matters.
    local d; d="$(mktemp -d "${TMPDIR:-/tmp}/nutshell-stat.XXXXXX")"
    _stat_stub "$d" gnu-numeric
    assert_eq "$(_stat_flag_under "$d")" "-c"
    rm -rf "$d"
}
