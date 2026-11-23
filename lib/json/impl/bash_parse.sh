#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/json/impl/bash_parse.sh - JSON parsed in bash alone
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# The parser under `lib/json/impl/bash.sh`, the reader that runs wherever bash
# 4.3 does with no jq, no python and no perl, so a container with none of them
# still reads JSON. It only reads. It uses no other module, so the toml module
# loads it alone to read what taplo or yq print.
#
# The document is parsed once into a tree of numbered nodes and every question
# is answered from the tree. A node has a type in `_JB_T` and, for a scalar, its
# value in `_JB_V`, decoded. A container keeps its child count in `_JB_C` and
# its children as `_JB_CH[<node>.<index>]`, in document order; a child of an
# object remembers its key in `_JB_KY`, and the object finds a key's index in
# `_JB_KI[<node><US><key>]`. Nodes are numbers, not paths built from keys, so a
# key can hold any character at all. The root is node 0.
#
# Strings are bytes, because the parse runs under `LC_ALL=C` where an offset is
# a byte count and reading is linear. The text a caller gets back is those
# bytes, which is UTF-8 when the document was. An escaped U+0000 cannot live in
# a bash string and is dropped.
#
# Output matches the other backends: a container comes back compact with its
# keys sorted bytewise, which for UTF-8 is code point order, a string bare, and
# any other scalar as the document wrote it. A repeated key keeps its last
# value, as jq does, in the place of its first. Segments of a path arrive
# already split by the caller, joined by the unit separator, and the first path
# that does not lead anywhere is a miss with status 1.
#
# `_JB_ODDN` says the document has a number jq may print another way than it
# was written (a fraction, an exponent, more digits than a double keeps), and
# `_JB_ODDS` a string it would not (a NUL, a surrogate with no pair).

[ -n "${_NUTSHELL_JSON_IMPL_BASH_PARSE_SH:-}" ] && return 0
_NUTSHELL_JSON_IMPL_BASH_PARSE_SH=1

declare -gA _JB_T=() _JB_V=() _JB_C=() _JB_CH=() _JB_KY=() _JB_KI=() _JB_UC=()
declare -ga _jb_stk=()
_JB_SRC="" _JB_SO=0 _JB_LEN=0 _jb_s="" _jb_key=""
_JB_ID=0 _JB_TEXT="" _JB_RC=1 _JB_CHUNK=256 _JB_DEPTH=400 _JB_ODDN=0 _JB_ODDS=0 _JB_MAXN=0
_JB_US=$'\x1f'
_JB_WS=$' \t\n\r'
_JB_RE_STR=$'^"[^"\\\\\x01-\x1f]*(\\\\.[^"\\\\\x01-\x1f]*)*"'
_JB_RE_NUM='^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?'
_JB_RE_CTL=$'[\x01-\x07\x0b\x0e-\x1f\x7f]'

# The document is read a token at a time off the front of a short buffer,
# `_jb_s`, refilled from `_JB_SRC` at `_JB_SO`. Cutting a token off a long
# string copies the rest of it, so a parse over the whole text was quadratic
# and 94 KB took fourteen seconds; over a buffer of a few hundred bytes each cut
# is cheap. The loop is one function with a state for what may come next, as
# the toml module's tree of a tool's JSON was, since a call per character or
# per value is most of what a bash parser spends.

# _jb_more [n] -> adds n bytes, a chunk by default, of the document to the
# buffer; rc 1 when none is left
_jb_more() {
    (( _JB_SO < _JB_LEN )) || return 1
    local n=${1:-$_JB_CHUNK}
    _jb_s+="${_JB_SRC:_JB_SO:n}"
    _JB_SO=$(( _JB_SO + n ))
}

# _jb_utf8 <code point> -> `_jb_u`, its UTF-8 bytes
_jb_utf8() {
    local c=$1
    if (( c < 0x80 )); then
        printf -v _jb_u '\\x%02x' "$c"
    elif (( c < 0x800 )); then
        printf -v _jb_u '\\x%02x\\x%02x' $(( 0xC0 | c >> 6 )) $(( 0x80 | c & 0x3F ))
    elif (( c < 0x10000 )); then
        printf -v _jb_u '\\x%02x\\x%02x\\x%02x' $(( 0xE0 | c >> 12 )) \
            $(( 0x80 | c >> 6 & 0x3F )) $(( 0x80 | c & 0x3F ))
    else
        printf -v _jb_u '\\x%02x\\x%02x\\x%02x\\x%02x' $(( 0xF0 | c >> 18 )) \
            $(( 0x80 | c >> 12 & 0x3F )) $(( 0x80 | c >> 6 & 0x3F )) $(( 0x80 | c & 0x3F ))
    fi
    printf -v _jb_u "$_jb_u"
}

# _jb_decode <body> -> `_jb_str`, a string's body with its escapes decoded; rc
# 1 for an escape JSON does not have
_jb_decode() {
    local m="$1" h lo seg dg i n f="" IFS
    local -a part
    _jb_str=""
    if [[ "$m" != *\\* ]]; then _jb_str="$m"; return 0; fi
    # Every escape by a substitution over the whole body, a pass in C each:
    # one at a time, each cut copied the rest, and a 2 KB command with a
    # hundred escapes took 5ms. A literal backslash is held as 0x01 meanwhile,
    # a byte a JSON string cannot hold raw, so `\\n` stays a backslash and an
    # `n`; it is put back in the text between the `\u`s, never in what a `\u`
    # decodes to. Each `\u` becomes 0x02, which splits the body into the text
    # before the first and, for each, its four digits and the text after.
    m="${m//\\\\/$'\x01'}"
    m="${m//\\\"/\"}" m="${m//\\\//\/}"
    m="${m//\\b/$'\b'}" m="${m//\\f/$'\f'}" m="${m//\\n/$'\n'}"
    m="${m//\\r/$'\r'}" m="${m//\\t/$'\t'}"
    m="${m//\\u/$'\x02'}"
    [[ "$m" == *\\* || "$m" == *$'\x02' ]] && return 1
    if [[ "$m" != *$'\x02'* ]]; then _jb_str="${m//$'\x01'/\\}"; return 0; fi
    [[ "$-" == *f* ]] && f=1
    set -f; IFS=$'\x02'; part=($m); IFS=$' \t\n'
    [[ -n "$f" ]] || set +f
    _jb_str="${part[0]//$'\x01'/\\}"
    n=${#part[@]}
    for (( i = 1; i < n; i++ )); do
        seg="${part[i]}" h="${part[i]:0:4}"
        # What a code point outside the surrogates decodes to is kept, by its
        # digits: a command repeats the same few escapes.
        if [[ -n "${_JB_UC[$h]+x}" ]]; then
            seg="${seg:4}"; _jb_str+="${_JB_UC[$h]}${seg//$'\x01'/\\}"
            continue
        fi
        [[ "$h" == [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f] ]] || return 1
        seg="${seg:4}" dg="$h" h=$(( 16#$h ))
        if (( h >= 0xD800 && h < 0xDC00 )); then
            lo="${part[i+1]-}"; lo="${lo:0:4}"
            if [[ -z "$seg" && "$lo" =~ ^[0-9A-Fa-f]{4}$ ]] \
                && (( 16#$lo >= 0xDC00 && 16#$lo < 0xE000 )); then
                h=$(( 0x10000 + (h - 0xD800) * 0x400 + 16#$lo - 0xDC00 ))
                i=$(( i + 1 )); seg="${part[i]:4}"
            else
                h=0xFFFD _JB_ODDS=1
            fi
        elif (( h >= 0xDC00 && h < 0xE000 )); then
            h=0xFFFD _JB_ODDS=1
        fi
        if (( h )); then
            _jb_utf8 "$h"; _jb_str+="$_jb_u"
            (( 16#$dg >= 0xD800 && 16#$dg < 0xE000 )) || _JB_UC[$dg]="$_jb_u"
        else
            _JB_ODDS=1
        fi
        _jb_str+="${seg//$'\x01'/\\}"
    done
}

# _jb_string -> `_jb_str`, the string at the front of the buffer, decoded and
# cut off; rc 1 when malformed. A string longer than the buffer grows it by
# its own length each time, so a long one is matched a few times, not once a
# chunk.
_jb_string() {
    while ! [[ "$_jb_s" =~ $_JB_RE_STR ]]; do
        _jb_more $(( ${#_jb_s} + _JB_CHUNK )) || return 1
    done
    local m="${BASH_REMATCH[0]}"
    _jb_s="${_jb_s:${#m}}"
    m="${m:1:${#m}-2}"
    if [[ "$m" == *\\* ]]; then _jb_decode "$m"; else _jb_str="$m"; fi
}

# _jb_place -> `_jb_n`, a new node where the next value goes: the root, the
# next key of the open object (or the one it repeats) or the next element of
# the open array
_jb_place() {
    local d=${#_jb_stk[@]} p i k
    _jb_n=$_JB_ID
    _JB_ID=$(( _JB_ID + 1 ))
    (( d )) || return 0
    p=${_jb_stk[d-1]}
    if [[ "${_JB_T[$p]}" == object ]]; then
        k="$p$_JB_US$_jb_key"
        _JB_KY[$_jb_n]="$_jb_key"
        i="${_JB_KI[$k]-}"
        if [[ -n "$i" ]]; then _JB_CH[$p.$i]=$_jb_n; return 0; fi
        _JB_KI[$k]=${_JB_C[$p]}
    fi
    _JB_CH[$p.${_JB_C[$p]}]=$_jb_n
    _JB_C[$p]=$(( _JB_C[$p] + 1 ))
}

# _jb_parse -> the tree of `_JB_SRC`; rc 1 when it is not one JSON document
# States: v a value, V a value or `]`, K a key or `}`, k a key, : the colon,
# c a comma or the closer of the open container, e the end.
_jb_parse() {
    local st=v c m p d
    _jb_stk=() _jb_s=""
    while :; do
        (( ! _JB_MAXN || _JB_ID <= _JB_MAXN )) || return 3
        (( ${#_jb_s} >= 64 )) || _jb_more
        if [[ "$_jb_s" == [$_JB_WS]* ]]; then
            _jb_s="${_jb_s#"${_jb_s%%[!$_JB_WS]*}"}"
            continue
        fi
        [[ -n "$_jb_s" ]] || break
        c="${_jb_s:0:1}"
        case "$st$c" in
            [vV]'{'|[vV]'[')
                (( ${#_jb_stk[@]} < _JB_DEPTH )) || return 1
                _jb_place
                _JB_C[$_jb_n]=0
                if [[ "$c" == '{' ]]; then _JB_T[$_jb_n]=object st=K
                else _JB_T[$_jb_n]=array st=V; fi
                _jb_stk+=("$_jb_n")
                _jb_s="${_jb_s:1}"
                continue ;;
            [Kc]'}'|[Vc]']')
                d=${#_jb_stk[@]}
                p=${_jb_stk[d-1]}
                [[ "$c" == '}' && "${_JB_T[$p]}" == object || "$c" == ']' && "${_JB_T[$p]}" == array ]] \
                    || return 1
                unset "_jb_stk[d-1]"
                _jb_s="${_jb_s:1}" ;;
            c,)
                p=${_jb_stk[${#_jb_stk[@]}-1]}
                st=v
                [[ "${_JB_T[$p]}" == object ]] && st=k
                _jb_s="${_jb_s:1}"
                continue ;;
            [kK]'"')
                _jb_string || return 1
                _jb_key="$_jb_str" st=:
                continue ;;
            :':')
                st=v
                _jb_s="${_jb_s:1}"
                continue ;;
            [vV]'"')
                _jb_string || return 1
                _jb_place
                _JB_T[$_jb_n]=string _JB_V[$_jb_n]="$_jb_str" ;;
            [vV][-0-9])
                # A number running to the end of the buffer may go on past it.
                while [[ "$_jb_s" =~ $_JB_RE_NUM ]] && m="${BASH_REMATCH[0]}" \
                    && (( ${#m} == ${#_jb_s} )) && _jb_more; do :; done
                [[ "$_jb_s" =~ $_JB_RE_NUM ]] || return 1
                m="${BASH_REMATCH[0]}"
                _jb_s="${_jb_s:${#m}}"
                _jb_place
                _JB_T[$_jb_n]=number _JB_V[$_jb_n]="$m"
                [[ "$m" == *[.eE]* || ${#m} -gt 15 ]] && _JB_ODDN=1 ;;
            [vV][tfn])
                case "${_jb_s:0:5}" in
                    true*)  m=true  _jb_s="${_jb_s:4}"; _jb_place; _JB_T[$_jb_n]=boolean ;;
                    false)  m=false _jb_s="${_jb_s:5}"; _jb_place; _JB_T[$_jb_n]=boolean ;;
                    null*)  m=null  _jb_s="${_jb_s:4}"; _jb_place; _JB_T[$_jb_n]=null ;;
                    *) return 1 ;;
                esac
                _JB_V[$_jb_n]="$m" ;;
            *)
                return 1 ;;
        esac
        # A value or a closer was taken: what follows it.
        st=c
        (( ${#_jb_stk[@]} )) || st=e
    done
    [[ "$st" == e ]]
}

# _jb_load <text> -> 0 parsed, 1 not JSON, 3 more than `_JB_MAXN` values where
# that is set above zero (the caller then asks a tool). The last document is
# kept.
# The toml module reads its tools' JSON with it, so it is the library's.
#[pub(lib)]
_jb_load() {
    local LC_ALL=C
    [[ "$_JB_TEXT" == "$1" && -n "$1" ]] && return "$_JB_RC"
    _JB_T=() _JB_V=() _JB_C=() _JB_CH=() _JB_KY=() _JB_KI=()
    _JB_SRC="$1" _JB_LEN=${#1} _JB_SO=0 _JB_ID=0 _JB_RC=0 _JB_ODDN=0 _JB_ODDS=0
    _jb_parse || _JB_RC=$?
    _JB_SRC="" _jb_s="" _JB_TEXT="$1"
    # Past the budget is no answer about the document, so it is not kept.
    if (( _JB_RC == 3 )); then _JB_TEXT=""; return 3; fi
    (( _JB_RC == 0 )) || _JB_RC=1
    return "$_JB_RC"
}

# _jb_find <path> -> `_jb_node`, the node a path names; rc 1 for none. With
# `_JB_JQ_PATH` set, rc 3 where jq reads the path another way: a segment of
# digits it takes for an index on an object, any other on an array.
#[pub(super)]
_jb_find() {
    local rest="${1:-}" seg node=0 i
    while [[ -n "$rest" ]]; do
        if [[ "$rest" == *"$_JB_US"* ]]; then seg="${rest%%"$_JB_US"*}"; rest="${rest#*"$_JB_US"}"
        else seg="$rest"; rest=""; fi
        [[ -n "$seg" ]] || continue
        case "${_JB_T[$node]}" in
            array)
                if [[ -n "${_JB_JQ_PATH:-}" && "$seg" == *[!0-9]* ]]; then return 3; fi
                [[ "$seg" =~ ^[0-9]{1,9}$ ]] || return 1
                (( 10#$seg < _JB_C[$node] )) || return 1
                node="${_JB_CH[$node.$(( 10#$seg ))]}" ;;
            object)
                if [[ -n "${_JB_JQ_PATH:-}" && "$seg" != *[!0-9]* ]]; then return 3; fi
                i="${_JB_KI[$node$_JB_US$seg]-}"
                [[ -n "$i" ]] || return 1
                node="${_JB_CH[$node.$i]}" ;;
            *) return 1 ;;
        esac
    done
    _jb_node=$node
}
