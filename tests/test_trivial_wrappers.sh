#!/usr/bin/env bash
# =============================================================================
# test_trivial_wrappers.sh - Trivial Wrapper Function Detection Test
# =============================================================================
# Detects functions that have only 1-2 lines of meaningful code that just wrap
# another call, AND are not used frequently enough to justify their existence.
#
# RULES:
#   - Functions with 1-2 lines of actual code (excluding declarations, comments)
#     are considered "trivial wrappers"
#   - Trivial wrappers are ALLOWED if ANY of these conditions are met:
#     * They have >= LOCAL_USAGE_THRESHOLD usages in the same file (default: 4)
#     * They have >= GLOBAL_USAGE_THRESHOLD usages across codebase (default: 6)
#     * They use >= MIN_VARS_FOR_ERGONOMIC variables (default: 2) - ergonomic benefit
#     * They have >= TOKEN_COMPLEXITY_PASS tokens/spaces (default: 4) - complex enough
#     * They have #@@ALLOW_TRIVIAL_WRAPPER@@ comment above them
#   - Functions with >= TOKEN_COMPLEXITY_WARN tokens get a warning, not error
#   - Otherwise, they should be inlined or expanded with real logic
#
# Thresholds (configurable via environment variables):
#   LOCAL_USAGE_THRESHOLD    - Minimum usages in same file to allow (default: 4)
#   GLOBAL_USAGE_THRESHOLD   - Minimum usages across codebase to allow (default: 6)
#   MIN_VARS_FOR_ERGONOMIC   - Minimum variables used to be considered ergonomic (default: 2)
#   TOKEN_COMPLEXITY_WARN    - Token count that triggers warning instead of error (default: 3)
#   TOKEN_COMPLEXITY_PASS    - Token count that auto-passes (default: 4)
#   WARN_THRESHOLD           - Number of violations before warning (default: 5)
#   FAIL_THRESHOLD           - Number of violations before failing (default: 20)
#
# Usage: ./scripts/tests/test_trivial_wrappers.sh
#
# Exit codes:
#   0 - All checks passed (may have warnings)
#   1 - Too many trivial wrappers found
# =============================================================================

set -uo pipefail

# Source the test framework
source "$(dirname "${BASH_SOURCE[0]}")/framework.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

LOCAL_USAGE_THRESHOLD="${LOCAL_USAGE_THRESHOLD:-4}"
GLOBAL_USAGE_THRESHOLD="${GLOBAL_USAGE_THRESHOLD:-6}"
MIN_VARS_FOR_ERGONOMIC="${MIN_VARS_FOR_ERGONOMIC:-2}"
TOKEN_COMPLEXITY_WARN="${TOKEN_COMPLEXITY_WARN:-3}"
TOKEN_COMPLEXITY_PASS="${TOKEN_COMPLEXITY_PASS:-4}"
WARN_THRESHOLD="${WARN_THRESHOLD:-5}"
FAIL_THRESHOLD="${FAIL_THRESHOLD:-20}"

# =============================================================================
# FUNCTION ANALYSIS
# =============================================================================

# Check if a function has the ALLOW_TRIVIAL_WRAPPER annotation
# Returns 0 if allowed, 1 if not
has_allow_annotation() {
    local file="$1"
    local func_name="$2"
    
    # Look for the annotation in the 5 lines before the function definition
    # This handles cases where there might be doc comments between annotation and func
    local line_num
    line_num=$(grep -n "^[[:space:]]*${func_name}[[:space:]]*()[[:space:]]*{" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    
    if [[ -z "$line_num" ]]; then
        # Try alternate function syntax
        line_num=$(grep -n "^[[:space:]]*function[[:space:]]\+${func_name}[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    fi
    
    if [[ -z "$line_num" ]] || [[ "$line_num" -lt 1 ]]; then
        return 1
    fi
    
    # Check the 5 lines before the function definition
    local start_line=$((line_num - 5))
    if [[ $start_line -lt 1 ]]; then
        start_line=1
    fi
    
    if sed -n "${start_line},${line_num}p" "$file" 2>/dev/null | grep -q '#@@ALLOW_TRIVIAL_WRAPPER@@'; then
        return 0
    fi
    
    return 1
}

# Count usages of a function in a specific file (excluding the definition)
count_local_usages() {
    local file="$1"
    local func_name="$2"
    
    # Count occurrences that are NOT the function definition
    local count
    count=$(grep -c "\b${func_name}\b" "$file" 2>/dev/null || echo "0")
    # Ensure it's a number
    count="${count//[^0-9]/}"
    if [[ -z "$count" ]]; then
        count=0
    fi
    echo "$count"
}

# Count usages of a function across all script files (excluding the definition)
count_global_usages() {
    local func_name="$1"
    local defining_file="$2"
    
    local count=0
    
    # Use grep -r for efficiency, count total matches
    local total
    total=$(grep -r "\b${func_name}\b" "$LIB_DIR" --include="*.sh" 2>/dev/null | grep -v "\.legacy" | wc -l || echo "0")
    total="${total//[^0-9]/}"
    if [[ -z "$total" ]]; then
        total=0
    fi
    
    # Subtract 1 for the definition itself
    count=$((total - 1))
    if [[ $count -lt 0 ]]; then
        count=0
    fi
    
    echo "$count"
}

# Count unique variables used in a function body
# Returns the count of distinct variable references ($var, ${var}, $1, $2, etc.)
count_variables_used() {
    local body="$1"
    
    # Extract all variable references:
    # - Named variables: $var, ${var}, ${var:-...}
    # - Positional parameters: $1, $2, ${1}, ${10}
    # - Special variables: $@, $*, $#, $?, $$
    local var_count
    var_count=$(echo "$body" | grep -oE '\$\{?[a-zA-Z_0-9@*#?!-][a-zA-Z0-9_]*' | \
        sed 's/^\${\?//' | \
        sort -u | \
        wc -l | \
        tr -d ' ')
    
    # Ensure it's a number
    var_count="${var_count//[^0-9]/}"
    if [[ -z "$var_count" ]]; then
        var_count=0
    fi
    
    echo "$var_count"
}

# Count token complexity (number of whitespace-separated tokens/words)
# This measures how "complex" a line is - more tokens = more ergonomic benefit
count_token_complexity() {
    local body="$1"
    
    # Count distinct whitespace boundaries (spaces, tabs between words)
    # We count the number of whitespace sequences, which equals tokens - 1
    local space_count
    space_count=$(echo "$body" | grep -oE '[[:space:]]+' | wc -l | tr -d ' ')
    
    # Ensure it's a number
    space_count="${space_count//[^0-9]/}"
    if [[ -z "$space_count" ]]; then
        space_count=0
    fi
    
    echo "$space_count"
}

# Analyze all functions in a file and detect trivial wrappers
# Output format: "filepath|funcname|line_count|local_usages|global_usages|var_count|body"
analyze_file_for_wrappers() {
    local file="$1"
    local rel_path="${file#$REPO_ROOT/}"
    
    # First pass: extract all potential trivial wrappers using awk
    local wrappers
    wrappers=$(awk -v file="$rel_path" '
    BEGIN {
        in_func = 0
        func_name = ""
        brace_count = 0
        body = ""
        meaningful_lines = 0
        func_start_line = 0
    }
    
    # Match function definition start
    /^[[:space:]]*(function[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)[[:space:]]*\{?/ {
        if (in_func && brace_count > 0) {
            # Nested function - skip
            next
        }
        
        # Extract function name
        line = $0
        gsub(/^[[:space:]]*(function[[:space:]]+)?/, "", line)
        gsub(/[[:space:]]*\(.*/, "", line)
        func_name = line
        
        in_func = 1
        brace_count = 0
        body = ""
        meaningful_lines = 0
        func_start_line = NR
        
        # Count opening brace if on same line
        if (match($0, /\{/)) {
            brace_count = 1
        }
        next
    }
    
    # Process lines when inside a function
    in_func {
        # Count braces
        n = gsub(/\{/, "{")
        brace_count += n
        n = gsub(/\}/, "}")
        brace_count -= n
        
        # Skip opening brace only line
        if ($0 ~ /^[[:space:]]*\{[[:space:]]*$/) {
            next
        }
        
        # Check if function ended
        if (brace_count <= 0) {
            # Output if this looks like a trivial wrapper (1-2 meaningful lines)
            if (meaningful_lines >= 1 && meaningful_lines <= 2 && body != "") {
                # Clean up body for output
                gsub(/\n+$/, "", body)
                gsub(/\n/, " ; ", body)
                printf "%s|%s|%d|%s\n", file, func_name, meaningful_lines, body
            }
            
            in_func = 0
            func_name = ""
            body = ""
            meaningful_lines = 0
            next
        }
        
        # Skip empty lines
        if ($0 ~ /^[[:space:]]*$/) {
            next
        }
        
        # Skip comment lines
        if ($0 ~ /^[[:space:]]*#/) {
            next
        }
        
        # Skip closing brace only
        if ($0 ~ /^[[:space:]]*\}[[:space:]]*$/) {
            next
        }
        
        # Skip local variable declarations (they dont count as meaningful logic)
        if ($0 ~ /^[[:space:]]*local[[:space:]]/) {
            next
        }
        
        # Skip readonly declarations
        if ($0 ~ /^[[:space:]]*readonly[[:space:]]/) {
            next
        }
        
        # Skip export declarations
        if ($0 ~ /^[[:space:]]*export[[:space:]]/) {
            next
        }
        
        # Skip bare return statements
        if ($0 ~ /^[[:space:]]*return[[:space:]]*[0-9]*[[:space:]]*$/) {
            next
        }
        
        # Skip return $?
        if ($0 ~ /^[[:space:]]*return[[:space:]]+\$\?[[:space:]]*$/) {
            next
        }
        
        # This is a meaningful line
        meaningful_lines++
        
        # Store the line content
        line = $0
        gsub(/^[[:space:]]+/, "", line)
        gsub(/[[:space:]]+$/, "", line)
        
        if (body == "") {
            body = line
        } else {
            body = body "\n" line
        }
    }
    ' "$file")
    
    # Second pass: for each potential wrapper, count usages and check annotation
    echo "$wrappers" | while IFS='|' read -r filepath funcname line_count body; do
        [[ -z "$funcname" ]] && continue
        
        # Check for ALLOW annotation
        if has_allow_annotation "$file" "$funcname"; then
            continue  # Skip - explicitly allowed
        fi
        
        # Count usages
        local local_usages global_usages
        local_usages=$(count_local_usages "$file" "$funcname")
        # Ensure numeric and subtract definition
        local_usages="${local_usages//[^0-9]/}"
        if [[ -z "$local_usages" ]]; then
            local_usages=0
        fi
        local_usages=$((local_usages - 1))
        if [[ $local_usages -lt 0 ]]; then
            local_usages=0
        fi
        
        global_usages=$(count_global_usages "$funcname" "$file")
        global_usages="${global_usages//[^0-9]/}"
        if [[ -z "$global_usages" ]]; then
            global_usages=0
        fi
        
        # Check if usage thresholds are met
        if [[ $local_usages -ge $LOCAL_USAGE_THRESHOLD ]] || [[ $global_usages -ge $GLOBAL_USAGE_THRESHOLD ]]; then
            continue  # Skip - meets usage threshold
        fi
        
        # Count variables used in the body
        local var_count
        var_count=$(count_variables_used "$body")
        
        # Check if this wrapper has ergonomic benefit (uses multiple variables)
        if [[ $var_count -ge $MIN_VARS_FOR_ERGONOMIC ]]; then
            continue  # Skip - provides ergonomic benefit (remembers multiple vars)
        fi
        
        # Count token complexity
        local token_count
        token_count=$(count_token_complexity "$body")
        
        # Check if this wrapper is complex enough to auto-pass
        if [[ $token_count -ge $TOKEN_COMPLEXITY_PASS ]]; then
            continue  # Skip - complex enough to be ergonomic
        fi
        
        # Determine if this is a warning or error based on token complexity
        local severity="error"
        if [[ $token_count -ge $TOKEN_COMPLEXITY_WARN ]]; then
            severity="warn"
        fi
        
        # This is a trivial wrapper that should be flagged
        echo "$filepath|$funcname|$line_count|$local_usages|$global_usages|$var_count|$token_count|$severity|$body"
    done
}

# Check if a wrapper is truly trivial based on its content
# Some patterns indicate actual value even in 1-2 lines
is_trivial_content() {
    local body="$1"
    
    # If it has complex conditionals spanning logic, it's not trivial
    if [[ "$body" == *"if "* ]] && [[ "$body" == *"then"* ]]; then
        return 1  # Not trivial
    fi
    
    # If it has a loop, it's not trivial
    if [[ "$body" == *"for "* ]] || [[ "$body" == *"while "* ]] || [[ "$body" == *"until "* ]]; then
        return 1
    fi
    
    # Multiple pipe operations suggest real transformation
    local pipe_count
    pipe_count=$(echo "$body" | grep -o '|' | wc -l | tr -d ' ')
    if [[ $pipe_count -gt 2 ]]; then
        return 1
    fi
    
    # Everything else is trivial
    return 0
}

# =============================================================================
# MAIN TEST
# =============================================================================

test_trivial_wrappers() {
    log_header "Trivial Wrapper Function Detection Test"
    log_info "Detecting functions with 1-2 lines that just wrap another call"
    log_info "Thresholds (ANY passes): local >= $LOCAL_USAGE_THRESHOLD OR global >= $GLOBAL_USAGE_THRESHOLD usages"
    log_info "Ergonomic: >= $MIN_VARS_FOR_ERGONOMIC variables OR >= $TOKEN_COMPLEXITY_PASS tokens auto-pass"
    log_info "Token complexity >= $TOKEN_COMPLEXITY_WARN triggers warning instead of error"
    log_info "Use #@@ALLOW_TRIVIAL_WRAPPER@@ above a function to explicitly allow it"
    echo ""
    
    local files
    files=$(get_script_files)
    
    if [[ -z "$files" ]]; then
        log_fail "No .sh files found to test"
        return 1
    fi
    
    local file_count=0
    local wrapper_count=0
    local -a wrappers=()
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        file_count=$((file_count + 1))
        
        # Analyze this file
        local results
        results=$(analyze_file_for_wrappers "$file")
        
        while IFS='|' read -r filepath funcname line_count local_usages global_usages var_count token_count severity body; do
            [[ -z "$funcname" ]] && continue
            
            # Check if content is trivial
            if is_trivial_content "$body"; then
                wrappers+=("$filepath|$funcname|$line_count|$local_usages|$global_usages|$var_count|$token_count|$severity|$body")
                wrapper_count=$((wrapper_count + 1))
            fi
        done <<< "$results"
        
    done <<< "$files"
    
    echo ""
    log_info "Scanned $file_count files"
    echo ""
    
    if [[ $wrapper_count -eq 0 ]]; then
        log_pass "No trivial wrapper functions found"
        TESTS_PASSED=1
        TESTS_RUN=1
        return 0
    fi
    
    # Report all wrappers found
    log_section "Trivial Wrappers Found: $wrapper_count"
    echo ""
    
    # Group by file for cleaner output
    local current_file=""
    local error_count=0
    local warn_count=0
    
    for entry in "${wrappers[@]}"; do
        IFS='|' read -r filepath funcname line_count local_usages global_usages var_count token_count severity body <<< "$entry"
        
        if [[ "$filepath" != "$current_file" ]]; then
            if [[ -n "$current_file" ]]; then
                echo ""
            fi
            echo -e "${CYAN}$filepath${NC}"
            current_file="$filepath"
        fi
        
        if [[ "$severity" == "warn" ]]; then
            log_warn "$funcname() - $line_count line(s), $local_usages local / $global_usages global usages, $var_count vars, $token_count tokens"
            warn_count=$((warn_count + 1))
        else
            log_fail "$funcname() - $line_count line(s), $local_usages local / $global_usages global usages, $var_count vars, $token_count tokens"
            error_count=$((error_count + 1))
        fi
        echo -e "       ${MAGENTA}$body${NC}"
    done
    
    echo ""
    
    if [[ $error_count -gt $FAIL_THRESHOLD ]]; then
        echo -e "${RED}Found $error_count errors, $warn_count warnings (fail threshold: $FAIL_THRESHOLD)${NC}"
        echo -e "${RED}These functions should be inlined, expanded, or marked with #@@ALLOW_TRIVIAL_WRAPPER@@${NC}"
        TESTS_FAILED=$error_count
        TESTS_WARNED=$warn_count
        TESTS_RUN=$wrapper_count
    elif [[ $error_count -gt 0 ]]; then
        echo -e "${RED}Found $error_count errors, $warn_count warnings${NC}"
        TESTS_FAILED=$error_count
        TESTS_WARNED=$warn_count
        TESTS_RUN=$wrapper_count
    elif [[ $warn_count -gt $WARN_THRESHOLD ]]; then
        echo -e "${YELLOW}Found $warn_count warnings (warn threshold: $WARN_THRESHOLD)${NC}"
        TESTS_WARNED=$warn_count
        TESTS_PASSED=1
        TESTS_RUN=1
    else
        echo -e "${YELLOW}Found $warn_count warnings${NC}"
        TESTS_WARNED=$warn_count
        TESTS_PASSED=1
        TESTS_RUN=1
    fi
    
    echo ""
    echo "What makes a function a 'trivial wrapper':"
    echo "  - Only 1-2 lines of meaningful code (excluding declarations, comments)"
    echo "  - Just calls another function/command without adding logic"
    echo "  - Does NOT meet ANY of the ergonomic thresholds below"
    echo ""
    echo "How to resolve:"
    echo "  1. Inline the wrapper at call sites (if rarely used)"
    echo "  2. Expand with real logic (error handling, validation, logging)"
    echo "  3. Add #@@ALLOW_TRIVIAL_WRAPPER@@ above the function if it's intentional API"
    echo ""
    echo "NOT trivial (passes if ANY condition is met):"
    echo "  - Functions with >2 lines of meaningful code"
    echo "  - Functions with >= $LOCAL_USAGE_THRESHOLD local or >= $GLOBAL_USAGE_THRESHOLD global usages"
    echo "  - Functions using >= $MIN_VARS_FOR_ERGONOMIC variables (ergonomic benefit)"
    echo "  - Functions with >= $TOKEN_COMPLEXITY_PASS tokens (complex enough)"
    echo "  - Functions with conditionals, loops, or complex logic"
    echo "  - Functions marked with #@@ALLOW_TRIVIAL_WRAPPER@@"
    echo ""
    echo "WARNING instead of ERROR:"
    echo "  - Functions with >= $TOKEN_COMPLEXITY_WARN tokens get a warning, not error"
    
    if [[ $error_count -gt 0 ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# RUN TEST
# =============================================================================

main() {
    test_trivial_wrappers
    local result=$?
    print_summary "Trivial Wrapper Detection"
    exit_with_status
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
