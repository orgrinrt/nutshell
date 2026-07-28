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
# Sourced by json.sh when python3 or python is present. All available backends
# are loaded rather than only the selected one, so a caller (or a test) can
# move `_JSON_IMPL` and get the implementation it named.
#
# One program, read from stdin, taking the operation and its arguments on argv.
#
# Every function here used to build its own program by interpolating the
# document into the source text between triple quotes. That is code injection,
# and it was also simply broken: a document containing a quote produced a
# python syntax error, so `json_get '{"a":"he said \"hi\""}' a` returned
# nothing at all. Arguments on argv cannot be read as source.
#
# Output follows the contract at the top of json.sh: documents compact with
# sorted keys, text left as UTF-8, scalars spelled as JSON rather than as
# python. The last is not a detail. `print(value)` gave `True` where jq gave
# `true` and `None` where the others gave `null`, so what a caller had to
# compare against depended on which tool happened to be installed.
# =============================================================================

nut_once || return 0

# Get python command (python3 preferred)
_json_python_cmd() {
    if deps_has "python3"; then
        echo "${_TOOL_PATH[python3]}"
    else
        echo "${_TOOL_PATH[python]}"
    fi
}

# _json_py <operation> <arguments...>
#
# `-` as the program path means "read the program from stdin", which keeps the
# program and the document on separate channels.
_json_py() {
    local python_cmd
    python_cmd="$(_json_python_cmd)"
    "$python_cmd" - "$@" <<'PYTHON' 2>/dev/null
import json
import sys

op = sys.argv[1]
args = sys.argv[2:]


def dump(value):
    return json.dumps(value, separators=(",", ":"), sort_keys=True,
                      ensure_ascii=False)


def emit(value):
    if isinstance(value, (dict, list)):
        print(dump(value))
    elif value is None:
        print("null")
    elif value is True:
        print("true")
    elif value is False:
        print("false")
    elif isinstance(value, str):
        # Bare, the way jq -r gives it, so a string is usable as a shell value
        # without stripping quotes off it first.
        print(value)
    else:
        print(json.dumps(value))


def walk(data, path):
    """Follow a dotted path.

    Raises when the path does not lead anywhere, which the caller turns into a
    status of 1: an absent key is absent, and answering `null` cannot be told
    apart from a key that is present and holds null.
    """
    for part in path.split("."):
        if not part:
            continue
        if isinstance(data, list):
            data = data[int(part)]
        else:
            data = data[part]
    return data


def kind(value):
    if value is None:
        return "null"
    if value is True or value is False:
        return "boolean"
    if isinstance(value, dict):
        return "object"
    if isinstance(value, list):
        return "array"
    if isinstance(value, str):
        return "string"
    return "number"


def parent_and_last(data, path):
    parts = [p for p in path.split(".") if p]
    current = data
    for part in parts[:-1]:
        current = current[int(part)] if isinstance(current, list) else current[part]
    return current, parts[-1]


def main():
    if op == "valid":
        json.loads(args[0])
        return 0

    data = json.loads(args[0])
    path = args[1] if len(args) > 1 else ""

    if op == "get":
        emit(walk(data, path))
    elif op == "keys":
        target = walk(data, path)
        if isinstance(target, dict):
            for k in sorted(target.keys()):
                print(k)
        elif isinstance(target, list):
            for i in range(len(target)):
                print(i)
    elif op == "type":
        print(kind(walk(data, path)))
    elif op == "length":
        print(len(walk(data, path)))
    elif op == "pretty":
        print(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False))
    elif op == "compact":
        print(dump(data))
    elif op == "set":
        current, last = parent_and_last(data, path)
        raw = args[2]
        try:
            value = json.loads(raw)
        except ValueError:
            value = raw
        if isinstance(current, list):
            current[int(last)] = value
        else:
            current[last] = value
        print(dump(data))
    elif op == "delete":
        current, last = parent_and_last(data, path)
        if isinstance(current, list):
            del current[int(last)]
        else:
            del current[last]
        print(dump(data))
    elif op == "merge":
        # Shallow, and deliberately. jq's `*` recurses into objects where this
        # replaces them, so one call built a different document depending on
        # the tool; the contract is that the right operand replaces a key
        # rather than merging into it.
        data.update(json.loads(args[1]))
        print(dump(data))
    else:
        return 2
    return 0


try:
    sys.exit(main())
except (KeyError, IndexError, TypeError, ValueError):
    sys.exit(1)
PYTHON
}

_json_get_python()     { _json_py get "$1" "${2:-}"; }
_json_set_python()     { _json_py set "$1" "$2" "$3"; }
_json_keys_python()    { _json_py keys "$1" "${2:-}"; }
_json_valid_python()   { _json_py valid "$1"; }
_json_pretty_python()  { _json_py pretty "$1"; }
_json_compact_python() { _json_py compact "$1"; }
_json_type_python()    { _json_py type "$1" "${2:-}"; }
_json_length_python()  { _json_py length "$1" "${2:-}"; }
_json_merge_python()   { _json_py merge "$1" "$2"; }
_json_delete_python()  { _json_py delete "$1" "$2"; }
