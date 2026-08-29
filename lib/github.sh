#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/github.sh - Releases, and picking the right file out of one
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 1: builds on `http` and `json`.
#
# Reading, never writing. Nothing here creates a release, uploads to one, or
# authenticates as anybody. It answers one question: a project publishes
# binaries, which file is the one for this machine, and where is it.
#
# The awkward part is that a release's asset names are the project's own
# convention and nothing else. `linux-binaries-x64.zip`,
# `foo-x86_64-unknown-linux-gnu.tar.gz` and `foo_1.2_amd64.deb` are all things
# real projects publish, so a guess from the platform is a guess and has to say
# so. A caller that knows the convention passes a pattern and gets no guessing
# at all.
#
# Usage:
#   use github
#
#   github_release_tag jtroo/kanata                 # -> v1.12.0
#   github_assets jtroo/kanata                      # -> name<TAB>url per line
#   github_fetch_asset jtroo/kanata "" '*linux*x64*' /tmp/k.zip
# =============================================================================

[ -n "${_NUTSHELL_GITHUB_SH:-}" ] && return 0
_NUTSHELL_GITHUB_SH=1

use http
use json
use log

# Where the api lives, overridable so a test can point somewhere it controls
# rather than spending somebody's rate limit to prove a string was parsed.
: "${GITHUB_API:=https://api.github.com}"

# -----------------------------------------------------------------------------
# The release
# -----------------------------------------------------------------------------

#[pub]
# The release document, as json.
#
# With no tag, the project's own idea of latest, which is not the newest tag:
# `/releases/latest` skips prereleases and drafts, and that is the right
# default for something being installed onto a machine somebody uses.
# Usage: github_release <owner/repo> [tag] -> json on stdout
github_release() {
    local repo="${1:-}" tag="${2:-}" url
    [ -n "$repo" ] || { log_error "github_release: no repository given"; return 2; }

    if [ -n "$tag" ]; then
        url="${GITHUB_API}/repos/${repo}/releases/tags/${tag}"
    else
        url="${GITHUB_API}/repos/${repo}/releases/latest"
    fi

    http_get_json "$url" >/dev/null 2>&1
    if ! http_ok; then
        local st; st="$(http_status)"
        case "$st" in
            404) log_error "github: no such release, ${repo}${tag:+ at ${tag}}" ;;
            403) log_error "github: refused, ${repo}. an unauthenticated api allows 60 requests an hour" ;;
            "")  log_error "github: could not reach ${GITHUB_API}: $(http_error)" ;;
            *)   log_error "github: ${repo} answered ${st}" ;;
        esac
        return 1
    fi
    http_body
}

#[pub]
# Usage: github_release_tag <owner/repo> [tag] -> the tag it resolved to
github_release_tag() {
    local j; j="$(github_release "$@")" || return $?
    json_get "$j" tag_name
}

# -----------------------------------------------------------------------------
# The assets
# -----------------------------------------------------------------------------

#[pub]
# Every asset in a release, one `name<TAB>url` per line.
#
# Tab separated because an asset name may hold a space and every one of these
# ends up in a filename. Nothing else in the format needs escaping: a github
# asset name cannot hold a tab or a newline.
# Usage: github_assets <owner/repo> [tag] -> lines on stdout
github_assets() {
    local j; j="$(github_release "$@")" || return $?
    _github_assets_from "$j"
}

# The same, from a document already fetched, so a caller doing two things with
# one release spends one request rather than three.
_github_assets_from() {
    local j="${1:-}" n i name url
    n="$(json_length "$j" assets 2>/dev/null)" || return 1
    [ -n "$n" ] || return 1
    i=0
    while [ "$i" -lt "$n" ]; do
        name="$(json_get "$j" "assets.${i}.name" 2>/dev/null)"
        url="$(json_get "$j" "assets.${i}.browser_download_url" 2>/dev/null)"
        [ -n "$name" ] && [ -n "$url" ] && printf '%s\t%s\n' "$name" "$url"
        i=$(( i + 1 ))
    done
    return 0
}

#[pub]
# What an asset for this machine might be called, most specific first.
#
# One glob per line, and there are several because there is no convention to
# follow. The same operating system is spelled `darwin`, `macos` and `apple`
# depending on whose release you are reading, and the same processor is `x64`,
# `x86_64` and `amd64`. A single glob picks one of those spellings and misses
# every project using another, which is not a guess, it is a coin toss with one
# side painted.
#
# Ordered so a line naming both the system and the processor is tried before
# one naming only the system, because an asset matching the narrower pattern is
# the better answer where both exist.
# Usage: github_platform_patterns -> globs, one per line
github_platform_patterns() {
    local oses="" arches="" o a
    case "$(uname -s 2>/dev/null)" in
        Linux)  oses="linux" ;;
        Darwin) oses="macos darwin apple osx" ;;
    esac
    case "$(uname -m 2>/dev/null)" in
        x86_64|amd64)  arches="x64 x86_64 amd64" ;;
        aarch64|arm64) arches="arm64 aarch64" ;;
    esac
    [ -n "$oses" ] || return 1

    for o in $oses; do
        for a in $arches; do printf '*%s*%s*\n' "$o" "$a"; done
    done
    # The system alone, last, for a release publishing one file per system.
    for o in $oses; do printf '*%s*\n' "$o"; done
    return 0
}

#[pub]
# The words this machine is, for saying what was guessed from.
# Usage: github_platform -> "linux/x64"
github_platform() {
    local o a
    o="$(uname -s 2>/dev/null)"; a="$(uname -m 2>/dev/null)"
    printf '%s/%s' "${o:-unknown}" "${a:-unknown}"
}

#[pub]
# Which asset matches, out of `name<TAB>url` lines on stdin.
#
# **Refuses an ambiguous match rather than taking the first.** Two files
# matching one pattern means the pattern did not say what the caller thought it
# said, and picking one of them is how a machine ends up with the debug build,
# or the source tarball, or the other architecture. The names are printed so
# the caller can narrow it.
# Usage: github_assets ... | github_asset_match '<glob>' -> one line
github_asset_match() {
    local pat="${1:-}" line name hits=0 first="" names=""
    [ -n "$pat" ] || { log_error "github_asset_match: no pattern"; return 2; }

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        name="${line%%	*}"
        # shellcheck disable=SC2254
        case "$name" in
            $pat) hits=$(( hits + 1 ))
                  [ "$hits" = "1" ] && first="$line"
                  names="${names}${names:+, }${name}" ;;
        esac
    done

    case "$hits" in
        0) log_error "github: nothing in the release matches ${pat}"; return 1 ;;
        1) printf '%s\n' "$first" ;;
        *) log_error "github: ${hits} files match ${pat}, so it does not say which one: ${names}"
           return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# Getting it
# -----------------------------------------------------------------------------

#[pub]
# Fetch one asset to a path.
#
# An empty pattern means guess from the platform, and a guess says so on the
# log, every time, because the alternative is a machine quietly holding the
# wrong architecture.
#
# Prints the asset name it took, so a caller can record what it actually
# installed rather than what it asked for.
# Usage: github_fetch_asset <owner/repo> <tag|""> <pattern|""> <dest> -> name
github_fetch_asset() {
    local repo="${1:-}" tag="${2:-}" pat="${3:-}" dest="${4:-}"
    [ -n "$repo" ] && [ -n "$dest" ] || {
        log_error "github_fetch_asset: wants a repository and a destination"; return 2; }

    local j; j="$(github_release "$repo" "$tag")" || return $?
    local resolved; resolved="$(json_get "$j" tag_name)"

    local line="" guessed=0 tried=""
    if [ -n "$pat" ]; then
        line="$(_github_assets_from "$j" | github_asset_match "$pat")" || return 1
    else
        guessed=1
        local cand
        while IFS= read -r cand; do
            [ -n "$cand" ] || continue
            tried="${tried}${tried:+, }${cand}"
            line="$(_github_assets_from "$j" | github_asset_match "$cand" 2>/dev/null)" && {
                pat="$cand"; break; }
            line=""
        done <<EOF
$(github_platform_patterns)
EOF
        if [ -z "$line" ]; then
            log_error "github: nothing in ${repo} ${resolved} matches this machine."
            log_error "github: tried ${tried:-nothing, since this platform has no spelling I know}"
            log_error "github: the release holds:"
            _github_assets_from "$j" | while IFS='	' read -r n _; do log_error "    ${n}"; done
            log_error "github: name the asset with a pattern in the row rather than leaving it to a guess"
            return 1
        fi
    fi

    local name url
    name="${line%%	*}"; url="${line#*	}"

    # **`log_info` writes to stdout**, and this function's stdout is the asset
    # name its caller reads. So every line here goes to stderr explicitly, and
    # the one that does not is the `printf` at the end. Found by a test that
    # asked for the name and got the log with the name appended to it.
    if [ "$guessed" = "1" ]; then
        log_warn "github: no asset pattern for ${repo}, so ${name} was guessed from $(github_platform) via ${pat}"
    fi
    log_info "github: ${repo} ${resolved}, taking ${name}" >&2

    http_download "$url" "$dest" || {
        log_error "github: could not download ${name}"
        return 1
    }
    printf '%s' "$name"
}

# -----------------------------------------------------------------------------
# Whether it is what it says
# -----------------------------------------------------------------------------

#[pub]
# The checksum a release publishes for one asset, if it publishes any.
#
# There is no standard for this. What projects do is ship a sidecar holding
# `<sum>  <name>` lines, under a name with `sha256` or `checksum` in it, so
# that is what gets looked for, and a release doing something else reports
# nothing rather than guessing.
#
# **Nothing is a real answer and is not a failure.** A caller has to decide
# what to do about an unverifiable download, and it cannot decide if this
# pretends the question was answered.
# Usage: github_asset_sha256 <owner/repo> <tag|""> <asset name> -> a sum, or nothing
github_asset_sha256() {
    local repo="${1:-}" tag="${2:-}" want="${3:-}"
    [ -n "$repo" ] && [ -n "$want" ] || return 2

    local j; j="$(github_release "$repo" "$tag")" || return $?

    local line name url sums=""
    while IFS= read -r line; do
        name="${line%%	*}"
        case "$name" in
            *sha256*|*SHA256*|*checksums*|*CHECKSUMS*) sums="${line#*	}"; break ;;
        esac
    done <<EOF
$(_github_assets_from "$j")
EOF
    [ -n "$sums" ] || return 1

    local body; body="$(http_get "$sums" >/dev/null 2>&1; http_body)" || return 1
    printf '%s\n' "$body" | while IFS= read -r line; do
        case "$line" in
            *"$want"*) printf '%s' "${line%% *}"; return 0 ;;
        esac
    done
    return 0
}

#[pub]
# Does this file hash to that.
#
# Reports what it could not do rather than passing. A machine with no sha256
# tool cannot verify, and "could not check" is a different answer from "it
# matched", which is the distinction that makes verification worth having.
# Usage: github_verify_sha256 <path> <sum> -> 0 matched, 1 differed, 2 could not check
github_verify_sha256() {
    local path="${1:-}" want="${2:-}" got=""
    [ -n "$path" ] && [ -n "$want" ] || return 2
    [ -r "$path" ] || { log_error "github: nothing at ${path} to check"; return 2; }

    if command -v sha256sum >/dev/null 2>&1; then
        got="$(sha256sum -- "$path" 2>/dev/null)"; got="${got%% *}"
    elif command -v shasum >/dev/null 2>&1; then
        got="$(shasum -a 256 -- "$path" 2>/dev/null)"; got="${got%% *}"
    else
        log_warn "github: no sha256sum or shasum here, so ${path} is unverified"
        return 2
    fi

    [ -n "$got" ] || { log_warn "github: could not hash ${path}"; return 2; }
    if [ "$got" = "$want" ]; then
        return 0
    fi
    log_error "github: ${path} hashes to ${got}, and the release says ${want}"
    return 1
}
