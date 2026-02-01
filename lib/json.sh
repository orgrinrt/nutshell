#!/usr/bin/env bash
# =============================================================================
# nutshell/core/json.sh - JSON parsing and manipulation
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# @@ALLOW_LOC_650@@
# Layer 0 (Core): Depends on deps.sh for tool detection
#
# Provides JSON parsing and manipulation functions. Uses lazy-init stubs to
# select the best available tool (jq > python > perl > pure bash fallback).
#
# Features:
#   - Get values by path (dot notation or jq syntax)
#   - Set/modify values
#   - Array operations
#   - Validation
#   - Pretty printing
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_JSON_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_JSON_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

_NUTSHELL_JSON_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_NUTSHELL_JSON_DIR" == "${BASH_SOURCE[0]}" ]] && _NUTSHELL_JSON_DIR="."
source "${_NUTSHELL_JSON_DIR}/deps.sh"

# -----------------------------------------------------------------------------
# Module Status
# -----------------------------------------------------------------------------

_JSON_READY=0
_JSON_ERROR=""
_JSON_IMPL=""

# Check for available JSON tools
if deps_has "jq"; then
    _JSON_READY=1
    _JSON_IMPL="jq"
elif deps_has "python3" || deps_has "python"; then
    _JSON_READY=1
    _JSON_IMPL="python"
elif deps_has "perl"; then
    _JSON_READY=1
    _JSON_IMPL="perl"
else
    _JSON_ERROR="No JSON tool available (need jq, python, or perl)"
fi

# -----------------------------------------------------------------------------
# Internal Implementation Functions
# -----------------------------------------------------------------------------

# Get python command (python3 preferred)
_json_python_cmd() {
    if deps_has "python3"; then
        echo "${_TOOL_PATH[python3]}"
    else
        echo "${_TOOL_PATH[python]}"
    fi
}

# jq implementation of json_get
_json_get_jq() {
    local json="${1:-}"
    local path="${2:-}"
    
    # Convert dot notation to jq path if needed
    if [[ "$path" != "."* ]]; then
        path=".${path}"
    fi
    
    echo "$json" | "${_TOOL_PATH[jq]}" -r "$path" 2>/dev/null
}

# Python implementation of json_get
_json_get_python() {
    local json="${1:-}"
    local path="${2:-}"
    local python_cmd
    python_cmd=$(_json_python_cmd)
    
    # Convert path to Python dict access
    # e.g., "foo.bar.0.baz" -> ['foo']['bar'][0]['baz']
    "$python_cmd" -c "
import json
import sys

data = json.loads('''$json''')
path = '$path'

# Navigate the path
current = data
for part in path.split('.'):
    if not part:
        continue
    if part.isdigit():
        current = current[int(part)]
    else:
        current = current[part]

# Output
if isinstance(current, (dict, list)):
    print(json.dumps(current))
else:
    print(current if current is not None else 'null')
" 2>/dev/null
}

# Perl implementation of json_get
_json_get_perl() {
    local json="${1:-}"
    local path="${2:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        my $json_text = $ARGV[0];
        my $path = $ARGV[1];
        
        my $data = decode_json($json_text);
        
        for my $part (split /\./, $path) {
            next if $part eq "";
            if ($part =~ /^\d+$/) {
                $data = $data->[$part];
            } else {
                $data = $data->{$part};
            }
        }
        
        if (ref($data) eq "HASH" || ref($data) eq "ARRAY") {
            print encode_json($data);
        } elsif (defined $data) {
            print $data;
        } else {
            print "null";
        }
    ' "$json" "$path" 2>/dev/null
}

# jq implementation of json_set
_json_set_jq() {
    local json="${1:-}"
    local path="${2:-}"
    local value="${3:-}"
    
    if [[ "$path" != "."* ]]; then
        path=".${path}"
    fi
    
    # Determine if value is a string or other JSON type
    if [[ "$value" == "true" || "$value" == "false" || "$value" == "null" || \
          "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ || \
          "$value" == "["* || "$value" == "{"* ]]; then
        echo "$json" | "${_TOOL_PATH[jq]}" "$path = $value" 2>/dev/null
    else
        echo "$json" | "${_TOOL_PATH[jq]}" --arg v "$value" "$path = \$v" 2>/dev/null
    fi
}

# Python implementation of json_set
_json_set_python() {
    local json="${1:-}"
    local path="${2:-}"
    local value="${3:-}"
    local python_cmd
    python_cmd=$(_json_python_cmd)
    
    "$python_cmd" -c "
import json

data = json.loads('''$json''')
path = '$path'
value_str = '''$value'''

# Parse value
try:
    value = json.loads(value_str)
except:
    value = value_str

# Navigate to parent and set
parts = [p for p in path.split('.') if p]
current = data
for part in parts[:-1]:
    if part.isdigit():
        current = current[int(part)]
    else:
        current = current[part]

last = parts[-1]
if last.isdigit():
    current[int(last)] = value
else:
    current[last] = value

print(json.dumps(data))
" 2>/dev/null
}

# Perl implementation of json_set
_json_set_perl() {
    local json="${1:-}"
    local path="${2:-}"
    local value="${3:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        my $json_text = $ARGV[0];
        my $path = $ARGV[1];
        my $value_str = $ARGV[2];
        
        my $data = decode_json($json_text);
        
        # Parse value
        my $value;
        eval { $value = decode_json($value_str); };
        $value = $value_str if $@;
        
        # Navigate to parent
        my @parts = grep { $_ ne "" } split /\./, $path;
        my $current = $data;
        for my $i (0 .. $#parts - 1) {
            my $part = $parts[$i];
            if ($part =~ /^\d+$/) {
                $current = $current->[$part];
            } else {
                $current = $current->{$part};
            }
        }
        
        # Set value
        my $last = $parts[-1];
        if ($last =~ /^\d+$/) {
            $current->[$last] = $value;
        } else {
            $current->{$last} = $value;
        }
        
        print encode_json($data);
    ' "$json" "$path" "$value" 2>/dev/null
}

# jq implementation of json_keys
_json_keys_jq() {
    local json="${1:-}"
    local path="${2:-.}"
    
    if [[ "$path" != "."* ]]; then
        path=".${path}"
    fi
    
    echo "$json" | "${_TOOL_PATH[jq]}" -r "$path | keys[]" 2>/dev/null
}

# Python implementation of json_keys
_json_keys_python() {
    local json="${1:-}"
    local path="${2:-}"
    local python_cmd
    python_cmd=$(_json_python_cmd)
    
    "$python_cmd" -c "
import json

data = json.loads('''$json''')
path = '$path'

current = data
for part in path.split('.'):
    if not part:
        continue
    if part.isdigit():
        current = current[int(part)]
    else:
        current = current[part]

if isinstance(current, dict):
    for k in current.keys():
        print(k)
elif isinstance(current, list):
    for i in range(len(current)):
        print(i)
" 2>/dev/null
}

# Perl implementation of json_keys
_json_keys_perl() {
    local json="${1:-}"
    local path="${2:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        my $json_text = $ARGV[0];
        my $path = $ARGV[1];
        
        my $data = decode_json($json_text);
        
        for my $part (split /\./, $path) {
            next if $part eq "";
            if ($part =~ /^\d+$/) {
                $data = $data->[$part];
            } else {
                $data = $data->{$part};
            }
        }
        
        if (ref($data) eq "HASH") {
            print "$_\n" for keys %$data;
        } elsif (ref($data) eq "ARRAY") {
            print "$_\n" for 0 .. $#$data;
        }
    ' "$json" "$path" 2>/dev/null
}

# jq implementation of json_valid
_json_valid_jq() {
    local json="${1:-}"
    echo "$json" | "${_TOOL_PATH[jq]}" -e . >/dev/null 2>&1
}

# Python implementation of json_valid
_json_valid_python() {
    local json="${1:-}"
    local python_cmd
    python_cmd=$(_json_python_cmd)
    
    "$python_cmd" -c "
import json
try:
    json.loads('''$json''')
except:
    exit(1)
" 2>/dev/null
}

# Perl implementation of json_valid
_json_valid_perl() {
    local json="${1:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        eval { decode_json($ARGV[0]); };
        exit($@ ? 1 : 0);
    ' "$json" 2>/dev/null
}

# jq implementation of json_pretty
_json_pretty_jq() {
    local json="${1:-}"
    echo "$json" | "${_TOOL_PATH[jq]}" '.' 2>/dev/null
}

# Python implementation of json_pretty
_json_pretty_python() {
    local json="${1:-}"
    local python_cmd
    python_cmd=$(_json_python_cmd)
    
    "$python_cmd" -c "
import json
print(json.dumps(json.loads('''$json'''), indent=2))
" 2>/dev/null
}

# Perl implementation of json_pretty
_json_pretty_perl() {
    local json="${1:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        my $coder = JSON::PP->new->pretty;
        print $coder->encode(decode_json($ARGV[0]));
    ' "$json" 2>/dev/null
}

# jq implementation of json_compact
_json_compact_jq() {
    local json="${1:-}"
    echo "$json" | "${_TOOL_PATH[jq]}" -c '.' 2>/dev/null
}

# Python implementation of json_compact
_json_compact_python() {
    local json="${1:-}"
    local python_cmd
    python_cmd=$(_json_python_cmd)
    
    "$python_cmd" -c "
import json
print(json.dumps(json.loads('''$json'''), separators=(',', ':')))
" 2>/dev/null
}

# Perl implementation of json_compact
_json_compact_perl() {
    local json="${1:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        print encode_json(decode_json($ARGV[0]));
    ' "$json" 2>/dev/null
}

# jq implementation of json_type
_json_type_jq() {
    local json="${1:-}"
    local path="${2:-.}"
    
    if [[ "$path" != "."* ]]; then
        path=".${path}"
    fi
    
    echo "$json" | "${_TOOL_PATH[jq]}" -r "$path | type" 2>/dev/null
}

# Python implementation of json_type
_json_type_python() {
    local json="${1:-}"
    local path="${2:-}"
    local python_cmd
    python_cmd=$(_json_python_cmd)
    
    "$python_cmd" -c "
import json

data = json.loads('''$json''')
path = '$path'

current = data
for part in path.split('.'):
    if not part:
        continue
    if part.isdigit():
        current = current[int(part)]
    else:
        current = current[part]

t = type(current).__name__
type_map = {'dict': 'object', 'list': 'array', 'str': 'string', 'int': 'number', 'float': 'number', 'bool': 'boolean', 'NoneType': 'null'}
print(type_map.get(t, t))
" 2>/dev/null
}

# Perl implementation of json_type
_json_type_perl() {
    local json="${1:-}"
    local path="${2:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        my $json_text = $ARGV[0];
        my $path = $ARGV[1];
        
        my $data = decode_json($json_text);
        
        for my $part (split /\./, $path) {
            next if $part eq "";
            if ($part =~ /^\d+$/) {
                $data = $data->[$part];
            } else {
                $data = $data->{$part};
            }
        }
        
        my $ref = ref($data);
        if ($ref eq "HASH") { print "object"; }
        elsif ($ref eq "ARRAY") { print "array"; }
        elsif (!defined $data) { print "null"; }
        elsif (JSON::PP::is_bool($data)) { print "boolean"; }
        elsif ($data =~ /^-?\d+(\.\d+)?$/) { print "number"; }
        else { print "string"; }
    ' "$json" "$path" 2>/dev/null
}

# jq implementation of json_length
_json_length_jq() {
    local json="${1:-}"
    local path="${2:-.}"
    
    if [[ "$path" != "."* ]]; then
        path=".${path}"
    fi
    
    echo "$json" | "${_TOOL_PATH[jq]}" -r "$path | length" 2>/dev/null
}

# Python implementation of json_length
_json_length_python() {
    local json="${1:-}"
    local path="${2:-}"
    local python_cmd
    python_cmd=$(_json_python_cmd)
    
    "$python_cmd" -c "
import json

data = json.loads('''$json''')
path = '$path'

current = data
for part in path.split('.'):
    if not part:
        continue
    if part.isdigit():
        current = current[int(part)]
    else:
        current = current[part]

print(len(current) if hasattr(current, '__len__') else 0)
" 2>/dev/null
}

# Perl implementation of json_length
_json_length_perl() {
    local json="${1:-}"
    local path="${2:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        my $json_text = $ARGV[0];
        my $path = $ARGV[1];
        
        my $data = decode_json($json_text);
        
        for my $part (split /\./, $path) {
            next if $part eq "";
            if ($part =~ /^\d+$/) {
                $data = $data->[$part];
            } else {
                $data = $data->{$part};
            }
        }
        
        if (ref($data) eq "HASH") { print scalar keys %$data; }
        elsif (ref($data) eq "ARRAY") { print scalar @$data; }
        elsif (defined $data) { print length($data); }
        else { print 0; }
    ' "$json" "$path" 2>/dev/null
}

# -----------------------------------------------------------------------------
# Public API - Core Functions
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Get a value from JSON by path
# Usage: json_get '{"foo":"bar"}' "foo" -> "bar"
# Usage: json_get '{"a":{"b":1}}' "a.b" -> "1"
# Usage: json_get '[1,2,3]' "1" -> "2"
# Returns: The value at the path, or empty if not found
json_get() {
    local json="${1:-}"
    local path="${2:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_get_jq "$json" "$path" ;;
        python) _json_get_python "$json" "$path" ;;
        perl)   _json_get_perl "$json" "$path" ;;
    esac
}

# @@PUBLIC_API@@
# Set a value in JSON by path
# Usage: json_set '{"foo":"bar"}' "foo" "baz" -> '{"foo":"baz"}'
# Usage: json_set '{}' "new.key" "value" -> '{"new":{"key":"value"}}'
# Returns: The modified JSON
json_set() {
    local json="${1:-}"
    local path="${2:-}"
    local value="${3:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_set_jq "$json" "$path" "$value" ;;
        python) _json_set_python "$json" "$path" "$value" ;;
        perl)   _json_set_perl "$json" "$path" "$value" ;;
    esac
}

# @@PUBLIC_API@@
# Get all keys at a path in JSON
# Usage: json_keys '{"a":1,"b":2}' -> prints "a" and "b" on separate lines
# Usage: json_keys '{"x":{"y":1}}' "x" -> prints "y"
# Returns: Keys, one per line
json_keys() {
    local json="${1:-}"
    local path="${2:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_keys_jq "$json" "$path" ;;
        python) _json_keys_python "$json" "$path" ;;
        perl)   _json_keys_perl "$json" "$path" ;;
    esac
}

# @@PUBLIC_API@@
# Check if JSON is valid
# Usage: json_valid '{"foo":"bar"}' -> returns 0 (valid)
# Usage: json_valid 'not json' -> returns 1 (invalid)
# Returns: 0 if valid, 1 if invalid
json_valid() {
    local json="${1:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && return 1
    
    case "$_JSON_IMPL" in
        jq)     _json_valid_jq "$json" ;;
        python) _json_valid_python "$json" ;;
        perl)   _json_valid_perl "$json" ;;
    esac
}

# @@PUBLIC_API@@
# Pretty print JSON with indentation
# Usage: json_pretty '{"a":1,"b":2}' -> prints formatted JSON
# Returns: Pretty-printed JSON
json_pretty() {
    local json="${1:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_pretty_jq "$json" ;;
        python) _json_pretty_python "$json" ;;
        perl)   _json_pretty_perl "$json" ;;
    esac
}

# @@PUBLIC_API@@
# Compact JSON (remove whitespace)
# Usage: json_compact '{ "a": 1, "b": 2 }' -> '{"a":1,"b":2}'
# Returns: Compact JSON on single line
json_compact() {
    local json="${1:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_compact_jq "$json" ;;
        python) _json_compact_python "$json" ;;
        perl)   _json_compact_perl "$json" ;;
    esac
}

# @@PUBLIC_API@@
# Get the type of a JSON value
# Usage: json_type '{"a":1}' -> "object"
# Usage: json_type '[1,2]' -> "array"
# Usage: json_type '"str"' -> "string"
# Usage: json_type '123' -> "number"
# Usage: json_type 'true' -> "boolean"
# Usage: json_type 'null' -> "null"
# Returns: "object", "array", "string", "number", "boolean", or "null"
json_type() {
    local json="${1:-}"
    local path="${2:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_type_jq "$json" "$path" ;;
        python) _json_type_python "$json" "$path" ;;
        perl)   _json_type_perl "$json" "$path" ;;
    esac
}

# @@PUBLIC_API@@
# Get the length of a JSON array or object
# Usage: json_length '[1,2,3]' -> "3"
# Usage: json_length '{"a":1,"b":2}' -> "2"
# Returns: Length as number
json_length() {
    local json="${1:-}"
    local path="${2:-}"
    
    [[ -z "$json" ]] && return 1
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    case "$_JSON_IMPL" in
        jq)     _json_length_jq "$json" "$path" ;;
        python) _json_length_python "$json" "$path" ;;
        perl)   _json_length_perl "$json" "$path" ;;
    esac
}

# -----------------------------------------------------------------------------
# Public API - Convenience Functions
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Check if a path exists in JSON
# Usage: json_has '{"a":{"b":1}}' "a.b" -> returns 0 (exists)
# Usage: json_has '{"a":1}' "b" -> returns 1 (not found)
# Returns: 0 if path exists, 1 otherwise
json_has() {
    local json="${1:-}"
    local path="${2:-}"
    
    local result
    result=$(json_get "$json" "$path" 2>/dev/null)
    [[ -n "$result" && "$result" != "null" ]]
}

# @@PUBLIC_API@@
# Get value with default if not found
# Usage: json_get_or '{"a":1}' "b" "default" -> "default"
# Usage: json_get_or '{"a":1}' "a" "default" -> "1"
# Returns: Value at path or default
json_get_or() {
    local json="${1:-}"
    local path="${2:-}"
    local default="${3:-}"
    
    local result
    result=$(json_get "$json" "$path" 2>/dev/null)
    
    if [[ -n "$result" && "$result" != "null" ]]; then
        echo "$result"
    else
        echo "$default"
    fi
}

# @@PUBLIC_API@@
# Create a simple JSON object from key-value pairs
# Usage: json_object "key1" "value1" "key2" "value2" -> '{"key1":"value1","key2":"value2"}'
# Returns: JSON object
json_object() {
    local result="{"
    local first=1
    
    while [[ $# -ge 2 ]]; do
        local key="$1"
        local value="$2"
        shift 2
        
        [[ $first -eq 0 ]] && result+=","
        first=0
        
        # Escape special characters in value
        value="${value//\\/\\\\}"
        value="${value//\"/\\\"}"
        value="${value//$'\n'/\\n}"
        value="${value//$'\t'/\\t}"
        
        result+="\"${key}\":\"${value}\""
    done
    
    result+="}"
    echo "$result"
}

# @@PUBLIC_API@@
# Create a JSON array from values
# Usage: json_array "a" "b" "c" -> '["a","b","c"]'
# Returns: JSON array
json_array() {
    local result="["
    local first=1
    
    for value in "$@"; do
        [[ $first -eq 0 ]] && result+=","
        first=0
        
        # Escape special characters
        value="${value//\\/\\\\}"
        value="${value//\"/\\\"}"
        value="${value//$'\n'/\\n}"
        value="${value//$'\t'/\\t}"
        
        result+="\"${value}\""
    done
    
    result+="]"
    echo "$result"
}

# @@PUBLIC_API@@
# Merge two JSON objects (second overwrites first for conflicts)
# Usage: json_merge '{"a":1}' '{"b":2}' -> '{"a":1,"b":2}'
# Returns: Merged JSON object
json_merge() {
    local json1="${1:-\{\}}"
    local json2="${2:-\{\}}"
    
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    if [[ "$_JSON_IMPL" == "jq" ]]; then
        echo "$json1" | "${_TOOL_PATH[jq]}" -c ". * $json2" 2>/dev/null
    elif [[ "$_JSON_IMPL" == "python" ]]; then
        local python_cmd
        python_cmd=$(_json_python_cmd)
        "$python_cmd" -c "
import json
a = json.loads('''$json1''')
b = json.loads('''$json2''')
a.update(b)
print(json.dumps(a))
" 2>/dev/null
    else
        # Perl fallback
        "${_TOOL_PATH[perl]}" -MJSON::PP -e '
            my $a = decode_json($ARGV[0]);
            my $b = decode_json($ARGV[1]);
            @{$a}{keys %$b} = values %$b;
            print encode_json($a);
        ' "$json1" "$json2" 2>/dev/null
    fi
}

# @@PUBLIC_API@@
# Delete a key from JSON
# Usage: json_delete '{"a":1,"b":2}' "a" -> '{"b":2}'
# Returns: JSON with key removed
json_delete() {
    local json="${1:-}"
    local path="${2:-}"
    
    [[ "$_JSON_READY" != "1" ]] && { echo "$_JSON_ERROR" >&2; return 1; }
    
    if [[ "$path" != "."* ]]; then
        path=".${path}"
    fi
    
    if [[ "$_JSON_IMPL" == "jq" ]]; then
        echo "$json" | "${_TOOL_PATH[jq]}" "del($path)" 2>/dev/null
    elif [[ "$_JSON_IMPL" == "python" ]]; then
        local python_cmd
        python_cmd=$(_json_python_cmd)
        "$python_cmd" -c "
import json

data = json.loads('''$json''')
path = '${path#.}'

parts = [p for p in path.split('.') if p]
current = data
for part in parts[:-1]:
    if part.isdigit():
        current = current[int(part)]
    else:
        current = current[part]

last = parts[-1]
if last.isdigit():
    del current[int(last)]
else:
    del current[last]

print(json.dumps(data))
" 2>/dev/null
    else
        "${_TOOL_PATH[perl]}" -MJSON::PP -e '
            my $data = decode_json($ARGV[0]);
            my $path = $ARGV[1];
            $path =~ s/^\.//;
            
            my @parts = grep { $_ ne "" } split /\./, $path;
            my $current = $data;
            for my $i (0 .. $#parts - 1) {
                my $part = $parts[$i];
                if ($part =~ /^\d+$/) {
                    $current = $current->[$part];
                } else {
                    $current = $current->{$part};
                }
            }
            
            my $last = $parts[-1];
            if ($last =~ /^\d+$/) {
                splice @$current, $last, 1;
            } else {
                delete $current->{$last};
            }
            
            print encode_json($data);
        ' "$json" "$path" 2>/dev/null
    fi
}

# @@PUBLIC_API@@
# Read JSON from a file
# Usage: json_read "/path/to/file.json" -> prints JSON content
# Returns: JSON content of file
json_read() {
    local file="${1:-}"
    
    [[ ! -f "$file" ]] && { echo "File not found: $file" >&2; return 1; }
    
    cat "$file"
}

# @@PUBLIC_API@@
# Write JSON to a file (pretty printed)
# Usage: json_write '{"a":1}' "/path/to/file.json"
# Returns: 0 on success, 1 on failure
json_write() {
    local json="${1:-}"
    local file="${2:-}"
    
    [[ -z "$file" ]] && return 1
    
    json_pretty "$json" > "$file"
}

# -----------------------------------------------------------------------------
# Module Status Functions
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Check if JSON module is ready
# Usage: json_ready -> returns 0 if ready, 1 if not
json_ready() {
    [[ "$_JSON_READY" == "1" ]]
}

# @@PUBLIC_API@@
# Get JSON module error (if not ready)
# Usage: json_error -> prints error message
json_error() {
    echo "$_JSON_ERROR"
}

# @@PUBLIC_API@@
# Get which JSON implementation is being used
# Usage: json_impl -> "jq" | "python" | "perl" | ""
json_impl() {
    echo "$_JSON_IMPL"
}
