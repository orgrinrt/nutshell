#!/usr/bin/env bash
# =============================================================================
# test_no_cruft.sh - Deprecation and Backwards Compatibility Detection Test
# =============================================================================
# Detects any code that exists only for backwards compatibility, deprecation,
# or legacy support. Such code is cruft that should be removed immediately.
#
# FLAGGED PATTERNS:
#   - Comments containing: deprecated, backwards compat, legacy, obsolete,
#     "TODO: remove", "FIXME: remove", "to be removed", "will be removed"
#   - Function names containing: deprecated, legacy, old_, _old, compat
#   - Variable names containing: deprecated, legacy, old_, _old
#   - Any shims or wrappers marked as temporary
#
# This test has ZERO tolerance - any cruft is an error.
#
# Usage: ./scripts/tests/test_no_cruft.sh
#
# Exit codes:
#   0 - No cruft found
#   1 - Cruft detected - must be removed before committing
# =============================================================================

set -uo pipefail

# Source the test framework
source "$(dirname "${BASH_SOURCE[0]}")/framework.sh"

# =============================================================================
# CRUFT PATTERNS (as grep -E regex)
# =============================================================================

# Combined pattern for comments (case-insensitive search)
COMMENT_PATTERN='(deprecated|backwards?.?compat|legacy|obsolete|todo:?.?remove|fixme:?.?remove|to.be.removed|will.be.removed|remove.in.future|temporary.fix|temp.fix|hack:?.?remove|workaround.for.old|shim.for|compat.layer|compatibility.layer|for.backwards|old.api|old.interface|superseded|replaced.by|use.instead|don.?t.use|do.not.use|no.longer.used|not.used.anymore)'

# Pattern for function/variable names
NAME_PATTERN='(_deprecated|deprecated_|_legacy|legacy_|_old$|^old_|_compat$|compat_|_shim$|shim_|_obsolete|obsolete_)'

# =============================================================================
# DETECTION FUNCTIONS
# =============================================================================

# Search for cruft patterns in comments using grep (fast)
find_comment_cruft() {
    local file="$1"
    local rel_path="${file#$REPO_ROOT/}"
    
    # Search for comment lines containing cruft patterns
    grep -niE "^[[:space:]]*#.*${COMMENT_PATTERN}" "$file" 2>/dev/null | while IFS=: read -r line_num content; do
        # Extract which pattern matched
        local lower_content
        lower_content=$(echo "$content" | tr '[:upper:]' '[:lower:]')
        
        local matched_pattern="cruft pattern"
        if echo "$lower_content" | grep -qE 'deprecated'; then
            matched_pattern="deprecated"
        elif echo "$lower_content" | grep -qE 'legacy'; then
            matched_pattern="legacy"
        elif echo "$lower_content" | grep -qE 'obsolete'; then
            matched_pattern="obsolete"
        elif echo "$lower_content" | grep -qE 'backwards?.?compat'; then
            matched_pattern="backwards compat"
        elif echo "$lower_content" | grep -qE 'todo:?.?remove|fixme:?.?remove'; then
            matched_pattern="TODO/FIXME remove"
        elif echo "$lower_content" | grep -qE 'to.be.removed|will.be.removed|remove.in.future'; then
            matched_pattern="to be removed"
        elif echo "$lower_content" | grep -qE 'temporary|temp.fix'; then
            matched_pattern="temporary"
        elif echo "$lower_content" | grep -qE 'shim|compat.layer'; then
            matched_pattern="compatibility shim"
        fi
        
        echo "$rel_path|$line_num|comment|$matched_pattern|$content"
    done
}

# Search for cruft in function names using grep (fast)
find_function_name_cruft() {
    local file="$1"
    local rel_path="${file#$REPO_ROOT/}"
    
    # Search for function definitions with cruft in names
    # Note: _old and old_ must be at word boundaries to avoid false positives like "delete_older_than"
    grep -niE "^[[:space:]]*(function[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*(deprecated|legacy|_old$|^old_|_compat$|_shim$|obsolete)[a-zA-Z0-9_]*[[:space:]]*\(" "$file" 2>/dev/null | while IFS=: read -r line_num content; do
        # Extract function name
        local func_name
        func_name=$(echo "$content" | sed -E 's/^[[:space:]]*(function[[:space:]]+)?([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\(.*/\2/')
        
        local matched_pattern="name pattern"
        local lower_name
        lower_name=$(echo "$func_name" | tr '[:upper:]' '[:lower:]')
        
        if echo "$lower_name" | grep -qE 'deprecated'; then
            matched_pattern="_deprecated"
        elif echo "$lower_name" | grep -qE 'legacy'; then
            matched_pattern="_legacy"
        elif echo "$lower_name" | grep -qE 'obsolete'; then
            matched_pattern="_obsolete"
        elif echo "$lower_name" | grep -qE '_old|old_'; then
            matched_pattern="_old"
        elif echo "$lower_name" | grep -qE 'compat'; then
            matched_pattern="_compat"
        elif echo "$lower_name" | grep -qE 'shim'; then
            matched_pattern="_shim"
        fi
        
        echo "$rel_path|$line_num|function|$matched_pattern|$func_name"
    done
}

# Search for cruft in global variable names using grep (fast)
find_variable_name_cruft() {
    local file="$1"
    local rel_path="${file#$REPO_ROOT/}"
    
    # Search for global variable assignments with cruft in names
    # Note: _OLD and OLD_ must be at boundaries to avoid false positives
    grep -nE "^[A-Z_][A-Z0-9_]*(DEPRECATED|LEGACY|_OLD$|^OLD_|_COMPAT$|_SHIM$|OBSOLETE)[A-Z0-9_]*=" "$file" 2>/dev/null | while IFS=: read -r line_num content; do
        # Extract variable name
        local var_name
        var_name=$(echo "$content" | sed -E 's/^([A-Z_][A-Z0-9_]*)=.*/\1/')
        
        local matched_pattern="name pattern"
        if echo "$var_name" | grep -qiE 'deprecated'; then
            matched_pattern="DEPRECATED"
        elif echo "$var_name" | grep -qiE 'legacy'; then
            matched_pattern="LEGACY"
        elif echo "$var_name" | grep -qiE 'obsolete'; then
            matched_pattern="OBSOLETE"
        elif echo "$var_name" | grep -qiE '_old|old_'; then
            matched_pattern="OLD"
        elif echo "$var_name" | grep -qiE 'compat'; then
            matched_pattern="COMPAT"
        elif echo "$var_name" | grep -qiE 'shim'; then
            matched_pattern="SHIM"
        fi
        
        echo "$rel_path|$line_num|variable|$matched_pattern|$var_name"
    done
}

# =============================================================================
# MAIN TEST
# =============================================================================

test_no_cruft() {
    log_header "Deprecation & Backwards Compatibility Detection"
    log_info "Searching for cruft that should be removed"
    log_info "Zero tolerance - any cruft is an error"
    echo ""
    
    local files
    files=$(get_script_files)
    
    if [[ -z "$files" ]]; then
        log_fail "No .sh files found to test"
        return 1
    fi
    
    local file_count=0
    local cruft_count=0
    local -a cruft_items=()
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        file_count=$((file_count + 1))
        
        # Search for comment cruft
        while IFS='|' read -r filepath line_num cruft_type pattern content; do
            [[ -z "$filepath" ]] && continue
            cruft_items+=("$filepath|$line_num|$cruft_type|$pattern|$content")
            cruft_count=$((cruft_count + 1))
        done <<< "$(find_comment_cruft "$file")"
        
        # Search for function name cruft
        while IFS='|' read -r filepath line_num cruft_type pattern content; do
            [[ -z "$filepath" ]] && continue
            cruft_items+=("$filepath|$line_num|$cruft_type|$pattern|$content")
            cruft_count=$((cruft_count + 1))
        done <<< "$(find_function_name_cruft "$file")"
        
        # Search for variable name cruft
        while IFS='|' read -r filepath line_num cruft_type pattern content; do
            [[ -z "$filepath" ]] && continue
            cruft_items+=("$filepath|$line_num|$cruft_type|$pattern|$content")
            cruft_count=$((cruft_count + 1))
        done <<< "$(find_variable_name_cruft "$file")"
        
    done <<< "$files"
    
    echo ""
    log_info "Scanned $file_count files"
    echo ""
    
    if [[ $cruft_count -eq 0 ]]; then
        log_pass "No cruft found - codebase is clean"
        TESTS_PASSED=1
        TESTS_RUN=1
        return 0
    fi
    
    # Report all cruft found
    log_section "Cruft Found: $cruft_count items"
    echo ""
    
    local current_file=""
    for entry in "${cruft_items[@]}"; do
        IFS='|' read -r filepath line_num cruft_type pattern content <<< "$entry"
        
        if [[ "$filepath" != "$current_file" ]]; then
            if [[ -n "$current_file" ]]; then
                echo ""
            fi
            echo -e "${CYAN}$filepath${NC}"
            current_file="$filepath"
        fi
        
        case "$cruft_type" in
            comment)
                log_fail "Line $line_num: Comment contains '$pattern'"
                ;;
            function)
                log_fail "Line $line_num: Function '$content' contains '$pattern'"
                ;;
            variable)
                log_fail "Line $line_num: Variable '$content' contains '$pattern'"
                ;;
        esac
        
        # Show the content (truncated if too long)
        local display_content="$content"
        # Remove leading whitespace for display
        display_content="${display_content#"${display_content%%[![:space:]]*}"}"
        if [[ ${#display_content} -gt 80 ]]; then
            display_content="${display_content:0:77}..."
        fi
        echo -e "       ${MAGENTA}${display_content}${NC}"
    done
    
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                          CRUFT DETECTED                               ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}Found $cruft_count items that must be removed before committing.${NC}"
    echo ""
    echo "Why this matters:"
    echo "  - Deprecated code is dead weight that confuses maintainers"
    echo "  - Backwards compatibility layers accumulate tech debt"
    echo "  - 'Temporary' workarounds become permanent problems"
    echo "  - Legacy code hides the actual implementation"
    echo ""
    echo "What to do:"
    echo "  1. Remove the flagged code entirely"
    echo "  2. If functionality is needed, implement it properly (no 'compat' layers)"
    echo "  3. If code is truly obsolete, delete it - git has history"
    echo "  4. Never mark code as 'deprecated' - just remove it"
    
    TESTS_FAILED=$cruft_count
    TESTS_RUN=$cruft_count
    
    return 1
}

# =============================================================================
# RUN TEST
# =============================================================================

main() {
    test_no_cruft
    local result=$?
    print_summary "Cruft Detection"
    exit_with_status
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
