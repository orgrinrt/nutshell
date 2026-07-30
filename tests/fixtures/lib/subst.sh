use alpha

# Reaches into alpha only through process substitution, which the call scanner
# did not split on, so this module looked like it called nothing at all.
subst_reader() {
    local line
    while IFS= read -r line; do
        printf '%s\n' "$line"
    done < <(alpha_public)
}
