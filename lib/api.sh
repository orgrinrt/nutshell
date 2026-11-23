#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/api.sh - A library's public functions, listed
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 2: uses attr, modgraph, toml and fs.
#
# Every module a library declares that is not marked `internal`, and under each
# the functions marked `#[pub]` with the `# Usage:` line written above them.
# What counts as a module comes from the module graph, what counts as public
# from its visibility, and what a function's usage says from `attr`: this
# module scans nothing of its own.
#
# An internal module a public one loads, and whose name sits under it, is part
# of it: what its file marks `#[pub]` is listed under the public module, since
# a `use` of that module is what puts it in reach. `json_query` is written in
# `json/query.sh` and listed under `json`. An internal module no public one
# loads is listed nowhere.
#
# Sorted by byte order and written the same way every time, so a listing can
# be committed and a later run diffed against it. A function with no usage
# line is listed by name alone, which is what a reader of the file should see.
#
# Usage:
#   use api
#
#   api_text     "/path/to/library"            # every module, plain text
#   api_text     "/path/to/library" toml       # one module
#   api_markdown "/path/to/library" "" "title" # a block per module, as markdown

[ -n "${_NUTSHELL_API_SH:-}" ] && return 0
_NUTSHELL_API_SH=1

use attr modgraph toml

# _api_dir <root> -> the directory the library's modules sit under
_api_dir() {
    local d
    for d in lib libs; do
        [[ -d "${1}/${d}" ]] && { printf '%s/%s' "$1" "$d"; return 0; }
    done
    printf '%s' "$1"
}

# _api_file <root> <module> -> the file `use` would load for it, or fails
_api_file() {
    local root="$1" mod="$2" rel
    if [[ -r "${root}/lib.nut" ]]; then
        _lib_nut_lookup "$root" "$mod" any
        return
    fi
    rel="${mod//::/\/}"
    local c
    for c in "${root}/libs/${rel}.sh" "${root}/lib/${rel}.sh" "${root}/${rel}.sh"; do
        [[ -f "$c" ]] && { printf '%s' "$c"; return 0; }
    done
    return 1
}

# _api_internal <root> <module> -> succeeds when lib.nut marks it internal
_api_internal() {
    [[ -r "${1}/lib.nut" ]] || return 1
    _lib_nut_lookup "$1" "$2" any >/dev/null 2>&1 || return 1
    ! _lib_nut_lookup "$1" "$2" public >/dev/null 2>&1
}

# _api_parts <root> <module> -> the module, then each internal module under its
# name that it loads, and those that load further, one per line. What those
# files mark `#[pub]` is in reach after a `use` of the module, so it is listed
# under it: `json_query` sits in `json::query`, which only `json` loads.
_api_parts() {
    local root="$1" mod="$2" seen=" $2 " queue="$2" m d
    printf '%s\n' "$mod"
    while [[ -n "$queue" ]]; do
        m="${queue%% *}"
        [[ "$queue" == *" "* ]] && queue="${queue#* }" || queue=""
        for d in $(modgraph_declares "$m"); do
            [[ "$d" == "${mod}::"* ]] || continue
            [[ "$seen" == *" ${d} "* ]] && continue
            seen+="${d} "
            _api_internal "$root" "$d" || continue
            printf '%s\n' "$d"
            queue="${queue:+${queue} }${d}"
        done
    done
}

# _api_entries <root> <module> -> its public functions, one `usage` per line,
# sorted by function name; a function with no usage line is its bare name. A
# name the module and one of its internal files both define is listed once,
# from the module's own file.
_api_entries() {
    local root="$1" mod="$2" part file fn tab line found pairs="" seen=" " i=0
    local -a usages=()
    tab="$(printf '\t')"
    while IFS= read -r part; do
        file="$(_api_file "$root" "$part")" || { [[ "$part" == "$mod" ]] && return 1; continue; }
        usages[i]="$(attr_usages "$file")"
        while IFS= read -r fn; do
            [[ -n "$fn" && "$seen" != *" ${fn} "* ]] || continue
            seen+="${fn} "
            pairs+="${fn}${tab}${i}"$'\n'
        done < <(modgraph_public "$part")
        i=$((i + 1))
    done < <(_api_parts "$root" "$mod")

    while IFS="$tab" read -r fn i; do
        [[ -n "$fn" ]] || continue
        # Every usage line of the function, in file order, or its name.
        found=0
        while IFS= read -r line; do
            [[ "${line%%"$tab"*}" == "$fn" ]] || continue
            printf '%s\n' "${line#*"$tab"}"
            found=1
        done <<< "${usages[i]}"
        [[ "$found" -eq 1 ]] || printf '%s\n' "$fn"
    done < <(printf '%s' "$pairs" | LC_ALL=C sort -t "$tab" -k1,1)
}

# _api_walk <root> <module-or-empty> <emit> -> calls `<emit> <module> <entries>`
# for each listed module in order, or says why it cannot
_api_walk() {
    local root="$1" want="$2" emit="$3" mod entries found=0
    MODGRAPH_ROOT="$root" modgraph_build "$(_api_dir "$root")" || return 1

    if [[ -n "$want" ]]; then
        if _api_internal "$root" "$want"; then
            echo "api: '${want}' is internal to that library" >&2
            return 1
        fi
        if ! modgraph_modules | grep -qxF -- "$want"; then
            echo "api: no module '${want}' in ${root}" >&2
            return 1
        fi
        entries="$(_api_entries "$root" "$want")"
        if [[ -z "$entries" ]]; then
            echo "api: '${want}' has no public functions" >&2
            return 1
        fi
        "$emit" "$want" "$entries"
        return 0
    fi

    while IFS= read -r mod; do
        [[ -n "$mod" ]] || continue
        _api_file "$root" "$mod" >/dev/null 2>&1 || continue
        _api_internal "$root" "$mod" && continue
        entries="$(_api_entries "$root" "$mod")"
        [[ -n "$entries" ]] || continue
        "$emit" "$mod" "$entries"
    done < <(modgraph_modules | LC_ALL=C sort -u)
}

_api_emit_text() {
    printf '%s\n' "$1"
    printf '%s\n' "$2" | sed 's/^/  /'
}

_API_MD_FIRST=1
_api_emit_md() {
    [[ "$_API_MD_FIRST" -eq 1 ]] || printf '\n'
    _API_MD_FIRST=0
    printf '## %s\n\n```\n%s\n```\n' "$1" "$2"
}

#[pub]
# Usage: api_text <library-root> [<module>] -> prints each module and its public functions
api_text() {
    _api_walk "$1" "${2:-}" _api_emit_text
}

# api_title <library-root> <fallback>
#
# The library's `[package] name` when its nut.toml has one, else the fallback.
#
#[pub]
# Usage: api_title <library-root> <fallback> -> prints the name the library calls itself
api_title() {
    local name
    if [[ -r "${1}/nut.toml" ]] && name="$(toml_get "${1}/nut.toml" package.name 2>/dev/null)" && [[ -n "$name" ]]; then
        printf '%s' "$name"
    else
        printf '%s' "$2"
    fi
}

#[pub]
# Usage: api_markdown <library-root> [<module>] [<title>] -> prints a markdown page, a code block per module
api_markdown() {
    local root="$1" want="${2:-}" fallback="${3:-api}" out
    _API_MD_FIRST=1
    out="$(_api_walk "$root" "$want" _api_emit_md)" || return 1
    printf '# %s\n\n%s\n' "$(api_title "$root" "$fallback")" "$out"
}
