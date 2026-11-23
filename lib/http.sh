#!/usr/bin/env bash
# =============================================================================
# nutshell/core/http.sh - HTTP request handling
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): Depends on deps.sh for tool detection
#
# Provides HTTP request functions through curl, or wget where curl is absent.
# There is no third rung: HTTPS from perl needs modules no base image carries,
# so a machine with neither refuses, and `http_ready` says which two it wanted.
#
# Features:
#   - GET, POST, PUT, DELETE, PATCH requests
#   - Headers management
#   - JSON request/response helpers
#   - File download/upload
#   - Response handling (status code, headers, body)
#   - Options the module writes per tool: --header, --headers-from (a secret,
#     kept off the command line), --body-file with --content-type, --insecure
#   - Retries of a transient failure, NUT_HTTP_RETRIES and NUT_HTTP_RETRY_DELAY
# =============================================================================

# Prevent multiple inclusion
# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE`
# and so needs bash. Under a POSIX shell it is not found, the
# `|| return 0` beside it fires on every load, and the module reports
# success having defined nothing.
[ -n "${_NUTSHELL_HTTP_SH:-}" ] && return 0
_NUTSHELL_HTTP_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

# Declared, not sourced by path. A hand-rolled `source` loads the module and
# hides it from the module-contract check, which reads `use` lines, so the
# dependency was real and unrecorded at once.
use deps
use super::http::opts
use super::http::retry
use super::http::wget

# -----------------------------------------------------------------------------
# Module Status
# -----------------------------------------------------------------------------

_HTTP_READY=0
_HTTP_ERROR=""
_HTTP_IMPL=""

#[pub]
# Pick the tool again, from what `deps` knows now. Run at load, and after
# `deps_forget` when a tool has come or gone.
# Usage: http_detect
http_detect() {
    _deps_on_reset http_detect
    _HTTP_READY=0
    _HTTP_IMPL=""
    _HTTP_ERROR=""
    if deps_has "curl"; then
        _HTTP_READY=1
        _HTTP_IMPL="curl"
    elif deps_has "wget"; then
        _HTTP_READY=1
        _HTTP_IMPL="wget"
    else
        _HTTP_ERROR="http: needs curl or wget, and this machine has neither"
    fi
}
http_detect

# -----------------------------------------------------------------------------
# Response Storage
# -----------------------------------------------------------------------------

# Last response data (populated by http_* functions)
_HTTP_LAST_STATUS=""
_HTTP_LAST_HEADERS=""
_HTTP_LAST_BODY=""

# Default timeout (seconds)
HTTP_TIMEOUT=30

# Default user agent
HTTP_USER_AGENT="nutshell-http/1.0"

# Follow redirects by default
HTTP_FOLLOW_REDIRECTS=1

# Maximum redirects to follow
HTTP_MAX_REDIRECTS=10

# -----------------------------------------------------------------------------
# Internal Implementation - curl
# -----------------------------------------------------------------------------

# One attempt. The options are in _HTTP_O_REST and _HTTP_X_ARGS, taken by
# `_http_prepare`, and the tool is _HTTP_CALL_BIN.
_http_request_curl() {
    local method="${1:-GET}"
    local url="${2:-}"
    local data="${3:-}"

    local -a curl_args=(
        -s                              # Silent
        -S                              # Show errors
        -w '\n%{http_code}'             # Append status code
        -D -                            # Dump headers to stdout
        -X "$method"                    # HTTP method
        --max-time "$HTTP_TIMEOUT"      # Timeout
        -A "$HTTP_USER_AGENT"           # User agent
    )

    # Follow redirects
    if [[ "$HTTP_FOLLOW_REDIRECTS" == "1" ]]; then
        curl_args+=(-L --max-redirs "$HTTP_MAX_REDIRECTS")
    fi

    # Add data if provided
    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    # The options, then what the caller handed on, then the URL
    curl_args+=("${_HTTP_X_ARGS[@]}" "${_HTTP_O_REST[@]}" "$url")

    # Execute and capture output
    local output
    output=$(_http_curl_run "${curl_args[@]}" 2>&1)
    local exit_code=$?
    _HTTP_TRY_RC=$exit_code
    _HTTP_LAST_STATUS=""

    if [[ $exit_code -ne 0 ]]; then
        _HTTP_LAST_HEADERS=""
        _HTTP_LAST_BODY="curl error: $output"
        return 1
    fi

    # Parse output: headers, body, status code
    # Format: headers\r\n\r\nbody\nstatus_code

    # Extract status code (last line)
    _HTTP_LAST_STATUS="${output##*$'\n'}"
    output="${output%$'\n'*}"

    # Split headers and body (separated by blank line)
    if [[ "$output" == *$'\r\n\r\n'* ]]; then
        _HTTP_LAST_HEADERS="${output%%$'\r\n\r\n'*}"
        _HTTP_LAST_BODY="${output#*$'\r\n\r\n'}"
    elif [[ "$output" == *$'\n\n'* ]]; then
        _HTTP_LAST_HEADERS="${output%%$'\n\n'*}"
        _HTTP_LAST_BODY="${output#*$'\n\n'}"
    else
        _HTTP_LAST_HEADERS=""
        _HTTP_LAST_BODY="$output"
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Internal Implementation - wget
# -----------------------------------------------------------------------------

_http_request_wget() {
    local method="${1:-GET}"
    local url="${2:-}"
    local data="${3:-}"

    # One try: the retries are the module's, so the count means the same on
    # curl, which has none of its own, and wget, which has twenty.
    local -a wget_args=(
        -nv                             # Messages on one line each, for the retry test
        -O -                            # Output to stdout
        -S                              # Print headers
        --tries=1                       # Retrying is `_http_retrying`'s
        --method="$method"              # HTTP method
        --timeout="$HTTP_TIMEOUT"       # Timeout
        --user-agent="$HTTP_USER_AGENT" # User agent
    )

    # Follow redirects (wget follows by default, limit with max-redirect)
    if [[ "$HTTP_FOLLOW_REDIRECTS" != "1" ]]; then
        wget_args+=(--max-redirect=0)
    else
        wget_args+=(--max-redirect="$HTTP_MAX_REDIRECTS")
    fi

    # Add data if provided
    if [[ -n "$data" ]]; then
        wget_args+=(--body-data="$data")
    fi

    # The options, then what the caller handed on, then the URL
    wget_args+=("${_HTTP_X_ARGS[@]}" "${_HTTP_O_REST[@]}" "$url")

    # Execute and capture output: stdout is the body, stderr the headers and
    # wget's own messages, kept apart so a body is never read as either.
    local body errf errtxt
    errf="$(mktemp "${TMPDIR:-/tmp}/nut-http.XXXXXX")" || {
        _HTTP_LAST_STATUS=""; _HTTP_LAST_HEADERS=""
        _HTTP_LAST_BODY="wget error: no temporary file"
        return 1
    }
    body=$("$_HTTP_CALL_BIN" "${wget_args[@]}" 2>"$errf")
    local exit_code=$?
    _HTTP_TRY_RC=$exit_code
    errtxt="$(cat "$errf")"
    rm -f "$errf"

    _http_wget_parse_err "$errtxt"
    _HTTP_LAST_BODY="$body"

    if [[ $exit_code -ne 0 && -z "$_HTTP_LAST_STATUS" ]]; then
        _HTTP_LAST_BODY="wget error: $errtxt"
        return 1
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Internal Request Dispatcher
# -----------------------------------------------------------------------------

# One attempt, on the tool `_http_prepare` picked for this call.
_http_request() {
    case "$_HTTP_CALL_IMPL" in
        curl) _http_request_curl "$@" ;;
        wget) _http_request_wget "$@" ;;
        *)
            _HTTP_LAST_STATUS=""
            _HTTP_LAST_HEADERS=""
            _HTTP_LAST_BODY="$_HTTP_ERROR"
            return 1
            ;;
    esac
}

# _http_call <method> <url> <data> <args...> -> options taken, the request made, retried
_http_call() {
    local method="$1" url="$2" data="$3"; shift 3
    _http_prepare "$data" "$@" || return $?
    _HTTP_TRY_METHOD="$method"
    if [[ "$method" == "HEAD" && "$_HTTP_CALL_IMPL" == "curl" ]]; then
        _HTTP_O_REST=(-I "${_HTTP_O_REST[@]}")
    fi
    _http_retrying _http_request "$method" "$url" "$data"
}

# _http_with_body <method> <url> [data] <args...> -> a request that carries a body
# The data is the argument after the url unless that is one of the module's
# options, so a body from a file is `http_post "$url" --body-file "$f"` as well
# as with an empty data argument.
_http_with_body() {
    local method="$1" url="${2:-}" data=""
    shift 2 2>/dev/null || shift $#

    if [[ $# -gt 0 ]] && ! _http_is_option "$1"; then
        data="$1"
        shift
    fi

    [[ -z "$url" ]] && { _HTTP_LAST_BODY="URL required"; return 1; }
    [[ "$_HTTP_READY" != "1" ]] && { _HTTP_LAST_BODY="$_HTTP_ERROR"; return 1; }

    _http_call "$method" "$url" "$data" "$@"
}

# -----------------------------------------------------------------------------
# Public API - Core Request Functions
# -----------------------------------------------------------------------------
#
# After the url, and after the data where there is one, come the options in
# `http/opts.sh`: `--header`, `--headers-from`, `--body-file`, `--content-type`
# and `--insecure`. Anything else is handed to the tool. A call that fails is
# tried again where the failure may pass, as `http/retry.sh` says.

#[pub]
# Perform HTTP GET request
# Usage: http_get "https://example.com/api" -> stores response in _HTTP_LAST_*
# Usage: http_get "https://example.com/api" --header "Authorization: Bearer token"
# Usage: http_get "https://example.com/api" --headers-from - <<< "Authorization: Bearer $token"
# Usage: http_get "https://localhost:8443/" --insecure -> test-only, TLS is not verified
# Returns: 0 on success, 1 on failure, 2 for an option refused. Response in http_body, http_status, http_headers
http_get() {
    local url="${1:-}"
    shift

    [[ -z "$url" ]] && { _HTTP_LAST_BODY="URL required"; return 1; }
    [[ "$_HTTP_READY" != "1" ]] && { _HTTP_LAST_BODY="$_HTTP_ERROR"; return 1; }

    _http_call "GET" "$url" "" "$@"
}

#[pub]
# Perform HTTP POST request
# Usage: http_post "https://example.com/api" "data=value" -> stores response
# Usage: http_post "https://example.com/api" '{"key":"value"}' --header "Content-Type: application/json"
# Usage: http_post "https://example.com/api" --body-file body.json --content-type application/json
# Returns: 0 on success, 1 on failure, 2 for an option refused
http_post() {
    _http_with_body "POST" "$@"
}

#[pub]
# Perform HTTP PUT request
# Usage: http_put "https://example.com/api/1" '{"key":"value"}'
# Usage: http_put "https://example.com/api/1" --body-file body.json --content-type application/json
# Returns: 0 on success, 1 on failure, 2 for an option refused
http_put() {
    _http_with_body "PUT" "$@"
}

#[pub]
# Perform HTTP PATCH request
# Usage: http_patch "https://example.com/api/1" '{"key":"value"}'
# Returns: 0 on success, 1 on failure, 2 for an option refused
http_patch() {
    _http_with_body "PATCH" "$@"
}

#[pub]
# Perform HTTP DELETE request
# Usage: http_delete "https://example.com/api/1"
# Returns: 0 on success, 1 on failure, 2 for an option refused
http_delete() {
    local url="${1:-}"
    shift

    [[ -z "$url" ]] && { _HTTP_LAST_BODY="URL required"; return 1; }
    [[ "$_HTTP_READY" != "1" ]] && { _HTTP_LAST_BODY="$_HTTP_ERROR"; return 1; }

    _http_call "DELETE" "$url" "" "$@"
}

#[pub]
# Perform HTTP HEAD request (headers only)
# Usage: http_head "https://example.com" -> stores headers in _HTTP_LAST_HEADERS
# Returns: 0 on success, 1 on failure, 2 for an option refused
http_head() {
    local url="${1:-}"
    shift

    [[ -z "$url" ]] && { _HTTP_LAST_BODY="URL required"; return 1; }
    [[ "$_HTTP_READY" != "1" ]] && { _HTTP_LAST_BODY="$_HTTP_ERROR"; return 1; }

    _http_call "HEAD" "$url" "" "$@"
}

# -----------------------------------------------------------------------------
# Public API - Response Access
# -----------------------------------------------------------------------------

#[pub]
# Get the response body from the last request
# Usage: http_body -> prints response body
http_body() {
    echo "$_HTTP_LAST_BODY"
}

#[pub]
# Get the HTTP status code from the last request
# Usage: http_status -> prints status code (e.g., "200")
http_status() {
    echo "$_HTTP_LAST_STATUS"
}

#[pub]
# Get the response headers from the last request
# Usage: http_headers -> prints all headers
http_headers() {
    echo "$_HTTP_LAST_HEADERS"
}

#[pub]
# Get a specific header value from the last request
# Usage: http_header "Content-Type" -> prints header value
http_header() {
    local name="${1:-}"
    [[ -z "$name" ]] && return 1
    
    # Case-insensitive search
    echo "$_HTTP_LAST_HEADERS" | grep -i "^${name}:" | head -1 | sed 's/^[^:]*:[[:space:]]*//'
}

#[pub]
# Check if the last request was successful (2xx status)
# Usage: http_ok -> returns 0 if success, 1 otherwise
http_ok() {
    [[ "$_HTTP_LAST_STATUS" =~ ^2[0-9][0-9]$ ]]
}

#[pub]
# Check if the last request resulted in a redirect (3xx status)
# Usage: http_redirect -> returns 0 if redirect, 1 otherwise
http_redirect() {
    [[ "$_HTTP_LAST_STATUS" =~ ^3[0-9][0-9]$ ]]
}

#[pub]
# Check if the last request resulted in client error (4xx status)
# Usage: http_client_error -> returns 0 if client error, 1 otherwise
http_client_error() {
    [[ "$_HTTP_LAST_STATUS" =~ ^4[0-9][0-9]$ ]]
}

#[pub]
# Check if the last request resulted in server error (5xx status)
# Usage: http_server_error -> returns 0 if server error, 1 otherwise
http_server_error() {
    [[ "$_HTTP_LAST_STATUS" =~ ^5[0-9][0-9]$ ]]
}

# -----------------------------------------------------------------------------
# Public API - JSON Helpers
# -----------------------------------------------------------------------------

#[pub]
# POST JSON data with correct content type
# Usage: http_post_json "https://api.example.com" '{"key":"value"}'
# Returns: 0 on success, 1 on failure
http_post_json() {
    local url="${1:-}"
    local json="${2:-}"
    shift 2 2>/dev/null || shift $#
    
    http_post "$url" "$json" --header "Content-Type: application/json" --header "Accept: application/json" "$@"
}

#[pub]
# PUT JSON data with correct content type
# Usage: http_put_json "https://api.example.com/1" '{"key":"value"}'
# Returns: 0 on success, 1 on failure
http_put_json() {
    local url="${1:-}"
    local json="${2:-}"
    shift 2 2>/dev/null || shift $#
    
    http_put "$url" "$json" --header "Content-Type: application/json" --header "Accept: application/json" "$@"
}

#[pub]
# PATCH JSON data with correct content type
# Usage: http_patch_json "https://api.example.com/1" '{"key":"value"}'
# Returns: 0 on success, 1 on failure
http_patch_json() {
    local url="${1:-}"
    local json="${2:-}"
    shift 2 2>/dev/null || shift $#
    
    http_patch "$url" "$json" --header "Content-Type: application/json" --header "Accept: application/json" "$@"
}

#[pub]
# GET with JSON accept header
# Usage: http_get_json "https://api.example.com"
# Returns: 0 on success, 1 on failure
http_get_json() {
    local url="${1:-}"
    shift
    
    http_get "$url" --header "Accept: application/json" "$@"
}

# -----------------------------------------------------------------------------
# Public API - File Operations
# -----------------------------------------------------------------------------

# One attempt at a download. Leaves the answer's status and headers where there
# were any, so an error page is told from a network failure and a Retry-After
# is read. The module's options only: `http_download` refuses the rest.
_http_download_once() {
    local url="$1" output="$2" rc raw
    _HTTP_LAST_STATUS=""
    _HTTP_LAST_HEADERS=""
    if [[ "$_HTTP_CALL_IMPL" == "curl" ]]; then
        raw="$(_http_curl_run -fsS -L -D - -o "$output" -w '%{http_code}' \
            --max-time "$HTTP_TIMEOUT" \
            -A "$HTTP_USER_AGENT" \
            "${_HTTP_X_ARGS[@]}" \
            "$url")"
        rc=$?
        _HTTP_LAST_HEADERS="${raw%???}"
        raw="${raw: -3}"
        [[ "$raw" =~ ^[1-5][0-9][0-9]$ ]] && _HTTP_LAST_STATUS="$raw"
    else
        raw="$("$_HTTP_CALL_BIN" -nv -S -O "$output" --tries=1 \
            --timeout="$HTTP_TIMEOUT" \
            --user-agent="$HTTP_USER_AGENT" \
            "${_HTTP_X_ARGS[@]}" \
            "$url" 2>&1 >/dev/null)"
        rc=$?
        _http_wget_parse_err "$raw"
    fi
    _HTTP_TRY_RC=$rc
    return $rc
}

#[pub]
# Download a file to a local path
# Usage: http_download "https://example.com/file.zip" "/tmp/file.zip"
# Usage: http_download "https://example.com/file.zip" "/tmp/file.zip" --header "Accept: application/zip"
# Returns: 0 on success, non-zero on failure, an error status included, so a
# 404 page is never saved as though it were the file. 2 for an option refused.
# A 429, 502, 503 or 504 and a connection that failed are tried again.
# Only the module's own options are taken after the output path: anything else
# is refused with status 2 naming it, since a curl flag means something else to wget.
http_download() {
    local url="${1:-}"
    local output="${2:-}"

    [[ -z "$url" ]] && return 1
    [[ -z "$output" ]] && return 1
    [[ "$_HTTP_READY" != "1" ]] && return 1
    shift 2

    _http_prepare "" "$@" || return $?
    _http_no_rest http_download || return 2
    if [[ -n "$_HTTP_O_BODY_FILE" ]]; then
        _http_opts_fail "--body-file is for a request that sends a body, and a download does not"
        return 2
    fi
    _HTTP_TRY_METHOD="GET"
    _http_retrying _http_download_once "$url" "$output"
}

#[pub]
# Upload a file via POST (multipart form data)
# Usage: http_upload "https://example.com/upload" "/path/to/file" "file"
# Takes the module's own options after the field, and refuses anything else.
# Returns: 0 on success, 1 on failure, 2 for an option or argument refused
http_upload() {
    local url="${1:-}"
    local file="${2:-}"
    local field="${3:-file}"
    shift 3 2>/dev/null || shift $#

    [[ -z "$url" ]] && { _HTTP_LAST_BODY="URL required"; return 1; }
    [[ ! -f "$file" ]] && { _HTTP_LAST_BODY="File not found: $file"; return 1; }
    [[ "$_HTTP_READY" != "1" ]] && { _HTTP_LAST_BODY="$_HTTP_ERROR"; return 1; }

    _http_prepare "" "$@" || return $?
    _http_no_rest http_upload || return 2
    if [[ "$_HTTP_CALL_IMPL" == "curl" ]]; then
        local output
        output=$(_http_curl_run -sS -w '\n%{http_code}' \
            -X POST \
            -F "${field}=@${file}" \
            --max-time "$HTTP_TIMEOUT" \
            -A "$HTTP_USER_AGENT" \
            "${_HTTP_X_ARGS[@]}" \
            "$url" 2>&1)

        _HTTP_LAST_STATUS="${output##*$'\n'}"
        _HTTP_LAST_BODY="${output%$'\n'*}"
        _HTTP_LAST_HEADERS=""
    else
        # wget doesn't support multipart form easily
        _HTTP_LAST_BODY="File upload not supported with wget"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Public API - Configuration
# -----------------------------------------------------------------------------
#
# Configuration is the variables, listed in this module's header. The setters
# that stood here, `http_set_timeout` and friends, assigned one of them with a
# default and did nothing else, so the module offered two ways to say one thing
# and the reader had to learn both to be sure they agreed.
#
#     HTTP_TIMEOUT=60
#     HTTP_USER_AGENT="MyApp/1.0"
#     HTTP_MAX_REDIRECTS=5
#
# `http_follow_redirects` stays, because it does something an assignment does
# not: it takes true and false and 1 and 0, and the variable holds only 1 or 0.

#[pub]
# Enable or disable following redirects
# Usage: http_follow_redirects true
# Usage: http_follow_redirects false
http_follow_redirects() {
    if [[ "${1:-true}" == "true" || "${1:-}" == "1" ]]; then
        HTTP_FOLLOW_REDIRECTS=1
    else
        HTTP_FOLLOW_REDIRECTS=0
    fi
}

# -----------------------------------------------------------------------------
# Public API - Utility Functions
# -----------------------------------------------------------------------------

#[pub]
# URL encode a string
# Usage: http_urlencode "hello world" -> "hello%20world"
http_urlencode() {
    local string="${1:-}"
    local encoded=""
    local i char
    
    for ((i = 0; i < ${#string}; i++)); do
        char="${string:$i:1}"
        case "$char" in
            [a-zA-Z0-9.~_-])
                encoded+="$char"
                ;;
            ' ')
                encoded+='%20'
                ;;
            *)
                encoded+=$(printf '%%%02X' "'$char")
                ;;
        esac
    done
    
    echo "$encoded"
}

#[pub]
# URL decode a string
# Usage: http_urldecode "hello%20world" -> "hello world"
http_urldecode() {
    local string="${1:-}"
    # Replace + with space, then decode %XX
    string="${string//+/ }"
    printf '%b' "${string//%/\\x}"
}

#[pub]
# Build query string from key-value pairs
# Usage: http_query "key1" "value1" "key2" "value2" -> "key1=value1&key2=value2"
http_query() {
    local query=""
    local first=1
    
    while [[ $# -ge 2 ]]; do
        local key="$1"
        local value="$2"
        shift 2
        
        [[ $first -eq 0 ]] && query+="&"
        first=0
        
        query+="$(http_urlencode "$key")=$(http_urlencode "$value")"
    done
    
    echo "$query"
}

#[pub]
# Build full URL with query parameters
# Usage: http_url "https://example.com/api" "key1" "value1" "key2" "value2"
# Returns: "https://example.com/api?key1=value1&key2=value2"
http_url() {
    local base="${1:-}"
    shift
    
    if [[ $# -eq 0 ]]; then
        echo "$base"
        return
    fi
    
    local query
    query=$(http_query "$@")
    
    if [[ "$base" == *"?"* ]]; then
        echo "${base}&${query}"
    else
        echo "${base}?${query}"
    fi
}

# -----------------------------------------------------------------------------
# Module Status Functions
# -----------------------------------------------------------------------------

#[pub]
# Check if HTTP module is ready. Where it is not, the tools it wanted are named
# on stderr.
# Usage: http_ready -> returns 0 if ready, 1 if not
http_ready() {
    [[ "$_HTTP_READY" == "1" ]] && return 0
    echo "$_HTTP_ERROR" >&2
    return 1
}

#[pub]
# Get HTTP module error (if not ready)
# Usage: http_error -> prints error message
http_error() {
    echo "$_HTTP_ERROR"
}

#[pub]
# Get which HTTP implementation is being used
# Usage: http_impl -> "curl" | "wget" | ""
http_impl() {
    echo "$_HTTP_IMPL"
}
