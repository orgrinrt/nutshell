#!/usr/bin/env bash
# =============================================================================
# nutshell/checkcache - A check's answer for a file, kept until it can change
# =============================================================================
# Part of nutshell. https://github.com/orgrinrt/nutshell
#
# A check's finding about a file is a pure function of two things: the file,
# and the check that read it. Neither changes between two runs of the gate, and
# the overwhelming case is that nothing changed at all, so the overwhelming
# case should cost nothing.
#
# **The checker is part of the key, not just the file.** A check that gains a
# step, or tightens a threshold, has to read every file again; a cache over the
# file alone would keep answering with the old check's opinion and there would
# be no way to tell. The config counts for the same reason: the thresholds come
# out of `nut.toml` and they are what the answer was measured against.
#
# Freshness is a recorded stamp, not `-nt`.
#
# `-nt` only sees mtime moving forward, and `tar -x`, `rsync -a`, `cp -p` and
# `touch -t` all move it backward. A review reproduced it: content replaced
# wholesale, mtime set to 2000, and the cache served "no findings" for the new
# file. That is the one direction a cache must never be wrong in, and the
# header used to assert it could not happen.
#
# So an entry records what its inputs were, and a hit needs every one to match:
# the file's mtime and size, the same for the check script and the config, the
# newest mtime anywhere under the interpreter, and a format number.
#
# The interpreter is in there because a check is not one file. Editing
# `lib/srcfile.sh` changes what `check_trivial_wrappers` reports while touching
# neither the check nor the config, and op's ruling is explicit that a check
# gaining a step has to read everything again.
#
# The stamps come from one `stat` for every input at once rather than one per
# file, because a fork per lookup is the cost this exists to avoid, and the
# first version of this cache was measurably slower than no cache for exactly
# that reason.
#
# Usage:
#   use checkcache
#
#   if nut_cache_hit "$check" "$file"; then
#       nut_cache_read "$check" "$file"      # the findings, as they were
#   else
#       findings="$(work_it_out "$file")"
#       nut_cache_write "$check" "$file" "$findings"
#   fi
# =============================================================================

[ -n "${_NUTSHELL_CHECKCACHE_SH:-}" ] && return 0
readonly _NUTSHELL_CHECKCACHE_SH=1

if ! command -v use >/dev/null 2>&1; then
    printf 'nutshell: source nutshell first\n' >&2
    return 1
fi

# Off by default until a caller turns it on, because a cache that is wrong is
# worse than a check that is slow.
NUT_CACHE_ENABLED="${NUT_CACHE:-0}"

# Bumped when the entry format or the meaning of a stamp changes, so entries
# written by an older nutshell are misses rather than lies.
_NUT_CACHE_FORMAT=2

# The stamps live in a `map` rather than an associative array, which is bash's.
# `map` is on the floor and does the same job through one variable per entry;
# `map_read` leaves the answer in a variable so a lookup costs no fork, which
# matters here because this is the hot path of the checker.
use map
map_new _NUT_CACHE_STAMP
_NUT_CACHE_BASE=""
_NUT_CACHE_STAT=""

# Which `stat` this machine has, decided once by what it prints rather than by
# what it returns.
#
# BSD spells the format `-f` and GNU spells it `-c`. Choosing with
# `stat -f ... || stat -c ...` looks right and is not: on GNU, `-f` is not a
# format flag at all, it asks for file-system status, and it does not
# recognise `%m`. It can therefore exit 0 having printed something that is not
# an mtime, the `||` never fires, and every stamp on Linux is garbage that
# compares equal to itself. Invalidation stops, silently, on the platform most
# of this runs on.
#
# So the probe reads the answer back, against a file whose size it already
# knows. Requiring only "starts with a digit" would rest on a premise nothing
# here can check: that no `stat` ever leads its wrong-flag output with a
# number. GNU prints the literal `%m` and a stub might print a block count, and
# the difference decides whether Linux gets working invalidation.
#
# A written file of known length removes the premise. A format is accepted when
# it returns that exact length, which only the right spelling can do.
#
# Prints `-f` or `-c`, or nothing when neither works.
_nut_cache_stat_flag() {
    [ -n "$_NUT_CACHE_STAT" ] && { printf '%s' "${_NUT_CACHE_STAT#none}"; return 0; }

    local probe out flag fmt rc=1
    probe="$(mktemp "${TMPDIR:-/tmp}/nutshell-stat.XXXXXX")" || { _NUT_CACHE_STAT="none"; return 1; }
    # Ten bytes, no trailing newline, so the size is known exactly.
    printf '0123456789' > "$probe"

    for flag in -f -c; do
        case "$flag" in
            -f) fmt='%m %z' ;;
            -c) fmt='%Y %s' ;;
        esac
        out="$(stat "$flag" "$fmt" "$probe" 2>/dev/null)" || continue
        # `<mtime> <size>`, and the size has to be the one just written.
        case "$out" in *' '*) ;; *) continue ;; esac
        case "${out%% *}" in ''|*[!0-9]*) continue ;; esac
        [ "${out##* }" = "10" ] || continue
        _NUT_CACHE_STAT="$flag"
        rc=0
        break
    done

    rm -f "$probe"
    [ "$rc" -eq 0 ] || { _NUT_CACHE_STAT="none"; return 1; }
    printf '%s' "$_NUT_CACHE_STAT"
    return 0
}

# The `<mtime> <size> <path>` format for whichever `stat` this is.
_nut_cache_stat_fmt() {
    case "$(_nut_cache_stat_flag)" in
        -f) printf '%%m %%z %%N' ;;
        -c) printf '%%Y %%s %%n' ;;
        *)  return 1 ;;
    esac
}

# `<mtime> <size>` for a set of paths, in one call.
_nut_cache_stat_into() {
    local line mtime size path flag fmt out
    # Gathered first, then walked from a here-document.
    #
    # It was `done < <(...)`, which is bash's, and the loop cannot go on the
    # right of a pipe instead: the body calls `map_set`, so a subshell would
    # record every stamp somewhere that dies when the loop ends and the cache
    # would simply never fill. A here-document keeps the loop in this shell,
    # and the text is one short line per input path.
    flag="$(_nut_cache_stat_flag)" || return 0
    fmt="$(_nut_cache_stat_fmt)"   || return 0
    out="$(stat "$flag" "$fmt" "$@" 2>/dev/null)" || return 0
    [ -n "$out" ] || return 0

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        # `<mtime> <size> <path>`, split from the front. Taking the size with
        # `${v##* }` takes the last field, which is the path, so the size was
        # stat'd and then thrown away and a content change landing on the same
        # mtime hit. Two `git checkout`s inside one second do that, and so does
        # `touch -r`.
        mtime="${line%% *}"; line="${line#* }"
        size="${line%% *}";  path="${line#* }"
        [ -n "$path" ] || continue
        map_set _NUT_CACHE_STAMP "$path" "${mtime} ${size}"
    done <<EOF
$out
EOF
    return 0
}

# The stamp for one path, or nothing when it could not be read.
_nut_cache_stamp_of() {
    local p="${1:-}" v
    [ -n "$p" ] || return 1
    map_read v _NUT_CACHE_STAMP "$p"
    if [ -z "$v" ]; then
        _nut_cache_stat_into "$p"
        map_read v _NUT_CACHE_STAMP "$p"
    fi
    [ -n "$v" ] || return 1
    # Already `<mtime> <size>`; there is nothing to re-parse out of it.
    printf '%s' "$v"
}

# What every entry shares: the interpreter's newest file and the format.
#
# One `find` per run, not per file. Editing any module under the interpreter
# moves it and every entry becomes a miss, which is the coarse but correct
# answer to "the checker is more than one file".
_nut_cache_base() {
    [ -n "$_NUT_CACHE_BASE" ] && { printf '%s' "$_NUT_CACHE_BASE"; return 0; }
    local root="${NUTSHELL_ROOT:-}" newest=""
    if [ -n "$root" ] && [ -d "$root/lib" ]; then
        # The newest *file*, not the directory's own mtime. A directory's mtime
        # moves when an entry is added or removed and not when a file inside it
        # is edited, so stat'ing `lib` caught `git pull` and a new module and
        # missed the case this exists for: editing `lib/srcfile.sh` in place
        # changes what a check reports while touching nothing else.
        #
        # One `find` and one batched `stat`, per run rather than per file.
        local flag fmt
        flag="$(_nut_cache_stat_flag)" && case "$flag" in -f) fmt='%m' ;; *) fmt='%Y' ;; esac
        [ -n "${flag:-}" ] && newest="$(
            find "$root/lib" "$root/init" -type f -exec stat "$flag" "$fmt" {} + 2>/dev/null
        )"
        newest="$(printf '%s\n' "$newest" | sort -rn | head -1)"
    fi
    _NUT_CACHE_BASE="f${_NUT_CACHE_FORMAT}:${newest:-none}"
    printf '%s' "$_NUT_CACHE_BASE"
}

# Where an answer is kept. Under the store, beside the toolchains and externs,
# because it is derived data about this machine and not part of any project.
_nut_cache_root() {
    if [ -n "${NUT_CACHE_DIR:-}" ]; then
        printf '%s' "${NUT_CACHE_DIR%/}"
        return 0
    fi
    if command -v nutshell_store_root >/dev/null 2>&1; then
        printf '%s/checks' "$(nutshell_store_root)"
        return 0
    fi
    printf '%s/nutshell/checks' "${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}"
}

# One file's answer, for one check.
#
# The path is percent-encoded rather than flattened. Replacing every `/` with
# `_` maps `lib/toml/json.sh` and `lib/toml_json.sh` onto one entry, and the
# answer for one is then served for the other.
# Percent-encode anything that is not safe in a file name.
#
# Walked by cutting the first character off rather than indexing, because
# `${in:i:1}` is bash's and so is the C-style `for`. A safe run is taken whole
# instead of one character at a time, which is fewer passes on the common case
# where most of a path is already safe.
_nut_cache_escape() {
    local in="${1:-}" out="" run c
    while [ -n "$in" ]; do
        run="${in%%[!A-Za-z0-9._-]*}"
        if [ -n "$run" ]; then
            out="${out}${run}"
            in="${in#"$run"}"
            continue
        fi
        c="${in%"${in#?}"}"
        out="${out}$(printf '%%%02X' "'$c")"
        in="${in#?}"
    done
    printf '%s' "$out"
}

_nut_cache_path() {
    local check="${1:-}" file="${2:-}"
    { [ -n "$check" ] && [ -n "$file" ]; } || return 1
    printf '%s/%s/%s' "$(_nut_cache_root)" \
        "$(_nut_cache_escape "$check")" "$(_nut_cache_escape "$file")"
}

# Everything an entry's freshness depends on, as one line.
_nut_cache_key() {
    local file="${1:-}" src="${NUT_CACHE_CHECKER:-}" cfg="${CONFIG_FILE:-}"
    local sf sc sg
    sf="$(_nut_cache_stamp_of "$file")" || return 1
    sc="$(_nut_cache_stamp_of "$src")"  || return 1
    sg="$(_nut_cache_stamp_of "$cfg")"  || return 1
    printf '%s|%s|%s|%s' "$(_nut_cache_base)" "$sf" "$sc" "$sg"
}

#[pub]
# Is there an answer for this file that nothing has invalidated?
#
# Every input has to be exactly as it was: the file, the check script, the
# config, the interpreter, and the entry format. Any of them unreadable is a
# miss rather than a hit, because an input that cannot be checked has not been
# checked.
#
# `NUT_CACHE_CHECKER` and `CONFIG_FILE` are both required. The config used to
# be tested only when the variable happened to be set, so an unset one skipped
# the test and the entry hit anyway.
# Usage: nut_cache_hit <check> <file> -> returns 0 on a usable answer
nut_cache_hit() {
    [ "${NUT_CACHE_ENABLED:-0}" = "1" ] || return 1
    local check="${1:-}" file="${2:-}" entry want have
    entry="$(_nut_cache_path "$check" "$file")" || return 1
    [ -f "$entry" ] || return 1
    want="$(_nut_cache_key "$file")" || return 1
    IFS= read -r have < "$entry" 2>/dev/null || return 1
    [ "$have" = "$want" ]
}

#[pub]
# The answer that was kept, without its stamp line.
# Usage: nut_cache_read <check> <file> -> prints what was cached
nut_cache_read() {
    local entry; entry="$(_nut_cache_path "$1" "$2")" || return 1
    [ -r "$entry" ] || return 1
    tail -n +2 "$entry"
}

#[pub]
# Keep an answer, with the stamp of everything it depended on. A failure to
# write is not a failure of the check: the run still has the answer, it just
# will not have it next time.
# Usage: nut_cache_write <check> <file> <findings>
nut_cache_write() {
    [ "${NUT_CACHE_ENABLED:-0}" = "1" ] || return 0
    local entry key
    entry="$(_nut_cache_path "$1" "$2")" || return 0
    key="$(_nut_cache_key "$2")" || return 0
    mkdir -p "${entry%/*}" 2>/dev/null || return 0
    { printf '%s\n' "$key"; printf '%s' "${3:-}"; } > "$entry" 2>/dev/null || return 0
    return 0
}

#[pub]
# Throw the whole thing away.
# Usage: nut_cache_clear [check]
nut_cache_clear() {
    local root; root="$(_nut_cache_root)"
    if [ -n "${1:-}" ]; then
        rm -rf "${root}/$(_nut_cache_escape "$1")"
    else
        rm -rf "$root"
    fi
    return 0
}
