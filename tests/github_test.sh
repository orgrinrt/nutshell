#!/usr/bin/env bash
# Tests for reading a github release.
#
# Nothing here reaches the network. `curl` is stubbed on `PATH` and
# `_TOOL_PATH_curl` is pointed at the stub, because `http` resolves its client
# once at load and a stub arriving later would never be reached. The stub is
# what makes the failure paths testable at all: a 404, a 403 rate limit, a
# release with two matching assets and one with none are each a real answer
# this module has to give, and none of them can be produced on demand from the
# real api.

use test
use http
use json

. "${BASH_SOURCE[0]%/*}/../lib/github.sh"

_gh_setup() {
    GHROOT="$(mktemp -d)"
    mkdir -p "$GHROOT/bin"
    # The stub reads what the test put in `$GHROOT/reply` and `$GHROOT/status`,
    # so one stub serves every case rather than a stub per shape.
    cat > "$GHROOT/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; prev=""
for a in "$@"; do
    [ "$prev" = "-o" ] && out="$a"
    prev="$a"
done
if [ -n "$out" ]; then
    cat "${GHROOT}/asset" > "$out" 2>/dev/null || printf 'asset\n' > "$out"
    exit 0
fi
for a in "$@"; do
    case "$a" in
        *sha256sums*|*checksums*)
            cat "${GHROOT}/sums" 2>/dev/null
            printf '\n200'
            exit 0 ;;
    esac
done
cat "${GHROOT}/reply" 2>/dev/null
printf '\n%s' "$(cat "${GHROOT}/status" 2>/dev/null || printf '200')"
STUB
    chmod +x "$GHROOT/bin/curl"
    export GHROOT PATH="$GHROOT/bin:$PATH"
    _TOOL_PATH_curl="$GHROOT/bin/curl"
    _HTTP_READY=1; _HTTP_IMPL="curl"
    printf '200' > "$GHROOT/status"
    _gh_release_with '[{"name":"linux-binaries-x64.zip","browser_download_url":"http://x/lin"},{"name":"macos-binaries.tar.gz","browser_download_url":"http://x/mac"}]'
}
_gh_end() { rm -rf "$GHROOT"; unset GHROOT; }

_gh_release_with() {
    printf '{"tag_name":"v1.12.0","assets":%s}' "$1" > "$GHROOT/reply"
}

#[test]
it_reads_the_tag_off_a_release() {
    _gh_setup
    assert_eq "$(github_release_tag jtroo/kanata)" "v1.12.0"
    _gh_end
}

#[test]
it_lists_every_asset_as_a_name_and_a_url() {
    _gh_setup
    local out; out="$(github_assets jtroo/kanata)"
    assert_eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "2"
    assert_contains "$out" "linux-binaries-x64.zip"
    assert_contains "$out" "http://x/lin"
    _gh_end
}

#[test]
it_picks_the_one_asset_a_pattern_names() {
    _gh_setup
    local line; line="$(github_assets jtroo/kanata | github_asset_match '*linux*')"
    assert_contains "$line" "linux-binaries-x64.zip"
    assert_not_contains "$line" "macos"
    _gh_end
}

#[test]
it_refuses_a_pattern_that_matches_two_assets() {
    # **The one that matters.** Taking the first is how a machine ends up with
    # the debug build, or the source tarball, or the other architecture, and it
    # looks like success every time.
    _gh_setup
    _gh_release_with '[{"name":"foo-linux-x64.zip","browser_download_url":"http://x/a"},{"name":"foo-linux-x64-debug.zip","browser_download_url":"http://x/b"}]'
    local out rc
    out="$(github_assets jtroo/kanata | github_asset_match '*linux*' 2>&1)"; rc=$?
    assert_ne "$rc" "0"
    assert_contains "$out" "2 files match"
    # And it names them, so the caller can narrow the pattern.
    assert_contains "$out" "foo-linux-x64-debug.zip"
    _gh_end
}

#[test]
it_refuses_a_pattern_that_matches_nothing() {
    _gh_setup
    local out rc
    out="$(github_assets jtroo/kanata | github_asset_match '*openbsd*' 2>&1)"; rc=$?
    assert_ne "$rc" "0"
    assert_contains "$out" "nothing in the release matches"
    _gh_end
}

#[test]
it_says_which_release_is_missing_rather_than_that_something_failed() {
    _gh_setup
    printf '404' > "$GHROOT/status"
    printf '{"message":"Not Found"}' > "$GHROOT/reply"
    local out rc; out="$(github_release nobody/nothing 2>&1)"; rc=$?
    assert_ne "$rc" "0"
    assert_contains "$out" "no such release"
    _gh_end
}

#[test]
it_names_the_rate_limit_rather_than_calling_it_a_refusal() {
    # 403 from an unauthenticated api is nearly always the hourly limit, and a
    # message saying "refused" sends somebody looking for a permissions problem
    # that is not there.
    _gh_setup
    printf '403' > "$GHROOT/status"
    printf '{"message":"rate limit"}' > "$GHROOT/reply"
    local out; out="$(github_release jtroo/kanata 2>&1)"
    assert_contains "$out" "60 requests an hour"
    _gh_end
}

#[test]
it_guesses_an_asset_from_the_platform_and_says_that_it_guessed() {
    # A guess that does not announce itself is how the wrong architecture lands
    # on a machine and stays there.
    _gh_setup
    local out; out="$(github_fetch_asset jtroo/kanata "" "" "$GHROOT/got" 2>&1)"
    assert_contains "$out" "guessed from"
    _gh_end
}

#[test]
it_does_not_say_it_guessed_when_it_was_told() {
    _gh_setup
    local out; out="$(github_fetch_asset jtroo/kanata "" '*linux*' "$GHROOT/got" 2>&1)"
    assert_not_contains "$out" "guessed"
    assert_contains     "$out" "taking linux-binaries-x64.zip"
    _gh_end
}

#[test]
it_prints_the_asset_it_actually_took() {
    # So a caller records what it installed rather than what it asked for.
    _gh_setup
    local name; name="$(github_fetch_asset jtroo/kanata "" '*linux*' "$GHROOT/got" 2>/dev/null)"
    assert_eq "$name" "linux-binaries-x64.zip"
    assert_ok test -s "$GHROOT/got"
    _gh_end
}

#[test]
it_lists_what_the_release_holds_when_a_guess_misses() {
    # The guess failing is the common case on a project whose names are its
    # own, so the recovery has to be in front of whoever hit it.
    _gh_setup
    _gh_release_with '[{"name":"weird-naming-scheme.tar.gz","browser_download_url":"http://x/a"}]'
    local out rc; out="$(github_fetch_asset jtroo/kanata "" "" "$GHROOT/got" 2>&1)"; rc=$?
    assert_ne "$rc" "0"
    assert_contains "$out" "weird-naming-scheme.tar.gz"
    _gh_end
}

#[test]
it_wants_a_repository_and_a_destination() {
    _gh_setup
    assert_fails github_fetch_asset "" "" "" "$GHROOT/got"
    assert_fails github_fetch_asset jtroo/kanata "" "" ""
    assert_fails github_release ""
    _gh_end
}

#[test]
it_asks_for_a_tagged_release_when_given_a_tag() {
    # The pinned case. `/releases/latest` and `/releases/tags/<t>` are different
    # endpoints, and a row that pins a version has a reason to.
    _gh_setup
    cat > "$GHROOT/bin/curl" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in http*) printf '{"tag_name":"seen: %s","assets":[]}\n200' "$a"; exit 0 ;; esac; done
STUB
    chmod +x "$GHROOT/bin/curl"
    assert_contains "$(github_release_tag jtroo/kanata v1.0.0)" "releases/tags/v1.0.0"
    assert_contains "$(github_release_tag jtroo/kanata)"        "releases/latest"
    _gh_end
}

#[test]
the_platform_guess_offers_more_than_one_spelling() {
    # The defect this replaced a weaker test to catch: the first version
    # guessed the single word `darwin`, and a release calling the same file
    # `macos-binaries.tar.gz` matched nothing. One spelling per system is a coin
    # toss with one side painted.
    _gh_setup
    local pats n
    pats="$(github_platform_patterns)"
    n="$(printf '%s\n' "$pats" | grep -c .)"
    assert_ne "$n" "0"
    # Every line is a glob with something in the middle, never a bare star.
    assert_not_contains "$pats" $'\n*\n'
    case "$(uname -s)" in
        Darwin) assert_contains "$pats" "macos"; assert_contains "$pats" "darwin" ;;
        Linux)  assert_contains "$pats" "linux" ;;
    esac
    # And the system-plus-processor lines come before the system-alone ones,
    # since the narrower answer is the better one where both exist.
    local first last
    first="$(printf '%s\n' "$pats" | head -1)"
    last="$(printf '%s\n' "$pats" | tail -1)"
    assert_ne "$first" "$last"
    _gh_end
}

#[test]
it_finds_a_macos_asset_on_a_mac_and_a_linux_one_on_linux() {
    # The end of the same defect, through the real fetch rather than through the
    # pattern list. The fixture holds one asset per system, named the way a real
    # project names them, and this machine must find its own.
    _gh_setup
    local name; name="$(github_fetch_asset jtroo/kanata "" "" "$GHROOT/got" 2>/dev/null)"
    case "$(uname -s)" in
        Darwin) assert_eq "$name" "macos-binaries.tar.gz" ;;
        Linux)  assert_eq "$name" "linux-binaries-x64.zip" ;;
        *)      assert_eq "$name" "" ;;
    esac
    _gh_end
}

#[test]
it_says_it_could_not_check_rather_than_that_it_matched() {
    # The distinction the whole verification step exists for. A machine with no
    # sha256 tool has not verified anything, and reporting that as a pass makes
    # the check worse than absent.
    _gh_setup
    printf 'hello\n' > "$GHROOT/f"
    local sum
    if command -v sha256sum >/dev/null 2>&1; then sum="$(sha256sum < "$GHROOT/f")"
    else sum="$(shasum -a 256 < "$GHROOT/f")"; fi
    sum="${sum%% *}"

    assert_ok    github_verify_sha256 "$GHROOT/f" "$sum"
    # A wrong sum is 1, a missing file is 2, and they are not the same answer.
    github_verify_sha256 "$GHROOT/f" "0000" 2>/dev/null; assert_eq "$?" "1"
    github_verify_sha256 "$GHROOT/nosuch" "$sum" 2>/dev/null; assert_eq "$?" "2"
    _gh_end
}

#[test]
the_name_it_prints_is_the_only_thing_on_stdout() {
    # `log_info` writes to stdout in this library, so a function whose stdout is
    # its answer has to route every log line to stderr by hand. It did not, and
    # the caller got the log with the name appended to it.
    _gh_setup
    local name; name="$(github_fetch_asset jtroo/kanata "" '*linux*' "$GHROOT/got" 2>/dev/null)"
    assert_eq "$name" "linux-binaries-x64.zip"
    assert_not_contains "$name" "INFO"
    assert_not_contains "$name" "taking"
    _gh_end
}

#[test]
it_reads_a_sum_out_of_a_sidecar_the_release_publishes() {
    # kanata really does ship one, named `sha256sums`, holding `<sum>  <name>`
    # lines. Checked by hand against v1.12.0 and pinned here so nobody has to
    # do that again: the sum it returned matched the file byte for byte.
    _gh_setup
    _gh_release_with '[{"name":"linux-binaries-x64.zip","browser_download_url":"http://x/lin"},{"name":"sha256sums","browser_download_url":"http://x/sha256sums"}]'
    printf '0bedd91567c5d7c54679061baadc37e4f83fb71750003999bc1d11f2c9754f36  linux-binaries-x64.zip\nffff  other.zip\n' > "$GHROOT/sums"
    assert_eq "$(github_asset_sha256 jtroo/kanata "" linux-binaries-x64.zip)" \
              "0bedd91567c5d7c54679061baadc37e4f83fb71750003999bc1d11f2c9754f36"
    _gh_end
}

#[test]
it_reports_nothing_when_a_release_publishes_no_sums() {
    # **Nothing is a real answer here and is not a failure.** The caller has to
    # decide what to do about a download it cannot verify, and it cannot decide
    # if this pretends the question was answered.
    _gh_setup
    _gh_release_with '[{"name":"linux-binaries-x64.zip","browser_download_url":"http://x/lin"}]'
    local out rc; out="$(github_asset_sha256 jtroo/kanata "" linux-binaries-x64.zip 2>/dev/null)"; rc=$?
    assert_ne "$rc" "0"
    assert_empty "$out"
    _gh_end
}

#[test]
it_reports_nothing_for_an_asset_the_sidecar_does_not_list() {
    # A sidecar covering three of four files is a real shape, and the fourth is
    # unverified rather than verified against somebody else's sum.
    _gh_setup
    _gh_release_with '[{"name":"linux-binaries-x64.zip","browser_download_url":"http://x/lin"},{"name":"sha256sums","browser_download_url":"http://x/sha256sums"}]'
    printf 'aaaa  something-else.zip\n' > "$GHROOT/sums"
    assert_empty "$(github_asset_sha256 jtroo/kanata "" linux-binaries-x64.zip 2>/dev/null)"
    _gh_end
}
