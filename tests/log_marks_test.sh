#!/usr/bin/env bash
# Tests for marked, nested log output.
#
# Two properties. A run where one line went wrong has to be skimmable, so the
# mark's column and the depth are the contract rather than decoration. And
# log_run has to return what the command returned: a runner that reports
# success on a failed command is worse than no runner.

use log test

setup() { log_reset; LOG_COLOR=never; LOG_LEVEL=info; log_marks text; }

_strip() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

# --- marks -------------------------------------------------------------------

#[test]
it_marks_each_kind_of_line_differently() {
    local out
    out="$( { log_ok a; log_warned b; log_failed c; log_flat d; } 2>&1 | _strip)"
    assert_eq "$(grep -c . <<<"$out")" "4"
    # Four kinds, four marks in column one.
    assert_eq "$(cut -c1 <<<"$out" | sort -u | grep -c .)" "4"
}

#[test]
it_leaves_a_flat_line_unmarked() {
    local out; out="$(log_flat "just a fact" 2>&1 | _strip)"
    assert_eq "${out:0:1}" " "
}

#[test]
it_keeps_every_mark_to_one_column() {
    local out
    out="$( { log_ok top
              log_open deeper
              log_ok inside
              log_open "deeper still"
              log_failed "further in"; } 2>&1 | _strip)"
    # The mark sits outside the indent, so scanning column one finds every
    # result whatever depth produced it.
    local second; second="$(cut -c2 <<<"$out" | sort -u)"
    assert_eq "$(grep -c . <<<"$second")" "1"
    assert_eq "$second" " "
}

#[test]
it_uses_words_when_told_to() {
    log_marks text
    local out; out="$( { log_ok a; log_failed b; } 2>&1 | _strip)"
    assert_ok python3 -c 'import sys; sys.stdin.buffer.read().decode("ascii")' <<<"$out"
}

#[test]
it_uses_icons_when_told_to() {
    log_marks icon
    local out; out="$(log_ok a 2>&1 | _strip)"
    assert_fails python3 -c 'import sys; sys.stdin.buffer.read().decode("ascii")' <<<"$out"
    log_marks text
}

#[test]
it_draws_no_marks_when_told_to() {
    log_marks none
    local out; out="$( { log_ok a; log_failed b; } 2>&1 | _strip)"
    # A blank column rather than no column: the text still lines up with a run
    # that does have marks, which is the point of turning them off rather than
    # of not having them.
    assert_eq "$(cut -c1 <<<"$out" | sort -u | tr -d '\n')" " "
    assert_ok grep -q '^  a$' <<<"$out"
    log_marks text
}

#[test]
it_picks_words_in_a_locale_that_cannot_draw_icons() {
    local out
    out="$(LC_ALL=C LANG=C bash -c '
        cd '"$PWD"'; . ./init; use log
        LOG_COLOR=never; log_ok a; log_failed b' 2>&1 | _strip)"
    # An icon that renders as three bytes of noise is worse than a plus.
    assert_ok python3 -c 'import sys; sys.stdin.buffer.read().decode("ascii")' <<<"$out"
}

# --- depth --------------------------------------------------------------------

#[test]
it_indents_what_belongs_to_a_step() {
    local out; out="$( { log_open outer; log_ok inner; } 2>&1 | _strip)"
    assert_ok grep -q '^.   inner' <<<"$(sed -n 2p <<<"$out")"
}

#[test]
it_nests_further_than_one_level() {
    local out
    out="$( { log_open a; log_open b; log_ok c; } 2>&1 | _strip)"
    # log_substep was fixed at one level. This is the gap that wanted filling.
    assert_ok grep -q '^.     c' <<<"$(sed -n 3p <<<"$out")"
}

#[test]
it_returns_to_the_previous_depth() {
    log_open one >/dev/null 2>&1; assert_eq "$LOG_DEPTH" "1"
    log_open two >/dev/null 2>&1; assert_eq "$LOG_DEPTH" "2"
    log_close ok x >/dev/null 2>&1; assert_eq "$LOG_DEPTH" "1"
    log_close ok y >/dev/null 2>&1; assert_eq "$LOG_DEPTH" "0"
}

#[test]
it_does_not_go_below_the_top() {
    log_close ok "nothing was open" >/dev/null 2>&1
    log_close ok "still nothing"    >/dev/null 2>&1
    # A negative depth is a negative printf width, which is an error and not
    # an indent.
    assert_eq "$LOG_DEPTH" "0"
    assert_ok log_ok after >/dev/null 2>&1
}

#[test]
it_closes_a_step_silently_when_told_nothing() {
    log_open one >/dev/null 2>&1
    # Two calls, deliberately. Capturing the output puts log_close in a
    # subshell, where the depth it changes is discarded, so a single call
    # cannot check both things at once.
    local out; out="$(log_open two >/dev/null 2>&1; log_close 2>&1)"
    assert_eq "$out" ""
    log_close 2>/dev/null
    assert_eq "$LOG_DEPTH" "0"
}

#[test]
it_keeps_the_depth_right_even_when_the_level_hides_the_line() {
    LOG_LEVEL=error
    log_open quiet >/dev/null 2>&1
    # The heading is suppressed. The depth still has to move, or every line
    # after it is indented wrongly for the rest of the run.
    assert_eq "$LOG_DEPTH" "1"
    log_close >/dev/null 2>&1
    LOG_LEVEL=info
}

# --- running a command -----------------------------------------------------------

#[test]
it_returns_what_the_command_returned() {
    log_run "fine" true >/dev/null 2>&1;   assert_eq "$?" "0"
    log_run "not fine" false >/dev/null 2>&1; assert_eq "$?" "1"
    log_run "particular" bash -c 'exit 42' >/dev/null 2>&1; assert_eq "$?" "42"
}

#[test]
it_marks_a_failed_command_as_failed() {
    local out; out="$(log_run "a thing" bash -c 'exit 3' 2>&1 | _strip)"
    assert_ok grep -q 'exit 3' <<<"$out"
}

#[test]
it_counts_a_failed_command() {
    # Not captured, because a capture is a subshell and the count made in one
    # does not come back. That is a real property of the counters and callers
    # need to know it; the doc comment on log_worst says so.
    log_reset
    log_run "a thing" bash -c 'exit 3' >/dev/null 2>&1
    assert_eq "$LOG_FAILURES" "1"
    assert_eq "$(log_worst)" "fail"
}

#[test]
it_shows_both_streams_of_what_the_command_printed() {
    local out; out="$(log_run noisy bash -c 'echo out; echo err >&2' 2>&1 | _strip)"
    assert_ok grep -q 'out' <<<"$out"
    assert_ok grep -q 'err' <<<"$out"
}

#[test]
it_keeps_the_status_marker_out_of_the_output() {
    local out; out="$(log_run quiet true 2>&1 | _strip)"
    assert_fails grep -qE '^[^ ]? +[0-9]+$' <<<"$out"
    assert_fails grep -q $'\037' <<<"$out"
}

#[test]
it_indents_a_commands_output_under_its_step() {
    local out; out="$(log_run label bash -c 'echo hello' 2>&1 | _strip)"
    assert_ok grep -q '^.   hello' <<<"$out"
}

#[test]
it_leaves_the_depth_where_it_found_it() {
    log_open outer >/dev/null 2>&1
    log_run inner true >/dev/null 2>&1
    assert_eq "$LOG_DEPTH" "1"
    log_run "inner that failed" false >/dev/null 2>&1
    assert_eq "$LOG_DEPTH" "1"
}

# --- the verdict --------------------------------------------------------------------

#[test]
it_calls_a_clean_run_ok() {
    log_ok a >/dev/null 2>&1; log_flat b >/dev/null 2>&1
    assert_eq "$(log_worst)" "ok"
}

#[test]
it_remembers_a_warning() {
    log_ok a >/dev/null 2>&1; log_warned b >/dev/null 2>&1
    assert_eq "$(log_worst)" "warn"
}

#[test]
it_lets_a_failure_outrank_a_warning() {
    log_warned a >/dev/null 2>&1; log_failed b >/dev/null 2>&1
    assert_eq "$(log_worst)" "fail"
}

#[test]
it_counts_a_problem_even_when_the_level_hides_it() {
    LOG_LEVEL=error
    log_warned "not shown" >/dev/null 2>&1
    # The verdict is about what happened, not about what was displayed. A run
    # quieted with LOG_LEVEL must not come out looking clean.
    assert_eq "$(log_worst)" "warn"
    LOG_LEVEL=info
}

#[test]
it_forgets_the_previous_run_on_reset() {
    log_failed a >/dev/null 2>&1
    assert_eq "$(log_worst)" "fail"
    log_reset
    assert_eq "$(log_worst)" "ok"
    assert_eq "$LOG_FAILURES" "0"
}

# --- what was already here ------------------------------------------------------------

#[test]
it_leaves_the_existing_levels_alone() {
    LOG_COLOR=never
    local out
    out="$(log_warn "old shape" 2>&1)"
    # The tagged format is what every caller already prints. Adding marks must
    # not have changed it.
    assert_ok grep -q '^\[WARN\] old shape' <<<"$out"
    out="$(log_step "a heading" 2>&1)"
    assert_ok grep -q '==>' <<<"$out"
}
