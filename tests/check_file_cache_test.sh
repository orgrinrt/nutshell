#!/usr/bin/env bash
# Tests for reading a file once and answering from it.
#
# Every check reads the same twenty-odd files, and used to do it with a
# pipeline per question per function: `grep | head | cut` for a definition,
# `tail | grep | head | cut` for its end, a seven-stage `grep -v` chain for its
# body, and five more processes to count what was in it. Thousands of processes
# per check, and each check starting again from nothing.
#
# The answers have to be the same ones. A faster checker that reports different
# functions is not a faster checker.

use test

. "${BASH_SOURCE[0]%/*}/../lib/check-runner.sh"

_cfc_tmp() { printf '%s' "$(mktemp -d "${TMPDIR:-/tmp}/nutshell-filecache.XXXXXX")"; }

# A file with one of each shape the body reader has to judge.
_cfc_file() {
    local d="$1"
    mkdir -p "$d"
    cat > "$d/a.sh" <<'EOS'
#!/usr/bin/env bash

thin() { other "$1"; }

#[pub]
documented() {
    local a="$1"
    printf '%s' "$a"
}

does_work() {
    local a="$1" b="$2"
    # a comment, which is not a line of body

    readonly c=3
    if [[ -n "$a" ]]; then
        printf '%s-%s' "$a" "$b"
    fi
    return
}
EOS
    printf '%s' "$d/a.sh"
}

#[test]
it_finds_where_a_function_is_defined() {
    local d; d="$(_cfc_tmp)"; local f; f="$(_cfc_file "$d")"
    assert_ok nut_load_file "$f"
    assert_eq "$(nut_defined_at "$f" documented)" "6"
    assert_eq "$(nut_defined_at "$f" does_work)" "11"
    assert_fails nut_defined_at "$f" no_such_function
    rm -rf "$d"
}

#[test]
it_finds_where_a_function_ends() {
    local d; d="$(_cfc_tmp)"; local f; f="$(_cfc_file "$d")"
    nut_load_file "$f"
    assert_eq "$(nut_ends_at "$f" documented)" "9"
    assert_eq "$(nut_ends_at "$f" does_work)" "20"
    rm -rf "$d"
}

#[test]
it_drops_the_lines_that_are_not_body() {
    local d; d="$(_cfc_tmp)"; local f; f="$(_cfc_file "$d")"
    nut_load_file "$f"
    local -a body=()
    assert_ok nut_body_of "$f" does_work body
    # `local`, `readonly`, the comment, the blank and the bare `return` all go.
    # What is left is the `if`, the `printf` and the `fi`.
    assert_eq "${#body[@]}" "3"
    assert_contains "${body[*]}" "printf"
    assert_fails grep -q 'readonly' <<<"${body[*]}"
    assert_fails grep -q 'local' <<<"${body[*]}"
    rm -rf "$d"
}

#[test]
it_refuses_an_array_name_that_is_not_one() {
    local d; d="$(_cfc_tmp)"; local f; f="$(_cfc_file "$d")"
    nut_load_file "$f"
    # The name reaches `eval`. Anything but a plain identifier is refused
    # before it gets there.
    local -a body=()
    assert_fails nut_body_of "$f" does_work 'x[$(touch /tmp/nut-should-not-exist)]'
    assert_fails test -e /tmp/nut-should-not-exist
    rm -rf "$d"
}

#[test]
it_reads_a_file_once_however_often_it_is_asked() {
    local d; d="$(_cfc_tmp)"; local f; f="$(_cfc_file "$d")"
    nut_load_file "$f"
    # The file is edited underneath, and the cache is what answers. A loader
    # that re-read on every call would see the new content, which is the shape
    # that was costing thousands of processes.
    printf 'changed() { :; }\n' > "$f"
    nut_load_file "$f"
    assert_ok nut_defined_at "$f" does_work
    assert_fails nut_defined_at "$f" changed
    rm -rf "$d"
}

#[test]
it_says_how_many_lines_a_file_has() {
    local d; d="$(_cfc_tmp)"; local f; f="$(_cfc_file "$d")"
    nut_load_file "$f"
    assert_eq "$(nut_file_lines "$f")" "$(wc -l < "$f" | tr -d ' ')"
    assert_eq "$(nut_file_line "$f" 3)" 'thin() { other "$1"; }'
    rm -rf "$d"
}

#[test]
it_refuses_a_file_that_is_not_there() {
    assert_fails nut_load_file "/no/such/file/at/all.sh"
    assert_fails nut_load_file ""
}

# --- the answers have to be the ones the pipelines gave ------------------------

#[test]
it_counts_the_same_variables_the_five_stage_pipeline_did() {
    local d; d="$(_cfc_tmp)"; local f; f="$(_cfc_file "$d")"
    nut_load_file "$f"
    local -a body=()
    nut_body_of "$f" does_work body

    # The old shape, kept here as the oracle rather than as the implementation:
    # grep the names out, drop the punctuation, unique them, count. Five
    # processes, and the only reason it is acceptable in a test is that a test
    # runs once and a checker runs per function.
    local want
    want="$(printf '%s\n' "${body[@]}" \
        | grep -oE '\$\{?[a-zA-Z_][a-zA-Z0-9_]*' | sed 's/[${}]//g' \
        | sort -u | wc -l | tr -d ' ')"

    local -A seen=(); local line rest name
    for line in "${body[@]}"; do
        rest="$line"
        while [[ "$rest" =~ \$\{?([a-zA-Z_][a-zA-Z0-9_]*) ]]; do
            name="${BASH_REMATCH[1]}"; seen["$name"]=1
            rest="${rest#*"${BASH_REMATCH[0]}"}"
        done
    done
    assert_eq "${#seen[@]}" "$want"
    # And not vacuously zero, which is what a broken reader would give.
    assert_ne "${#seen[@]}" "0"
    rm -rf "$d"
}

#[test]
it_counts_the_same_tokens_the_pipeline_did() {
    local d; d="$(_cfc_tmp)"; local f; f="$(_cfc_file "$d")"
    nut_load_file "$f"
    local -a body=()
    nut_body_of "$f" does_work body

    local want
    want="$(printf '%s\n' "${body[@]}" | tr -s '[:space:]' '\n' | grep -v '^$' \
        | wc -l | tr -d ' ')"

    local line n=0; local -a words=()
    for line in "${body[@]}"; do
        # shellcheck disable=SC2206
        words=($line); n=$(( n + ${#words[@]} ))
    done
    assert_eq "$n" "$want"
    assert_ne "$n" "0"
    rm -rf "$d"
}

#[test]
# The out-name form, which exists so a caller can have the answer without a
# fork around it. Same answers as printing, and it has to stay that way: the
# printing form is what the tests above pin and what every existing caller
# uses.
it_answers_into_a_named_variable() {
    local d; d="$(_cfc_tmp)"; local f; f="$(_cfc_file "$d")"
    assert_ok nut_load_file "$f"

    local where=0 stops=0
    assert_ok nut_defined_at "$f" documented where
    assert_eq "$where" "6"
    assert_ok nut_ends_at "$f" documented stops
    assert_eq "$stops" "9"

    # Nothing is printed when a name was given, so a caller cannot get the
    # answer twice and a caller that forgot the name gets no silent empty.
    assert_eq "$(nut_defined_at "$f" documented where)" ""

    # A name that is not one is refused rather than eval'd.
    assert_fails nut_defined_at "$f" documented '1bad'
    assert_fails nut_ends_at "$f" documented 'no; rm -rf /'

    # A function that is not there still fails, and does not write.
    local untouched=nope
    assert_fails nut_defined_at "$f" no_such_function untouched
    assert_eq "$untouched" "nope"
    rm -rf "$d"
}

#[test]
# The trap that `printf -v` sets for anyone writing one of these.
#
# bash scopes dynamically, so a local in the callee with the same name as the
# out-variable shadows the caller's. The write lands in the callee's frame and
# dies there, the caller reads its own untouched variable, and nothing reports
# it. `nut_ends_at` had exactly this: it used `end` internally and `nut_body_of`
# asks for `end`.
#
# So the names a caller is most likely to pick are the ones worth asserting.
it_writes_through_names_the_callee_might_use_itself() {
    local d; d="$(_cfc_tmp)"; local f; f="$(_cfc_file "$d")"
    assert_ok nut_load_file "$f"

    local name
    for name in at start end n line file out fn i; do
        local -n _probe="$name" 2>/dev/null || true
        unset "$name"
        eval "local ${name}=unset"
        assert_ok nut_defined_at "$f" documented "$name"
        assert_eq "$(eval "printf '%s' \"\$${name}\"")" "6" \
            "nut_defined_at lost the answer into its own '${name}'"
        eval "local ${name}=unset"
        assert_ok nut_ends_at "$f" documented "$name"
        assert_eq "$(eval "printf '%s' \"\$${name}\"")" "9" \
            "nut_ends_at lost the answer into its own '${name}'"
    done
    rm -rf "$d"
}
