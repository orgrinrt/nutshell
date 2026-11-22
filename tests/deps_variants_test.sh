#!/usr/bin/env bash
# Tests for what `deps` has to know before a toml backend can be picked: which
# `yq` this is, which `taplo`, and whether either can read TOML at all.
#
# `which yq` is ambiguous on a machine with two of them (mikefarah's Go binary
# and the python wrapper), so the answer cannot come from the name. It comes
# from asking the binary, and from `[deps.paths]` in the manifest of the unit
# that is running, wherever the process was started.
#
# Every tool here is a fake written into a temporary directory, so no test
# passes or fails on what the machine happens to have installed.

use deps test

# A tool that answers `--version` with a line and anything else with some json,
# and writes `called` to a log when it is run, so a test can tell whether it was
# asked at all. A version of `BROKEN` is a tool that fails.
_dv_fake() {
    local file="$1" ver="$2" log="${3:-}" out="${4:-}" version_arm
    [ -n "$out" ] || out='{"a": 1}'
    if [ "$ver" = BROKEN ]; then
        version_arm='exit 1'
    else
        version_arm="echo '${ver}'"
    fi
    {
        printf '#!/bin/sh\n'
        [ -n "$log" ] && printf 'echo called >> "%s"\n' "$log"
        printf 'case "$*" in\n  *--version*) %s ;;\n  *) cat >/dev/null; echo '"'"'%s'"'"' ;;\nesac\n' \
            "$version_arm" "$out"
    } > "$file"
    chmod +x "$file"
}

_dv_mikefarah() { _dv_fake "$1" 'yq (https://github.com/mikefarah/yq/) version v4.44.3' "${2:-}" "${3:-}"; }
_dv_python()    { _dv_fake "$1" 'yq 0.0.0' "${2:-}"; }
_dv_taplo()     { _dv_fake "$1" 'taplo 0.9.3' "${2:-}"; }

# A unit: a manifest with a `[deps.paths]` body, and a script one directory
# below it, the way a project keeps its scripts apart from its manifest.
_dv_unit() {
    local root="$1" paths="$2" body="$3"
    mkdir -p "${root}/sub"
    printf '[deps.paths]\n%s\n' "$paths" > "${root}/nut.toml"
    printf 'use deps\n%s\n' "$body" > "${root}/sub/s.sh"
}

# Run a script as nutshell does, from a directory that is not its own, so only
# the unit can be what finds the manifest. stdout only, or stderr only.
_dv_out() { ( cd / && "${NUTSHELL_ROOT}/bin/nutshell" "$1" 2>/dev/null ); }
_dv_err() { ( cd / && "${NUTSHELL_ROOT}/bin/nutshell" "$1" 2>&1 >/dev/null ); }

#[test]
it_tells_a_mikefarah_yq_from_the_python_one() {
    local t; t="$(mktemp -d)"
    _dv_mikefarah "$t/yq-go"; _dv_python "$t/yq-py"
    _dv_unit "$t/go" "yq = \"$t/yq-go\"" 'deps_variant yq'
    _dv_unit "$t/py" "yq = \"$t/yq-py\"" 'deps_variant yq'
    assert_eq "$(_dv_out "$t/go/sub/s.sh")" "mikefarah"
    assert_eq "$(_dv_out "$t/py/sub/s.sh")" "python"
    rm -rf "$t"
}

#[test]
it_calls_a_yq_that_will_not_report_itself_unknown() {
    local t; t="$(mktemp -d)"
    _dv_fake "$t/yq" BROKEN
    _dv_unit "$t/u" "yq = \"$t/yq\"" 'deps_variant yq'
    assert_eq "$(_dv_out "$t/u/sub/s.sh")" "unknown"
    rm -rf "$t"
}

#[test]
it_reads_deps_paths_from_the_scripts_own_unit_with_cwd_elsewhere() {
    local t; t="$(mktemp -d)"
    _dv_mikefarah "$t/yq-go"
    _dv_unit "$t/u" "yq = \"$t/yq-go\"" 'deps_path yq'
    assert_eq "$(_dv_out "$t/u/sub/s.sh")" "$t/yq-go"
    rm -rf "$t"
}

#[test]
it_prefers_the_scripts_unit_over_the_working_directory() {
    local t; t="$(mktemp -d)"
    _dv_mikefarah "$t/yq-go"; _dv_python "$t/yq-py"
    _dv_unit "$t/unit" "yq = \"$t/yq-go\"" 'deps_variant yq'
    _dv_unit "$t/cwd"  "yq = \"$t/yq-py\"" 'true'
    assert_eq "$( cd "$t/cwd" && "${NUTSHELL_ROOT}/bin/nutshell" "$t/unit/sub/s.sh" 2>/dev/null )" "mikefarah"
    rm -rf "$t"
}

#[test]
it_still_falls_back_to_the_manifest_in_the_working_directory() {
    # A scratch script inside the project being worked in has no unit of its
    # own, and that project's manifest is the right answer for it.
    local t; t="$(mktemp -d)"
    _dv_mikefarah "$t/yq-go"
    _dv_unit "$t/proj" "yq = \"$t/yq-go\"" 'true'
    mkdir -p "$t/loose"
    printf 'use deps\ndeps_variant yq\n' > "$t/loose/s.sh"
    assert_eq "$( cd "$t/proj" && "${NUTSHELL_ROOT}/bin/nutshell" "$t/loose/s.sh" 2>/dev/null )" "mikefarah"
    rm -rf "$t"
}

#[test]
it_refuses_a_deps_paths_entry_that_is_not_an_executable() {
    # It used to fall through to PATH and answer with another binary, so a
    # typo in the manifest pinned nothing and said nothing.
    local t; t="$(mktemp -d)"
    _dv_unit "$t/u" 'sed = "/nonexistent/sed"' \
        'deps_has sed && echo FOUND; deps_path sed; echo "rc=$?"'
    local out err
    out="$(_dv_out "$t/u/sub/s.sh")"
    err="$(_dv_err "$t/u/sub/s.sh")"
    assert_not_contains "$out" "FOUND"
    assert_not_contains "$out" "/usr/bin/sed"
    assert_contains "$out" "rc=1"
    assert_contains "$err" "[deps.paths]"
    assert_contains "$err" "/nonexistent/sed"
    rm -rf "$t"
}

#[test]
it_reads_a_deps_paths_entry_written_as_a_dotted_key() {
    # `[deps]` with `paths.sed = ...` is the same table as `[deps.paths]` with
    # `sed = ...`. It used to pin nothing and say nothing.
    local t; t="$(mktemp -d)"
    mkdir -p "$t/u/sub"
    printf '[deps]\npaths.sed = "/nonexistent/sed"\n' > "$t/u/nut.toml"
    printf 'use deps\n%s\n' 'deps_has sed && echo FOUND; deps_path sed; echo "rc=$?"' > "$t/u/sub/s.sh"
    local out err
    out="$(_dv_out "$t/u/sub/s.sh")"
    err="$(_dv_err "$t/u/sub/s.sh")"
    assert_not_contains "$out" "FOUND"
    assert_not_contains "$out" "/usr/bin/sed"
    assert_contains "$out" "rc=1"
    assert_contains "$err" "/nonexistent/sed"
    rm -rf "$t"
}

#[test]
it_reads_a_deps_paths_entry_written_at_the_root_with_padded_dots() {
    local t; t="$(mktemp -d)"
    _dv_mikefarah "$t/yq-go"
    mkdir -p "$t/u/sub"
    printf 'deps . paths . yq = "%s"\n' "$t/yq-go" > "$t/u/nut.toml"
    printf 'use deps\ndeps_path yq\n' > "$t/u/sub/s.sh"
    assert_eq "$(_dv_out "$t/u/sub/s.sh")" "$t/yq-go"
    rm -rf "$t"
}

#[test]
it_reads_deps_paths_written_as_an_inline_table() {
    # Valid TOML, and the same pin as `[deps.paths]` with `sed = ...`. It was
    # refused while the reader here could not read an inline table; the toml
    # reader can, so the pin is honoured, and a pin to a file that is not an
    # executable is refused as it is in any other spelling.
    local t; t="$(mktemp -d)"
    mkdir -p "$t/u/sub"
    printf '[deps]\npaths = { sed = "/nonexistent/sed" }\n' > "$t/u/nut.toml"
    printf 'use deps\n%s\n' 'deps_has sed && echo FOUND; deps_path sed; echo "rc=$?"' > "$t/u/sub/s.sh"
    local out err
    out="$(_dv_out "$t/u/sub/s.sh")"
    err="$(_dv_err "$t/u/sub/s.sh")"
    assert_not_contains "$out" "FOUND"
    assert_contains "$out" "rc=1"
    assert_contains "$err" "[deps.paths]"
    assert_contains "$err" "/nonexistent/sed"
    rm -rf "$t"
}

#[test]
it_reads_a_deps_paths_entry_with_a_quoted_key() {
    # `"sed"` and `sed` are one key in TOML.
    local t; t="$(mktemp -d)"
    mkdir -p "$t/u/sub"
    printf '[deps.paths]\n"sed" = "/nonexistent/sed"\n' > "$t/u/nut.toml"
    printf 'use deps\n%s\n' 'deps_has sed && echo FOUND; deps_path sed; echo "rc=$?"' > "$t/u/sub/s.sh"
    local out err
    out="$(_dv_out "$t/u/sub/s.sh")"
    err="$(_dv_err "$t/u/sub/s.sh")"
    assert_not_contains "$out" "FOUND"
    assert_contains "$out" "rc=1"
    assert_contains "$err" "/nonexistent/sed"
    rm -rf "$t"
}

#[test]
it_reads_a_deps_paths_entry_under_a_quoted_header() {
    local t; t="$(mktemp -d)"
    mkdir -p "$t/u/sub"
    printf '["deps"."paths"]\nsed = "/nonexistent/sed"\n' > "$t/u/nut.toml"
    printf 'use deps\n%s\n' 'deps_has sed && echo FOUND; deps_path sed; echo "rc=$?"' > "$t/u/sub/s.sh"
    local out err
    out="$(_dv_out "$t/u/sub/s.sh")"
    err="$(_dv_err "$t/u/sub/s.sh")"
    assert_not_contains "$out" "FOUND"
    assert_contains "$out" "rc=1"
    assert_contains "$err" "/nonexistent/sed"
    rm -rf "$t"
}

#[test]
it_reads_a_deps_paths_entry_written_as_a_literal_string() {
    local t; t="$(mktemp -d)"
    mkdir -p "$t/u/sub"
    printf "[deps.paths]\nsed = '/nonexistent/sed'\n" > "$t/u/nut.toml"
    printf 'use deps\n%s\n' 'deps_has sed && echo FOUND; deps_path sed; echo "rc=$?"' > "$t/u/sub/s.sh"
    local out err
    out="$(_dv_out "$t/u/sub/s.sh")"
    err="$(_dv_err "$t/u/sub/s.sh")"
    assert_not_contains "$out" "FOUND"
    assert_contains "$out" "rc=1"
    assert_contains "$err" "/nonexistent/sed"
    rm -rf "$t"
}

#[test]
it_says_once_that_the_manifest_is_not_toml_and_pins_nothing() {
    # A manifest this cannot read is said, with its line, and the tools are
    # still found on PATH: refusing every tool would stop the run that is
    # reporting the fault.
    local t; t="$(mktemp -d)"
    mkdir -p "$t/u/sub"
    printf '[deps.paths\nsed = "/nonexistent/sed"\n' > "$t/u/nut.toml"
    printf 'use deps\n%s\n' 'deps_has sed && echo SED-OK; deps_has awk && echo AWK-OK' > "$t/u/sub/s.sh"
    local out err
    out="$(_dv_out "$t/u/sub/s.sh")"
    err="$(_dv_err "$t/u/sub/s.sh")"
    assert_contains "$out" "SED-OK"
    assert_contains "$out" "AWK-OK"
    assert_contains "$err" "nut.toml"
    assert_eq "$(printf '%s\n' "$err" | grep -c '^\[ERROR\] deps:')" "1" "said once, not once per tool"
    rm -rf "$t"
}

#[test]
it_refuses_a_deps_paths_entry_that_is_empty() {
    local t; t="$(mktemp -d)"
    _dv_unit "$t/u" 'sed = ""' 'deps_has sed && echo FOUND; echo done'
    assert_not_contains "$(_dv_out "$t/u/sub/s.sh")" "FOUND"
    assert_contains "$(_dv_err "$t/u/sub/s.sh")" "[deps.paths]"
    rm -rf "$t"
}

#[test]
it_still_resolves_a_tool_the_manifest_does_not_mention() {
    # The control for the two refusals above: an entry for one tool is no
    # reason to refuse another.
    local t; t="$(mktemp -d)"
    _dv_unit "$t/u" 'sed = "/nonexistent/sed"' 'deps_has grep && echo FOUND'
    assert_contains "$(_dv_out "$t/u/sub/s.sh")" "FOUND"
    rm -rf "$t"
}

#[test]
it_sees_a_tool_installed_after_deps_forget() {
    local t old; t="$(mktemp -d)"; old="$PATH"
    mkdir -p "$t/bin"
    PATH="$t/bin:$PATH"
    assert_fails deps_has nut_fresh_tool_xyzzy
    printf '#!/bin/sh\n' > "$t/bin/nut_fresh_tool_xyzzy"; chmod +x "$t/bin/nut_fresh_tool_xyzzy"
    # The miss is remembered for the life of the process, deliberately.
    assert_fails deps_has nut_fresh_tool_xyzzy
    deps_forget nut_fresh_tool_xyzzy
    assert_ok deps_has nut_fresh_tool_xyzzy
    assert_eq "$(deps_path nut_fresh_tool_xyzzy)" "$t/bin/nut_fresh_tool_xyzzy"
    PATH="$old"; rm -rf "$t"
}

#[test]
it_forgets_one_tool_and_leaves_the_others_resolved() {
    deps_has sed; deps_has grep
    local grep_path="${_TOOL_PATH_grep}"
    deps_forget sed
    assert_eq "${_TOOL_PATH_sed:-}" ""
    assert_eq "${_TOOL_PATH_grep:-}" "$grep_path"
    assert_ok deps_has sed
    assert_ne "${_TOOL_PATH_sed:-}" ""
}

#[test]
it_forgets_everything_without_arguments() {
    deps_has sed; deps_has awk
    deps_forget
    assert_eq "${_TOOL_PATH_sed:-}" ""
    assert_eq "${_TOOL_PATH_awk:-}" ""
    assert_eq "${_TOOLS_AVAILABLE:-}" ""
    # Capabilities are derived from tools, so they are asked of the tools again.
    assert_ok deps_has sed
    assert_ok deps_can sed_extended
}

#[test]
it_resolves_a_cold_tool_when_asked_whether_it_is_gnu() {
    # The first question in the process is `deps_is_gnu`, so nothing has
    # resolved `find` for it. The pinned `find` does not say it is GNU, which
    # the real one on this machine does, so "not" is the answer only if the
    # pinned tool was found and probed before the question was answered.
    local t; t="$(mktemp -d)"
    _dv_fake "$t/find" BROKEN
    _dv_unit "$t/u" "find = \"$t/find\"" 'deps_is_gnu find && echo gnu || echo not'
    assert_eq "$(_dv_out "$t/u/sub/s.sh")" "not"
    rm -rf "$t"
}

#[test]
it_makes_has_command_honour_deps_paths() {
    local t; t="$(mktemp -d)"
    _dv_fake "$t/nut_fake_cmd" 'fake 1'
    _dv_unit "$t/u" "nut_fake_cmd = \"$t/nut_fake_cmd\"" \
        'use validate
has_command nut_fake_cmd && echo yes || echo no
has_command nut_no_such_cmd_xyzzy && echo yes || echo no'
    assert_eq "$(_dv_out "$t/u/sub/s.sh")" "$(printf 'yes\nno')"
    rm -rf "$t"
}

#[test]
it_makes_hash_use_the_sha256sum_deps_resolved() {
    local t; t="$(mktemp -d)"
    printf 'x\n' > "$t/f"
    printf '#!/bin/sh\necho "feedface  $2"\n' > "$t/sha256sum"; chmod +x "$t/sha256sum"
    _dv_unit "$t/u" "sha256sum = \"$t/sha256sum\"" \
        "use hash
hash_impl; echo
hash_sha256 \"$t/f\"; echo"
    assert_eq "$(_dv_out "$t/u/sub/s.sh")" "$(printf 'sha256sum\nfeedface')"
    rm -rf "$t"
}

#[test]
it_leaves_command_v_to_deps_alone() {
    # The count that was 14 outside `deps.sh` when this was written. A tool is
    # found through `deps_has`, so `[deps.paths]` and the cache apply to it; a
    # function is asked about with `type`, which is not a tool lookup.
    local hits
    hits="$(grep -rn 'command -v' "${NUTSHELL_ROOT}/lib" | grep -v -e '/lib/deps\.sh:' -e '/lib/deps/' || true)"
    assert_eq "$hits" ""
}

#[test]
it_normalises_the_architecture() {
    use os
    uname() { printf '%s\n' "$_DV_MACHINE"; }
    local m
    for m in x86_64 amd64; do _DV_MACHINE="$m"; assert_eq "$(os_arch)" "x86_64"; done
    for m in aarch64 arm64; do _DV_MACHINE="$m"; assert_eq "$(os_arch)" "arm64"; done
    # Anything else is passed through as the machine said it.
    for m in i686 armv7l riscv64; do _DV_MACHINE="$m"; assert_eq "$(os_arch)" "$m"; done
    unset -f uname
}

#[test]
it_tells_a_taplo_from_something_else() {
    local t; t="$(mktemp -d)"
    _dv_taplo "$t/taplo"; _dv_fake "$t/other" 'something 1.0'
    _dv_unit "$t/a" "taplo = \"$t/taplo\"" 'deps_variant taplo'
    _dv_unit "$t/b" "taplo = \"$t/other\"" 'deps_variant taplo'
    assert_eq "$(_dv_out "$t/a/sub/s.sh")" "taplo"
    assert_eq "$(_dv_out "$t/b/sub/s.sh")" "unknown"
    rm -rf "$t"
}

#[test]
it_probes_toml_read_only_when_asked() {
    local t; t="$(mktemp -d)"
    _dv_mikefarah "$t/yq" "$t/log"
    _dv_unit "$t/u" "yq = \"$t/yq\"" \
        'deps_has sed; deps_can sed_extended
[ -e "'"$t"'/log" ] && echo "called early" || echo "quiet"
deps_can toml_read && echo yes || echo no
[ -e "'"$t"'/log" ] && echo "called" || echo "never"'
    assert_eq "$(_dv_out "$t/u/sub/s.sh")" "$(printf 'quiet\nyes\ncalled')"
    rm -rf "$t"
}

#[test]
it_counts_only_mikefarah_for_toml_read() {
    local t; t="$(mktemp -d)"
    _dv_python "$t/yq-py" "$t/log"
    _dv_unit "$t/u" "yq = \"$t/yq-py\"" 'deps_cap toml_read'
    assert_eq "$(_dv_out "$t/u/sub/s.sh")" "0"
    rm -rf "$t"
}

#[test]
it_reports_no_toml_read_when_the_parse_fails() {
    # A mikefarah yq that answers with something that is not the document: the
    # flag is what the tool does, not what its version line claims.
    local t; t="$(mktemp -d)"
    _dv_mikefarah "$t/yq" "" 'Error: bad file'
    _dv_unit "$t/u" "yq = \"$t/yq\"" 'deps_variant yq; deps_cap toml_read'
    assert_eq "$(_dv_out "$t/u/sub/s.sh")" "$(printf 'mikefarah\n0')"
    rm -rf "$t"
}

#[test]
it_probes_toml_json_taplo_by_what_taplo_emits() {
    local t; t="$(mktemp -d)"
    _dv_taplo "$t/taplo" "$t/log"
    _dv_fake "$t/taplo-bad" 'taplo 0.9.3' "" 'oops'
    _dv_unit "$t/ok"  "taplo = \"$t/taplo\"" 'deps_cap toml_json_taplo'
    _dv_unit "$t/bad" "taplo = \"$t/taplo-bad\"" 'deps_cap toml_json_taplo'
    assert_eq "$(_dv_out "$t/ok/sub/s.sh")" "1"
    assert_eq "$(_dv_out "$t/bad/sub/s.sh")" "0"
    assert_ok test -e "$t/log"
    rm -rf "$t"
}

# `deps_pinned` reads a manifest for the pin of a tool, whatever the spelling.
# Each expected path is the literal written into the manifest of the test.
_dv_pinned() {
    local t body="$1" tool="${2:-sed}" out rc
    t="$(mktemp -d)"; printf '%s\n' "$body" > "$t/nut.toml"
    out="$( ( cd / && "${NUTSHELL_ROOT}/bin/nutshell" -c "use deps::pins; deps_pinned '$t/nut.toml' '$tool'; echo rc=\$?" ) 2>&1)"
    rm -rf "$t"
    printf '%s' "$out"
}

#[test]
it_reads_a_pin_in_every_spelling_toml_allows() {
    assert_eq "$(_dv_pinned $'[deps.paths]\nsed = "/opt/a/sed"')" $'/opt/a/sed\nrc=0'
    assert_eq "$(_dv_pinned $'[deps]\npaths.sed = "/opt/b/sed"')" $'/opt/b/sed\nrc=0'
    assert_eq "$(_dv_pinned $'deps.paths.sed = "/opt/c/sed"')" $'/opt/c/sed\nrc=0'
    assert_eq "$(_dv_pinned $'[deps.paths]\n"sed" = \'/opt/d/sed\'')" $'/opt/d/sed\nrc=0'
    assert_eq "$(_dv_pinned $'deps = { paths = { sed = "/opt/e/sed" } }')" $'/opt/e/sed\nrc=0'
}

#[test]
it_reads_the_pin_of_a_tool_whose_name_holds_a_dot() {
    assert_eq "$(_dv_pinned $'[deps.paths]\n"python3.11" = "/opt/py/python3.11"' python3.11)" $'/opt/py/python3.11\nrc=0'
}

#[test]
it_reports_no_pin_for_a_tool_the_manifest_does_not_name() {
    assert_eq "$(_dv_pinned $'[deps.paths]\nawk = "/opt/a/awk"')" "rc=1"
}

#[test]
it_refuses_a_pin_that_is_a_table() {
    local out; out="$(_dv_pinned $'[deps.paths.sed]\npath = "/opt/a/sed"')"
    assert_contains "$out" "is a table"
    assert_contains "$out" "rc=2"
}
