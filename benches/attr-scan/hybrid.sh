#!/usr/bin/env bash
# The third arm: the new loop shape with the old regex predicates.
#
# It exists because the other two arms move two variables at once. One is the
# shipped implementation with the shipped loop, the other is `case` predicates
# with a restructured loop, and a comparison between them cannot say which of
# the two did the work. This holds the loop constant and swaps only the
# predicate, which is the arm that decides it.
#
# Only `attr_find` is here, because that is the whole workload. It is a copy of
# the new loop with `[[ =~ ]]` where the new one calls `_attr_is_attr_t`,
# `_attr_name_set_t` and `_attr_defines_set_t`, and nothing else changed.

ATTR_PATTERN='^[[:space:]]*#\[[a-z_][a-z0-9_]*(\(.*\))?\][[:space:]]*$'
ATTR_DEFINES_PATTERN='^[[:space:]]*(function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*)|([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*\(\))'

attr_find() {
    local file="$1" want="$2"
    local line pending=0 t name defines

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            [![:space:]]*) t="$line" ;;
            *) t="${line#"${line%%[![:space:]]*}"}" ;;
        esac

        case "$t" in
            '') continue ;;
            '#['*)
                if [[ "$t" =~ $ATTR_PATTERN ]]; then
                    name=""
                    [[ "$t" =~ ^[[:space:]]*#\[([a-zA-Z_][a-zA-Z0-9_]*) ]] \
                        && name="${BASH_REMATCH[1]}"
                    [ "$name" = "$want" ] && pending=1
                fi
                continue ;;
            '#'*) continue ;;
        esac

        defines=""
        [[ "$t" =~ $ATTR_DEFINES_PATTERN ]] \
            && defines="${BASH_REMATCH[2]:-${BASH_REMATCH[3]}}"
        if [ -n "$defines" ]; then
            [ "$pending" -eq 1 ] && printf '%s\n' "$defines"
            pending=0
            continue
        fi

        pending=0
    done < "$file"
}
