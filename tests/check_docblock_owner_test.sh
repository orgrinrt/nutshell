#!/usr/bin/env bash
# Tests for whether a docblock belongs to the function it landed on.
#
# Attributes attach downward, to the next definition. So a `#[pub]` block and
# its `Usage:` line, with a second function inserted underneath them, document
# that second function instead. Two things break at once and neither shows:
# the function the block was written for goes undocumented, and a private
# helper gets marked public.
#
# It was in every repository this gate runs on, four times, and the existing
# docs check reported the helper as documented because it was, by the block
# meant for somebody else.

use test

NUT_CHECK_LOAD_ONLY=1 . "${BASH_SOURCE[0]%/*}/../examples/checks/check_public_api_docs.sh"

# A file on disk, since the readers work over one, plus the docblock the check
# would have extracted for a given definition.
_dbo_file() {
    local f; f="$(mktemp "${TMPDIR:-/tmp}/nutshell-dbo.XXXXXX")"
    printf '%s' "$1" > "$f"
    printf '%s' "$f"
}

# Whether the block above <func> in <file> is orphaned, and from whom.
_orphan_of() {
    local file="$1" func="$2" block
    _pad_load "$file" || return 1
    get_function_docblock "$file" "$func" >/dev/null
    block="$PAD_DOCBLOCK"
    docblock_orphaned_from "$file" "$func" "$block"
}

#[test]
it_catches_a_block_the_next_definition_stole() {
    # The case that was actually shipped, four times, reduced.
    local f; f="$(_dbo_file '#!/usr/bin/env bash

#[pub]
# What the public one does.
# Usage: the_public_one -> prints a thing
# A private helper that got inserted underneath.
_the_helper() {
    printf helper
}

the_public_one() {
    _the_helper
}
')"
    assert_eq "$(_orphan_of "$f" "_the_helper")" "the_public_one"
    rm -f "$f"
}

#[test]
it_leaves_a_block_that_names_its_own_function_alone() {
    # The control. A detector that answered yes always would pass the test
    # above and fail every real file in the tree.
    local f; f="$(_dbo_file '#!/usr/bin/env bash

#[pub]
# What it does.
# Usage: the_public_one -> prints a thing
the_public_one() {
    printf thing
}

_the_helper() {
    printf helper
}
')"
    assert_fails _orphan_of "$f" "the_public_one"
    rm -f "$f"
}

#[test]
it_does_not_mistake_an_invocation_example_for_a_name() {
    # `Usage: exit "$(doctor_exit)"` names `exit`, which defines nothing here.
    # A detector matching the first token without checking it is defined
    # reports every such block, and this shape is all over the tree.
    local f; f="$(_dbo_file '#!/usr/bin/env bash

#[pub]
# An exit status for the whole run.
# Usage: exit "$(doctor_exit)"
doctor_exit() {
    printf 0
}
')"
    assert_fails _orphan_of "$f" "doctor_exit"
    rm -f "$f"
}

#[test]
it_does_not_flag_a_block_referring_back_to_something_above_it() {
    # Naming a function defined *earlier* is prose about a relationship, not a
    # block that slid down past its own definition. Only later counts.
    local f; f="$(_dbo_file '#!/usr/bin/env bash

first_one() {
    printf first
}

#[pub]
# Does the same as first_one, for the other shape.
# Usage: first_one
second_one() {
    printf second
}
')"
    assert_fails _orphan_of "$f" "second_one"
    rm -f "$f"
}

#[test]
it_does_not_flag_a_name_that_is_defined_nowhere() {
    # A `Usage:` naming something from another module is a cross reference. It
    # cannot be an orphan here, because there is nothing here to be orphaned
    # from.
    local f; f="$(_dbo_file '#!/usr/bin/env bash

#[pub]
# Wraps the thing from the other module.
# Usage: some_other_modules_function
the_wrapper() {
    printf wrapped
}
')"
    assert_fails _orphan_of "$f" "the_wrapper"
    rm -f "$f"
}

#[test]
it_reads_a_hyphenated_and_a_function_keyword_definition() {
    # Both spellings bash accepts. A detector that only knew `name()` would
    # report the block below as an orphan of a function it could not see was
    # defined.
    local f; f="$(_dbo_file '#!/usr/bin/env bash

#[pub]
# Usage: the_public_one -> prints a thing
_the_helper() {
    printf helper
}

function the_public_one {
    _the_helper
}
')"
    assert_eq "$(_orphan_of "$f" "_the_helper")" "the_public_one"
    rm -f "$f"
}

#[test]
it_finds_the_orphan_when_a_later_usage_line_is_the_right_one() {
    # A block can carry more than one `Usage:`. One matching the definition it
    # sits above means the block belongs here, whatever else it mentions.
    local f; f="$(_dbo_file '#!/usr/bin/env bash

#[pub]
# Usage: the_public_one -> the other form
# Usage: _the_helper -> this form
_the_helper() {
    printf helper
}

the_public_one() {
    _the_helper
}
')"
    assert_fails _orphan_of "$f" "_the_helper"
    rm -f "$f"
}
