#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/modgraph.sh - The module graph, analysed once and cached
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 1: uses fs, xdg and log.
#
# What every module declares, defines and calls, in one table. Building it
# takes a pass over every file in a library, which is too slow to repeat for
# each question somebody wants to ask of it, so it is built once per distinct
# state of the library and cached globally. A second run against an unchanged
# library reads a file.
#
# Three facts per module, and every check downstream is a query over them:
#
#   declares  the modules it names in a `use` line
#   defines   the functions it introduces
#   calls     the module-prefixed functions it invokes
#
# The graph deliberately holds facts rather than judgements. Whether a cycle is
# a defect, whether an undeclared call is one, whether a module nothing uses
# should be deleted: those are the checker's opinions, and keeping them out of
# here means a second checker can hold different ones without rebuilding.
#
# Usage:
#   use modgraph
#
#   modgraph_build "/path/to/lib"        # cached; call freely
#   modgraph_modules                     # every module name
#   modgraph_declares  toml              # what toml said it uses
#   modgraph_defines   string            # what string introduces
#   modgraph_calls     toml              # prefixed functions toml invokes
#   modgraph_owner     str_trim          # which module defines it
#
# Portability: the scan is one awk program, written to POSIX awk only, so it
# runs the same under gawk, mawk, BSD awk and busybox awk. Nothing here reaches
# for a GNU extension, because the one place a module graph is most useful is a
# machine somebody else set up.
#
# The constructs used are all POSIX: bracket character classes, ERE grouping,
# `match` with RSTART and RLENGTH, `sub`, `gsub`, `split`, `substr`, `printf`.
# `for (k in array)` is POSIX too, though its order is unspecified, so the
# serialised graph may list a module's functions differently between awks. That
# changes the cache file's bytes and nothing about its meaning.
#
# Environment:
#   MODGRAPH_NOCACHE - set to 1 to rebuild every time (for developing a check)
# =============================================================================

nut_once || return 0

use fs xdg deps

# awk does the whole scan, so its absence is not a degraded mode to fall back
# from. Said once, here, rather than discovered as an empty graph later.
deps_require awk "modgraph needs awk to read a library" || return 1

declare -gA _MG_DECLARES=()
declare -gA _MG_DEFINES=()
declare -gA _MG_CALLS=()
declare -gA _MG_OWNER=()
# Visibility per function: `pub`, `lib`, or absent for module-private.
declare -gA _MG_VIS=()
declare -ga _MG_MODULES=()
_MG_ROOT=""

# -----------------------------------------------------------------------------
# Cache identity
# -----------------------------------------------------------------------------

# _mg_fingerprint <dir>
#
# What the library looks like right now. Names, sizes and modification times
# rather than content: reading every file to hash it would cost as much as the
# analysis the cache exists to avoid, and a file whose size and mtime are both
# unchanged has not been edited by anything this cache needs to notice.
# Bumped whenever the scan changes shape. The fingerprint covers the library's
# files, which is not enough on its own: change how a module is read and every
# cached graph is stale while still looking current, which is how a fixed
# scanner kept reporting a fixed bug.
readonly _MG_SCHEMA=4

_mg_fingerprint() {
    local dir="$1"
    { ls -1 "$dir"/*.sh 2>/dev/null | while IFS= read -r f; do
          printf '%s:%s:%s\n' "${f##*/}" "$(fs_size "$f" 2>/dev/null)" "$(fs_mtime "$f" 2>/dev/null)"
      done
      printf 'schema:%s\n' "$_MG_SCHEMA"
      # Which library, not only what is in it. Without this two libraries whose
      # files happen to share names, sizes and modification times resolve to
      # one cache file and each reads the other's graph.
      printf 'dir:%s\n' "$dir"
    } | cksum | tr -d ' '
}

_mg_cache_file() {
    local dir="$1" print
    print="$(_mg_fingerprint "$dir")"
    xdg_set_app_name nutshell
    printf '%s/modgraph/%s.graph' "$(xdg_app_cache)" "$print"
}

# -----------------------------------------------------------------------------
# Reading a module
# -----------------------------------------------------------------------------

# _mg_scan <file> -> four tab-separated sections
#
# One awk pass per file. The shape this replaced asked the file a question at a
# time: a sed, then three grep pipelines, then `attr_has` and `attr_arg` for
# every function found, each of which read the whole file again in bash. Around
# seven hundred full reads for a library this size, and the analysis is a
# single linear scan of the text.
#
# Attributes are tracked as pending state as the scan walks, which is the same
# thing `attr_on` does, done once for every definition rather than once per
# definition per query.
_mg_scan() {
    awk '
        # An attribute line: remember it, do not clear anything.
        /^[[:space:]]*#\[[a-z_][a-z0-9_]*(\(.*\))?\][[:space:]]*$/ {
            line = $0
            sub(/^[[:space:]]*#\[/, "", line)
            sub(/\][[:space:]]*$/, "", line)
            name = line; arg = ""
            if (match(line, /\(.*\)$/)) {
                arg  = substr(line, RSTART + 1, RLENGTH - 2)
                name = substr(line, 1, RSTART - 1)
            }
            if (name == "pub") pending_pub = (arg == "" ? "pub" : arg)
            next
        }

        # A declaration of intent.
        /^[[:space:]]*use[[:space:]]+/ {
            line = $0
            sub(/^[[:space:]]*use[[:space:]]+/, "", line)
            sub(/#.*$/, "", line)
            n = split(line, parts, /[[:space:]]+/)
            for (i = 1; i <= n; i++) if (parts[i] != "") declares[parts[i]] = 1
            next
        }

        # A definition. Consumes whatever attributes were pending.
        /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)/ {
            fn = $0
            sub(/^[[:space:]]*/, "", fn)
            sub(/\(\).*$/, "", fn)
            defines[fn] = 1
            if (pending_pub != "") vis[fn] = pending_pub
            pending_pub = ""
        }

        # Prose and blank lines do not break a run of attributes; anything else
        # does, so a stray marker cannot drift onto an unrelated definition.
        {
            stripped = $0
            gsub(/[[:space:]]/, "", stripped)
            if (stripped != "" && $0 !~ /^[[:space:]]*#/) pending_pub = ""
        }

        # Calls, and only calls. Every module-prefixed token used to count,
        # which meant a local named `in_section` read as a call to a function
        # of that name in whichever module happened to define one. Now a token
        # counts only in command position: first word of the line, or first
        # after a separator that starts a new command.
        {
            code = $0
            sub(/#.*$/, "", code)
            # Turn command separators into line breaks, so "first word of a
            # command" becomes "first word of a segment".
            gsub(/\$\(/, "\n", code)
            # Process substitution too. Without it `done < <(attr_find ...)`
            # was not a call, so `test` recorded no calls into `attr` at all
            # and a module reaching into another only that way passed the
            # contract check untouched.
            gsub(/[<>]\(/, "\n", code)
            gsub(/[;|&`]/, "\n", code)
            gsub(/\(\)/, "", code)
            n = split(code, segs, "\n")
            for (si = 1; si <= n; si++) {
                seg = segs[si]
                sub(/^[[:space:]]+/, "", seg)
                # Shell keywords introduce a command rather than being one.
                while (match(seg, /^(if|then|else|elif|while|until|do|done|fi|!|\{|\}|\[\[)[[:space:]]+/)) {
                    seg = substr(seg, RSTART + RLENGTH)
                    sub(/^[[:space:]]+/, "", seg)
                }
                if (match(seg, /^_?[a-z][a-z0-9]*_[a-z0-9_]+/)) {
                    word = substr(seg, RSTART, RLENGTH)
                    rest = substr(seg, RSTART + RLENGTH, 1)
                    # An assignment is not a call.
                    if (rest != "=") calls[word] = 1
                }
            }
        }

        END {
            d = ""; for (k in declares) d = d k " "
            f = ""; for (k in defines)  f = f k " "
            c = ""; for (k in calls)    c = c k " "
            v = ""; for (k in vis)      v = v k "=" vis[k] " "
            printf "declares\t%s\n", d
            printf "defines\t%s\n",  f
            printf "calls\t%s\n",    c
            printf "vis\t%s\n",      v
        }
    ' "$1" 2>/dev/null
}

# -----------------------------------------------------------------------------
# Building
# -----------------------------------------------------------------------------

declare -gA _MG_SEEN=()

_mg_reset() {
    _MG_DECLARES=(); _MG_DEFINES=(); _MG_CALLS=(); _MG_OWNER=(); _MG_VIS=(); _MG_MODULES=()
    _MG_SEEN=()
}

# A second file for a module already recorded: its declarations, definitions
# and calls are added to that module rather than becoming another one.
_mg_merge_into() {
    local mod="$1" file="$2" kind values fn pair
    local visraw=""
    while IFS=$'\t' read -r kind values; do
        case "$kind" in
            declares) _MG_DECLARES[$mod]="${_MG_DECLARES[$mod]:-} $values" ;;
            defines)  _MG_DEFINES[$mod]="${_MG_DEFINES[$mod]:-} $values" ;;
            calls)    _MG_CALLS[$mod]="${_MG_CALLS[$mod]:-} $values" ;;
            vis)      visraw="$values" ;;
        esac
    done < <(_mg_scan "$file")

    # The variant's own definitions belong to the same module, and its
    # visibilities are its own: a function public in one spelling and absent
    # from the other still has to answer as public.
    for fn in ${_MG_DEFINES[$mod]:-}; do
        _MG_OWNER[$fn]="$mod"
    done
    for pair in ${visraw:-}; do
        _MG_VIS[${pair%%=*}]="${pair#*=}"
    done
}

# The module a file belongs to, from the manifest when there is one.
#
# A module may name several files, which is what a gate attribute does:
# `string.sh`
# and `string.posix.sh` are one module written twice for two shells and only
# one is ever loaded. Named from the path, the second becomes a module called
# `string.posix` that calls fifteen functions from `string` and declares none
# of them, and the contract check reports every one.
#
# Falls back to the file stem, which is what every file without a manifest
# entry gets and what this always did.
_mg_module_of() {
    local file="$1" root="${2:-}" rel name f _rest
    local stem="${file##*/}"; stem="${stem%.sh}"
    [[ -n "$root" && -r "${root}/lib.nut" ]] || { printf '%s' "$stem"; return 0; }
    rel="${file#"${root}/"}"
    while read -r name f _rest || [[ -n "$name" ]]; do
        [[ -z "$name" || "${name:0:1}" == "#" ]] && continue
        if [[ "$f" == "$rel" ]]; then
            # The leaf, since this graph works in file-stem names throughout
            # and a `::` path would not match anything else in it.
            printf '%s' "${name##*::}"
            return 0
        fi
    done < "${root}/lib.nut"
    printf '%s' "$stem"
}

_mg_analyse() {
    local dir="$1" file mod line kind values
    # The library root, so the manifest can say which module a file is. `dir`
    # is the lib directory; the manifest sits above it.
    local root="${MODGRAPH_ROOT:-${dir%/*}}"
    for file in "$dir"/*.sh; do
        [[ -f "$file" ]] || continue
        mod="$(_mg_module_of "$file" "$root")"
        # A module already seen is a variant of it. Its calls and definitions
        # join the ones already recorded rather than starting a second module.
        if [[ -n "${_MG_SEEN[$mod]:-}" ]]; then
            _mg_merge_into "$mod" "$file"
            continue
        fi
        _MG_SEEN[$mod]=1
        _MG_MODULES+=("$mod")
        while IFS=$'\t' read -r kind values; do
            case "$kind" in
                declares) _MG_DECLARES[$mod]="$values" ;;
                defines)  _MG_DEFINES[$mod]="$values" ;;
                calls)    _MG_CALLS[$mod]="$values" ;;
                vis)      _MG_VISRAW="$values" ;;
            esac
        done < <(_mg_scan "$file")

        local fn pair
        for fn in ${_MG_DEFINES[$mod]:-}; do
            _MG_OWNER[$fn]="$mod"
        done
        # Visibility is read from the file rather than inferred from the name.
        # A leading underscore is a convention people follow most of the time,
        # and "most of the time" is not something a resolver can be built on.
        for pair in ${_MG_VISRAW:-}; do
            _MG_VIS[${pair%%=*}]="${pair#*=}"
        done
        _MG_VISRAW=""
    done
}

# One record per fact, never one record per module with several payloads.
#
# The compact shape, `M <mod> <declares> <defines> <calls>`, read back wrong,
# and did so silently. Tab is an IFS whitespace character, so bash collapses a
# run of them into one delimiter: a module that declares nothing writes two
# tabs in a row, `read` sees one, and every later field shifts left. The graph
# reloaded with each module's defines sitting in its declares, which reads as
# "everything is declared" and made the check report a clean library from a
# cache while reporting the truth from a fresh build.
#
# Splitting it means the payload that can be empty is always the last field,
# and a trailing empty field is the one case this does not bite.
_mg_serialise() {
    local mod fn
    for mod in "${_MG_MODULES[@]}"; do
        printf 'D\t%s\t%s\n' "$mod" "${_MG_DECLARES[$mod]:-}"
        printf 'F\t%s\t%s\n' "$mod" "${_MG_DEFINES[$mod]:-}"
        printf 'C\t%s\t%s\n' "$mod" "${_MG_CALLS[$mod]:-}"
        for fn in ${_MG_DEFINES[$mod]:-}; do
            [[ -n "${_MG_VIS[$fn]:-}" ]] && printf 'V\t%s\t%s\n' "$fn" "${_MG_VIS[$fn]}"
        done
    done
}

_mg_load() {
    local file="$1" tag key payload fn
    _mg_reset
    while IFS=$'\t' read -r tag key payload; do
        case "$tag" in
            D) _MG_MODULES+=("$key"); _MG_DECLARES[$key]="$payload" ;;
            F) _MG_DEFINES[$key]="$payload"
               for fn in $payload; do _MG_OWNER[$fn]="$key"; done ;;
            C) _MG_CALLS[$key]="$payload" ;;
            V) _MG_VIS[$key]="$payload" ;;
        esac
    done < "$file"
}

# modgraph_build <lib-dir>
#
# Analyse the library, or read the analysis back if nothing has changed.
#[pub]
# Usage: modgraph_build "path/to/lib" -> populates the graph, returns 0
modgraph_build() {
    local dir="${1:-${NUTSHELL_ROOT}/lib}"
    _MG_ROOT="$dir"

    if [[ "${MODGRAPH_NOCACHE:-0}" == "1" ]]; then
        _mg_reset; _mg_analyse "$dir"; return 0
    fi

    local cache
    cache="$(_mg_cache_file "$dir")"
    if [[ -f "$cache" ]]; then
        _mg_load "$cache"
        return 0
    fi

    _mg_reset
    _mg_analyse "$dir"
    fs_mkdir "${cache%/*}" 2>/dev/null && _mg_serialise > "$cache" 2>/dev/null
    return 0
}

# -----------------------------------------------------------------------------
# Queries
# -----------------------------------------------------------------------------

#[pub]
# Usage: modgraph_modules -> prints every module name, one per line
modgraph_modules() { printf '%s\n' "${_MG_MODULES[@]}"; }

#[pub]
# Usage: modgraph_declares toml -> prints the modules toml names in a use line
modgraph_declares() { printf '%s' "${_MG_DECLARES[$1]:-}"; }

#[pub]
# Usage: modgraph_defines string -> prints the functions string introduces
modgraph_defines() { printf '%s' "${_MG_DEFINES[$1]:-}"; }

#[pub]
# Usage: modgraph_calls toml -> prints the prefixed functions toml invokes
modgraph_calls() { printf '%s' "${_MG_CALLS[$1]:-}"; }

#[pub]
# Usage: modgraph_owner str_trim -> prints the module defining it, if any
modgraph_owner() { printf '%s' "${_MG_OWNER[$1]:-}"; }

# modgraph_visibility <function>
#
# `pub` when consumers may call it, `lib` when only other modules in the same
# library may, and nothing at all when it is module-private.
#
#[pub]
# Usage: modgraph_visibility str_trim -> prints "pub", "lib", or nothing
modgraph_visibility() { printf '%s' "${_MG_VIS[$1]:-}"; }

# -----------------------------------------------------------------------------
# Cycles
# -----------------------------------------------------------------------------

# modgraph_cycle
#
# One cycle if the declaration graph has any, as `a -> b -> a`. Depth-first
# with the path carried down, so what comes back is the route rather than the
# bare fact, and a reader can see which edge to cut.
#
#[pub]
# Usage: modgraph_cycle -> prints a cycle path, or nothing. Returns 1 if none.
modgraph_cycle() {
    local -A state=()
    local found=""

    _mg_visit() {
        local node="$1" path="$2" next
        [[ -n "$found" ]] && return
        case "${state[$node]:-}" in
            open)  found="$path"; return ;;  # path already ends at the repeat
            done)  return ;;
        esac
        state[$node]="open"
        for next in ${_MG_DECLARES[$node]:-}; do
            [[ -n "${_MG_DECLARES[$next]+set}" ]] || continue
            _mg_visit "$next" "${path} -> ${next}"
        done
        state[$node]="done"
    }

    local mod
    for mod in "${_MG_MODULES[@]}"; do
        [[ -n "$found" ]] && break
        [[ "${state[$mod]:-}" == "done" ]] && continue
        _mg_visit "$mod" "$mod"
    done

    unset -f _mg_visit
    [[ -z "$found" ]] && return 1
    printf '%s' "${found# -> }"
    return 0
}

# -----------------------------------------------------------------------------
# The audit
# -----------------------------------------------------------------------------

# modgraph_audit
#
# Every violation the graph can see, one per line, in a single pass:
#
#   cycle       <path>                  the declaration graph loops
#   undeclared  <module> <fn> <owner>   a cross-module call with no `use`
#   private     <module> <fn> <owner>   a call to something not visible here
#   unreachable <module>                nothing uses it and it exports nothing
#   unused      <module> <dep>          declared, and nothing called from it
#
# One pass and direct reads, because the obvious shape is not viable. Asking
# the accessors question by question means a command substitution per call
# site, and a library of this size has around nine hundred of them: the forks
# cost more than the analysis. Reachability written as "for each module, scan
# every other" is quadratic on top of that. Here the used-set is built once and
# membership is a lookup.
#
# What it cannot see, stated plainly so nobody reads silence as approval:
#
#   - dynamic calls. `$cmd arg` or `eval` resolve at runtime and no pass over
#     the text will know what they name.
#   - functions a caller supplies. A module taking a callback calls something
#     this library never defines, which is indistinguishable from a builtin.
#   - whether an unused declaration is really unused. `unused` means no call
#     was seen, and a module can depend on another for a variable it sets or
#     for something it does when loaded. That is why it is reported apart from
#     the violations: it is a question, not a verdict.
#   - anything about a module that failed to parse. A file is text to this.
#
#[pub]
# Usage: modgraph_audit -> prints violations, one per line. Returns 1 if any.
modgraph_audit() {
    local found=0 mod fn owner vis declared
    local -A used=()

    local cycle
    if cycle="$(modgraph_cycle)"; then
        printf 'cycle\t%s\n' "$cycle"
        found=1
    fi

    # One pass for the used-set, so reachability is a lookup rather than a
    # second nested walk.
    for mod in "${_MG_MODULES[@]}"; do
        for fn in ${_MG_DECLARES[$mod]:-}; do
            used[$fn]=1
        done
    done

    for mod in "${_MG_MODULES[@]}"; do
        declared=" ${_MG_DECLARES[$mod]:-} "

        for fn in ${_MG_CALLS[$mod]:-}; do
            owner="${_MG_OWNER[$fn]:-}"
            # Undefined in this library: a builtin, an external command, or a
            # function the caller supplies. Not ours to judge.
            [[ -z "$owner" || "$owner" == "$mod" ]] && continue

            if [[ "$declared" != *" $owner "* ]]; then
                printf 'undeclared\t%s\t%s\t%s\n' "$mod" "$fn" "$owner"
                found=1
            fi

            vis="${_MG_VIS[$fn]:-}"
            if [[ "$vis" != "pub" && "$vis" != "lib" ]]; then
                printf 'private\t%s\t%s\t%s\n' "$mod" "$fn" "$owner"
                found=1
            fi
        done

        # Declared and never called. Reported, not failed: a module can depend
        # on another for a variable or for what it does when loaded, and
        # neither is a call. Six of these were real, and had been invisible
        # because nothing looked.
        local dep used_dep
        for dep in ${_MG_DECLARES[$mod]:-}; do
            used_dep=0
            for fn in ${_MG_CALLS[$mod]:-}; do
                [[ "${_MG_OWNER[$fn]:-}" == "$dep" ]] && { used_dep=1; break; }
            done
            [[ "$used_dep" -eq 0 ]] && printf 'unused\t%s\t%s\n' "$mod" "$dep"
        done
    done

    for mod in "${_MG_MODULES[@]}"; do
        [[ -n "${used[$mod]:-}" ]] && continue
        # Nothing declares it. That alone is fine: a module consumers load
        # directly is exactly what a library is for. It is unreachable only if
        # it also exports nothing.
        local exported=0
        for fn in ${_MG_DEFINES[$mod]:-}; do
            [[ -n "${_MG_VIS[$fn]:-}" ]] && { exported=1; break; }
        done
        if [[ "$exported" -eq 0 ]]; then
            printf 'unreachable\t%s\n' "$mod"
            found=1
        fi
    done

    return $(( found ))
}
