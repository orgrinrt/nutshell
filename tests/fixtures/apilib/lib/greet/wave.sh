#!/usr/bin/env bash
# greet::wave - internal in lib.nut and loaded by greet, so what it marks pub is
# greet's to list.

#[pub]
# Usage: greet_wave <name> -> prints a wave
greet_wave() { printf 'o/ %s\n' "$1"; }

_greet_wave_private() { :; }
