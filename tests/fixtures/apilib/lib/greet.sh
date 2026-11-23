#!/usr/bin/env bash
# greet - a fixture module with two public functions written out of order, one
# public function with no usage line, and one private function, and loads
# an internal module whose public function it lists as its own.

use super::greet::wave

#[pub]
# Usage: greet_zulu <name> -> prints a farewell
greet_zulu() { printf 'bye %s\n' "$1"; }

#[pub]
# Some prose between the attribute and the usage line, as a doc comment has.
# Usage: greet_alpha <name> -> prints a greeting
greet_alpha() { printf 'hello %s\n' "$1"; }

#[pub]
greet_bare() { :; }

_greet_private() { :; }
