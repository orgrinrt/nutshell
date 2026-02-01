#!/usr/bin/env nutshell
# =============================================================================
# check_file_size.sh - File Size (Lines of Code) Validation Check
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Checks that no file exceeds certain LOC thresholds (stripped of comments
# and empty lines). This encourages modular design and maintainable code.
#
# FULLY CONFIG-DRIVEN: All thresholds and patterns come from nut.toml.
# See examples/configs/empty.nut.toml for all available options.
#
# Per-file override:
#   Add # @@ALLOW_LOC_NNN@@ at the top of a file (within first 10 lines)
#   to set a custom limit for that specific file. For example:
#     # @@ALLOW_LOC_600@@
#   This MUST be set explicitly - there is no "skip" option.
#   The file will still fail if it exceeds the custom limit.
#
# Usage: ./examples/checks/check_file_size.sh
#
# Exit codes:
#   0 - All files within acceptable limits
#   1 - One or more files exceed their threshold, or test disabled
# =============================================================================

set -uo pipefail

# Load the check-runner framework (provides cfg_*, log_*, etc.)
use check-runner

# =============================================================================
# CONFIG-DRIVEN PARAMETERS
# =============================================================================

# Thresholds (will be loaded from config)
MAX_LOC=300
MAX_TOTAL_LINES=500
EXEMPT_ANNOTATION_PATTERN="@@ALLOW_LOC_([0-9]+)@@"

# Arrays for patterns
declare -a EXEMPT_PATTERNS=()

load_config() {
    # Check if test is enabled
    if ! cfg_is_true "tests.file_size"; then
        log_info "File size test is disabled in config"
        exit 0
    fi
    
    # Load thresholds from config
    MAX_LOC="$(cfg_get_or "tests.file_size.max_loc" "300")"
    MAX_TOTAL_LINES="$(cfg_get_or "tests.file_size.max_total_lines" "500")"
    EXEMPT_ANNOTATION_PATTERN="$(cfg_get_or "tests.file_size.exempt_annotation_pattern" "@@ALLOW_LOC_([0-9]+)@@")"
    
    # Load exempt patterns
    cfg_get_array "tests.file_size.exempt_patterns" EXEMPT_PATTERNS || EXEMPT_PATTERNS=()
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Check if a path matches any exempt pattern
is_exempt_path() {
    local path="$1"
    
    for pattern in "${EXEMPT_PATTERNS[@]}"; do
        if [[ "$path" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

# Check if file has a custom LOC limit annotation
# Returns the custom limit if found, empty string otherwise
get_custom_loc_limit() {
    local file="$1"
    
    # Search first 10 lines for the annotation pattern (with optional space after #)
    local annotation
    annotation=$(head -n 10 "$file" 2>/dev/null | grep -oE "#[[:space:]]*${EXEMPT_ANNOTATION_PATTERN}" | head -1)
    
    if [[ -n "$annotation" ]]; then
        # Extract the number
        echo "$annotation" | grep -oE '[0-9]+'
    fi
}

# =============================================================================
# MAIN TEST
# =============================================================================

test_file_sizes() {
    log_header "File Size (LOC) Validation Test"
    log_info "Checking lines of code (excluding comments and empty lines)"
    log_info "Default thresholds: max LOC = $MAX_LOC | max total = $MAX_TOTAL_LINES"
    log_info "Annotation pattern: # $EXEMPT_ANNOTATION_PATTERN"
    if [[ ${#EXEMPT_PATTERNS[@]} -gt 0 ]]; then
        log_info "Exempt patterns: ${EXEMPT_PATTERNS[*]}"
    fi
    echo ""
    
    local files
    files=$(get_script_files)
    
    if [[ -z "$files" ]]; then
        log_fail "No .sh files found to test"
        return 1
    fi
    
    local file_count=0
    local warn_count=0
    local fail_count=0
    
    # Arrays to track files by category
    local -a passed_files=()
    local -a warned_files=()
    local -a failed_files=()
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        file_count=$((file_count + 1))
        
        # Get relative path for display
        local rel_path="${file#$REPO_ROOT/}"
        
        # Check if this file is exempt by path pattern
        if is_exempt_path "$rel_path"; then
            log_pass "$rel_path (exempt by pattern)"
            passed_files+=("$rel_path")
            continue
        fi
        
        # Count lines of code (excluding comments and empty lines)
        local loc
        loc=$(count_code_lines "$file")
        
        # Also get total lines for context
        local total
        total=$(count_total_lines "$file")
        
        # Check for custom limit
        local custom_limit
        custom_limit=$(get_custom_loc_limit "$file")
        
        local effective_warn_threshold="$MAX_LOC"
        local effective_fail_threshold="$MAX_TOTAL_LINES"
        local has_custom_limit=false
        
        if [[ -n "$custom_limit" ]]; then
            has_custom_limit=true
            effective_fail_threshold="$custom_limit"
            # Set warn threshold to 80% of custom limit
            effective_warn_threshold=$((custom_limit * 80 / 100))
        fi
        
        # Determine status
        if [[ $loc -ge $effective_fail_threshold ]]; then
            if [[ "$has_custom_limit" == "true" ]]; then
                log_fail "$rel_path: $loc LOC (total: $total lines) - EXCEEDS CUSTOM LIMIT of $custom_limit"
                echo -e "       ${RED}File has # @@ALLOW_LOC_${custom_limit}@@ but still exceeds it!${NC}"
            else
                log_fail "$rel_path: $loc LOC (total: $total lines)"
                echo -e "       ${RED}Exceeds fail threshold of $MAX_TOTAL_LINES LOC${NC}"
            fi
            echo -e "       ${RED}This file is too large and should be split into smaller modules${NC}"
            failed_files+=("$rel_path ($loc LOC)")
            fail_count=$((fail_count + 1))
        elif [[ $loc -ge $effective_warn_threshold ]]; then
            if [[ "$has_custom_limit" == "true" ]]; then
                log_pass "$rel_path: $loc LOC (custom limit: $custom_limit)"
                passed_files+=("$rel_path")
            else
                log_test_warn "$rel_path: $loc LOC (total: $total lines)"
                echo -e "       ${YELLOW}Exceeds warn threshold of $MAX_LOC LOC${NC}"
                echo -e "       ${YELLOW}Consider refactoring to improve maintainability${NC}"
                warned_files+=("$rel_path ($loc LOC)")
                warn_count=$((warn_count + 1))
            fi
        else
            if [[ "$has_custom_limit" == "true" ]]; then
                log_pass "$rel_path: $loc LOC (custom limit: $custom_limit)"
            else
                log_pass "$rel_path: $loc LOC"
            fi
            passed_files+=("$rel_path")
        fi
    done <<< "$files"
    
    echo ""
    log_section "Summary by Category"
    
    echo ""
    echo -e "${GREEN}Files within limits: ${#passed_files[@]}${NC}"
    
    if [[ ${#warned_files[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}Files exceeding warn threshold ($MAX_LOC LOC): ${#warned_files[@]}${NC}"
        for f in "${warned_files[@]}"; do
            echo -e "  ${YELLOW}⚠${NC} $f"
        done
    fi
    
    if [[ ${#failed_files[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}Files exceeding fail threshold: ${#failed_files[@]}${NC}"
        for f in "${failed_files[@]}"; do
            echo -e "  ${RED}✗${NC} $f"
        done
    fi
    
    echo ""
    log_info "Checked $file_count files"
    
    echo ""
    echo "To set a custom limit for a file that has been manually reviewed:"
    echo "  Add # @@ALLOW_LOC_NNN@@ in the first 10 lines of the file"
    echo "  Example: # @@ALLOW_LOC_600@@ allows up to 600 LOC"
    echo ""
    echo "Note: Custom limits must be explicitly set - there is no 'skip' option."
    echo "      Files will still fail if they exceed their custom limit."
    
    # Update global counters
    TESTS_RUN=$file_count
    TESTS_PASSED=$((file_count - fail_count - warn_count))
    TESTS_FAILED=$fail_count
    TESTS_WARNED=$warn_count
    
    return $fail_count
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Load configuration from nut.toml
    load_config
    
    # Run the test
    test_file_sizes
    local result=$?
    
    # Print summary and exit
    print_summary "File Size Validation"
    exit_with_status
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
