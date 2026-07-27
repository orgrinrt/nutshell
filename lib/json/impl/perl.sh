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
# =============================================================================

nut_once || return 0

# Perl implementation of json_get
_json_get_perl() {
    local json="${1:-}"
    local path="${2:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        my $json_text = $ARGV[0];
        my $path = $ARGV[1];
        
        my $data = decode_json($json_text);
        
        for my $part (split /\./, $path) {
            next if $part eq "";
            if ($part =~ /^\d+$/) {
                $data = $data->[$part];
            } else {
                $data = $data->{$part};
            }
        }
        
        if (ref($data) eq "HASH" || ref($data) eq "ARRAY") {
            print JSON::PP->new->canonical->encode($data);
        } elsif (defined $data) {
            print $data;
        } else {
            print "null";
        }
    ' "$json" "$path" 2>/dev/null
}

# Perl implementation of json_set
_json_set_perl() {
    local json="${1:-}"
    local path="${2:-}"
    local value="${3:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        my $json_text = $ARGV[0];
        my $path = $ARGV[1];
        my $value_str = $ARGV[2];
        
        my $data = decode_json($json_text);
        
        # Parse value
        my $value;
        eval { $value = decode_json($value_str); };
        $value = $value_str if $@;
        
        # Navigate to parent
        my @parts = grep { $_ ne "" } split /\./, $path;
        my $current = $data;
        for my $i (0 .. $#parts - 1) {
            my $part = $parts[$i];
            if ($part =~ /^\d+$/) {
                $current = $current->[$part];
            } else {
                $current = $current->{$part};
            }
        }
        
        # Set value
        my $last = $parts[-1];
        if ($last =~ /^\d+$/) {
            $current->[$last] = $value;
        } else {
            $current->{$last} = $value;
        }
        
        print JSON::PP->new->canonical->encode($data);
    ' "$json" "$path" "$value" 2>/dev/null
}

# Perl implementation of json_keys
_json_keys_perl() {
    local json="${1:-}"
    local path="${2:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        my $json_text = $ARGV[0];
        my $path = $ARGV[1];
        
        my $data = decode_json($json_text);
        
        for my $part (split /\./, $path) {
            next if $part eq "";
            if ($part =~ /^\d+$/) {
                $data = $data->[$part];
            } else {
                $data = $data->{$part};
            }
        }
        
        if (ref($data) eq "HASH") {
            # Sorted. A perl hash has no order, and its iteration order is
            # randomised per process, so this returned the same keys in a
            # different order on every run while jq and python were stable.
            print "$_\n" for sort keys %$data;
        } elsif (ref($data) eq "ARRAY") {
            print "$_\n" for 0 .. $#$data;
        }
    ' "$json" "$path" 2>/dev/null
}

# Perl implementation of json_valid
_json_valid_perl() {
    local json="${1:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        eval { decode_json($ARGV[0]); };
        exit($@ ? 1 : 0);
    ' "$json" 2>/dev/null
}

# Perl implementation of json_pretty
_json_pretty_perl() {
    local json="${1:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        my $coder = JSON::PP->new->pretty->canonical;
        print $coder->encode(decode_json($ARGV[0]));
    ' "$json" 2>/dev/null
}

# Perl implementation of json_compact
_json_compact_perl() {
    local json="${1:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        print JSON::PP->new->canonical->encode(decode_json($ARGV[0]));
    ' "$json" 2>/dev/null
}

# Perl implementation of json_type
_json_type_perl() {
    local json="${1:-}"
    local path="${2:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        my $json_text = $ARGV[0];
        my $path = $ARGV[1];
        
        my $data = decode_json($json_text);
        
        for my $part (split /\./, $path) {
            next if $part eq "";
            if ($part =~ /^\d+$/) {
                $data = $data->[$part];
            } else {
                $data = $data->{$part};
            }
        }
        
        my $ref = ref($data);
        if ($ref eq "HASH") { print "object"; }
        elsif ($ref eq "ARRAY") { print "array"; }
        elsif (!defined $data) { print "null"; }
        elsif (JSON::PP::is_bool($data)) { print "boolean"; }
        elsif ($data =~ /^-?\d+(\.\d+)?$/) { print "number"; }
        else { print "string"; }
    ' "$json" "$path" 2>/dev/null
}

# Perl implementation of json_length
_json_length_perl() {
    local json="${1:-}"
    local path="${2:-}"
    
    "${_TOOL_PATH[perl]}" -MJSON::PP -e '
        my $json_text = $ARGV[0];
        my $path = $ARGV[1];
        
        my $data = decode_json($json_text);
        
        for my $part (split /\./, $path) {
            next if $part eq "";
            if ($part =~ /^\d+$/) {
                $data = $data->[$part];
            } else {
                $data = $data->{$part};
            }
        }
        
        if (ref($data) eq "HASH") { print scalar keys %$data; }
        elsif (ref($data) eq "ARRAY") { print scalar @$data; }
        elsif (defined $data) { print length($data); }
        else { print 0; }
    ' "$json" "$path" 2>/dev/null
}

_json_merge_perl() {
    local json1="$1" json2="$2"
        # Perl fallback
        "${_TOOL_PATH[perl]}" -MJSON::PP -e '
            my $a = decode_json($ARGV[0]);
            my $b = decode_json($ARGV[1]);
            @{$a}{keys %$b} = values %$b;
            print JSON::PP->new->canonical->encode($a);
        ' "$json1" "$json2" 2>/dev/null
}

_json_delete_perl() {
    local json="$1" path="$2"
        "${_TOOL_PATH[perl]}" -MJSON::PP -e '
            my $data = decode_json($ARGV[0]);
            my $path = $ARGV[1];
            $path =~ s/^\.//;
            
            my @parts = grep { $_ ne "" } split /\./, $path;
            my $current = $data;
            for my $i (0 .. $#parts - 1) {
                my $part = $parts[$i];
                if ($part =~ /^\d+$/) {
                    $current = $current->[$part];
                } else {
                    $current = $current->{$part};
                }
            }
            
            my $last = $parts[-1];
            if ($last =~ /^\d+$/) {
                splice @$current, $last, 1;
            } else {
                delete $current->{$last};
            }
            
            print JSON::PP->new->canonical->encode($data);
        ' "$json" "$path" 2>/dev/null
}
