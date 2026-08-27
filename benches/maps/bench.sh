#!/usr/bin/env bash
# =============================================================================
# nutshell/benches/maps - What a map costs without bash associative arrays
# =============================================================================
#
# POSIX sh has no associative arrays. nutshell uses them where they decide how
# fast it is: the config cache, the toolchain tables, the attribute tables, and
# the file-line table the QA checks read. So "make nutshell POSIX" has a price,
# and the price is a number rather than an opinion.
#
# **Two arms are not maps and are labelled so.** `slots by index` and `slots by
# stride` are what a map becomes once the key has already been resolved and the
# caller holds the index. They are here because the gap between them and the
# arms beside them prices the key lookup, which is the thing a design would be
# trading away. They are not alternatives to `declare -A`.
#
# The size defaults to the largest real table: `_PAD_LINES` in the docs check
# holds one entry per line of source, 9606 across 24 files. The keys are the
# real shape too, `<path>:<n>`, because two arms cannot take a key with a slash
# or a colon in it and the encoding that fixes that is part of what they cost.
#
# Usage:
#   ./bench maps [entries] [lookups]
# =============================================================================

use bench

ENTRIES="${1:-2000}"
LOOKUPS="${2:-500}"
REAL_TABLE=9606

# -----------------------------------------------------------------------------
# The input, shaped like nutshell's own keys
# -----------------------------------------------------------------------------

declare -a KEYS=() VALS=()
_generate() {
    local i
    for (( i = 0; i < ENTRIES; i++ )); do
        # `<path>:<n>`, which is what `_PAD_LINES` and `_PAD_AT` are keyed by.
        # Slash, dot, dash and colon all appear, and none of them may go into a
        # variable name unencoded.
        KEYS+=("lib/some-module.sh:$i")
        VALS+=("value number $i")
    done
}

# A key as a variable name. Every arm that builds a name out of a key pays this.
_encode() {
    local k="$1" out="" i c
    for (( i = 0; i < ${#k}; i++ )); do
        c="${k:i:1}"
        case "$c" in
            [A-Za-z0-9_]) out+="$c" ;;
            *) printf -v c '_%02x' "'$c"; out+="$c" ;;
        esac
    done
    printf '%s' "$out"
}

# -----------------------------------------------------------------------------
# The arms. Each builds a table of ENTRIES pairs, then does LOOKUPS hits and
# LOOKUPS misses, and prints the value it last found so nothing can be
# optimised away by not being used.
# -----------------------------------------------------------------------------

# A: bash associative array. The thing being given up.
arm_bash_assoc() {
    declare -A m=()
    local i last=""
    for (( i = 0; i < ENTRIES; i++ )); do m["${KEYS[$i]}"]="${VALS[$i]}"; done
    for (( i = 0; i < LOOKUPS; i++ )); do last="${m["${KEYS[$(( i * ENTRIES / LOOKUPS ))]}"]:-}"; done
    for (( i = 0; i < LOOKUPS; i++ )); do last="${m["no/such-key.sh:$i"]:-MISS}"; done
    printf '%s' "$last"
}

# B: variable names built out of the key, read and written through `eval`.
#    The classic POSIX substitute, and the one that needs the encoding.
arm_eval_names() {
    local i last="" n
    for (( i = 0; i < ENTRIES; i++ )); do
        n="$(_encode "${KEYS[$i]}")"
        eval "_aa_${n}=\${VALS[\$i]}"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        n="$(_encode "${KEYS[$(( i * ENTRIES / LOOKUPS ))]}")"
        eval "last=\${_aa_${n}:-}"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        n="$(_encode "no/such-key.sh:$i")"
        eval "last=\${_aa_${n}:-MISS}"
    done
    printf '%s' "$last"
}

# B2: the same, without a fork for the encoding. `_encode` above is called
#     through a command substitution, which is what a caller writes first and
#     is a fork per operation. This is the same arm with the encoding done in
#     place, and the gap between the two is the cost of that habit rather than
#     of the technique.
arm_eval_names_nofork() {
    local i last="" n
    for (( i = 0; i < ENTRIES; i++ )); do
        printf -v n '%s' "${KEYS[$i]//[^A-Za-z0-9_]/_}"
        eval "_bb_${n}=\${VALS[\$i]}"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        printf -v n '%s' "${KEYS[$(( i * ENTRIES / LOOKUPS ))]//[^A-Za-z0-9_]/_}"
        eval "last=\${_bb_${n}:-}"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        printf -v n '%s' "no/such-key.sh:${i}"
        n="${n//[^A-Za-z0-9_]/_}"
        eval "last=\${_bb_${n}:-MISS}"
    done
    printf '%s' "$last"
}

# C: one string holding every pair, scanned with parameter expansion.
#    No forks and no files, and quadratic the moment the table is large.
arm_one_string() {
    local map=$'\n' i last="" rest
    for (( i = 0; i < ENTRIES; i++ )); do map+="${KEYS[$i]}=${VALS[$i]}"$'\n'; done
    # A miss has to be a miss. `${map#*pat}` returns the whole string unchanged
    # when the pattern is absent, so without the membership test below this arm
    # answered a real value for a key that was not there. The correctness
    # control caught it on the first run, which is the reason that control is
    # there and ahead of the timing.
    local pat
    for (( i = 0; i < LOOKUPS; i++ )); do
        pat=$'\n'"${KEYS[$(( i * ENTRIES / LOOKUPS ))]}"=
        if [[ "$map" == *"$pat"* ]]; then
            rest="${map#*"$pat"}"; last="${rest%%$'\n'*}"
        else
            last="MISS"
        fi
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        pat=$'\n'"no/such-key.sh:${i}="
        if [[ "$map" == *"$pat"* ]]; then
            rest="${map#*"$pat"}"; last="${rest%%$'\n'*}"
        else
            last="MISS"
        fi
    done
    printf '%s' "$last"
}

# D: one file, a line per pair, read back in the shell.
arm_one_file() {
    local d; d="$(mktemp -d "${TMPDIR:-/tmp}/aa.XXXXXX")"
    local f="$d/map" i last="" k v want
    for (( i = 0; i < ENTRIES; i++ )); do printf '%s\t%s\n' "${KEYS[$i]}" "${VALS[$i]}"; done > "$f"
    for (( i = 0; i < LOOKUPS; i++ )); do
        want="${KEYS[$(( i * ENTRIES / LOOKUPS ))]}"
        last=""
        while IFS=$'\t' read -r k v; do [[ "$k" == "$want" ]] && { last="$v"; break; }; done < "$f"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        want="no/such-key.sh:$i"; last="MISS"
        while IFS=$'\t' read -r k v; do [[ "$k" == "$want" ]] && { last="$v"; break; }; done < "$f"
    done
    rm -rf "$d"
    printf '%s' "$last"
}

# E: the filesystem as the table, one file per key. The lookup is a read of a
#    known path rather than a search, which is the only arm here whose lookup
#    does not get slower as the table grows.
arm_dir_table() {
    local d; d="$(mktemp -d "${TMPDIR:-/tmp}/aa.XXXXXX")"
    local i last="" n
    for (( i = 0; i < ENTRIES; i++ )); do
        n="${KEYS[$i]//[^A-Za-z0-9_]/_}"
        printf '%s' "${VALS[$i]}" > "$d/$n"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        n="${KEYS[$(( i * ENTRIES / LOOKUPS ))]//[^A-Za-z0-9_]/_}"
        last=""; [[ -r "$d/$n" ]] && read -r last < "$d/$n"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        n="no/such-key.sh:${i}"; n="${n//[^A-Za-z0-9_]/_}"
        last="MISS"; [[ -r "$d/$n" ]] && read -r last < "$d/$n"
    done
    rm -rf "$d"
    printf '%s' "$last"
}

# A memory filesystem, if this machine has one.
#
# Not POSIX. The standard says nothing about where a path's bytes live, and
# that is the only syscall lever a shell really has: `dd bs=` shapes a transfer
# and nothing shapes an allocation. Linux has `/dev/shm` and usually a tmpfs
# `/tmp`; macOS has neither, so this arm reports itself skipped there rather
# than quietly measuring a disk and calling it memory.
_memfs() {
    local d
    for d in /dev/shm /run/shm; do
        [[ -d "$d" && -w "$d" ]] && { printf '%s' "$d"; return 0; }
    done
    # A tmpfs `/tmp`, where the platform can be asked.
    if command -v findmnt >/dev/null 2>&1; then
        case "$(findmnt -no FSTYPE --target /tmp 2>/dev/null)" in
            tmpfs|ramfs) printf '/tmp'; return 0 ;;
        esac
    fi
    return 1
}

# F: the same table as E, on a memory filesystem. The gap between the two is
#    what the disk was costing, which is the part of a syscall a shell can
#    actually do something about.
arm_memfs_table() {
    local root; root="$(_memfs)" || { printf 'SKIP'; return 0; }
    local d; d="$(mktemp -d "${root}/aa.XXXXXX")"
    local i last="" n
    for (( i = 0; i < ENTRIES; i++ )); do
        n="${KEYS[$i]//[^A-Za-z0-9_]/_}"
        printf '%s' "${VALS[$i]}" > "$d/$n"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        n="${KEYS[$(( i * ENTRIES / LOOKUPS ))]//[^A-Za-z0-9_]/_}"
        last=""; [[ -r "$d/$n" ]] && read -r last < "$d/$n"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        n="no/such-key.sh:${i}"; n="${n//[^A-Za-z0-9_]/_}"
        last="MISS"; [[ -r "$d/$n" ]] && read -r last < "$d/$n"
    done
    rm -rf "$d"
    printf '%s' "$last"
}

# G: slots addressed by arithmetic, with the caller holding the index.
#
#    The table is `_g0.._gN`, and a lookup is one `eval` on a name built from a
#    number. No per-character encoding anywhere, because nothing has to turn a
#    key into a name: whatever resolved the key once handed back the index and
#    the caller kept it.
#
#    This is the ceiling for the technique, and it is not a map. It is what a
#    map becomes once the key lookup has already happened, so it says what the
#    key lookup is actually costing in every other arm.
arm_slots_by_index() {
    local i last=""
    for (( i = 0; i < ENTRIES; i++ )); do eval "_g${i}=\${VALS[\$i]}"; done
    for (( i = 0; i < LOOKUPS; i++ )); do
        eval "last=\${_g$(( i * ENTRIES / LOOKUPS )):-}"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        eval "last=\${_g$(( ENTRIES + i )):-MISS}"
    done
    printf '%s' "$last"
}

# G2: the same slots, several fields per entry, addressed by stride.
#
#     `_h$(( i * 3 + f ))` is a record of three fields. Whether striding costs
#     anything over one field is the question; the arithmetic is native and the
#     name is still just a number.
arm_slots_by_stride() {
    local i last="" base
    for (( i = 0; i < ENTRIES; i++ )); do
        base=$(( i * 3 ))
        eval "_h${base}=\${KEYS[\$i]}"
        eval "_h$(( base + 1 ))=\${VALS[\$i]}"
        eval "_h$(( base + 2 ))=\$i"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        base=$(( (i * ENTRIES / LOOKUPS) * 3 ))
        eval "last=\${_h$(( base + 1 )):-}"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        base=$(( (ENTRIES + i) * 3 ))
        eval "last=\${_h$(( base + 1 )):-MISS}"
    done
    printf '%s' "$last"
}

# H: a hash table built by hand over those slots.
#
#    The honest version of "index it yourself": hash the key with shell
#    arithmetic, probe linearly on collision, store key and value side by side
#    so a probe can tell a hit from a neighbour. This is what it costs to keep
#    string keys without the shell's own symbol table doing the work.
#
#    The hash is over every character, which is where the cost goes, and that
#    is the point of measuring it: the shell's symbol table hashes in C.
_hash_into() {
    local __s="${2:-}" __n __i __h=5381 __c
    __n=${#__s}
    for (( __i = 0; __i < __n; __i++ )); do
        printf -v __c '%d' "'${__s:__i:1}"
        __h=$(( (__h * 33 + __c) & 0x7fffffff ))
    done
    printf -v "$1" '%d' "$(( __h % BUCKETS ))"
}

arm_hand_rolled_hash() {
    local BUCKETS=$(( ENTRIES * 2 ))
    local i last="" h probe k
    for (( i = 0; i < ENTRIES; i++ )); do
        _hash_into h "${KEYS[$i]}"
        probe=$h
        while :; do
            eval "k=\${_kk${probe}+set}"
            [[ -z "$k" ]] && break
            probe=$(( (probe + 1) % BUCKETS ))
        done
        eval "_kk${probe}=\${KEYS[\$i]}"
        eval "_vv${probe}=\${VALS[\$i]}"
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        local want="${KEYS[$(( i * ENTRIES / LOOKUPS ))]}"
        _hash_into h "$want"
        probe=$h; last="MISS"
        while :; do
            eval "k=\${_kk${probe}-}"
            [[ -z "$k" ]] && break
            if [[ "$k" == "$want" ]]; then eval "last=\${_vv${probe}}"; break; fi
            probe=$(( (probe + 1) % BUCKETS ))
        done
    done
    for (( i = 0; i < LOOKUPS; i++ )); do
        local want="no/such-key.sh:$i"
        _hash_into h "$want"
        probe=$h; last="MISS"
        while :; do
            eval "k=\${_kk${probe}-}"
            [[ -z "$k" ]] && break
            if [[ "$k" == "$want" ]]; then eval "last=\${_vv${probe}}"; break; fi
            probe=$(( (probe + 1) % BUCKETS ))
        done
    done
    printf '%s' "$last"
}


# -----------------------------------------------------------------------------
# The bench
# -----------------------------------------------------------------------------

_generate

# Every arm prints the value it last found, which is how they are compared. An
# arm whose encoding collides two keys answers differently, and the harness
# then refuses the whole run rather than reporting that arm as the fastest.
_answer_of() { "$1"; }

bench_case "What a map costs without bash associative arrays"
bench_size "$ENTRIES"
bench_verify _answer_of

# The first is the baseline. Ceilings are stated per arm rather than hidden,
# because which arms have one at all is itself the result: the two that address
# a key directly have none.
bench_arm "bash declare -A"                  arm_bash_assoc
bench_arm "eval names, encoded via subshell" arm_eval_names        4000
bench_arm "eval names, encoded in place"     arm_eval_names_nofork
bench_arm "one string, scanned"              arm_one_string         800
bench_arm "one file, read in shell"          arm_one_file          4000
bench_arm "one file per key"                 arm_dir_table
bench_arm "one file per key, in memory"      arm_memfs_table        0 "no memory filesystem here"
bench_arm "slots by index (not a map)"       arm_slots_by_index
bench_arm "slots by stride (not a map)"      arm_slots_by_stride
bench_arm "hash table rolled by hand"        arm_hand_rolled_hash  4000

bench_run || exit 1

printf '\n'
printf 'The real table this stands in for is %s entries, and the arms that\n' "$REAL_TABLE"
printf 'search rather than address grow with it. Run with a larger first\n'
printf 'argument to see that; the default is small enough to finish.\n'
