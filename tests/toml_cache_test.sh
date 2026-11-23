#!/usr/bin/env bash
# Tests for the tree the toml floor keeps between processes.
#
# Reading a 332-line manifest in bash takes about 37ms, and the interpreter and
# `deps` both read one before a script's first line: the engine pin and the
# `[deps.paths]` pins. A process keeps the tree it parsed, so what is cached
# here is the parse across processes, keyed by the file's text: a file whose
# text changed is parsed again, whatever its mtime says.
#
# Each process is a fresh bash under `env -i`, with its own cache directory, so
# nothing the test process holds reaches it. Each reads through the floor
# alone, `_TOML_FLOOR_ONLY`, since the floor is what keeps the tree; a tool's
# JSON is read again by the tool.

use test

INIT="${BASH_SOURCE[0]%/*}/../init"

_tc_fresh() {
    _TC_D="$(mktemp -d "${TMPDIR:-/tmp}/nut-tomlcache.XXXXXX")"
    printf '[package]\nname = "first"\n\n[deps.paths]\njq = "/opt/jq"\n' > "$_TC_D/nut.toml"
}

# _tc_read <key> [prelude] -> what `toml_get` printed, and stderr, in a new process
_tc_read() {
    env -i HOME="$HOME" PATH="$PATH" XDG_CACHE_HOME="${_TC_CACHE:-$_TC_D/cache}" \
        bash -c '. "$1" || exit 1; use toml; _TOML_FLOOR_ONLY=1; eval "$3"; toml_get "$2/nut.toml" "$4"' \
        _ "$INIT" "$_TC_D" "${2:-}" "$1" 2>&1
}

# A parse that says it ran, so a process answered from the kept tree is told
# apart from one that read the file again.
_TC_CANARY='_toml_parse_text() { printf "parsed "; _TOML_ERR="canary"; return 2; }'

#[test]
it_answers_a_second_process_from_the_tree_the_first_kept() {
    _tc_fresh
    local first second
    first="$(_tc_read package.name)"
    second="$(_tc_read package.name "$_TC_CANARY")"
    rm -rf "$_TC_D"
    assert_eq "$first" "first"
    assert_eq "$second" "first"
}

#[test]
it_parses_a_file_whose_text_changed_since_the_tree_was_kept() {
    # The positive control for the one above: the canary fires where there is
    # no kept tree for this text, so its silence there means something.
    _tc_fresh
    _tc_read package.name >/dev/null
    printf '[package]\nname = "second"\n' > "$_TC_D/nut.toml"
    local canary fresh
    canary="$(_tc_read package.name "$_TC_CANARY")"
    fresh="$(_tc_read package.name)"
    rm -rf "$_TC_D"
    assert_contains "$canary" "parsed"
    assert_eq "$fresh" "second"
}

#[test]
it_reads_the_file_where_the_cache_cannot_be_written() {
    _tc_fresh
    # A file where the directory would go, so nothing can be made under it.
    printf 'x' > "$_TC_D/cache"
    local out; out="$(_tc_read deps.paths.jq)"
    rm -rf "$_TC_D"
    assert_eq "$out" "/opt/jq"
}

#[test]
it_keeps_the_answers_of_a_table_and_an_array_through_the_cache() {
    # The tree is the whole tree, not the value asked for first: a second
    # process reading another key of the kept file gets that key.
    _tc_fresh
    printf '[a]\nlist = [1, 2, 3]\n[a.b]\n"k.d" = "dotted"\n' >> "$_TC_D/nut.toml"
    _tc_read package.name >/dev/null
    local list dotted
    list="$(_tc_read a.list "$_TC_CANARY")"
    dotted="$(_tc_read 'a.b."k.d"' "$_TC_CANARY")"
    rm -rf "$_TC_D"
    assert_eq "$list" "[1, 2, 3]"
    assert_eq "$dotted" "dotted"
}

# --- a kept tree nobody else could have written --------------------------------
#
# A kept tree is run as shell by the reader, so a file somebody else could write
# is code somebody else chose. Each plant below is a tree that would announce
# itself on stderr and refuse; the read must answer from the file, and say
# nothing of the plant.

# _tc_place -> `_TC_AT`, where the tree of `$_TC_D/nut.toml` is kept
_tc_place() {
    _TC_AT="$(env -i HOME="$HOME" PATH="$PATH" XDG_CACHE_HOME="${_TC_CACHE:-$_TC_D/cache}" \
        bash -c '. "$1" || exit 1; use toml; _toml_cache_at "$2/nut.toml" && printf %s "$_tca"' \
        _ "$INIT" "$_TC_D")"
}

# _tc_plant <file mode> <directory mode>: a tree that runs where it is read
_tc_plant() {
    _tc_place
    mkdir -p "${_TC_AT%/*}"
    printf 'printf "PLANTED "; return 1\n' > "$_TC_AT"
    chmod "$1" "$_TC_AT"
    chmod "$2" "${_TC_AT%/*}"
}

#[test]
it_runs_a_planted_tree_nobody_else_could_write_as_the_positive_control() {
    # Shows the plant is where the reader looks and does run when trusted, so
    # its silence in the two tests after this one means something.
    _tc_fresh
    _tc_plant 600 700
    local out; out="$(_tc_read package.name)"
    rm -rf "$_TC_D"
    assert_contains "$out" "PLANTED"
    assert_contains "$out" "first"
}

#[test]
it_reads_the_file_when_the_cache_path_is_a_fifo_or_a_device() {
    # Opening a FIFO blocks until a writer comes, and that open came before any
    # check of what the path is, so a FIFO planted there hung every start of
    # every script in the project. A device link is the same hazard.
    local kind out rc
    for kind in fifo device; do
        _tc_fresh
        _tc_place
        mkdir -p "${_TC_AT%/*}"
        chmod 700 "${_TC_AT%/*}"
        case "$kind" in
            fifo) mkfifo "$_TC_AT" ;;
            device) ln -s /dev/zero "$_TC_AT" ;;
        esac
        rc=0; out="$(timeout 10 bash -c "$(declare -f _tc_read); _TC_D='$_TC_D'; INIT='$INIT'; _tc_read package.name")" || rc=$?
        rm -rf "$_TC_D"
        assert_eq "${rc}/${out}" "0/first" "cache path is a ${kind}"
    done
}

#[test]
it_does_not_run_a_kept_tree_others_can_write() {
    local mode out
    for mode in 620 602 666; do
        _tc_fresh
        _tc_plant "$mode" 700
        out="$(_tc_read package.name)"
        rm -rf "$_TC_D"
        assert_eq "$out" "first" "file mode $mode"
    done
}

#[test]
it_does_not_run_a_kept_tree_in_a_directory_others_can_write() {
    local mode out
    for mode in 770 707 777 1777; do
        _tc_fresh
        _tc_plant 600 "$mode"
        out="$(_tc_read package.name)"
        rm -rf "$_TC_D"
        assert_eq "$out" "first" "directory mode $mode"
    done
}

#[test]
it_keeps_no_tree_where_there_is_no_home_for_one() {
    # With neither HOME nor XDG_CACHE_HOME there is no directory that is the
    # reader's own, and a shared fallback is one anybody can plant in.
    _tc_fresh
    local run='. "$1" || exit 1; use toml; _TOML_FLOOR_ONLY=1; eval "$3"; toml_get "$2/nut.toml" package.name'
    local first second
    first="$(env -i PATH="$PATH" bash -c "$run" _ "$INIT" "$_TC_D" "" 2>&1)"
    second="$(env -i PATH="$PATH" bash -c "$run" _ "$INIT" "$_TC_D" "$_TC_CANARY" 2>&1)"
    rm -rf "$_TC_D"
    assert_eq "$first" "first"
    assert_contains "$second" "parsed"
}

#[test]
it_keeps_a_tree_it_can_trust_again_under_any_umask() {
    # Written under a umask that would leave it open to everybody, the kept
    # tree is still one the next process takes.
    _tc_fresh
    local second
    (umask 000; _tc_read package.name >/dev/null)
    second="$(_tc_read package.name "$_TC_CANARY")"
    rm -rf "$_TC_D"
    assert_eq "$second" "first"
}

# --- a kept tree that no longer stands for the parse ---------------------------

#[test]
it_parses_again_where_the_floor_changed_after_the_tree_was_kept() {
    # A copy of the floor and of this file, so touching them touches nothing
    # else. Each of the four, made newer than the kept tree, sends the read
    # back to the parser.
    local g root out
    for g in impl/bash.sh impl/bash_lex.sh impl/bash_path.sh cache.sh; do
        _tc_fresh
        root="${INIT%/init}/lib/toml"
        mkdir -p "$_TC_D/floor/impl"
        cp "$root"/impl/bash.sh "$root"/impl/bash_lex.sh "$root"/impl/bash_path.sh "$_TC_D/floor/impl/"
        cp "$root"/cache.sh "$_TC_D/floor/"
        local pin="_TOML_CACHE_FLOOR=$_TC_D/floor/impl _TOML_CACHE_SELF=$_TC_D/floor/cache.sh"
        _tc_read package.name "$pin" >/dev/null
        touch -t 209901010000 "$_TC_D/floor/$g"
        out="$(_tc_read package.name "$pin; $_TC_CANARY")"
        rm -rf "$_TC_D"
        assert_contains "$out" "parsed" "$g newer than the tree"
    done
}

#[test]
it_takes_the_tree_while_the_floor_is_older_as_the_positive_control() {
    local root out
    _tc_fresh
    root="${INIT%/init}/lib/toml"
    mkdir -p "$_TC_D/floor/impl"
    cp "$root"/impl/bash.sh "$root"/impl/bash_lex.sh "$root"/impl/bash_path.sh "$_TC_D/floor/impl/"
    cp "$root"/cache.sh "$_TC_D/floor/"
    touch -t 200001010000 "$_TC_D/floor/impl/"*.sh "$_TC_D/floor/cache.sh"
    local pin="_TOML_CACHE_FLOOR=$_TC_D/floor/impl _TOML_CACHE_SELF=$_TC_D/floor/cache.sh"
    _tc_read package.name "$pin" >/dev/null
    out="$(_tc_read package.name "$pin; $_TC_CANARY")"
    rm -rf "$_TC_D"
    assert_eq "$out" "first"
}

#[test]
it_parses_again_under_another_bash() {
    _tc_fresh
    _tc_read package.name >/dev/null
    local out; out="$(_tc_read package.name "BASH_VERSION=0.0.0-other; $_TC_CANARY")"
    rm -rf "$_TC_D"
    assert_contains "$out" "parsed"
}

#[test]
it_reads_the_file_past_a_corrupt_kept_tree() {
    # Cut short, and garbage: each is read past in silence, and the answer is
    # the file's.
    local body out
    for body in 'garbage ((( "' "$(printf '[[ 1 ]]\n_TOML_T=([R]=table ')"; do
        _tc_fresh
        _tc_read package.name >/dev/null
        _tc_place
        printf '%s' "$body" > "$_TC_AT"
        out="$(_tc_read package.name)"
        rm -rf "$_TC_D"
        assert_eq "$out" "first" "kept tree: $body"
    done
}

#[test]
it_does_not_run_a_kept_tree_that_is_a_link() {
    # A link to a tree that would be trusted where it lies.
    local out
    _tc_fresh
    _tc_place
    mkdir -p "${_TC_AT%/*}" "$_TC_D/elsewhere"
    chmod 700 "$_TC_D/elsewhere"
    printf 'printf "PLANTED "; return 1\n' > "$_TC_D/elsewhere/tree"
    chmod 600 "$_TC_D/elsewhere/tree"
    ln -s "$_TC_D/elsewhere/tree" "$_TC_AT"
    out="$(_tc_read package.name)"
    rm -rf "$_TC_D"
    assert_eq "$out" "first"
}

#[test]
it_does_not_run_a_kept_tree_under_a_linked_directory() {
    # The tree's own directory, then the one above it, each a link to a
    # directory that would be trusted where it lies.
    local out level
    for level in 1 2; do
        _tc_fresh
        _tc_place
        local d="${_TC_AT%/*}"
        [[ "$level" == 2 ]] && d="${d%/*}"
        mkdir -p "${d%/*}" "$_TC_D/elsewhere"
        chmod 700 "$_TC_D/elsewhere"
        if [[ "$level" == 2 ]]; then
            mkdir -m 700 "$_TC_D/elsewhere/toml"
            ln -s "$_TC_D/elsewhere" "$d"
        else
            ln -s "$_TC_D/elsewhere" "$d"
        fi
        printf 'printf "PLANTED "; return 1\n' > "$_TC_AT"
        chmod 600 "$_TC_AT"
        out="$(_tc_read package.name)"
        rm -rf "$_TC_D"
        assert_eq "$out" "first" "a link $level directories up"
    done
}

#[test]
it_does_not_run_a_kept_tree_under_any_directory_others_can_write() {
    # Each directory from the tree's up to the cache root: one that others can
    # write is one where the tree, or a directory on its way, can be swapped.
    local out level d
    for level in 2 3; do
        _tc_fresh
        _tc_plant 600 700
        d="$_TC_AT"
        for (( i = 0; i < level; i++ )); do d="${d%/*}"; done
        chmod 777 "$d"
        out="$(_tc_read package.name)"
        chmod 700 "$d"
        rm -rf "$_TC_D"
        assert_eq "$out" "first" "mode 777 $level directories up: $d"
    done
}

#[test]
it_runs_the_tree_it_read_and_checked_not_one_swapped_in_after_the_check() {
    # The check is wrapped so the kept tree is swapped, for one others could
    # write, the moment it passes. What runs must be what was checked.
    local wrap out
    _tc_fresh
    _tc_read package.name >/dev/null
    wrap='src="$(declare -f _toml_cache_trusted)"; eval "_tc_real${src#_toml_cache}"
_toml_cache_trusted() {
    _tc_real_trusted "$@" || return 1
    printf "printf \"PLANTED \"; return 1\n" > "$1.x"; chmod 666 "$1.x"; mv -f "$1.x" "$1"
}'
    out="$(_tc_read package.name "$wrap")"
    rm -rf "$_TC_D"
    assert_eq "$out" "first"
}

# _tc_tools <dir> <log> -> fake `taplo`, `yq` and `find` in <dir>: the first two
# answer `--version` and fail every other call, so they can serve no file, and
# all three log each call that is not a version probe. `find` then runs the
# real one, on the PATH the test had.
_tc_tools() {
    local d="$1" log="$2" t
    mkdir -p "$d"
    for t in taplo yq; do
        printf '#!/bin/sh\ncase "$*" in\n  *--version*) echo "%s 9.9.9" ;;\n  *) echo "%s $*" >> "%s"; exit 1 ;;\nesac\n' \
            "$t" "$t" "$log" > "$d/$t"
        chmod +x "$d/$t"
    done
    printf '#!/bin/sh\necho "find $*" >> "%s"\nPATH="%s" exec find "$@"\n' "$log" "$PATH" > "$d/find"
    chmod +x "$d/find"
}

#[test]
it_answers_toml_get_from_a_kept_tree_without_running_a_backend() {
    # Every backend is a fake on PATH that logs being run. A process with a kept
    # tree for the text answers from it; the same process with no kept tree runs
    # one, which is the positive control that the fakes are the ones deps finds.
    _tc_fresh
    local log="$_TC_D/log" out ctl
    : > "$log"
    _tc_tools "$_TC_D/bin" "$log"
    _tc_read package.name > /dev/null
    out="$(env -i HOME="$HOME" PATH="$_TC_D/bin:$PATH" XDG_CACHE_HOME="$_TC_D/cache" \
        bash -c '. "$1" || exit 1; use toml; toml_get "$2/nut.toml" package.name' _ "$INIT" "$_TC_D" 2>&1)"
    assert_eq "$out" "first"
    assert_eq "$(grep -c -E '^(taplo|yq) ' "$log")" "0" "a backend ran with a kept tree"
    ctl="$(env -i HOME="$HOME" PATH="$_TC_D/bin:$PATH" XDG_CACHE_HOME="$_TC_D/other" \
        bash -c '. "$1" || exit 1; use toml; toml_get "$2/nut.toml" package.name' _ "$INIT" "$_TC_D" 2>&1)"
    assert_eq "$ctl" "first"
    [[ "$(grep -c -E '^(taplo|yq) ' "$log")" -gt 0 ]]
    assert_eq "$?" "0" "the fakes are run where no tree is kept"
    rm -rf "$_TC_D"
}

#[test]
it_answers_toml_to_json_from_a_kept_tree_without_running_a_backend() {
    _tc_fresh
    local log="$_TC_D/log" out
    : > "$log"
    _tc_tools "$_TC_D/bin" "$log"
    _tc_read package.name > /dev/null
    out="$(env -i HOME="$HOME" PATH="$_TC_D/bin:$PATH" XDG_CACHE_HOME="$_TC_D/cache" \
        bash -c '. "$1" || exit 1; use toml::json; toml_to_json "$2/nut.toml"' _ "$INIT" "$_TC_D" 2>&1)"
    assert_eq "$out" '{"package":{"name":"first"},"deps":{"paths":{"jq":"/opt/jq"}}}'
    assert_eq "$(grep -c -E '^(taplo|yq) ' "$log")" "0" "a backend ran with a kept tree"
    rm -rf "$_TC_D"
}

# _tc_two <log> <script> -> a process that reads two files, `a.toml` and
# `b.toml` in the fresh directory, whose trees are kept, with the fakes first
# on PATH
_tc_two() {
    env -i HOME="$HOME" PATH="$_TC_D/bin:$PATH" XDG_CACHE_HOME="$_TC_D/cache" \
        bash -c '. "$1" || exit 1; use toml; _TOML_FLOOR_ONLY=1; d="$2"; log="$3"
n() { grep -c "^find " "$log"; }
'"$2" _ "$INIT" "$_TC_D" "$1" 2>&1
}

_tc_two_prime() {
    printf 'k = "a"\n' > "$_TC_D/a.toml"
    printf 'k = "b"\n' > "$_TC_D/b.toml"
    : > "$_TC_D/log"
    _tc_tools "$_TC_D/bin" "$_TC_D/log"
    _tc_two "$_TC_D/log" 'toml_get "$d/a.toml" k; toml_get "$d/b.toml" k' > /dev/null
}

#[test]
it_forks_no_find_for_a_directory_or_file_already_trusted_in_this_process() {
    # The tree held is one file's, so each of these four opens loads from the
    # cache. The first of each file forks the one find that checks it, the first
    # of all checking the cache directories in that same find; the second open
    # of either, and every one after, forks none.
    _tc_fresh
    _tc_two_prime
    local out
    out="$(_tc_two "$_TC_D/log" ': > "$log"
toml_get "$d/a.toml" k; first=$(n)
toml_get "$d/b.toml" k; toml_get "$d/a.toml" k; toml_get "$d/b.toml" k
echo "first=$first after=$(n)"')"
    rm -rf "$_TC_D"
    assert_contains "$out" "first=1 after=2"
}

#[test]
it_checks_a_directory_again_once_another_inode_is_there() {
    # The same process as above, with the cache directory replaced by a copy of
    # it, same path and mode, between two opens: a different inode, so checked
    # again. The positive control for the test above, whose zero means little
    # without a case where the count rises.
    _tc_fresh
    _tc_two_prime
    local out
    out="$(_tc_two "$_TC_D/log" ': > "$log"
toml_get "$d/a.toml" k
t="$d/cache/nutshell/toml"; mv "$t" "$t.old"; cp -a "$t.old" "$t"
before=$(n)
toml_get "$d/b.toml" k
echo "before=$before after=$(n)"')"
    rm -rf "$_TC_D"
    assert_contains "$out" "before=1 after=2"
}

#[test]
it_does_not_trust_a_directory_that_others_can_write_after_it_was_swapped() {
    # The swapped-in directory is the one others can write: checked again, so
    # the planted tree in it is not run.
    _tc_fresh
    _tc_two_prime
    local out
    out="$(_tc_two "$_TC_D/log" ': > "$log"
toml_get "$d/a.toml" k >/dev/null
t="$d/cache/nutshell/toml"; mv "$t" "$t.old"; cp -a "$t.old" "$t"; chmod 777 "$t"
for f in "$t"/*; do printf "printf \"PLANTED \"; return 1\n" > "$f.x"; chmod 600 "$f.x"; mv -f "$f.x" "$f"; done
toml_get "$d/b.toml" k')"
    rm -rf "$_TC_D"
    assert_eq "$out" "b"
}
