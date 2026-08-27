#!/usr/bin/env nutshell
# =============================================================================
# check_function_duplication.sh - Function Duplication Detection Check
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Gathers ALL function names from all .sh files, then performs fuzzy matching
# to detect potential duplications.
#
# FULLY CONFIG-DRIVEN: All thresholds and patterns come from nut.toml.
# See examples/configs/empty.nut.toml for all available options.
#
# Two modes of comparison:
#   1. Full function names - detects exact or near-exact duplicates (can fail)
#   2. Stripped prefixes - compares functions after removing the first word
#      before underscore (e.g., git_check_valid -> check_valid)
#      NOTE: Stripped comparison only WARNS, never fails, since identical
#      stripped names are often intentional API patterns (e.g., *_init, *_debug)
#
# Usage: ./examples/checks/check_function_duplication.sh
#
# Exit codes:
#   0 - All checks passed (may have warnings)
#   1 - One or more errors found, or test disabled
# =============================================================================

set -uo pipefail

# Load the check-runner framework (provides cfg_*, log_*, etc.)
use check-runner

# =============================================================================
# CONFIG-DRIVEN PARAMETERS
# =============================================================================

# Thresholds (will be loaded from config)
SIMILARITY_THRESHOLD="0.85"
MIN_LINES_TO_CHECK="3"

# Arrays for patterns
declare -a IGNORE_NAME_PATTERNS=()
declare -a EXCLUDE_PATTERNS=()

# Minimum function name length to consider for comparison
MIN_NAME_LENGTH=4

load_config() {
    # Check if test is enabled
    if ! cfg_is_true "tests.function_duplication"; then
        log_info "Function duplication test is disabled in config"
        exit 0
    fi
    
    # Load thresholds from config
    SIMILARITY_THRESHOLD="$(cfg_get_or "tests.function_duplication.similarity_threshold" "0.85")"
    MIN_LINES_TO_CHECK="$(cfg_get_or "tests.function_duplication.min_lines_to_check" "3")"
    
    # Load ignore patterns
    cfg_get_array "tests.function_duplication.ignore_name_patterns" IGNORE_NAME_PATTERNS || IGNORE_NAME_PATTERNS=()
    
    # Load exclude patterns
    cfg_get_array "tests.function_duplication.exclude_patterns" EXCLUDE_PATTERNS || EXCLUDE_PATTERNS=()
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Check if a path matches any exclude pattern
is_excluded_path() {
    local path="$1"
    
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ "$path" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

# Check if a function name matches any ignore pattern
is_ignored_name() {
    local name="$1"
    
    for pattern in "${IGNORE_NAME_PATTERNS[@]}"; do
        if echo "$name" | grep -qE "$pattern"; then
            return 0
        fi
    done
    return 1
}

# Collect all function names with their source files
# Output format: "function_name|file_path"
collect_all_functions() {
    local files
    files=$(get_script_files)
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        
        local rel_path="${file#$REPO_ROOT/}"
        
        # Check if this file is excluded
        if is_excluded_path "$rel_path"; then
            continue
        fi
        
        local functions
        functions=$(extract_functions "$file")
        
        while IFS= read -r func; do
            [[ -z "$func" ]] && continue
            
            # Skip short names
            if [[ ${#func} -lt $MIN_NAME_LENGTH ]]; then
                continue
            fi
            
            # Skip ignored names
            if is_ignored_name "$func"; then
                continue
            fi
            
            echo "${func}|${rel_path}"
        done <<< "$functions"
    done <<< "$files"
}

# =============================================================================
# OPTIMIZED COMPARISON - Single AWK pass for all comparisons
# =============================================================================

# Run full name comparison using optimized awk
# Returns lines in format: "FAIL|score|name1|name2|file1|file2" or "WARN|..."
# Every pair of files that are two spellings of one module, as `a>b`, so the
# comparison can skip a perfect score between them. Read from the manifest
# rather than named here, because a list here is a second place to update.
_variant_pairs() {
    local root="${REPO_ROOT:-$PWD}" name file rest word
    local -A owner=()
    [[ -r "${root}/lib.nut" ]] || return 0
    while read -r name file rest || [[ -n "$name" ]]; do
        [[ -z "$name" || "${name:0:1}" == "#" ]] && continue
        [[ -n "$file" ]] || continue
        if [[ -n "${owner[$name]:-}" ]]; then
            local prior
            for prior in ${owner[$name]}; do
                # Relative, as written in the manifest, because that is the
                # shape `collect_all_functions` produces. Emitted absolute
                # first, and nothing ever matched: the skip was proved on
                # hand-made absolute input and never once fired on the real
                # data, which is the whole reason a test builds its own input
                # carefully and then proves nothing.
                printf '%s>%s ' "$prior" "$file"
            done
        fi
        owner["$name"]="${owner[$name]:-} $file"
    done < "${root}/lib.nut"
}

# Computed once. There are two comparisons in this file and the second is the
# one that reported the variants: set inside the first, the second never saw it.
declare -g _NUT_DUP_VARIANTS=""
_variants_once() {
    [[ -n "${_NUT_DUP_VARIANTS_DONE:-}" ]] && return 0
    _NUT_DUP_VARIANTS="$(_variant_pairs)"
    _NUT_DUP_VARIANTS_DONE=1
}

# The list to use: whatever the caller set, else the manifest's.
#
# A caller passing its own used to be overwritten by the manifest's, which made
# the comparison untestable against anything but this repository.
_variants_for() {
    if [[ -n "${NUT_DUP_VARIANTS+x}" ]]; then printf '%s' "$NUT_DUP_VARIANTS"; return 0; fi
    _variants_once
    printf '%s' "$_NUT_DUP_VARIANTS"
}

compare_full_names() {
    local func_data="$1"
    local threshold="$2"
    local NUT_DUP_VARIANTS; NUT_DUP_VARIANTS="$(_variants_for)"
    
    echo "$func_data" | awk -F'|' -v threshold="$threshold" -v variants="${NUT_DUP_VARIANTS:-}" '
    # Levenshtein distance, abandoned as soon as it cannot matter.
    #
    # `maxd` is the largest distance the caller could still accept. Past that
    # the exact number is not wanted, so the row is checked and the whole thing
    # abandoned rather than filled in: the answer only has to be "more than
    # maxd", and returning maxd+1 says that.
    #
    # It matters because this is the whole cost of the check. 440 names is
    # about 96,000 pairs, and the length prune below leaves most of them, each
    # paying a full matrix. At the default threshold of 0.85 a twenty-character
    # name accepts three edits, so three rows of no hope is the answer and the
    # remaining seventeen were being computed for nothing.
    #
    # One row is kept rather than the matrix. Nothing reads the interior, and
    # an awk associative array of len1*len2 cells per pair was most of the
    # memory traffic.
    function levenshtein(s1, s2, maxd,    len1, len2, i, j, c1, cost, prev, cur, best, subst) {
        len1 = length(s1)
        len2 = length(s2)

        if (s1 == s2) return 0
        if (len1 == 0) return len2
        if (len2 == 0) return len1
        if (maxd == "") maxd = len1 + len2
        # A difference in length is already that many edits.
        if (len1 - len2 > maxd || len2 - len1 > maxd) return maxd + 1

        for (j = 0; j <= len2; j++) prev[j] = j

        for (i = 1; i <= len1; i++) {
            c1 = substr(s1, i, 1)
            cur[0] = i
            best = cur[0]
            for (j = 1; j <= len2; j++) {
                cost = (c1 == substr(s2, j, 1)) ? 0 : 1
                subst = prev[j-1] + cost
                cur[j] = prev[j] + 1
                if (cur[j-1] + 1 < cur[j]) cur[j] = cur[j-1] + 1
                if (subst < cur[j]) cur[j] = subst
                if (cur[j] < best) best = cur[j]
            }
            # Every path through this row already costs more than the caller
            # can accept, and a row only ever grows.
            if (best > maxd) return maxd + 1
            for (j = 0; j <= len2; j++) prev[j] = cur[j]
        }
        return prev[len2]
    }

    # Quick check: can these strings possibly have similarity >= threshold?
    function can_meet_threshold(s1, s2, threshold,    len1, len2, maxlen, minlen) {
        len1 = length(s1)
        len2 = length(s2)
        maxlen = (len1 > len2) ? len1 : len2
        minlen = (len1 < len2) ? len1 : len2
        if (maxlen == 0) return 1
        return ((minlen / maxlen) >= threshold)
    }
    
    function similarity(s1, s2, threshold,    len1, len2, maxlen, dist, maxd) {
        len1 = length(s1)
        len2 = length(s2)
        maxlen = (len1 > len2) ? len1 : len2
        if (maxlen == 0) return 1.0
        # The largest distance that could still clear the threshold. Anything
        # past it is rejected either way, so it does not have to be counted.
        maxd = int(maxlen * (1.0 - threshold))
        dist = levenshtein(s1, s2, maxd)
        if (dist > maxd) return 0.0
        return 1.0 - (dist / maxlen)
    }
    
    BEGIN {
        # Files that are two spellings of one module, as `a>b` pairs.
        #
        # A module carrying a `when=` row is written twice, once for bash and
        # once for POSIX sh, and the two hold the same function names on
        # purpose. Every one of those is a perfect score and none of them is a
        # copy: only one is ever sourced.
        n = split(variants, vs, " ")
        for (k = 1; k <= n; k++) is_variant_pair[vs[k]] = 1
    }

    function are_variants(a, b) {
        return (is_variant_pair[a ">" b] || is_variant_pair[b ">" a])
    }

    {
        names[NR] = $1
        files[NR] = $2
        count = NR
    }
    
    # The part after the module prefix, which is where two functions in one
    # family actually differ.
    function tail_of(name,    t) {
        t = name
        if (substr(t, 1, 1) == "_") t = substr(t, 2)
        if (index(t, "_") > 0) t = substr(t, index(t, "_") + 1)
        return t
    }

    # Do two names share the word the module is called?
    function same_prefix(a, b,    pa, pb) {
        pa = (substr(a, 1, 1) == "_") ? substr(a, 2) : a
        pb = (substr(b, 1, 1) == "_") ? substr(b, 2) : b
        if (index(pa, "_") == 0 || index(pb, "_") == 0) return 0
        return substr(pa, 1, index(pa, "_")) == substr(pb, 1, index(pb, "_"))
    }

    END {
        # Compare each pair (only once, i < j)
        for (i = 1; i < count; i++) {
            for (j = i + 1; j <= count; j++) {
                # Skip if same file
                if (files[i] == files[j]) continue
                
                # Early exit: if lengths are too different, skip expensive Levenshtein
                if (!can_meet_threshold(names[i], names[j], threshold)) continue
                
                score = similarity(names[i], names[j], threshold)
                
                if (score < threshold) continue

                # A module split across files keeps its prefix in every name,
                # and a long shared prefix carries the score on its own:
                # `toml_get` and `toml_set` come out at 0.875 while naming two
                # opposite operations. So a match that survives only because of
                # the prefix is an artefact of the naming convention, not a
                # copy. What the two names do has to look alike as well.
                if (same_prefix(names[i], names[j])) {
                    t1 = tail_of(names[i]); t2 = tail_of(names[j])
                    if (length(t1) > 0 && length(t2) > 0) {
                        if (!can_meet_threshold(t1, t2, threshold)) continue
                        if (similarity(t1, t2, threshold) < threshold) continue
                    }
                }

                if (are_variants(files[i], files[j])) continue

                printf "MATCH|%.3f|%s|%s|%s|%s\n", score, names[i], names[j], files[i], files[j]
            }
        }
    }
    '
}

# Strip prefix from function name for stripped comparison
# Input: "function_name|file_path"
# Output: "stripped_name|original_name|file_path"
add_stripped_names() {
    local func_data="$1"
    
    echo "$func_data" | awk -F'|' '
    function strip_prefix(name,    stripped) {
        # Remove leading underscore
        stripped = name
        if (substr(stripped, 1, 1) == "_") {
            stripped = substr(stripped, 2)
        }
        # Remove everything up to and including the first underscore
        if (index(stripped, "_") > 0) {
            stripped = substr(stripped, index(stripped, "_") + 1)
        }
        return stripped
    }
    
    {
        stripped = strip_prefix($1)
        if (length(stripped) >= 4) {
            # Four fields, because the comparison downstream reads `$4` for the
            # file and was being handed three. `files[]` was empty on every row
            # of that pass, so it could not name a file in its own report and
            # could not tell two spellings of one module apart.
            #
            # The prefix is what `strip_prefix` removed, kept so the report can
            # show the whole name.
            print stripped "|" substr($1, 1, length($1) - length(stripped)) "|" $1 "|" $2
        }
    }
    '
}

# Run stripped name comparison using optimized awk
# Returns lines in format: "WARN|score|stripped1|orig1|stripped2|orig2|file1|file2"
compare_stripped_names() {
    local NUT_DUP_VARIANTS; NUT_DUP_VARIANTS="$(_variants_for)"
    local func_data="$1"
    local threshold="$2"
    
    echo "$func_data" | awk -F'|' -v threshold="$threshold" -v variants="${NUT_DUP_VARIANTS:-}" '
    # The same abandoned-early distance as the first pass. See there for why.
    function levenshtein(s1, s2, maxd,    len1, len2, i, j, c1, cost, prev, cur, best, subst) {
        len1 = length(s1); len2 = length(s2)
        if (s1 == s2) return 0
        if (len1 == 0) return len2
        if (len2 == 0) return len1
        if (maxd == "") maxd = len1 + len2
        if (len1 - len2 > maxd || len2 - len1 > maxd) return maxd + 1
        for (j = 0; j <= len2; j++) prev[j] = j
        for (i = 1; i <= len1; i++) {
            c1 = substr(s1, i, 1)
            cur[0] = i; best = cur[0]
            for (j = 1; j <= len2; j++) {
                cost = (c1 == substr(s2, j, 1)) ? 0 : 1
                subst = prev[j-1] + cost
                cur[j] = prev[j] + 1
                if (cur[j-1] + 1 < cur[j]) cur[j] = cur[j-1] + 1
                if (subst < cur[j]) cur[j] = subst
                if (cur[j] < best) best = cur[j]
            }
            if (best > maxd) return maxd + 1
            for (j = 0; j <= len2; j++) prev[j] = cur[j]
        }
        return prev[len2]
    }

    function similarity(s1, s2, threshold,    len1, len2, maxlen, dist, maxd) {
        len1 = length(s1)
        len2 = length(s2)
        maxlen = (len1 > len2) ? len1 : len2
        if (maxlen == 0) return 1.0
        maxd = int(maxlen * (1.0 - threshold))
        dist = levenshtein(s1, s2, maxd)
        if (dist > maxd) return 0.0
        return 1.0 - (dist / maxlen)
    }
    
    BEGIN {
        n = split(variants, vs, " ")
        for (k = 1; k <= n; k++) is_variant_pair[vs[k]] = 1
    }

    function are_variants(a, b) {
        return (is_variant_pair[a ">" b] || is_variant_pair[b ">" a])
    }

    {
        stripped[NR] = $1
        prefixes[NR] = $2
        original[NR] = $3
        files[NR] = $4
        count = NR
    }
    
    END {
        for (i = 1; i < count; i++) {
            for (j = i + 1; j <= count; j++) {
                # Skip if same file
                if (files[i] == files[j]) continue

                # Different module prefixes means these are namespaced siblings
                # rather than duplicates. `arr_contains` and `str_contains` do
                # the same job for different types and are named that way on
                # purpose, so comparing their stripped forms scores 1.000 for
                # every such pair and reports the naming convention as a defect.
                # That is what this did to a library where every function is
                # `<module>_<verb>`: twelve warnings, not one of them real, and
                # no body duplication found at all.
                #
                # Within one prefix the comparison is worth having, since
                # `toml_get_or` against `toml_fetch_or` in the same module is a
                # real question.
                if (prefixes[i] != prefixes[j]) continue
                
                # Early exit: if lengths are too different, skip expensive Levenshtein
                if (!can_meet_threshold(stripped[i], stripped[j], threshold)) continue
                
                score = similarity(stripped[i], stripped[j], threshold)
                
                if (score >= threshold) {
                    if (are_variants(files[i], files[j])) continue
                    printf "WARN|%.3f|%s|%s|%s|%s|%s|%s\n", score, stripped[i], original[i], stripped[j], original[j], files[i], files[j]
                }
            }
        }
    }
    '
}

# =============================================================================
# TEST: Full Function Name Comparison
# =============================================================================

test_full_name_duplication() {
    log_section "Full Function Name Comparison"
    log_info "Similarity threshold: $SIMILARITY_THRESHOLD"
    if [[ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]]; then
        log_info "Excluding paths: ${EXCLUDE_PATTERNS[*]}"
    fi
    echo ""
    
    local func_data
    func_data=$(collect_all_functions)
    
    local count
    count=$(echo "$func_data" | grep -c . || echo "0")
    log_info "Found $count functions to compare"
    echo ""
    
    local results
    # An awk that will not parse prints nothing and exits non-zero, and this
    # check then reported a clean pass. That is how a reserved word used as a
    # variable name went unnoticed: the program never ran, so nothing was
    # similar to anything. A comparison that could not be made is not a pass.
    if ! results=$(compare_full_names "$func_data" "$SIMILARITY_THRESHOLD"); then
        log_fail "the name comparison could not run"
        return 1
    fi
    
    local failures=0
    
    while IFS='|' read -r level score name1 name2 file1 file2; do
        [[ -z "$level" ]] && continue
        
        log_fail "Similar functions (${score}): '$name1' ↔ '$name2'"
        echo -e "       ${RED}$file1${NC}"
        echo -e "       ${RED}$file2${NC}"
        failures=$((failures + 1))
    done <<< "$results"
    
    echo ""
    
    if [[ $failures -gt 0 ]]; then
        echo -e "${RED}Found $failures function pairs that are too similar - likely duplicates!${NC}"
    else
        log_pass "No problematic function name similarities found"
    fi
    
    return $failures
}

# =============================================================================
# TEST: Stripped Prefix Comparison
# =============================================================================

test_stripped_name_duplication() {
    log_section "Stripped Prefix Comparison"
    log_info "Compares function names after removing first word before underscore"
    log_info "e.g., 'git_check_valid' → 'check_valid', '_private_init' → 'init'"
    log_info "Similarity threshold: $SIMILARITY_THRESHOLD (warnings only, no failures)"
    log_info "Similar stripped names are often intentional API patterns (e.g., *_init, *_debug)"
    echo ""
    
    local func_data
    func_data=$(collect_all_functions)
    
    local stripped_data
    stripped_data=$(add_stripped_names "$func_data")
    
    local count
    count=$(echo "$stripped_data" | grep -c . || echo "0")
    log_info "Found $count functions with meaningful stripped names"
    echo ""
    
    local results
    if ! results=$(compare_stripped_names "$stripped_data" "$SIMILARITY_THRESHOLD"); then
        log_fail "the stripped-name comparison could not run"
        return 1
    fi
    
    local warnings=0
    
    while IFS='|' read -r level score strip1 orig1 strip2 orig2 file1 file2; do
        [[ -z "$level" ]] && continue
        
        log_test_warn "Similar core names (${score}): '$orig1' ['$strip1'] ↔ '$orig2' ['$strip2']"
        echo -e "       ${YELLOW}$file1${NC}"
        echo -e "       ${YELLOW}$file2${NC}"
        warnings=$((warnings + 1))
    done <<< "$results"
    
    echo ""
    
    if [[ $warnings -gt 0 ]]; then
        echo -e "${YELLOW}Found $warnings function pairs with similar core names${NC}"
        echo -e "${YELLOW}These are often intentional API patterns - review if consolidation makes sense${NC}"
    else
        log_pass "No stripped name similarities found"
    fi
    
    # Stripped names never fail - they're just warnings for review
    return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Load configuration from nut.toml
    load_config
    
    log_header "Function Duplication Detection Test"
    
    local full_failures=0
    local strip_failures=0
    
    test_full_name_duplication
    full_failures=$?
    
    echo ""
    
    test_stripped_name_duplication
    strip_failures=$?
    
    # Set failures count for summary
    TESTS_FAILED=$full_failures
    TESTS_WARNED=$strip_failures
    if [[ $TESTS_FAILED -eq 0 ]]; then
        TESTS_PASSED=2
    else
        TESTS_PASSED=1
    fi
    TESTS_RUN=2
    
    print_summary "Function Duplication Detection"
    exit_with_status
}

# A check script is an entry point, so it runs.
#
# This used to be guarded by `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`, the ordinary
# "executed, not sourced" test. Under nutshell it is never true: the `#!/usr/bin/env
# nutshell` shebang runs the interpreter, and the interpreter *sources* the
# script, which is what makes `use` available from its first line. So `$0` is
# the interpreter and `BASH_SOURCE[0]` is this file, and `main` was never
# called. Six of the eight built-in checks exited 0 having done nothing, and
# `./check` read that as a pass and printed one.
#
# `NUT_CHECK_LOAD_ONLY` is the one way in for a test that wants the comparison
# without a scan of the whole repository. It is an explicit opt-out rather than
# a guess about how the file was loaded, which is the distinction the paragraph
# above is about.
[[ -n "${NUT_CHECK_LOAD_ONLY:-}" ]] || main "$@"
