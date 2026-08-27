# A slice of real work, run identically by every arm.
#
# The arms load the library three different ways and this is what says they
# still do the same thing. It has to touch enough of the surface that a shaker
# dropping something needed shows up here rather than in a later run: strings,
# the filesystem, a toml read, validation and the log.
_wl() {
    local d f out=""
    d="$(fs_temp_dir wl)" || return 1
    f="$d/x.toml"
    printf 'name = "thing"\n[sec]\nkey = "v"\n' > "$f"

    out+="$(str_upper "$(str_trim "  hello  ")")|"
    out+="$(str_replace 'a*b' '*' '+')|"
    out+="$(str_join , a b c)|"
    out+="$(str_distance build buidl)|"
    out+="$(toml_get "$f" name)|"
    out+="$(toml_get "$f" sec.key)|"
    out+="$(fs_basename "$f")|"
    out+="$(fs_extension "$f")|"
    out+="$([ -n "$(fs_size "$f")" ] && echo sized)|"
    out+="$(is_integer 42 && echo int)|"
    out+="$(is_email a@b.c && echo mail)|"
    out+="$(os_name)|"
    rm -rf "$d"
    printf '%s' "$out"
}
