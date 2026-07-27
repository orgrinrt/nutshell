#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/json/impl/python.sh - JSON through python3 or python
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# One of three interchangeable backends behind `lib/json.sh`, which dispatches
# on `_JSON_IMPL`. Nothing here is called directly; the module's public
# functions pick a backend and forward.
#
# Sourced by json.sh when python3 or python is present. All available backends are loaded
# rather than only the selected one, so a caller (or a test) can move
# `_JSON_IMPL` and get the implementation it named.
# =============================================================================

nut_once || return 0

# `json.dumps` puts a space after every colon unless told not to, so this
# backend returned `{"a": 1}` where jq and perl returned `{"a":1}`. The same
# call gave different text depending on which tool happened to be installed,
# which is the failure a set of interchangeable backends exists to prevent.
# `separators` on every dump but the deliberately formatted one.

# Get python command (python3 preferred)
_json_python_cmd() {
    if deps_has "python3"; then
        echo "${_TOOL_PATH[python3]}"
    else
        echo "${_TOOL_PATH[python]}"
    fi
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
    print(json.dumps(current, separators=(',', ':'), sort_keys=True))
else:
    print(current if current is not None else 'null')
" 2>/dev/null
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

print(json.dumps(data, separators=(',', ':'), sort_keys=True))
" 2>/dev/null
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
    for k in sorted(current.keys()):
        print(k)
elif isinstance(current, list):
    for i in range(len(current)):
        print(i)
" 2>/dev/null
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

# Python implementation of json_pretty
_json_pretty_python() {
    local json="${1:-}"
    local python_cmd
    python_cmd=$(_json_python_cmd)
    
    "$python_cmd" -c "
import json
print(json.dumps(json.loads('''$json'''), indent=2, sort_keys=True))
" 2>/dev/null
}

# Python implementation of json_compact
_json_compact_python() {
    local json="${1:-}"
    local python_cmd
    python_cmd=$(_json_python_cmd)
    
    "$python_cmd" -c "
import json
print(json.dumps(json.loads('''$json'''), separators=(',', ':'), sort_keys=True))
" 2>/dev/null
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

_json_merge_python() {
    local json1="$1" json2="$2"
        local python_cmd
        python_cmd=$(_json_python_cmd)
        "$python_cmd" -c "
import json
a = json.loads('''$json1''')
b = json.loads('''$json2''')
a.update(b)
print(json.dumps(a, separators=(',', ':'), sort_keys=True))
" 2>/dev/null
}

_json_delete_python() {
    local json="$1" path="$2"
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

print(json.dumps(data, separators=(',', ':'), sort_keys=True))
" 2>/dev/null
}
