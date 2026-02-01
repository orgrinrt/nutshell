#!/usr/bin/env nutshell
# =============================================================================
# check_trivial_wrappers.sh - Trivial Wrapper Function Detection Check
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Detects functions that have only 1-2 lines of meaningful code that just wrap
# another call, AND are not used frequently enough to justify their existence.
#
# FULLY CONFIG-DRIVEN: All thresholds and patterns come from nut.toml.
# See examples/configs/empty.nut.toml for all available options.
#
# Usage: ./examples/checks/check_trivial_wrappers.sh
#
# Exit codes:
#   0 - All checks passed (may have warnings)
#   1 - Too many trivial wrappers found, or test disabled
# =============================================================================

set -uo pipefail

# Load the check-runner framework (provides cfg_*, log_*, etc.)
use check-runner

# Quiet mode - when run from main check runner, be terse
QUIET_MODE="${NUTSHELL_CHECK_QUIET:-0}"

# =============================================================================
# CONFIG-DRIVEN PARAMETERS
# All values loaded from nut.toml via the framework's cfg_get functions.
# No hardcoded defaults here - defaults come from templates/empty.nut.toml.
# =============================================================================

load_config() {
    # Check if test is enabled
    if ! cfg_is_true "tests.trivial_wrappers"; then
        log_info "Trivial wrapper test is disabled in config"
        exit 0
    fi
    
    # Load all thresholds from config
    MAX_LINES="$(cfg_get_or "tests.trivial_wrappers.max_lines" "2")"
    LOCAL_USAGE_THRESHOLD="$(cfg_get_or "tests.trivial_wrappers.local_usage_threshold" "4")"
    GLOBAL_USAGE_THRESHOLD="$(cfg_get_or "tests.trivial_wrappers.global_usage_threshold" "6")"
    MIN_VARS_FOR_ERGONOMIC="$(cfg_get_or "tests.trivial_wrappers.min_vars_for_ergonomic" "2")"
    TOKEN_COMPLEXITY_WARN="$(cfg_get_or "tests.trivial_wrappers.token_complexity_warn" "3")"
    TOKEN_COMPLEXITY_PASS="$(cfg_get_or "tests.trivial_wrappers.token_complexity_pass" "4")"
    WARN_THRESHOLD="$(cfg_get_or "tests.trivial_wrappers.warn_threshold" "5")"
    FAIL_THRESHOLD="$(cfg_get_or "tests.trivial_wrappers.fail_threshold" "20")"
    
    # Load annotation patterns from config
    PUBLIC_API_ANNOTATION="$(cfg_get_or "annotations.public_api" "@@PUBLIC_API@@")"
    ERGONOMICS_ANNOTATION="$(cfg_get_or "annotations.allow_trivial_wrapper_ergonomics" "@@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@")"
}

# =============================================================================
# FUNCTION ANALYSIS
# =============================================================================

# Check if a function has an exempting annotation
# Uses annotation patterns from config
# Returns 0 if exempt, 1 if not
has_exempt_annotation() {
    local file="$1"
    local func_name="$2"
    
    # Use the framework's has_trivial_wrapper_exemption which reads from config
    has_trivial_wrapper_exemption "$file" "$func_name"
}

# Count usages of a function in a specific file (excluding the definition)
count_local_usages() {
    local file="$1"
    local func_name="$2"
    
    local count
    count=$(grep -c "\b${func_name}\b" "$file" 2>/dev/null || echo "0")
    count="${count//[^0-9]/}"
    [[ -z "$count" ]] && count=0
    
    # Subtract 1 for the definition itself
    count=$((count - 1))
    [[ $count -lt 0 ]] && count=0
    
    echo "$count"
}

# Count usages of a function across all files
count_global_usages() {
    local func_name="$1"
    
    local total=0
    local file count
    
    while IFS= read -r file; do
        count=$(grep -c "\b${func_name}\b" "$file" 2>/dev/null || echo "0")
        count="${count//[^0-9]/}"
        [[ -z "$count" ]] && count=0
        total=$((total + count))
    done < <(get_script_files)
    
    # Subtract 1 for the definition
    total=$((total - 1))
    [[ $total -lt 0 ]] && total=0
    
    echo "$total"
}

# Extract meaningful code lines from a function body
# Excludes: comments, blank lines, local declarations, opening/closing braces
get_meaningful_lines() {
    local file="$1"
    local func_name="$2"
    
    # Find the line number where the function starts
    local func_line
    func_line=$(grep -n "^[[:space:]]*${func_name}[[:space:]]*()[[:space:]]*{" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    
    if [[ -z "$func_line" ]]; then
        # Try alternate syntax: function name() or function name ()
        func_line=$(grep -n "^[[:space:]]*function[[:space:]]\+${func_name}[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    fi
    
    [[ -z "$func_line" ]] && return
    
    # Find the closing brace - simple heuristic: next line starting with }
    # This works for most well-formatted shell functions
    local end_line
    end_line=$(tail -n "+$((func_line + 1))" "$file" | grep -n "^}" | head -1 | cut -d: -f1)
    
    if [[ -z "$end_line" ]]; then
        # Fallback: look for } at start of line with possible whitespace
        end_line=$(tail -n "+$((func_line + 1))" "$file" | grep -n "^[[:space:]]*}[[:space:]]*$" | head -1 | cut -d: -f1)
    fi
    
    [[ -z "$end_line" ]] && return
    
    # Adjust end_line to be absolute (it's relative to func_line+1)
    end_line=$((func_line + end_line))
    
    # Extract lines between func start and end, filter out non-meaningful lines
    sed -n "$((func_line + 1)),$((end_line - 1))p" "$file" 2>/dev/null | \
        grep -v '^[[:space:]]*#' | \
        grep -v '^[[:space:]]*$' | \
        grep -v '^[[:space:]]*local[[:space:]]' | \
        grep -v '^[[:space:]]*readonly[[:space:]]' | \
        grep -v '^[[:space:]]*return[[:space:]]*$' | \
        grep -v '^[[:space:]]*return[[:space:]]\+\$?' | \
        grep -v '^[[:space:]]*}[[:space:]]*$'
}

# Count meaningful lines in a function
count_meaningful_lines() {
    local file="$1"
    local func_name="$2"
    
    get_meaningful_lines "$file" "$func_name" | wc -l | tr -d ' '
}

# Count unique variables used in function body
count_variables_used() {
    local file="$1"
    local func_name="$2"
    
    get_meaningful_lines "$file" "$func_name" | \
        grep -oE '\$\{?[a-zA-Z_][a-zA-Z0-9_]*' | \
        sed 's/[${}]//g' | \
        sort -u | \
        wc -l | \
        tr -d ' '
}

# Count tokens (complexity indicator) in function body
count_tokens() {
    local file="$1"
    local func_name="$2"
    
    get_meaningful_lines "$file" "$func_name" | \
        tr -s '[:space:]' '\n' | \
        grep -v '^$' | \
        wc -l | \
        tr -d ' '
}

# Analyze a single function for trivial wrapper status
# Returns: pass, warn, or fail
analyze_function() {
    local file="$1"
    local func_name="$2"
    
    # Get metrics
    local line_count var_count token_count local_usages global_usages
    line_count=$(count_meaningful_lines "$file" "$func_name")
    
    # Not a trivial wrapper if more than MAX_LINES
    if [[ $line_count -gt $MAX_LINES ]]; then
        echo "pass:not_trivial"
        return
    fi
    
    # Check for exempt annotation
    if has_exempt_annotation "$file" "$func_name"; then
        echo "pass:annotated"
        return
    fi
    
    # Calculate other metrics
    var_count=$(count_variables_used "$file" "$func_name")
    token_count=$(count_tokens "$file" "$func_name")
    local_usages=$(count_local_usages "$file" "$func_name")
    global_usages=$(count_global_usages "$func_name")
    
    # Check ergonomic passes (ANY of these = pass)
    if [[ $local_usages -ge $LOCAL_USAGE_THRESHOLD ]]; then
        echo "pass:local_usage"
        return
    fi
    
    if [[ $global_usages -ge $GLOBAL_USAGE_THRESHOLD ]]; then
        echo "pass:global_usage"
        return
    fi
    
    if [[ $var_count -ge $MIN_VARS_FOR_ERGONOMIC ]]; then
        echo "pass:ergonomic_vars"
        return
    fi
    
    if [[ $token_count -ge $TOKEN_COMPLEXITY_PASS ]]; then
        echo "pass:complex"
        return
    fi
    
    # Warn vs fail based on token complexity
    if [[ $token_count -ge $TOKEN_COMPLEXITY_WARN ]]; then
        echo "warn:${line_count}:${local_usages}:${global_usages}:${var_count}:${token_count}"
        return
    fi
    
    echo "fail:${line_count}:${local_usages}:${global_usages}:${var_count}:${token_count}"
}

# Get the first meaningful line of a function (for display)
get_function_preview() {
    local file="$1"
    local func_name="$2"
    
    get_meaningful_lines "$file" "$func_name" | head -1 | sed 's/^[[:space:]]*//'
}

# =============================================================================
# MAIN TEST LOGIC
# =============================================================================

test_trivial_wrappers() {
    if [[ "$QUIET_MODE" != "1" ]]; then
        log_header "Trivial Wrapper Function Detection Test"
        
        log_info "Detecting functions with 1-$MAX_LINES lines that just wrap another call"
        log_info "Thresholds (ANY passes): local >= $LOCAL_USAGE_THRESHOLD OR global >= $GLOBAL_USAGE_THRESHOLD usages"
        log_info "Ergonomic: >= $MIN_VARS_FOR_ERGONOMIC variables OR >= $TOKEN_COMPLEXITY_PASS tokens auto-pass"
        log_info "Token complexity >= $TOKEN_COMPLEXITY_WARN triggers warning instead of error"
        log_info "Exempt annotations: $PUBLIC_API_ANNOTATION, $ERGONOMICS_ANNOTATION"
        echo ""
    fi
    
    local files
    files=$(get_script_files)
    
    local file_count=0
    local wrapper_count=0
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
        local file_issues=""
        
        # Get all functions in this file
        local functions
        functions=$(extract_functions "$file")
        
        while IFS= read -r func_name; do
            [[ -z "$func_name" ]] && continue
            
            local result
            result=$(analyze_function "$file" "$func_name")
            
            local status="${result%%:*}"
            local details="${result#*:}"
            
            case "$status" in
                pass)
                    # Passed - do nothing
                    ;;
                warn)
                    wrapper_count=$((wrapper_count + 1))
                    warn_count=$((warn_count + 1))
                    
                    IFS=':' read -r lines local_use global_use vars tokens <<< "$details"
                    local preview
                    preview=$(get_function_preview "$file" "$func_name")
                    
                    if [[ "$QUIET_MODE" != "1" ]]; then
                        if [[ $file_has_issues -eq 0 ]]; then
                            file_issues+="\n${rel_path}"
                            file_has_issues=1
                        fi
                        file_issues+="\n${YELLOW}[WARN]${NC} ${func_name}() - ${lines} line(s), ${local_use} local / ${global_use} global usages, ${vars} vars, ${tokens} tokens"
                        file_issues+="\n       ${preview}"
                    fi
                    
                    warnings+=("${func_name}() - ${lines} line(s), ${local_use} local / ${global_use} global usages, ${vars} vars, ${tokens} tokens")
                    ;;
                fail)
                    wrapper_count=$((wrapper_count + 1))
                    error_count=$((error_count + 1))
                    
                    IFS=':' read -r lines local_use global_use vars tokens <<< "$details"
                    local preview
                    preview=$(get_function_preview "$file" "$func_name")
                    
                    if [[ "$QUIET_MODE" != "1" ]]; then
                        if [[ $file_has_issues -eq 0 ]]; then
                            file_issues+="\n${rel_path}"
                            file_has_issues=1
                        fi
                        file_issues+="\n  ${RED}✗${NC} ${func_name}() - ${lines} line(s), ${local_use} local / ${global_use} global usages, ${vars} vars, ${tokens} tokens"
                        file_issues+="\n       ${preview}"
                    fi
                    
                    errors+=("${func_name}() - ${lines} line(s), ${local_use} local / ${global_use} global usages, ${vars} vars, ${tokens} tokens")
                    ;;
            esac
        done <<< "$functions"
        
        if [[ -n "$file_issues" ]] && [[ "$QUIET_MODE" != "1" ]]; then
            echo -e "$file_issues"
        fi
        
    done <<< "$files"
    
    if [[ "$QUIET_MODE" != "1" ]]; then
        log_info "Scanned $file_count files"
        echo ""
        
        # Summary and help text only in verbose mode
        if [[ $wrapper_count -gt 0 ]]; then
            log_section "Trivial Wrappers Found: $wrapper_count"
            echo ""
            
            if [[ $error_count -gt 0 ]]; then
                echo -e "${RED}Found $error_count errors, $warn_count warnings${NC}"
            else
                echo -e "${YELLOW}Found $warn_count warnings${NC}"
            fi
            echo ""
            
            # Help text
            echo "What makes a function a 'trivial wrapper':"
            echo "  - Only 1-$MAX_LINES lines of meaningful code (excluding declarations, comments)"
            echo "  - Just calls another function/command without adding logic"
            echo "  - Does NOT meet ANY of the ergonomic thresholds below"
            echo ""
            echo "How to resolve:"
            echo "  1. Inline the wrapper at call sites (if rarely used)"
            echo "  2. Expand with real logic (error handling, validation, logging)"
            echo "  3. Add # $PUBLIC_API_ANNOTATION if it's part of the public API"
            echo "  4. Add # $ERGONOMICS_ANNOTATION if it's intentional for API consistency"
            echo ""
            echo "NOT trivial (passes if ANY condition is met):"
            echo "  - Functions with >$MAX_LINES lines of meaningful code"
            echo "  - Functions with >= $LOCAL_USAGE_THRESHOLD local or >= $GLOBAL_USAGE_THRESHOLD global usages"
            echo "  - Functions using >= $MIN_VARS_FOR_ERGONOMIC variables (ergonomic benefit)"
            echo "  - Functions with >= $TOKEN_COMPLEXITY_PASS tokens (complex enough)"
            echo "  - Functions with conditionals, loops, or complex logic"
            echo "  - Functions marked with exempt annotations"
            echo ""
            echo "WARNING instead of ERROR:"
            echo "  - Functions with >= $TOKEN_COMPLEXITY_WARN tokens get a warning, not error"
            echo ""
        fi
    fi
    
    # Set test counters for framework
    TESTS_RUN=$wrapper_count
    if [[ $wrapper_count -eq 0 ]]; then
        TESTS_RUN=1
        TESTS_PASSED=1
    else
        TESTS_PASSED=$((wrapper_count - error_count - warn_count))
        [[ $TESTS_PASSED -lt 0 ]] && TESTS_PASSED=0
    fi
    TESTS_FAILED=$error_count
    TESTS_WARNED=$warn_count
    FAILED_TESTS=("${errors[@]}")
    WARNED_TESTS=("${warnings[@]}")
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Load configuration from nut.toml
    load_config
    
    # Run the test
    test_trivial_wrappers
    
    # Print summary and exit
    print_summary "Trivial Wrapper Detection"
    exit_with_status
}

main "$@"
