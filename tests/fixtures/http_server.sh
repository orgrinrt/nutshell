#!/usr/bin/env bash
# Sourced by the http tests that need a server answering several requests in a
# row on the loopback. Not a test itself.
#
# `nc` answers one connection and exits, so a sequence is a loop of them in the
# background, one per behaviour. Each request is saved whole to `<dir>/req.<n>`,
# so a test reads what the client really sent rather than what it meant to.
#
#   srv_start <port> <dir> <behaviour...>
#
# A behaviour is one of
#   <status>            answer with that status and the body `ok`
#   <status>:<body>     answer with that status and body
#   slow:<status>:<body> wait a second and a half, then answer
#   reset               read the request, then close without answering
#   hang                read the request and say nothing for three seconds
#   after:<secs>:<status>  answer with that status and `Retry-After: <secs>`
#
# Where `nc` is absent there is nothing to serve from; `srv_available` says so.

[ -n "${_NUTSHELL_FIXTURE_HTTP_SERVER:-}" ] && return 0
_NUTSHELL_FIXTURE_HTTP_SERVER=1

_SRV_PID=""
_SRV_PORT=""

# srv_available -> 0 when there is a server to talk to
srv_available() {
    deps_has nc
}

# srv_port -> a port in the range tests pick from
srv_port() {
    printf '%s' "$(( 20000 + RANDOM % 20000 ))"
}

# _srv_answer <status> <body> -> the response, on stdout
_srv_answer() {
    # an optional third argument is one more header line
    printf 'HTTP/1.1 %s Status\r\nContent-Length: %s\r\nConnection: close\r\n%s\r\n%s' \
        "$1" "${#2}" "${3:+$3$'\r\n'}" "$2"
}

srv_start() {
    local port="$1" dir="$2"; shift 2
    mkdir -p "$dir"
    (
        local i=0 b status body secs
        for b in "$@"; do
            i=$((i + 1))
            case "$b" in
                reset) nc -N -l 127.0.0.1 "$port" </dev/null >"$dir/req.$i" 2>/dev/null ;;
                hang) { sleep 3; } | nc -l 127.0.0.1 "$port" >"$dir/req.$i" 2>/dev/null ;;
                slow:*)
                    status="${b#slow:}"; body="${status#*:}"; status="${status%%:*}"
                    { sleep 1.5; _srv_answer "$status" "$body"; } \
                        | nc -l 127.0.0.1 "$port" >"$dir/req.$i" 2>/dev/null ;;
                after:*)
                    status="${b#after:}"; secs="${status%%:*}"; status="${status#*:}"
                    _srv_answer "$status" "ok" "Retry-After: $secs" \
                        | nc -l 127.0.0.1 "$port" >"$dir/req.$i" 2>/dev/null ;;
                *)
                    status="${b%%:*}"; body="ok"
                    [[ "$b" == *:* ]] && body="${b#*:}"
                    _srv_answer "$status" "$body" \
                        | nc -l 127.0.0.1 "$port" >"$dir/req.$i" 2>/dev/null ;;
            esac
        done
    ) &
    _SRV_PID=$!
    _SRV_PORT="$port"
    srv_wait_listening "$port"
}

# srv_wait_listening <port> -> returns once something listens on the port
#
# A fixed sleep lost the race on a loaded machine: the client connected before
# nc listened, and the server saw no request. Read from the kernel's table, so
# the wait makes no connection of its own; a host without it waits as before.
srv_wait_listening() {
    local hex i
    hex="$(printf '%04X' "$1")"
    [[ -r /proc/net/tcp ]] || { sleep 0.3; return 0; }
    for ((i = 0; i < 100; i++)); do
        grep -q ":${hex} 00000000:0000 0A" /proc/net/tcp && return 0
        sleep 0.05
    done
    return 0
}

# srv_requests <dir> -> how many requests the server was sent
srv_requests() {
    sleep 0.3
    local f n=0
    for f in "$1"/req.*; do
        [[ -s "$f" ]] && n=$((n + 1))
    done
    printf '%s' "$n"
}

# srv_request <dir> <n> -> the n-th request as received
srv_request() {
    sleep 0.3
    cat "$1/req.$2"
}

srv_stop() {
    [[ -n "$_SRV_PID" ]] || return 0
    kill "$_SRV_PID" 2>/dev/null
    pkill -P "$_SRV_PID" 2>/dev/null
    pkill -f "nc .*127.0.0.1 $_SRV_PORT" 2>/dev/null
    wait "$_SRV_PID" 2>/dev/null
    _SRV_PID=""
    return 0
}
