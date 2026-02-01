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
compare_full_names() {
    local func_data="$1"
    local threshold="$2"
    
    echo "$func_data" | awk -F'|' -v threshold="$threshold" '
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
                if (!can_meet_threshold(names[i], names[j], threshold)) continue
                
                score = similarity(names[i], names[j])
                
                if (score >= threshold) {
                    printf "MATCH|%.3f|%s|%s|%s|%s\n", score, names[i], names[j], files[i], files[j]
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
# Returns lines in format: "WARN|score|stripped1|orig1|stripped2|orig2|file1|file2"
compare_stripped_names() {
    local func_data="$1"
    local threshold="$2"
    
    echo "$func_data" | awk -F'|' -v threshold="$threshold" '
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
                if (!can_meet_threshold(stripped[i], stripped[j], threshold)) continue
                
                score = similarity(stripped[i], stripped[j])
                
                if (score >= threshold) {
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
    results=$(compare_full_names "$func_data" "$SIMILARITY_THRESHOLD")
    
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
    results=$(compare_stripped_names "$stripped_data" "$SIMILARITY_THRESHOLD")
    
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

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
