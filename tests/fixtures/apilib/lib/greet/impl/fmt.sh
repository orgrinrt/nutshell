#!/usr/bin/env bash
# greet::impl::fmt - internal in lib.nut and loaded by nothing, so never listed
# even with a pub marker.

#[pub]
# Usage: fmt_hidden -> must never appear in a listing
fmt_hidden() { :; }
