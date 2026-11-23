#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/toml/impl/bash_lex.sh - the cursor and the scalar readers
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The lowest part of the bash TOML reader: the cursor over the file's lines,
# and the readers for what sits on it that has no structure of its own, the
# four kinds of string with their escapes, numbers, booleans, dates and times.
# It calls nothing above it. `lib/toml/impl/bash.sh` builds the tree on it.
#
# The cursor is `_TL`, the file's lines, `_tp_ln`, the line it is on, and
# `_tp_s`, what is left of that line. Every reader consumes from the front of
# `_tp_s` and leaves the rest. A scalar is stored under the node it is given,
# in `_TOML_T` and `_TOML_V`.

# A guard of its own rather than `nut_once`, for the same reason as every file
# that can be sourced before the module system exists.
[ -n "${_NUTSHELL_TOML_IMPL_BASH_LEX_SH:-}" ] && return 0
_NUTSHELL_TOML_IMPL_BASH_LEX_SH=1

_TOML_RE_BSTR='^(([^"\\]|\\.)*)"'
_TOML_RE_LSTR="^'([^']*)'"
_TOML_RE_TOKEN='^[A-Za-z0-9_.:+-]+'
_TOML_RE_DTSP='^ [0-9]{2}:'
_TOML_RE_FOLD=$'^[ \t]*\n'
_TOML_RE_DEC='^[+-]?(0|[1-9](_?[0-9])*)$'
_TOML_RE_HEX='^0x[0-9A-Fa-f](_?[0-9A-Fa-f])*$'
_TOML_RE_OCT='^0o[0-7](_?[0-7])*$'
_TOML_RE_BIN='^0b[01](_?[01])*$'
_TOML_RE_FLOAT='^[+-]?(0|[1-9](_?[0-9])*)(\.[0-9](_?[0-9])*)?([eE][+-]?[0-9](_?[0-9])*)?$'
_TOML_RE_DATE='^[0-9]{4}-[0-9]{2}-[0-9]{2}([Tt ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([Zz]|[+-][0-9]{2}:[0-9]{2})?)?$'
_TOML_RE_TIME='^[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?$'

declare -gA _TOML_T=() _TOML_V=() _TOML_R=()
declare -ga _TL=()
_tp_id=""
_tp_ln=0
_tp_s=""
_TOML_ERR=""

#[pub(super)]
_tp_err() {
    _TOML_ERR="toml: ${_tp_id}:$(( _tp_ln + 1 )): $1"
    return 2
}

#[pub(super)]
_tp_skip_ws() { _tp_s="${_tp_s#"${_tp_s%%[![:blank:]]*}"}"; }

#[pub(super)]
_tp_next_line() {
    (( _tp_ln + 1 < ${#_TL[@]} )) || return 1
    _tp_ln=$(( _tp_ln + 1 ))
    _tp_s="${_TL[_tp_ln]}"
}

# Whitespace, comments and line ends, as an array allows between its values.
#[pub(super)]
_tp_skip_wsnl() {
    while :; do
        _tp_skip_ws
        if [[ -z "$_tp_s" || "$_tp_s" == '#'* ]]; then
            _tp_next_line || { _tp_err "unterminated array"; return 2; }
            continue
        fi
        return 0
    done
}

# What may follow a value or a header: nothing, or a comment.
#[pub(super)]
_tp_eol() {
    _tp_skip_ws
    [[ -z "$_tp_s" || "$_tp_s" == '#'* ]] && return 0
    _tp_err "unexpected text after the value: ${_tp_s}"
}

# _toml_utf8 <codepoint> <name> -> the character, written to <name>
# rc 1 for a codepoint that is no character, rc 2 for a name that is no name.
# The locals are prefixed because the caller picks the name.
_toml_utf8() {
    local __tu_cp="$1" __tu_out="$2" __tu_fmt
    [[ "$__tu_out" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
    [[ "$__tu_cp" =~ ^[0-9]{1,8}$ ]] || return 1
    __tu_cp=$(( 10#$__tu_cp ))
    (( __tu_cp > 0x10FFFF )) && return 1
    (( __tu_cp >= 0xD800 && __tu_cp <= 0xDFFF )) && return 1
    if (( __tu_cp < 0x80 )); then
        printf -v __tu_fmt '\\x%02x' "$__tu_cp"
    elif (( __tu_cp < 0x800 )); then
        printf -v __tu_fmt '\\x%02x\\x%02x' \
            $(( 0xC0 | (__tu_cp >> 6) )) $(( 0x80 | (__tu_cp & 0x3F) ))
    elif (( __tu_cp < 0x10000 )); then
        printf -v __tu_fmt '\\x%02x\\x%02x\\x%02x' \
            $(( 0xE0 | (__tu_cp >> 12) )) $(( 0x80 | ((__tu_cp >> 6) & 0x3F) )) \
            $(( 0x80 | (__tu_cp & 0x3F) ))
    else
        printf -v __tu_fmt '\\x%02x\\x%02x\\x%02x\\x%02x' \
            $(( 0xF0 | (__tu_cp >> 18) )) $(( 0x80 | ((__tu_cp >> 12) & 0x3F) )) \
            $(( 0x80 | ((__tu_cp >> 6) & 0x3F) )) $(( 0x80 | (__tu_cp & 0x3F) ))
    fi
    printf -v "$__tu_out" '%b' "$__tu_fmt"
}

# _tv_unescape <body> [ml] -> `_tv_out`, a basic string's body decoded
# With `ml`, a backslash that ends a line folds away the line end and every
# space, tab and line end after it.
#[pub(super)]
_tv_unescape() {
    local s="$1" ml="${2-}" c hex n cp
    _tv_out=""
    while [[ "$s" == *\\* ]]; do
        _tv_out+="${s%%\\*}"
        s="${s#*\\}"
        c="${s:0:1}"
        case "$c" in
            b) _tv_out+=$'\b' ;;
            t) _tv_out+=$'\t' ;;
            n) _tv_out+=$'\n' ;;
            f) _tv_out+=$'\f' ;;
            r) _tv_out+=$'\r' ;;
            '"') _tv_out+='"' ;;
            '\') _tv_out+='\' ;;
            u|U)
                n=4
                [[ "$c" == U ]] && n=8
                hex="${s:1:n}"
                if (( ${#hex} != n )) || ! [[ "$hex" =~ ^[0-9A-Fa-f]+$ ]]; then
                    _tp_err "escape \\${c} needs ${n} hex digits"
                    return 2
                fi
                cp=$(( 16#$hex ))
                if (( cp == 0 )); then
                    _tp_err "escape \\${c}${hex} is a NUL, which a shell value cannot hold"
                    return 2
                fi
                _toml_utf8 "$cp" _tv_ch || { _tp_err "escape \\${c}${hex} names no character"; return 2; }
                _tv_out+="$_tv_ch"
                s="${s:n+1}"
                continue ;;
            *)
                if [[ -n "$ml" && "$s" =~ $_TOML_RE_FOLD ]]; then
                    s="${s#"${s%%[![:space:]]*}"}"
                    continue
                fi
                _tp_err "escape \\${c} is not a TOML escape"
                return 2 ;;
        esac
        s="${s:1}"
    done
    _tv_out+="$s"
}

# _tv_raw <node> <line rest at start> <line at start> -> `_TOML_R`, as written
#[pub(super)]
_tv_raw() {
    local r i cur
    if (( $3 == _tp_ln )); then
        r="${2:0:${#2}-${#_tp_s}}"
    else
        r="$2"
        for (( i = $3 + 1; i < _tp_ln; i++ )); do
            r+=$'\n'"${_TL[i]}"
        done
        cur="${_TL[_tp_ln]}"
        r+=$'\n'"${cur:0:${#cur}-${#_tp_s}}"
    fi
    _TOML_R[$1]="$r"
}

#[pub(super)]
_tv_basic() {
    _tp_s="${_tp_s:1}"
    [[ "$_tp_s" =~ $_TOML_RE_BSTR ]] || { _tp_err "unterminated string"; return 2; }
    _tp_s="${_tp_s:${#BASH_REMATCH[0]}}"
    _tv_unescape "${BASH_REMATCH[1]}" || return 2
    _TOML_T[$1]=str
    _TOML_V[$1]="$_tv_out"
}

#[pub(super)]
_tv_literal() {
    [[ "$_tp_s" =~ $_TOML_RE_LSTR ]] || { _tp_err "unterminated literal string"; return 2; }
    _tp_s="${_tp_s:${#BASH_REMATCH[0]}}"
    _TOML_T[$1]=str
    _TOML_V[$1]="${BASH_REMATCH[1]}"
}

# _tv_mlstr <node> <quote> -> a `"""` or `'''` string, over as many lines as it takes
#[pub(super)]
_tv_mlstr() {
    local p="$1" q="$2" body="" pre run n
    _tp_s="${_tp_s:3}"
    # A line end straight after the opening delimiter is not part of the value.
    if [[ -z "$_tp_s" ]]; then
        _tp_next_line || { _tp_err "unterminated multi-line string"; return 2; }
    fi
    while :; do
        if [[ "$q" == '"' ]]; then
            pre="${_tp_s%%[\"\\]*}"
        else
            pre="${_tp_s%%\'*}"
        fi
        if [[ "$pre" == "$_tp_s" ]]; then
            body+="$_tp_s"$'\n'
            _tp_next_line || { _tp_err "unterminated multi-line string"; return 2; }
            continue
        fi
        body+="$pre"
        _tp_s="${_tp_s:${#pre}}"
        if [[ "${_tp_s:0:1}" == '\' ]]; then
            # The escape is kept whole for the decoder, so `\"` closes nothing.
            body+="${_tp_s:0:2}"
            _tp_s="${_tp_s:2}"
            continue
        fi
        if [[ "$q" == '"' ]]; then
            run="${_tp_s%%[!\"]*}"
        else
            run="${_tp_s%%[!\']*}"
        fi
        n=${#run}
        _tp_s="${_tp_s:n}"
        if (( n < 3 )); then
            body+="$run"
            continue
        fi
        (( n > 5 )) && { _tp_err "multi-line string closed by ${n} quotes, more than five"; return 2; }
        body+="${run:0:n-3}"
        break
    done
    _TOML_T[$p]=str
    if [[ "$q" == '"' ]]; then
        _tv_unescape "$body" ml || return 2
        _TOML_V[$p]="$_tv_out"
    else
        _TOML_V[$p]="$body"
    fi
}

# _tv_scalar <node> -> a number, a boolean, a date or a time
#[pub(super)]
_tv_scalar() {
    local p="$1" tok v
    [[ "$_tp_s" =~ $_TOML_RE_TOKEN ]] || { _tp_err "invalid value: ${_tp_s}"; return 2; }
    tok="${BASH_REMATCH[0]}"
    _tp_s="${_tp_s:${#tok}}"
    # A date and a time may be joined by a space rather than a T.
    if [[ "$tok" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && "$_tp_s" =~ $_TOML_RE_DTSP ]]; then
        _tp_s="${_tp_s:1}"
        [[ "$_tp_s" =~ $_TOML_RE_TOKEN ]]
        tok+=" ${BASH_REMATCH[0]}"
        _tp_s="${_tp_s:${#BASH_REMATCH[0]}}"
    fi
    v="${tok//_/}"
    if [[ "$tok" == true || "$tok" == false ]]; then
        _TOML_T[$p]=bool
        _TOML_V[$p]="$tok"
    elif [[ "$tok" =~ $_TOML_RE_DEC ]]; then
        _tv_in_range "$v" || { _tp_err "integer ${tok} is out of range"; return 2; }
        _TOML_T[$p]=int
        v="${v#+}"
        _TOML_V[$p]="${v/#-0/0}"
    elif [[ "$tok" =~ $_TOML_RE_HEX ]]; then
        _tv_radix "$p" "$tok" 16 "${v:2}" 16 || return 2
    elif [[ "$tok" =~ $_TOML_RE_OCT ]]; then
        _tv_radix "$p" "$tok" 8 "${v:2}" 21 || return 2
    elif [[ "$tok" =~ $_TOML_RE_BIN ]]; then
        _tv_radix "$p" "$tok" 2 "${v:2}" 63 || return 2
    elif [[ "$tok" == *[.eE]* && "$tok" =~ $_TOML_RE_FLOAT ]]; then
        _TOML_T[$p]=float
        _TOML_V[$p]="${v#+}"
    elif [[ "$tok" =~ ^[+-]?(inf|nan)$ ]]; then
        _TOML_T[$p]=inf
        _TOML_V[$p]="$tok"
    elif [[ "$tok" =~ $_TOML_RE_DATE || "$tok" =~ $_TOML_RE_TIME ]]; then
        # RFC 3339's spelling, the one `lib/toml.sh` names canonical: the
        # separator a `T`, and `t` and `z` upper case.
        tok="${tok/ /T}"
        _TOML_T[$p]=dt
        _TOML_V[$p]="${tok^^}"
    else
        _tp_err "invalid value: ${tok}"
        return 2
    fi
}

# _tv_in_range <decimal> -> whether it fits a signed 64-bit integer
# Nineteen digits can be either side of the end, so those are compared as text:
# at equal length the order of the digits is the order of the numbers.
_tv_in_range() {
    local d="${1#[+-]}" max=9223372036854775807
    [[ "$1" == -* ]] && max=9223372036854775808
    (( ${#d} < 19 )) && return 0
    (( ${#d} == 19 )) || return 1
    [[ ! "$d" > "$max" ]]
}

# _tv_radix <node> <token> <base> <digits> <most digits> -> an integer in decimal
_tv_radix() {
    local d="$4"
    d="${d#"${d%%[!0]*}"}"
    (( ${#d} <= $5 )) || { _tp_err "integer $2 is out of range"; return 2; }
    local n=$(( $3#${d:-0} ))
    (( n >= 0 )) || { _tp_err "integer $2 is out of range"; return 2; }
    _TOML_T[$1]=int
    _TOML_V[$1]="$n"
}
