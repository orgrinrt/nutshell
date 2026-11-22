#!/usr/bin/env bash
# A fixture for attr_usage. Not run, only read.

# Usage: header_example -> the module header's own line, never a function's
#
# Usage:
#   use usage

#[pub]
# Usage: after_attr <a> -> usage written after the attribute
after_attr() { :; }

# Usage: before_attr <a> -> usage written before the attribute
#[pub]
before_attr() { :; }

#[pub]
# Some prose that is not the usage line.
# Usage: with_prose <a> -> prose sits above it
# More prose below it.
with_prose() { :; }

#[pub]
# Usage: two_forms <a> -> the first form
# Usage: two_forms <a> <b> -> the second form
two_forms() { :; }

#[pub]
no_usage() { :; }

# Usage: detached -> a blank line separates this from the definition

detached() { :; }

# Usage: after_code -> real code between the comment and the definition
x=1
after_code() { :; }

function keyword_form {
    # Usage: inside_the_body -> a comment in a body belongs to nothing
    :
}

# Usage:
undefined_text() { :; }
