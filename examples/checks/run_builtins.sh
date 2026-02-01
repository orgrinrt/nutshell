#!/usr/bin/env bash
# =============================================================================
# run_builtins.sh - Built-in QA Checks Runner
# =============================================================================
# Executes all built-in nutshell QA checks with tree-structured output.
#
# Usage: ./examples/checks/run_builtins.sh [options]
#
# Options:
#   --stop-on-failure   Stop immediately on first test failure
#   --level=LEVEL       Output level: error, warn (default), info, debug
#   --no-color          Disable colored output
#   --help              Show this help message
#
# Exit codes:
#   0 - All tests passed (may have warnings)
#   1 - One or more tests failed
# =============================================================================

set -uo pipefail

# Get our script directory for finding sibling check scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Bootstrap nutshell (this is an entry point script)
. "${SCRIPT_DIR}/../../init"

# Load nutshell modules
use os color

# =============================================================================
# OPTIONS
# =============================================================================

STOP_ON_FAILURE=false
OUTPUT_LEVEL="warn"
USE_COLOR=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stop-on-failure)
            STOP_ON_FAILURE=true
            shift
            ;;
        --level=*)
            OUTPUT_LEVEL="${1#--level=}"
            shift
            ;;
        --no-color)
            USE_COLOR=false
            shift
            ;;
        --help)
            head -n 16 "$0" | tail -n +2 | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# =============================================================================
# COLORS
# =============================================================================

if [[ "$USE_COLOR" == "true" ]] && [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    DIM='\033[2m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    DIM=''
    BOLD=''
    NC=''
fi

# =============================================================================
# DIAGNOSTIC COLLECTION
# =============================================================================

# Temp file for collecting diagnostics
DIAG_FILE=$(mktemp)
trap "rm -f '$DIAG_FILE'" EXIT

# Parse test output and extract diagnostics
# Format in file: level|file|message|hint
parse_test_output() {
    local output="$1"
    
    # Pattern for [WARN] file: NNN LOC (total: MMM lines)
    local warn_pattern='^\[WARN\][[:space:]]+([^:]+):[[:space:]]*([0-9]+)[[:space:]]+LOC'
    # Pattern for [FAIL] or [ERROR] file: message
    local fail_pattern='^\[(FAIL|ERROR)\][[:space:]]+([^:]+):[[:space:]]*(.+)$'
    
    echo "$output" | while IFS= read -r line; do
        # Only capture the detailed [WARN] lines, not the summary ⚠ lines
        if [[ "$line" =~ $warn_pattern ]]; then
            local file="${BASH_REMATCH[1]}"
            local loc="${BASH_REMATCH[2]}"
            local hint="consider splitting or add @@ALLOW_LOC_${loc}@@"
            echo "warn|${file}|${loc} LOC|${hint}" >> "$DIAG_FILE"
        elif [[ "$line" =~ $fail_pattern ]]; then
            echo "error|${BASH_REMATCH[2]}|${BASH_REMATCH[3]}|" >> "$DIAG_FILE"
        fi
    done
}

# =============================================================================
# OUTPUT LEVEL FILTERING
# =============================================================================

should_show_level() {
    local level="$1"
    case "$OUTPUT_LEVEL" in
        debug) return 0 ;;
        info)  [[ "$level" != "debug" ]] ;;
        warn)  [[ "$level" == "warn" || "$level" == "error" ]] ;;
        error) [[ "$level" == "error" ]] ;;
    esac
}

# =============================================================================
# TEST TRACKING
# =============================================================================

declare -a TEST_NAMES=()
declare -a TEST_RESULTS=()

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
    
    # Progress indicator
    printf "  %-30s " "$test_name"
    
    local output exit_code
    output=$("$test_script" 2>&1)
    exit_code=$?
    
    # Parse output for diagnostics
    parse_test_output "$output"
    
    # Determine result based on exit code
    if [[ $exit_code -eq 0 ]]; then
        # Check if output mentions warnings (PASSED WITH WARNINGS)
        if echo "$output" | grep -q "PASSED WITH WARNINGS" 2>/dev/null; then
            TEST_RESULTS+=("warn")
            TOTAL_PASSED=$((TOTAL_PASSED + 1))
            TOTAL_WARNINGS=$((TOTAL_WARNINGS + 1))
            echo -e "${YELLOW}⚠${NC}"
        else
            TEST_RESULTS+=("pass")
            TOTAL_PASSED=$((TOTAL_PASSED + 1))
            echo -e "${GREEN}✓${NC}"
        fi
    else
        TEST_RESULTS+=("fail")
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
        echo -e "${RED}✗${NC}"
        
        if [[ "$STOP_ON_FAILURE" == "true" ]]; then
            echo ""
            echo -e "${RED}Stopping due to --stop-on-failure${NC}"
            print_diagnostics
            print_summary
            exit 1
        fi
    fi
}

# =============================================================================
# TREE-STRUCTURED DIAGNOSTIC OUTPUT
# =============================================================================

print_diagnostics() {
    [[ ! -s "$DIAG_FILE" ]] && return 0
    
    # Deduplicate
    local sorted_diags
    sorted_diags=$(sort -u "$DIAG_FILE")
    
    [[ -z "$sorted_diags" ]] && return 0
    
    # Build list of files with their diagnostics
    declare -A file_diags
    declare -a file_order=()
    
    while IFS='|' read -r level file message hint; do
        [[ -z "$level" || -z "$file" ]] && continue
        
        # Skip if level shouldn't be shown
        should_show_level "$level" || continue
        
        # Skip non-file entries (like test names used as placeholders)
        [[ "$file" != *"/"* && "$file" != *".sh"* ]] && continue
        
        # Track file order (first occurrence)
        if [[ -z "${file_diags[$file]:-}" ]]; then
            file_order+=("$file")
            file_diags[$file]=""
        fi
        file_diags[$file]+="${level}|${message}|${hint}"$'\n'
    done <<< "$sorted_diags"
    
    [[ ${#file_order[@]} -eq 0 ]] && return 0
    
    echo ""
    echo -e "${BOLD}Diagnostics:${NC}"
    
    # Group files by directory
    local last_dir=""
    
    for file in "${file_order[@]}"; do
        local dir base
        dir=$(dirname "$file")
        base=$(basename "$file")
        
        # Print directory header if changed
        if [[ "$dir" != "$last_dir" ]]; then
            echo ""
            echo -e "  ${CYAN}${dir}/${NC}"
            last_dir="$dir"
        fi
        
        # Print file
        echo -e "    ${BOLD}${base}${NC}"
        
        # Print diagnostics for this file (deduplicated by message)
        declare -A seen_msgs
        while IFS='|' read -r level message hint; do
            [[ -z "$level" || -z "$message" ]] && continue
            
            # Skip duplicates
            [[ -n "${seen_msgs[$message]:-}" ]] && continue
            seen_msgs[$message]=1
            
            local icon color
            case "$level" in
                error) icon="✗"; color="$RED" ;;
                warn)  icon="⚠"; color="$YELLOW" ;;
                info)  icon="ℹ"; color="$BLUE" ;;
                *)     icon="·"; color="$DIM" ;;
            esac
            
            echo -e "      ${color}${icon}${NC} ${message}"
            
            if [[ -n "$hint" ]]; then
                echo -e "        ${DIM}└─ ${hint}${NC}"
            fi
        done <<< "${file_diags[$file]}"
        unset seen_msgs
    done
}

# =============================================================================
# SUMMARY
# =============================================================================

print_summary() {
    echo ""
    
    local result_str result_color
    
    if [[ $TOTAL_FAILED -gt 0 ]]; then
        result_str="FAILED"
        result_color="$RED"
    elif [[ $TOTAL_WARNINGS -gt 0 ]]; then
        result_str="PASSED"
        result_color="$YELLOW"
    else
        result_str="PASSED"
        result_color="$GREEN"
    fi
    
    # Compact summary line
    local stats="${TOTAL_PASSED}/${TOTAL_TESTS} tests"
    [[ $TOTAL_WARNINGS -gt 0 ]] && stats+=", ${TOTAL_WARNINGS} with warnings"
    [[ $TOTAL_FAILED -gt 0 ]] && stats+=", ${TOTAL_FAILED} failed"
    
    echo -e "${BOLD}${result_color}${result_str}${NC} ${DIM}(${stats})${NC}"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo -e "${BOLD}nutshell QA${NC}"
    echo ""
    
    run_test "Config Schema" "$SCRIPT_DIR/check_config_schema.sh"
    run_test "Syntax" "$SCRIPT_DIR/check_syntax.sh"
    run_test "File Size" "$SCRIPT_DIR/check_file_size.sh"
    run_test "Duplication" "$SCRIPT_DIR/check_function_duplication.sh"
    run_test "Trivial Wrappers" "$SCRIPT_DIR/check_trivial_wrappers.sh"
    run_test "Cruft" "$SCRIPT_DIR/check_no_cruft.sh"
    run_test "Public API Docs" "$SCRIPT_DIR/check_public_api_docs.sh"
    
    print_diagnostics
    print_summary
    
    [[ $TOTAL_FAILED -gt 0 ]] && exit 1
    exit 0
}

main "$@"
