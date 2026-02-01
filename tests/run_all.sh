#!/usr/bin/env bash
# =============================================================================
# run_all.sh - Main Test Runner for Code Quality Tests
# =============================================================================
# Executes all code quality tests in sequence and provides a comprehensive
# summary of results.
#
# Usage: ./scripts/tests/run_all.sh [options]
#
# Options:
#   --stop-on-failure   Stop immediately on first test failure
#   --quiet             Only show summary (suppress individual test output)
#   --help              Show this help message
#
# Exit codes:
#   0 - All tests passed (may have warnings)
#   1 - One or more tests failed
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Options
STOP_ON_FAILURE=false
QUIET=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --stop-on-failure)
            STOP_ON_FAILURE=true
            shift
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        --help)
            head -n 20 "$0" | grep -E '^#' | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# COLORS
# =============================================================================

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# =============================================================================
# TEST TRACKING
# =============================================================================

declare -a TEST_NAMES=()
declare -a TEST_RESULTS=()
declare -a TEST_OUTPUTS=()

TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_WARNINGS=0

# =============================================================================
# TEST EXECUTION
# =============================================================================

run_test() {
    local test_name="$1"
    local test_script="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    TEST_NAMES+=("$test_name")
    
    echo ""
    echo -e "${BOLD}${BLUE}Running: $test_name${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local output
    local exit_code
    
    if [[ "$QUIET" == "true" ]]; then
        output=$("$test_script" 2>&1)
        exit_code=$?
    else
        # Run test and capture output while also displaying it
        output=$("$test_script" 2>&1)
        exit_code=$?
        echo "$output"
    fi
    
    TEST_OUTPUTS+=("$output")
    
    if [[ $exit_code -eq 0 ]]; then
        # Check if there were warnings in the output
        if echo "$output" | grep -q "PASSED WITH WARNINGS"; then
            TEST_RESULTS+=("warn")
            TOTAL_WARNINGS=$((TOTAL_WARNINGS + 1))
            echo -e "${YELLOW}Result: PASSED WITH WARNINGS${NC}"
        else
            TEST_RESULTS+=("pass")
            TOTAL_PASSED=$((TOTAL_PASSED + 1))
            echo -e "${GREEN}Result: PASSED${NC}"
        fi
    else
        TEST_RESULTS+=("fail")
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        echo -e "${RED}Result: FAILED${NC}"
        
        if [[ "$STOP_ON_FAILURE" == "true" ]]; then
            echo ""
            echo -e "${RED}Stopping due to --stop-on-failure${NC}"
            print_final_summary
            exit 1
        fi
    fi
}

# =============================================================================
# SUMMARY
# =============================================================================

print_final_summary() {
    echo ""
    echo ""
    echo -e "${BOLD}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                      CODE QUALITY TEST RESULTS                        ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Individual test results
    echo -e "${BOLD}Test Results:${NC}"
    echo ""
    
    for i in "${!TEST_NAMES[@]}"; do
        local name="${TEST_NAMES[$i]}"
        local result="${TEST_RESULTS[$i]}"
        
        case "$result" in
            pass)
                echo -e "  ${GREEN}✓${NC} $name"
                ;;
            warn)
                echo -e "  ${YELLOW}⚠${NC} $name (passed with warnings)"
                ;;
            fail)
                echo -e "  ${RED}✗${NC} $name"
                ;;
        esac
    done
    
    echo ""
    echo -e "${BOLD}Summary:${NC}"
    echo ""
    echo -e "  Total:     ${BOLD}$TOTAL_TESTS${NC}"
    echo -e "  ${GREEN}Passed:${NC}    ${BOLD}$TOTAL_PASSED${NC}"
    echo -e "  ${YELLOW}Warnings:${NC}  ${BOLD}$TOTAL_WARNINGS${NC}"
    echo -e "  ${RED}Failed:${NC}    ${BOLD}$TOTAL_FAILED${NC}"
    echo ""
    
    if [[ $TOTAL_FAILED -gt 0 ]]; then
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                              FAILED                                   ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${RED}${BOLD}Please fix all errors before committing!${NC}"
        echo -e "${YELLOW}Review all warnings and fix them if possible.${NC}"
        echo ""
        return 1
    elif [[ $TOTAL_WARNINGS -gt 0 ]]; then
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║                        PASSED WITH WARNINGS                          ║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}Consider fixing the warnings before committing.${NC}"
        echo ""
        return 0
    else
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║                            ALL PASSED                                ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        return 0
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo -e "${BOLD}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                    CODE QUALITY TEST SUITE                            ║${NC}"
    echo -e "${BOLD}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Running all code quality tests..."
    echo "Repository: $(cd "$SCRIPT_DIR/../.." && pwd)"
    echo ""
    
    # Run each test
    run_test "Syntax Validation" "$SCRIPT_DIR/test_syntax.sh"
    run_test "File Size (LOC) Limits" "$SCRIPT_DIR/test_file_size.sh"
    run_test "Function Duplication Detection" "$SCRIPT_DIR/test_function_duplication.sh"
    run_test "Trivial Wrapper Detection" "$SCRIPT_DIR/test_trivial_wrappers.sh"
    run_test "Cruft Detection (Deprecation/Legacy)" "$SCRIPT_DIR/test_no_cruft.sh"
    
    # Print final summary
    print_final_summary
    local result=$?
    
    exit $result
}

main "$@"
