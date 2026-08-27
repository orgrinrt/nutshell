#!/usr/bin/env bash
# Tests for `log_run`, which had none.
#
# It is the one function in `log.sh` that is hard to write on the POSIX floor:
# it has to stream a command's output as the command produces it, and it has to
# bring that command's exit status back to the shell that called it. A plain
# pipeline gives up the second, because the loop reading it runs in a subshell
# and what it counted does not return. A temp file gives up the first.
#
# It used bash's `< <(...)`. It uses a named pipe now, which is POSIX, and
# these are the properties that has to keep.

use log test

setup() { log_reset; log_marks text; }

#[test]
it_returns_the_commands_own_status() {
    # The reason to use it rather than printing around a command. A runner that
    # reports success on a failed command is worse than no runner.
    setup
    log_run "zero" sh -c 'exit 0' >/dev/null 2>&1
    assert_eq "$?" "0"
    log_run "seven" sh -c 'exit 7' >/dev/null 2>&1
    assert_eq "$?" "7"
    log_run "one" sh -c 'exit 1' >/dev/null 2>&1
    assert_eq "$?" "1"
    # A status above 127 is where a naive marker parse goes wrong.
    log_run "big" sh -c 'exit 200' >/dev/null 2>&1
    assert_eq "$?" "200"
}

#[test]
it_shows_the_commands_output_and_both_streams() {
    setup
    local out
    out="$(log_run "step" sh -c 'echo to-stdout; echo to-stderr >&2; exit 0' 2>&1)"
    assert_contains "$out" "to-stdout"
    assert_contains "$out" "to-stderr"
    assert_contains "$out" "step"
}

#[test]
it_does_not_print_the_status_marker() {
    # The status travels in the stream as a line beginning with a unit
    # separator. It is read and never printed, and a reader that stopped
    # recognising it would put the raw marker in the output.
    setup
    local out
    out="$(log_run "step" sh -c 'echo body; exit 3' 2>&1)"
    assert_contains "$out" "body"
    assert_not_contains "$out" "$(printf '\037')"
    # And the number does not leak either.
    assert_eq "$(printf '%s\n' "$out" | grep -c '^3$')" "0"
}

#[test]
it_streams_rather_than_buffering_to_the_end() {
    # The property the named pipe exists for, and the one a temp file would
    # lose silently: everything would still be correct, just all at once at the
    # end, which for a long step is the whole value of the function.
    setup
    local started mid tmp
    started="$(date +%s)"
    tmp="$(mktemp "${TMPDIR:-/tmp}/nut-stream.XXXXXX")"
    log_run "slow" sh -c 'echo first; sleep 2; echo second; exit 0' 2>&1 \
        | while IFS= read -r line; do
              case "$line" in
                  *first*) printf '%s\n' "$(( $(date +%s) - started ))" ;;
              esac
          done > "$tmp"
    mid="$(cat "$tmp" 2>/dev/null)"; rm -f "$tmp"
    # `first` must appear well before the command finishes at +2s.
    assert_ne "$mid" ""
    assert_ok test "$mid" -lt 2
}

#[test]
it_counts_a_failed_step_toward_the_verdict() {
    setup
    log_run "fine" sh -c 'exit 0' >/dev/null 2>&1
    assert_eq "$(log_worst)" "ok"
    log_run "broken" sh -c 'exit 4' >/dev/null 2>&1
    assert_eq "$(log_worst)" "fail"
}

#[test]
it_leaves_no_pipe_behind() {
    # The named pipe is made under TMPDIR and removed after. One left per call
    # would fill the directory over a long run, and the name is unpredictable
    # so nothing else would clean it.
    setup
    local before after
    before="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'nut-run.*' 2>/dev/null | wc -l | tr -d ' ')"
    log_run "a" sh -c 'exit 0' >/dev/null 2>&1
    log_run "b" sh -c 'echo x; exit 1' >/dev/null 2>&1
    after="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'nut-run.*' 2>/dev/null | wc -l | tr -d ' ')"
    assert_eq "$after" "$before"
}

#[test]
it_survives_a_command_that_produces_nothing() {
    setup
    local out
    out="$(log_run "quiet" sh -c 'exit 0' 2>&1)"
    assert_contains "$out" "quiet"
    log_run "quiet" sh -c 'exit 0' >/dev/null 2>&1
    assert_eq "$?" "0"
}

#[test]
it_survives_a_command_that_does_not_exist() {
    setup
    log_run "missing" no_such_command_xyzzy >/dev/null 2>&1
    local rc=$?
    assert_ne "$rc" "0"
    assert_eq "$(log_worst)" "fail"
}
