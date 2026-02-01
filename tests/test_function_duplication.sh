#!/usr/bin/env bash
# =============================================================================
# test_function_duplication.sh - Function Duplication Detection Test
# =============================================================================
# Gathers ALL function names from all .sh files (excluding .legacy/), then
# performs fuzzy matching to detect potential duplications.
#
# Two modes of comparison:
#   1. Full function names - detects exact or near-exact duplicates (can fail)
#   2. Stripped prefixes - compares functions after removing the first word
#      before underscore (e.g., git_check_valid -> check_valid)
#      NOTE: Stripped comparison only WARNS, never fails, since identical
#      stripped names are often intentional API patterns (e.g., *_init, *_debug)
#
# Thresholds (configurable via environment variables):
#   FULL_WARN_THRESHOLD  - Similarity for warning on full names (default: 0.85)
#   FULL_FAIL_THRESHOLD  - Similarity for failure on full names (default: 0.95)
#   STRIP_WARN_THRESHOLD - Similarity for warning on stripped names (default: 0.90)
#
# NOTE: Stripped name matches generate warnings for review but don't fail the test.
# This is because common API patterns (init, debug, exists, etc.) are intentional.
#
# Usage: ./scripts/tests/test_function_duplication.sh
#
# Exit codes:
#   0 - All checks passed (may have warnings)
#   1 - One or more errors found
# =============================================================================

set -uo pipefail

# Source the test framework
source "$(dirname "${BASH_SOURCE[0]}")/framework.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Thresholds for full function name comparison
FULL_WARN_THRESHOLD="${FULL_WARN_THRESHOLD:-0.85}"
FULL_FAIL_THRESHOLD="${FULL_FAIL_THRESHOLD:-0.95}"

# Thresholds for stripped prefix comparison (warn only, no fail)
STRIP_WARN_THRESHOLD="${STRIP_WARN_THRESHOLD:-0.90}"

# Minimum function name length to consider for comparison
MIN_NAME_LENGTH=4

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Collect all function names with their source files
# Output format: "function_name|file_path"
collect_all_functions() {
    local files
    files=$(get_script_files)
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        
        local rel_path="${file#$REPO_ROOT/}"
        local functions
        functions=$(extract_functions "$file")
        
        while IFS= read -r func; do
            [[ -z "$func" ]] && continue
            # Skip short names
            if [[ ${#func} -ge $MIN_NAME_LENGTH ]]; then
                echo "${func}|${rel_path}"
            fi
        done <<< "$functions"
    done <<< "$files"
}

# =============================================================================
# OPTIMIZED COMPARISON - Single AWK pass for all comparisons
# =============================================================================

# Run full name comparison using optimized awk
# Returns lines in format: "FAIL|score|name1|name2|file1|file2" or "WARN|..."
compare_full_names() {
    local func_data="$1"
    local warn_threshold="$2"
    local fail_threshold="$3"
    
    echo "$func_data" | awk -F'|' -v warn="$warn_threshold" -v fail="$fail_threshold" '
    # Levenshtein distance function
    function levenshtein(s1, s2,    len1, len2, i, j, c1, c2, cost, d, del, ins, repl, min) {
        len1 = length(s1)
        len2 = length(s2)
        
        if (s1 == s2) return 0
        if (len1 == 0) return len2
        if (len2 == 0) return len1
        
        # Initialize first row and column
        for (i = 0; i <= len1; i++) d[i, 0] = i
        for (j = 0; j <= len2; j++) d[0, j] = j
        
        for (i = 1; i <= len1; i++) {
            c1 = substr(s1, i, 1)
            for (j = 1; j <= len2; j++) {
                c2 = substr(s2, j, 1)
                cost = (c1 == c2) ? 0 : 1
                
                del = d[i-1, j] + 1
                ins = d[i, j-1] + 1
                repl = d[i-1, j-1] + cost
                
                min = del
                if (ins < min) min = ins
                if (repl < min) min = repl
                d[i, j] = min
            }
        }
        return d[len1, len2]
    }
    
    # Quick check: can these strings possibly have similarity >= threshold?
    # If length difference alone makes it impossible, skip expensive Levenshtein
    # This is mathematically correct: best case similarity = min_len / max_len
    function can_meet_threshold(s1, s2, threshold,    len1, len2, maxlen, minlen) {
        len1 = length(s1)
        len2 = length(s2)
        maxlen = (len1 > len2) ? len1 : len2
        minlen = (len1 < len2) ? len1 : len2
        if (maxlen == 0) return 1
        # Best possible similarity is when all chars of shorter string match
        # giving edit distance = length difference, similarity = minlen/maxlen
        return ((minlen / maxlen) >= threshold)
    }
    
    function similarity(s1, s2,    len1, len2, maxlen, dist) {
        len1 = length(s1)
        len2 = length(s2)
        maxlen = (len1 > len2) ? len1 : len2
        if (maxlen == 0) return 1.0
        dist = levenshtein(s1, s2)
        return 1.0 - (dist / maxlen)
    }
    
    {
        names[NR] = $1
        files[NR] = $2
        count = NR
    }
    
    END {
        # Compare each pair (only once, i < j)
        for (i = 1; i < count; i++) {
            for (j = i + 1; j <= count; j++) {
                # Skip if same file
                if (files[i] == files[j]) continue
                
                # Early exit: if lengths are too different, skip expensive Levenshtein
                if (!can_meet_threshold(names[i], names[j], warn)) continue
                
                score = similarity(names[i], names[j])
                
                if (score >= fail) {
                    printf "FAIL|%.3f|%s|%s|%s|%s\n", score, names[i], names[j], files[i], files[j]
                } else if (score >= warn) {
                    printf "WARN|%.3f|%s|%s|%s|%s\n", score, names[i], names[j], files[i], files[j]
                }
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
            print stripped "|" $1 "|" $2
        }
    }
    '
}

# Run stripped name comparison using optimized awk
# Returns lines in format: "FAIL|score|stripped1|orig1|stripped2|orig2|file1|file2" or "WARN|..."
compare_stripped_names() {
    local func_data="$1"
    local warn_threshold="$2"
    local fail_threshold="$3"
    
    echo "$func_data" | awk -F'|' -v warn="$warn_threshold" -v fail="$fail_threshold" '
    function levenshtein(s1, s2,    len1, len2, i, j, c1, c2, cost, d, del, ins, repl, min) {
        len1 = length(s1)
        len2 = length(s2)
        
        if (s1 == s2) return 0
        if (len1 == 0) return len2
        if (len2 == 0) return len1
        
        for (i = 0; i <= len1; i++) d[i, 0] = i
        for (j = 0; j <= len2; j++) d[0, j] = j
        
        for (i = 1; i <= len1; i++) {
            c1 = substr(s1, i, 1)
            for (j = 1; j <= len2; j++) {
                c2 = substr(s2, j, 1)
                cost = (c1 == c2) ? 0 : 1
                
                del = d[i-1, j] + 1
                ins = d[i, j-1] + 1
                repl = d[i-1, j-1] + cost
                
                min = del
                if (ins < min) min = ins
                if (repl < min) min = repl
                d[i, j] = min
            }
        }
        return d[len1, len2]
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
    
    function similarity(s1, s2,    len1, len2, maxlen, dist) {
        len1 = length(s1)
        len2 = length(s2)
        maxlen = (len1 > len2) ? len1 : len2
        if (maxlen == 0) return 1.0
        dist = levenshtein(s1, s2)
        return 1.0 - (dist / maxlen)
    }
    
    {
        stripped[NR] = $1
        original[NR] = $2
        files[NR] = $3
        count = NR
    }
    
    END {
        for (i = 1; i < count; i++) {
            for (j = i + 1; j <= count; j++) {
                # Skip if same file
                if (files[i] == files[j]) continue
                
                # Early exit: if lengths are too different, skip expensive Levenshtein
                if (!can_meet_threshold(stripped[i], stripped[j], warn)) continue
                
                score = similarity(stripped[i], stripped[j])
                
                # Stripped names only warn, never fail (common API patterns are intentional)
                if (score >= warn) {
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
    log_info "Warn threshold: $FULL_WARN_THRESHOLD | Fail threshold: $FULL_FAIL_THRESHOLD"
    echo ""
    
    local func_data
    func_data=$(collect_all_functions)
    
    local count
    count=$(echo "$func_data" | wc -l | tr -d ' ')
    log_info "Found $count functions to compare"
    echo ""
    
    local results
    results=$(compare_full_names "$func_data" "$FULL_WARN_THRESHOLD" "$FULL_FAIL_THRESHOLD")
    
    local failures=0
    local warnings=0
    
    while IFS='|' read -r level score name1 name2 file1 file2; do
        [[ -z "$level" ]] && continue
        
        case "$level" in
            FAIL)
                log_fail "Similar functions (${score}): '$name1' ↔ '$name2'"
                echo -e "       ${RED}$file1${NC}"
                echo -e "       ${RED}$file2${NC}"
                failures=$((failures + 1))
                ;;
            WARN)
                log_warn "Potentially similar (${score}): '$name1' ↔ '$name2'"
                echo -e "       ${YELLOW}$file1${NC}"
                echo -e "       ${YELLOW}$file2${NC}"
                warnings=$((warnings + 1))
                ;;
        esac
    done <<< "$results"
    
    echo ""
    
    if [[ $failures -gt 0 ]]; then
        echo -e "${RED}Found $failures function pairs that are too similar - likely duplicates!${NC}"
    fi
    if [[ $warnings -gt 0 ]]; then
        echo -e "${YELLOW}Found $warnings function pairs that may need review${NC}"
    fi
    if [[ $failures -eq 0 ]] && [[ $warnings -eq 0 ]]; then
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
    log_info "Warn threshold: $STRIP_WARN_THRESHOLD (warnings only, no failures)"
    log_info "Similar stripped names are often intentional API patterns (e.g., *_init, *_debug)"
    echo ""
    
    local func_data
    func_data=$(collect_all_functions)
    
    local stripped_data
    stripped_data=$(add_stripped_names "$func_data")
    
    local count
    count=$(echo "$stripped_data" | wc -l | tr -d ' ')
    log_info "Found $count functions with meaningful stripped names"
    echo ""
    
    local results
    results=$(compare_stripped_names "$stripped_data" "$STRIP_WARN_THRESHOLD" "1.01")
    
    local warnings=0
    
    while IFS='|' read -r level score strip1 orig1 strip2 orig2 file1 file2; do
        [[ -z "$level" ]] && continue
        
        # Stripped name matches are always warnings (intentional API patterns)
        log_warn "Similar core names (${score}): '$orig1' ['$strip1'] ↔ '$orig2' ['$strip2']"
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
# RUN TESTS
# =============================================================================

main() {
    log_header "Function Duplication Detection Test"
    
    local full_failures=0
    local strip_failures=0
    
    test_full_name_duplication
    full_failures=$?
    
    echo ""
    
    test_stripped_name_duplication
    strip_failures=$?
    
    # Set failures count for summary
    TESTS_FAILED=$((full_failures + strip_failures))
    if [[ $TESTS_FAILED -eq 0 ]]; then
        TESTS_PASSED=2
    fi
    TESTS_RUN=2
    
    print_summary "Function Duplication Detection"
    exit_with_status
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
