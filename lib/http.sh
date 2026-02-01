#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/http.sh - HTTP request handling
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): Depends on deps.sh for tool detection
#
# Provides HTTP request functions using lazy-init stubs to select the best
# available tool (curl > wget > perl).
#
# Features:
#   - GET, POST, PUT, DELETE, PATCH requests
#   - Headers management
#   - JSON request/response helpers
#   - File download/upload
#   - Response handling (status code, headers, body)
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_HTTP_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_HTTP_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

_NUTSHELL_HTTP_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_NUTSHELL_HTTP_DIR" == "${BASH_SOURCE[0]}" ]] && _NUTSHELL_HTTP_DIR="."
source "${_NUTSHELL_HTTP_DIR}/deps.sh"

# -----------------------------------------------------------------------------
# Module Status
# -----------------------------------------------------------------------------

_HTTP_READY=0
_HTTP_ERROR=""
_HTTP_IMPL=""

# Check for available HTTP tools
if deps_has "curl"; then
    _HTTP_READY=1
    _HTTP_IMPL="curl"
elif deps_has "wget"; then
    _HTTP_READY=1
    _HTTP_IMPL="wget"
else
    _HTTP_ERROR="No HTTP tool available (need curl or wget)"
fi

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

_http_request_curl() {
    local method="${1:-GET}"
    local url="${2:-}"
    local data="${3:-}"
    shift 3
    local -a extra_args=("$@")
    
    local curl_cmd="${_TOOL_PATH[curl]}"
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
    
    # Add extra arguments (headers, etc.)
    curl_args+=("${extra_args[@]}")
    
    # Add URL
    curl_args+=("$url")
    
    # Execute and capture output
    local output
    output=$("$curl_cmd" "${curl_args[@]}" 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        _HTTP_LAST_STATUS=""
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
    local header_end
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
    shift 3
    local -a extra_args=("$@")
    
    local wget_cmd="${_TOOL_PATH[wget]}"
    local -a wget_args=(
        -q                              # Quiet
        -O -                            # Output to stdout
        -S                              # Print headers
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
    
    # Add extra arguments
    wget_args+=("${extra_args[@]}")
    
    # Add URL
    wget_args+=("$url")
    
    # Execute and capture output (stderr has headers, stdout has body)
    local body headers
    body=$("$wget_cmd" "${wget_args[@]}" 2>&1)
    local exit_code=$?
    
    # wget puts headers in stderr with -S, but we redirected to stdout
    # Parse the output - headers start with "  HTTP/" and indented lines
    _HTTP_LAST_HEADERS=""
    _HTTP_LAST_BODY=""
    _HTTP_LAST_STATUS=""
    
    local in_headers=0
    local line
    while IFS= read -r line; do
        if [[ "$line" == *"HTTP/"* ]]; then
            in_headers=1
            _HTTP_LAST_HEADERS+="$line"$'\n'
            # Extract status code
            if [[ "$line" =~ HTTP/[0-9.]+" "([0-9]+) ]]; then
                _HTTP_LAST_STATUS="${BASH_REMATCH[1]}"
            fi
        elif [[ $in_headers -eq 1 && "$line" == "  "* ]]; then
            _HTTP_LAST_HEADERS+="${line#  }"$'\n'
        else
            in_headers=0
            _HTTP_LAST_BODY+="$line"$'\n'
        fi
    done <<< "$body"
    
    # Remove trailing newline from body
    _HTTP_LAST_BODY="${_HTTP_LAST_BODY%$'\n'}"
    
    if [[ $exit_code -ne 0 && -z "$_HTTP_LAST_STATUS" ]]; then
        _HTTP_LAST_BODY="wget error: $body"
        return 1
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# Internal Request Dispatcher
# -----------------------------------------------------------------------------

_http_request() {
    case "$_HTTP_IMPL" in
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

# -----------------------------------------------------------------------------
# Public API - Core Request Functions
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Perform HTTP GET request
# Usage: http_get "https://example.com/api" -> stores response in _HTTP_LAST_*
# Usage: http_get "https://example.com/api" "-H" "Authorization: Bearer token"
# Returns: 0 on success, 1 on failure. Response in http_body, http_status, http_headers
http_get() {
    local url="${1:-}"
    shift
    
    [[ -z "$url" ]] && { _HTTP_LAST_BODY="URL required"; return 1; }
    [[ "$_HTTP_READY" != "1" ]] && { _HTTP_LAST_BODY="$_HTTP_ERROR"; return 1; }
    
    _http_request "GET" "$url" "" "$@"
}

# @@PUBLIC_API@@
# Perform HTTP POST request
# Usage: http_post "https://example.com/api" "data=value" -> stores response
# Usage: http_post "https://example.com/api" '{"key":"value"}' "-H" "Content-Type: application/json"
# Returns: 0 on success, 1 on failure
http_post() {
    local url="${1:-}"
    local data="${2:-}"
    shift 2 2>/dev/null || shift $#
    
    [[ -z "$url" ]] && { _HTTP_LAST_BODY="URL required"; return 1; }
    [[ "$_HTTP_READY" != "1" ]] && { _HTTP_LAST_BODY="$_HTTP_ERROR"; return 1; }
    
    _http_request "POST" "$url" "$data" "$@"
}

# @@PUBLIC_API@@
# Perform HTTP PUT request
# Usage: http_put "https://example.com/api/1" '{"key":"value"}'
# Returns: 0 on success, 1 on failure
http_put() {
    local url="${1:-}"
    local data="${2:-}"
    shift 2 2>/dev/null || shift $#
    
    [[ -z "$url" ]] && { _HTTP_LAST_BODY="URL required"; return 1; }
    [[ "$_HTTP_READY" != "1" ]] && { _HTTP_LAST_BODY="$_HTTP_ERROR"; return 1; }
    
    _http_request "PUT" "$url" "$data" "$@"
}

# @@PUBLIC_API@@
# Perform HTTP PATCH request
# Usage: http_patch "https://example.com/api/1" '{"key":"value"}'
# Returns: 0 on success, 1 on failure
http_patch() {
    local url="${1:-}"
    local data="${2:-}"
    shift 2 2>/dev/null || shift $#
    
    [[ -z "$url" ]] && { _HTTP_LAST_BODY="URL required"; return 1; }
    [[ "$_HTTP_READY" != "1" ]] && { _HTTP_LAST_BODY="$_HTTP_ERROR"; return 1; }
    
    _http_request "PATCH" "$url" "$data" "$@"
}

# @@PUBLIC_API@@
# Perform HTTP DELETE request
# Usage: http_delete "https://example.com/api/1"
# Returns: 0 on success, 1 on failure
http_delete() {
    local url="${1:-}"
    shift
    
    [[ -z "$url" ]] && { _HTTP_LAST_BODY="URL required"; return 1; }
    [[ "$_HTTP_READY" != "1" ]] && { _HTTP_LAST_BODY="$_HTTP_ERROR"; return 1; }
    
    _http_request "DELETE" "$url" "" "$@"
}

# @@PUBLIC_API@@
# Perform HTTP HEAD request (headers only)
# Usage: http_head "https://example.com" -> stores headers in _HTTP_LAST_HEADERS
# Returns: 0 on success, 1 on failure
http_head() {
    local url="${1:-}"
    shift
    
    [[ -z "$url" ]] && { _HTTP_LAST_BODY="URL required"; return 1; }
    [[ "$_HTTP_READY" != "1" ]] && { _HTTP_LAST_BODY="$_HTTP_ERROR"; return 1; }
    
    if [[ "$_HTTP_IMPL" == "curl" ]]; then
        _http_request "HEAD" "$url" "" "-I" "$@"
    else
        _http_request "HEAD" "$url" "" "$@"
    fi
}

# -----------------------------------------------------------------------------
# Public API - Response Access
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Get the response body from the last request
# Usage: http_body -> prints response body
http_body() {
    echo "$_HTTP_LAST_BODY"
}

# @@PUBLIC_API@@
# Get the HTTP status code from the last request
# Usage: http_status -> prints status code (e.g., "200")
http_status() {
    echo "$_HTTP_LAST_STATUS"
}

# @@PUBLIC_API@@
# Get the response headers from the last request
# Usage: http_headers -> prints all headers
http_headers() {
    echo "$_HTTP_LAST_HEADERS"
}

# @@PUBLIC_API@@
# Get a specific header value from the last request
# Usage: http_header "Content-Type" -> prints header value
http_header() {
    local name="${1:-}"
    [[ -z "$name" ]] && return 1
    
    # Case-insensitive search
    echo "$_HTTP_LAST_HEADERS" | grep -i "^${name}:" | head -1 | sed 's/^[^:]*:[[:space:]]*//'
}

# @@PUBLIC_API@@
# Check if the last request was successful (2xx status)
# Usage: http_ok -> returns 0 if success, 1 otherwise
http_ok() {
    [[ "$_HTTP_LAST_STATUS" =~ ^2[0-9][0-9]$ ]]
}

# @@PUBLIC_API@@
# Check if the last request resulted in a redirect (3xx status)
# Usage: http_redirect -> returns 0 if redirect, 1 otherwise
http_redirect() {
    [[ "$_HTTP_LAST_STATUS" =~ ^3[0-9][0-9]$ ]]
}

# @@PUBLIC_API@@
# Check if the last request resulted in client error (4xx status)
# Usage: http_client_error -> returns 0 if client error, 1 otherwise
http_client_error() {
    [[ "$_HTTP_LAST_STATUS" =~ ^4[0-9][0-9]$ ]]
}

# @@PUBLIC_API@@
# Check if the last request resulted in server error (5xx status)
# Usage: http_server_error -> returns 0 if server error, 1 otherwise
http_server_error() {
    [[ "$_HTTP_LAST_STATUS" =~ ^5[0-9][0-9]$ ]]
}

# -----------------------------------------------------------------------------
# Public API - JSON Helpers
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# POST JSON data with correct content type
# Usage: http_post_json "https://api.example.com" '{"key":"value"}'
# Returns: 0 on success, 1 on failure
http_post_json() {
    local url="${1:-}"
    local json="${2:-}"
    shift 2 2>/dev/null || shift $#
    
    http_post "$url" "$json" -H "Content-Type: application/json" -H "Accept: application/json" "$@"
}

# @@PUBLIC_API@@
# PUT JSON data with correct content type
# Usage: http_put_json "https://api.example.com/1" '{"key":"value"}'
# Returns: 0 on success, 1 on failure
http_put_json() {
    local url="${1:-}"
    local json="${2:-}"
    shift 2 2>/dev/null || shift $#
    
    http_put "$url" "$json" -H "Content-Type: application/json" -H "Accept: application/json" "$@"
}

# @@PUBLIC_API@@
# PATCH JSON data with correct content type
# Usage: http_patch_json "https://api.example.com/1" '{"key":"value"}'
# Returns: 0 on success, 1 on failure
http_patch_json() {
    local url="${1:-}"
    local json="${2:-}"
    shift 2 2>/dev/null || shift $#
    
    http_patch "$url" "$json" -H "Content-Type: application/json" -H "Accept: application/json" "$@"
}

# @@PUBLIC_API@@
# GET with JSON accept header
# Usage: http_get_json "https://api.example.com"
# Returns: 0 on success, 1 on failure
http_get_json() {
    local url="${1:-}"
    shift
    
    http_get "$url" -H "Accept: application/json" "$@"
}

# -----------------------------------------------------------------------------
# Public API - File Operations
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Download a file to a local path
# Usage: http_download "https://example.com/file.zip" "/tmp/file.zip"
# Returns: 0 on success, 1 on failure
http_download() {
    local url="${1:-}"
    local output="${2:-}"
    
    [[ -z "$url" ]] && return 1
    [[ -z "$output" ]] && return 1
    [[ "$_HTTP_READY" != "1" ]] && return 1
    
    if [[ "$_HTTP_IMPL" == "curl" ]]; then
        "${_TOOL_PATH[curl]}" -sS -L -o "$output" \
            --max-time "$HTTP_TIMEOUT" \
            -A "$HTTP_USER_AGENT" \
            "$url"
    else
        "${_TOOL_PATH[wget]}" -q -O "$output" \
            --timeout="$HTTP_TIMEOUT" \
            --user-agent="$HTTP_USER_AGENT" \
            "$url"
    fi
}

# @@PUBLIC_API@@
# Upload a file via POST (multipart form data)
# Usage: http_upload "https://example.com/upload" "/path/to/file" "file"
# Returns: 0 on success, 1 on failure
http_upload() {
    local url="${1:-}"
    local file="${2:-}"
    local field="${3:-file}"
    shift 3 2>/dev/null || shift $#
    
    [[ -z "$url" ]] && { _HTTP_LAST_BODY="URL required"; return 1; }
    [[ ! -f "$file" ]] && { _HTTP_LAST_BODY="File not found: $file"; return 1; }
    [[ "$_HTTP_READY" != "1" ]] && { _HTTP_LAST_BODY="$_HTTP_ERROR"; return 1; }
    
    if [[ "$_HTTP_IMPL" == "curl" ]]; then
        local output
        output=$("${_TOOL_PATH[curl]}" -sS -w '\n%{http_code}' \
            -X POST \
            -F "${field}=@${file}" \
            --max-time "$HTTP_TIMEOUT" \
            -A "$HTTP_USER_AGENT" \
            "$@" \
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

# @@PUBLIC_API@@
# Set HTTP timeout in seconds
# Usage: http_set_timeout 60
http_set_timeout() {
    HTTP_TIMEOUT="${1:-30}"
}

# @@PUBLIC_API@@
# Set custom user agent
# Usage: http_set_user_agent "MyApp/1.0"
http_set_user_agent() {
    HTTP_USER_AGENT="${1:-nutshell-http/1.0}"
}

# @@PUBLIC_API@@
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

# @@PUBLIC_API@@
# Set maximum number of redirects to follow
# Usage: http_max_redirects 5
http_max_redirects() {
    HTTP_MAX_REDIRECTS="${1:-10}"
}

# -----------------------------------------------------------------------------
# Public API - Utility Functions
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
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

# @@PUBLIC_API@@
# URL decode a string
# Usage: http_urldecode "hello%20world" -> "hello world"
http_urldecode() {
    local string="${1:-}"
    # Replace + with space, then decode %XX
    string="${string//+/ }"
    printf '%b' "${string//%/\\x}"
}

# @@PUBLIC_API@@
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

# @@PUBLIC_API@@
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

# @@PUBLIC_API@@
# Check if HTTP module is ready
# Usage: http_ready -> returns 0 if ready, 1 if not
http_ready() {
    [[ "$_HTTP_READY" == "1" ]]
}

# @@PUBLIC_API@@
# Get HTTP module error (if not ready)
# Usage: http_error -> prints error message
http_error() {
    echo "$_HTTP_ERROR"
}

# @@PUBLIC_API@@
# Get which HTTP implementation is being used
# Usage: http_impl -> "curl" | "wget" | ""
http_impl() {
    echo "$_HTTP_IMPL"
}
