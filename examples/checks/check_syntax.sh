#!/usr/bin/env nutshell
# =============================================================================
# check_syntax.sh - Syntax Validation Check
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Recursively runs shell syntax check on all .sh files to ensure all shell
# scripts have valid syntax.
#
# FULLY CONFIG-DRIVEN: All settings come from nut.toml.
# See examples/configs/empty.nut.toml for all available options.
#
# Usage: ./examples/checks/check_syntax.sh
#
# Exit codes:
#   0 - All syntax checks passed
#   1 - One or more syntax errors found, or test disabled
# =============================================================================

set -uo pipefail

# Load the check-runner framework (provides cfg_*, log_*, etc.)
use check-runner

# Quiet mode - when run from main check runner, be terse
QUIET_MODE="${NUTSHELL_CHECK_QUIET:-0}"

# =============================================================================
# CONFIG-DRIVEN PARAMETERS
# =============================================================================

load_config() {
    # Check if test is enabled
    if ! cfg_is_true "tests.syntax"; then
        log_info "Syntax test is disabled in config"
        exit 0
    fi
    
    # Load settings from config
    SHELL_CMD="$(cfg_get_or "tests.syntax.shell" "bash")"
    FAIL_ON_ERROR="$(cfg_get_or "tests.syntax.fail_on_error" "true")"
}

# =============================================================================
# MAIN TEST
# =============================================================================

test_syntax_validation() {
    if [[ "$QUIET_MODE" != "1" ]]; then
        log_header "Syntax Validation Test"
        log_info "Running $SHELL_CMD -n on all .sh files"
        log_info "Fail on error: $FAIL_ON_ERROR"
        echo ""
    fi
    
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
        
        # Run syntax check and capture any errors
        local syntax_output
        if syntax_output=$("$SHELL_CMD" -n "$file" 2>&1); then
            if [[ "$QUIET_MODE" != "1" ]]; then
                log_pass "$rel_path"
            fi
        else
            if is_truthy "$FAIL_ON_ERROR"; then
                log_fail "$rel_path"
            else
                log_test_warn "$rel_path"
            fi
            # Print the actual syntax error indented
            if [[ "$QUIET_MODE" != "1" ]]; then
                echo "$syntax_output" | while IFS= read -r line; do
                    echo -e "       ${RED}$line${NC}"
                done
            fi
            error_count=$((error_count + 1))
        fi
    done <<< "$files"
    
    if [[ "$QUIET_MODE" != "1" ]]; then
        echo ""
        log_info "Checked $file_count files"
    fi
    
    # Set test counters
    TESTS_RUN=$file_count
    TESTS_PASSED=$((file_count - error_count))
    
    if is_truthy "$FAIL_ON_ERROR"; then
        TESTS_FAILED=$error_count
        TESTS_WARNED=0
    else
        TESTS_FAILED=0
        TESTS_WARNED=$error_count
    fi
    
    if [[ $error_count -gt 0 ]] && is_truthy "$FAIL_ON_ERROR"; then
        return 1
    fi
    return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Load configuration from nut.toml
    load_config
    
    # Run the test
    test_syntax_validation
    
    # Print summary and exit
    print_summary "Syntax Validation"
    exit_with_status
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
