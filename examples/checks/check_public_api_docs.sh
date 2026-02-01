#!/usr/bin/env nutshell
# =============================================================================
# check_public_api_docs.sh - Public API Documentation Validation Check
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Verifies that all functions marked with @@PUBLIC_API@@ annotation have
# proper documentation including usage examples.
#
# FULLY CONFIG-DRIVEN: All settings come from nut.toml.
# See examples/configs/empty.nut.toml for all available options.
#
# Checks:
#   - Functions with @@PUBLIC_API@@ must have a Usage: line
#   - Optionally checks for return value documentation (->)
#
# Usage: ./examples/checks/check_public_api_docs.sh
#
# Exit codes:
#   0 - All public API functions are documented
#   1 - One or more functions missing documentation, or test disabled
# =============================================================================

set -uo pipefail

# Load the check-runner framework (provides cfg_*, log_*, etc.)
use check-runner

# =============================================================================
# CONFIG-DRIVEN PARAMETERS
# =============================================================================

# Settings (will be loaded from config)
PUBLIC_API_ANNOTATION="@@PUBLIC_API@@"
declare -a REQUIRED_ELEMENTS=()
declare -a RECOMMENDED_ELEMENTS=()
MIN_DOC_LINES=1

load_config() {
    # Check if test is enabled
    if ! cfg_is_true "tests.public_api_docs"; then
        log_info "Public API docs test is disabled in config"
        exit 0
    fi
    
    # Load settings from config
    PUBLIC_API_ANNOTATION="$(cfg_get_or "tests.public_api_docs.public_api_annotation" "@@PUBLIC_API@@")"
    MIN_DOC_LINES="$(cfg_get_or "tests.public_api_docs.min_doc_lines" "1")"
    
    # Load required elements
    if ! cfg_get_array "tests.public_api_docs.required_elements" REQUIRED_ELEMENTS; then
        REQUIRED_ELEMENTS=("Usage:")
    fi
    
    # Load recommended elements
    if ! cfg_get_array "tests.public_api_docs.recommended_elements" RECOMMENDED_ELEMENTS; then
        RECOMMENDED_ELEMENTS=("->" "Returns" "returns" "Prints" "prints")
    fi
}

# =============================================================================
# DOCUMENTATION CHECKING FUNCTIONS
# =============================================================================

# Extract the docblock before a function definition
# Returns: the comment lines before the function (if any)
get_function_docblock() {
    local file="$1"
    local func_name="$2"
    
    # Find the line number of the function definition
    local func_line
    func_line=$(grep -n "^[[:space:]]*${func_name}[[:space:]]*()[[:space:]]*{" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    
    if [[ -z "$func_line" ]]; then
        # Try alternate syntax
        func_line=$(grep -n "^[[:space:]]*function[[:space:]]\+${func_name}[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    fi
    
    [[ -z "$func_line" ]] && return 1
    [[ "$func_line" -lt 2 ]] && return 1
    
    # Look backwards from the function definition to find comment block
    local start_line=$((func_line - 1))
    local docblock=""
    local current_line=$start_line
    
    while [[ $current_line -gt 0 ]]; do
        local line
        line=$(sed -n "${current_line}p" "$file" 2>/dev/null)
        
        # If line is a comment, add to docblock
        if echo "$line" | grep -qE '^[[:space:]]*#'; then
            docblock="${line}"$'\n'"${docblock}"
            current_line=$((current_line - 1))
        # If line is blank, might be part of docblock, continue
        elif [[ -z "${line// /}" ]]; then
            # Check if previous line is also blank or non-comment
            local prev_line
            prev_line=$(sed -n "$((current_line - 1))p" "$file" 2>/dev/null)
            if echo "$prev_line" | grep -qE '^[[:space:]]*#'; then
                current_line=$((current_line - 1))
            else
                break
            fi
        else
            # Non-comment, non-blank line - stop
            break
        fi
    done
    
    echo "$docblock"
}

# Check if docblock contains an element
docblock_has_element() {
    local docblock="$1"
    local element="$2"
    
    # Use grep -F for literal string matching (handles special chars like ->)
    # Use -- to prevent element from being interpreted as options
    echo "$docblock" | grep -qiF -- "$element"
}

# Count comment lines in docblock
count_doc_lines() {
    local docblock="$1"
    
    echo "$docblock" | grep -cE '^[[:space:]]*#' || echo "0"
}

# Find all functions marked with public API annotation
find_public_api_functions() {
    local file="$1"
    local rel_path="${file#$REPO_ROOT/}"
    
    # Find lines with the annotation
    local annotation_lines
    annotation_lines=$(grep -n "$PUBLIC_API_ANNOTATION" "$file" 2>/dev/null | cut -d: -f1)
    
    [[ -z "$annotation_lines" ]] && return
    
    # For each annotation, find the next function definition
    while IFS= read -r anno_line; do
        [[ -z "$anno_line" ]] && continue
        
        # Look forward to find the function definition
        local search_start=$((anno_line + 1))
        local search_end=$((anno_line + 10))
        
        local func_def
        func_def=$(sed -n "${search_start},${search_end}p" "$file" 2>/dev/null | \
            grep -E '^[[:space:]]*(function[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\([[:space:]]*\)' | head -1)
        
        if [[ -n "$func_def" ]]; then
            # Extract function name
            local func_name
            func_name=$(echo "$func_def" | sed -E 's/^[[:space:]]*(function[[:space:]]+)?([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(.*/\2/')
            
            # Find the actual line number of this function
            local func_line
            func_line=$(grep -n "^[[:space:]]*${func_name}[[:space:]]*()[[:space:]]*{" "$file" 2>/dev/null | head -1 | cut -d: -f1)
            if [[ -z "$func_line" ]]; then
                func_line=$(grep -n "^[[:space:]]*function[[:space:]]\+${func_name}[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1)
            fi
            
            echo "${func_name}|${func_line:-$anno_line}|${rel_path}"
        fi
    done <<< "$annotation_lines"
}

# =============================================================================
# MAIN TEST
# =============================================================================

test_public_api_docs() {
    log_header "Public API Documentation Validation"
    log_info "Checking functions marked with $PUBLIC_API_ANNOTATION"
    log_info "Required elements: ${REQUIRED_ELEMENTS[*]}"
    log_info "Recommended elements: ${RECOMMENDED_ELEMENTS[*]}"
    log_info "Minimum doc lines: $MIN_DOC_LINES"
    echo ""
    
    local files
    files=$(get_script_files)
    
    if [[ -z "$files" ]]; then
        log_fail "No .sh files found to test"
        return 1
    fi
    
    local file_count=0
    local func_count=0
    local error_count=0
    local warn_count=0
    
    declare -a errors=()
    declare -a warnings=()
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        [[ ! -f "$file" ]] && continue
        file_count=$((file_count + 1))
        
        local rel_path="${file#$REPO_ROOT/}"
        local file_has_issues=0
        
        # Find all public API functions in this file
        local public_functions
        public_functions=$(find_public_api_functions "$file")
        
        while IFS='|' read -r func_name func_line func_file; do
            [[ -z "$func_name" ]] && continue
            func_count=$((func_count + 1))
            
            # Get the docblock for this function
            local docblock
            docblock=$(get_function_docblock "$file" "$func_name")
            
            local has_error=0
            local has_warn=0
            local missing_required=""
            local missing_recommended=""
            
            # Check minimum doc lines
            local doc_lines
            doc_lines=$(count_doc_lines "$docblock")
            
            if [[ $doc_lines -lt $MIN_DOC_LINES ]]; then
                has_error=1
                missing_required="insufficient documentation ($doc_lines lines, need $MIN_DOC_LINES)"
            else
                # Check required elements
                for element in "${REQUIRED_ELEMENTS[@]}"; do
                    if ! docblock_has_element "$docblock" "$element"; then
                        has_error=1
                        if [[ -z "$missing_required" ]]; then
                            missing_required="$element"
                        else
                            missing_required="$missing_required, $element"
                        fi
                    fi
                done
                
                # Check recommended elements (only warn, don't fail)
                local has_any_recommended=0
                for element in "${RECOMMENDED_ELEMENTS[@]}"; do
                    if docblock_has_element "$docblock" "$element"; then
                        has_any_recommended=1
                        break
                    fi
                done
                
                if [[ $has_any_recommended -eq 0 ]] && [[ ${#RECOMMENDED_ELEMENTS[@]} -gt 0 ]]; then
                    has_warn=1
                    missing_recommended="none of: ${RECOMMENDED_ELEMENTS[*]}"
                fi
            fi
            
            # Report results
            if [[ $has_error -eq 1 ]]; then
                if [[ $file_has_issues -eq 0 ]]; then
                    echo -e "${CYAN}$rel_path${NC}"
                    file_has_issues=1
                fi
                log_fail "${func_name}() - missing required: $missing_required"
                errors+=("${rel_path}:${func_line} ${func_name}() - missing: $missing_required")
                error_count=$((error_count + 1))
            elif [[ $has_warn -eq 1 ]]; then
                if [[ $file_has_issues -eq 0 ]]; then
                    echo -e "${CYAN}$rel_path${NC}"
                    file_has_issues=1
                fi
                log_test_warn "${func_name}() - missing recommended: $missing_recommended"
                warnings+=("${rel_path}:${func_line} ${func_name}() - missing: $missing_recommended")
                warn_count=$((warn_count + 1))
            else
                log_pass "${func_name}()"
            fi
        done <<< "$public_functions"
        
        if [[ $file_has_issues -eq 1 ]]; then
            echo ""
        fi
        
    done <<< "$files"
    
    echo ""
    log_info "Scanned $file_count files, found $func_count public API functions"
    echo ""
    
    # Summary
    if [[ $error_count -eq 0 ]] && [[ $warn_count -eq 0 ]]; then
        log_pass "All public API functions are properly documented"
    else
        if [[ $error_count -gt 0 ]]; then
            echo -e "${RED}Found $error_count functions missing required documentation${NC}"
        fi
        if [[ $warn_count -gt 0 ]]; then
            echo -e "${YELLOW}Found $warn_count functions missing recommended documentation${NC}"
        fi
        echo ""
        echo "Required documentation elements:"
        for element in "${REQUIRED_ELEMENTS[@]}"; do
            echo "  - $element"
        done
        echo ""
        echo "Recommended documentation elements (any one of):"
        for element in "${RECOMMENDED_ELEMENTS[@]}"; do
            echo "  - $element"
        done
        echo ""
        echo "Example of well-documented public API function:"
        echo ""
        echo "  # @@PUBLIC_API@@"
        echo "  # Brief description of what the function does"
        echo "  # Usage: function_name \"arg1\" \"arg2\" -> \"result\""
        echo "  function_name() {"
        echo "      ..."
        echo "  }"
    fi
    
    # Set test counters
    TESTS_RUN=$func_count
    if [[ $func_count -eq 0 ]]; then
        TESTS_RUN=1
        TESTS_PASSED=1
    else
        TESTS_PASSED=$((func_count - error_count))
    fi
    TESTS_FAILED=$error_count
    TESTS_WARNED=$warn_count
    FAILED_TESTS=("${errors[@]}")
    WARNED_TESTS=("${warnings[@]}")
    
    [[ $error_count -gt 0 ]] && return 1
    return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Load configuration from nut.toml
    load_config
    
    # Run the test
    test_public_api_docs
    local result=$?
    
    # Print summary and exit
    print_summary "Public API Documentation"
    exit_with_status
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
