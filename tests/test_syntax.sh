#!/usr/bin/env bash
# =============================================================================
# test_syntax.sh - Syntax Validation Test
# =============================================================================
# Recursively runs bash -n on all .sh files under scripts/ (excluding .legacy/)
# to ensure all shell scripts have valid syntax.
#
# Usage: ./scripts/tests/test_syntax.sh
#
# Exit codes:
#   0 - All syntax checks passed
#   1 - One or more syntax errors found
# =============================================================================

set -uo pipefail

# Source the test framework
source "$(dirname "${BASH_SOURCE[0]}")/framework.sh"

# =============================================================================
# MAIN TEST
# =============================================================================

test_syntax_validation() {
    log_header "Syntax Validation Test"
    log_info "Running bash -n on all .sh files under scripts/ (excluding .legacy/)"
    echo ""
    
    local files
    files=$(get_script_files)
    
    if [[ -z "$files" ]]; then
        log_fail "No .sh files found to test"
        return 1
    fi
    
    local file_count=0
    local error_count=0
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        file_count=$((file_count + 1))
        
        # Get relative path for display
        local rel_path="${file#$REPO_ROOT/}"
        
        # Run bash -n and capture any errors
        local syntax_output
        if syntax_output=$(bash -n "$file" 2>&1); then
            log_pass "$rel_path"
        else
            log_fail "$rel_path"
            # Print the actual syntax error indented
            echo "$syntax_output" | while IFS= read -r line; do
                echo -e "       ${RED}$line${NC}"
            done
            error_count=$((error_count + 1))
        fi
    done <<< "$files"
    
    echo ""
    log_info "Checked $file_count files"
    
    if [[ $error_count -gt 0 ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# RUN TEST
# =============================================================================

main() {
    test_syntax_validation
    print_summary "Syntax Validation"
    exit_with_status
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
