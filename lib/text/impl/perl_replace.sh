#!/usr/bin/env bash
# =============================================================================
# nutshell/core/text/impl/perl_replace.sh - perl implementation for text_replace
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# This file provides the perl-based implementation of text_replace.
# When sourced, it REPLACES the stub in text.sh with the real function.
# Can also be executed directly for standalone use/testing.
#
# Perl is often preferred for complex regex patterns since it has
# consistent behavior across platforms (unlike BSD vs GNU sed).
# =============================================================================

# Implementation function (internal)
_text_replace_perl_impl() {
    local pattern="${1:-}"
    local replacement="${2:-}"
    local file="${3:-}"
    
    [ -z "$pattern" ] && return 1
    [ ! -f "$file" ] && return 1
    
    local perl_path="${_TOOL_PATH_perl:-perl}"
    
    # perl -i does in-place editing consistently across platforms
    # -p reads input line by line and prints after each line
    "$perl_path" -i -pe "s/${pattern}/${replacement}/g" "$file"
}

# Sourced, always: the resolver is the only thing that opens this file, and it
# sources it. The `if [[ "${BASH_SOURCE[0]}" != "${0}" ]]` this replaces asked
# whether that was so, which is a question with one answer and a bad
# substitution under a POSIX shell, where there is no `BASH_SOURCE` to
# subscript.
text_replace() {
    _text_replace_perl_impl "$@"
}
