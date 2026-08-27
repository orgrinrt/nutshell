#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/json/impl/perl.sh - JSON through perl
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# One of three interchangeable backends behind `lib/json.sh`, which dispatches
# on `_JSON_IMPL`. Nothing here is called directly; the module's public
# functions pick a backend and forward.
#
# Sourced by json.sh when perl is present. All available backends are loaded
# rather than only the selected one, so a caller (or a test) can move
# `_JSON_IMPL` and get the implementation it named.
#
# The last resort of the three, and the one whose defaults fight the contract
# hardest. Three of them, each of which made this backend answer differently
# from the others:
#
#   - a hash has no order and its iteration order is randomised per process, so
#     `canonical` is not a nicety here, it is the only way two runs agree
#   - `encode_json` returns a character string, and printing it to a stream
#     with no encoding layer produced mojibake for anything outside ASCII
#   - a JSON boolean is an object that stringifies to 1 and the empty string,
#     so `true` came back as `1` and `false` as `0`
#
# One program, taking the operation and its arguments on argv.
# =============================================================================

# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and uses
# `printf -v`. A file on the floor cannot ask a bash-only function whether it
# has been loaded: under a POSIX shell `nut_once` is not found, the `|| return
# 0` returns from the whole file, and the module then defines nothing while
# reporting success.
[ -n "${_NUTSHELL_JSON_IMPL_PERL_SH:-}" ] && return 0
_NUTSHELL_JSON_IMPL_PERL_SH=1

# _json_pl <operation> <arguments...>
_json_pl() {
    "${_TOOL_PATH_perl}" -MJSON::PP -e '
        use strict;
        use warnings;

        # UTF-8 out. Without it a character string is written byte by byte and
        # anything outside ASCII arrives mangled.
        binmode(STDOUT, ":encoding(UTF-8)");

        # Two coders, because the two directions see different things. What
        # arrives on argv is UTF-8 bytes, so the decoder is told so and hands
        # back characters; the encoder then produces characters, which the
        # output layer encodes once. One coder for both double-encoded: `café`
        # came back as `cafÃ©`, the UTF-8 bytes read as latin-1 and encoded
        # again.
        my $in    = JSON::PP->new->utf8->allow_nonref;
        my $coder = JSON::PP->new->canonical->allow_nonref;

        my ($op, @args) = @ARGV;

        # Walk a dotted path. Returns (found, value) so an absent key is told
        # apart from one present and holding null, which the caller turns into
        # a status. Answering "null" for both is what the other two backends
        # were made to stop doing.
        sub walk {
            my ($data, $path) = @_;
            for my $part (grep { $_ ne "" } split /\./, $path) {
                if (ref($data) eq "ARRAY") {
                    return (0, undef) unless $part =~ /^\d+$/ && $part < scalar(@$data);
                    $data = $data->[$part];
                } elsif (ref($data) eq "HASH") {
                    return (0, undef) unless exists $data->{$part};
                    $data = $data->{$part};
                } else {
                    return (0, undef);
                }
            }
            return (1, $data);
        }

        sub kind {
            my ($v) = @_;
            return "null"    unless defined $v;
            return "boolean" if JSON::PP::is_bool($v);
            return "object"  if ref($v) eq "HASH";
            return "array"   if ref($v) eq "ARRAY";
            # A scalar that has been used as a number is one. Perl does not
            # otherwise distinguish, and the document said which it was.
            return "number"  if $v =~ /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?$/;
            return "string";
        }

        sub emit {
            my ($v) = @_;
            if (!defined $v)                { print "null\n"; }
            elsif (JSON::PP::is_bool($v))   { print($v ? "true\n" : "false\n"); }
            elsif (ref($v))                 { print $coder->encode($v), "\n"; }
            elsif (kind($v) eq "number")    { print "$v\n"; }
            else                            { print "$v\n"; }
        }

        if ($op eq "valid") {
            eval { $in->decode($args[0]); 1 } or exit 1;
            exit 0;
        }

        my $data = eval { $in->decode($args[0]) };
        exit 1 unless defined $data || !$@;
        exit 1 if $@;

        my $path = defined $args[1] ? $args[1] : "";

        if ($op eq "get") {
            my ($found, $v) = walk($data, $path);
            exit 1 unless $found;
            emit($v);
        } elsif ($op eq "keys") {
            my ($found, $v) = walk($data, $path);
            exit 1 unless $found;
            if (ref($v) eq "HASH")     { print "$_\n" for sort keys %$v; }
            elsif (ref($v) eq "ARRAY") { print "$_\n" for 0 .. $#$v; }
        } elsif ($op eq "type") {
            my ($found, $v) = walk($data, $path);
            exit 1 unless $found;
            print kind($v), "\n";
        } elsif ($op eq "length") {
            my ($found, $v) = walk($data, $path);
            exit 1 unless $found;
            if (ref($v) eq "ARRAY")   { print scalar(@$v), "\n"; }
            elsif (ref($v) eq "HASH") { print scalar(keys %$v), "\n"; }
            else                      { print length($v), "\n"; }
        } elsif ($op eq "pretty") {
            print JSON::PP->new->canonical->pretty->encode($data);
        } elsif ($op eq "compact") {
            print $coder->encode($data), "\n";
        } elsif ($op eq "set" || $op eq "delete") {
            my @parts = grep { $_ ne "" } split /\./, $path;
            exit 1 unless @parts;
            my $last = pop @parts;
            my $current = $data;
            for my $part (@parts) {
                if (ref($current) eq "ARRAY") { $current = $current->[$part]; }
                else                          { $current = $current->{$part}; }
            }
            if ($op eq "set") {
                my $raw = $args[2];
                my $value = eval { $in->decode($raw) };
                $value = $raw if $@;
                if (ref($current) eq "ARRAY") { $current->[$last] = $value; }
                else                          { $current->{$last} = $value; }
            } else {
                if (ref($current) eq "ARRAY") { splice(@$current, $last, 1); }
                else                          { delete $current->{$last}; }
            }
            print $coder->encode($data), "\n";
        } elsif ($op eq "merge") {
            my $other = $in->decode($args[1]);
            # Shallow, matching the other two: the right operand replaces a key
            # rather than merging into it.
            @{$data}{keys %$other} = values %$other;
            print $coder->encode($data), "\n";
        } else {
            exit 2;
        }
        exit 0;
    ' "$@" 2>/dev/null
}

_json_get_perl()     { _json_pl get "$1" "${2:-}"; }
_json_set_perl()     { _json_pl set "$1" "$2" "$3"; }
_json_keys_perl()    { _json_pl keys "$1" "${2:-}"; }
_json_valid_perl()   { _json_pl valid "$1"; }
_json_pretty_perl()  { _json_pl pretty "$1"; }
_json_compact_perl() { _json_pl compact "$1"; }
_json_type_perl()    { _json_pl type "$1" "${2:-}"; }
_json_length_perl()  { _json_pl length "$1" "${2:-}"; }
_json_merge_perl()   { _json_pl merge "$1" "$2"; }
_json_delete_perl()  { _json_pl delete "$1" "$2"; }
