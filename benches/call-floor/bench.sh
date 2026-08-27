#!/usr/bin/env bash
# =============================================================================
# nutshell/benches/call-floor - What it costs to reach code that is not here
# =============================================================================
#
# The question is whether a compiled helper is worth writing. Not whether C is
# faster than shell at arithmetic, which is not in doubt, but whether the
# saving survives the price of reaching it.
#
# So this measures the price of reaching, and it is a floor: no helper of any
# kind, in any language, can cost less than getting to it. Everything a helper
# might do is on top.
#
# Three routes and one workload. The workload is the sum of one to N, chosen
# because it is the same arithmetic in both languages and because N is the
# knob: somewhere on that sweep the shell's per-operation cost overtakes the
# fork, and where that crossover sits is the whole answer.
#
#   in-shell       a bash arithmetic loop, no process anywhere
#   forked helper  a compiled binary, one fork and one exec per call
#   resident       the same binary started once, spoken to down a pipe
#
# The compile happens before anything is timed, which is the shape the idea
# actually proposes: build once when the library is installed or updated, from
# source, on the machine that will run it. That also settles the portability
# question by construction, since a binary compiled here inherits whatever
# libc is here and there is no ABI to get wrong.
#
# The C arms are skipped where there is no compiler, and the table says so
# rather than leaving a gap. A machine without one is not an error, it is the
# floor doing its job.
#
# Usage:
#   ./bench call-floor [iterations]
# =============================================================================

use bench

ITERS="${1:-40}"

# Where the helper is built. Outside every timed region, on purpose.
_TMP="$(mktemp -d "${TMPDIR:-/tmp}/nut-callfloor.XXXXXX")"
trap 'rm -rf "$_TMP"' EXIT

CC=""
for _c in cc gcc clang c99; do
    command -v "$_c" >/dev/null 2>&1 && { CC="$_c"; break; }
done

# The helper. Reads an N per line, prints the sum of one to N, and keeps going
# until the input ends. One binary serves both C arms: forked, it answers once
# and exits; resident, it answers for as long as it is fed.
if [ -n "$CC" ]; then
    cat > "${_TMP}/helper.c" <<'C'
#include <stdio.h>
int main(void) {
    long n;
    while (scanf("%ld", &n) == 1) {
        long i, s = 0;
        for (i = 1; i <= n; i++) s += i;
        printf("%ld\n", s);
        fflush(stdout);
    }
    return 0;
}
C
    "$CC" -O2 -o "${_TMP}/helper" "${_TMP}/helper.c" 2>/dev/null || CC=""
fi

HELPER="${_TMP}/helper"

# -----------------------------------------------------------------------------
# The arms
# -----------------------------------------------------------------------------

# The same sum, in bash, with no process involved at all.
arm_shell() {
    local i j s out=""
    for (( i = 0; i < ITERS; i++ )); do
        s=0
        for (( j = 1; j <= N; j++ )); do s=$(( s + j )); done
        out="$s"
    done
    printf '%s' "$out"
}

# One fork and one exec per call, which is what any helper invoked the ordinary
# way costs before it has done anything.
arm_forked() {
    local i out=""
    for (( i = 0; i < ITERS; i++ )); do out="$(printf '%s\n' "$N" | "$HELPER")"; done
    printf '%s' "$out"
}

# The same binary, started once and spoken to down a pipe. The fork is paid at
# the top and then not again, which is the only shape in which a helper's own
# speed is what decides anything.
arm_resident() {
    local i out=""
    coproc HELP { "$HELPER"; }
    for (( i = 0; i < ITERS; i++ )); do
        printf '%s\n' "$N" >&"${HELP[1]}"
        IFS= read -r out <&"${HELP[0]}"
    done
    exec {HELP[1]}>&-
    wait "$HELP_PID" 2>/dev/null
    printf '%s' "$out"
}

_answer_of() { "$1"; }

# -----------------------------------------------------------------------------
# The sweep
# -----------------------------------------------------------------------------
#
# One case per N. The arms answer the same sum at every N, so an arm that
# drifted would be refused rather than reported as fast.

for N in 10 100 1000 10000; do
    bench_reset
    bench_case "reaching a helper, against doing it here, at N=${N}"
    bench_size "$N"
    bench_verify _answer_of

    bench_arm "in-shell arithmetic" arm_shell
    if [ -n "$CC" ]; then
        bench_arm "forked helper"   arm_forked
        bench_arm "resident helper" arm_resident
    fi
    bench_run || exit 1
    printf '\n'
done

if [ -z "$CC" ]; then
    printf 'No compiler here, so only the in-shell arm ran. That is the floor\n'
    printf 'doing its job rather than a gap in the measurement.\n'
else
    printf 'Compiled with %s, before anything was timed.\n' "$CC"
fi
