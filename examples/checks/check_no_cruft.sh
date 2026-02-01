#!/usr/bin/env nutshell
# =============================================================================
# check_no_cruft.sh - Deprecation and Backwards Compatibility Detection Check
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Detects any code that exists only for backwards compatibility, deprecation,
# or legacy support. Such code is cruft that should be removed immediately.
#
# FULLY CONFIG-DRIVEN: All patterns and thresholds come from nut.toml.
# See examples/configs/empty.nut.toml for all available options.
#
# FLAGGED PATTERNS (configurable):
#   - Debug code patterns (echo DEBUG, set -x, etc.)
#   - TODO/FIXME patterns
#   - Deprecated/legacy/obsolete comments and names
#
# Usage: ./examples/checks/check_no_cruft.sh
#
# Exit codes:
#   0 - No cruft found
#   1 - Cruft detected, or test disabled
# =============================================================================

set -uo pipefail

# Load the check-runner framework (provides cfg_*, log_*, etc.)
use check-runner

# =============================================================================
# CONFIG-DRIVEN PARAMETERS
# =============================================================================

# Default patterns (used if config doesn't specify)
declare -a DEBUG_PATTERNS=()
declare -a TODO_PATTERNS=()
FAIL_ON_DEBUG="true"
FAIL_ON_TODO="false"
MAX_TODOS=10

load_config() {
    # Check if test is enabled
    if ! cfg_is_true "tests.cruft"; then
        log_info "Cruft test is disabled in config"
        exit 0
    fi
    
    # Load debug patterns from config
    if ! cfg_get_array "tests.cruft.debug_patterns" DEBUG_PATTERNS; then
        # Default debug patterns
        DEBUG_PATTERNS=(
            "echo.*DEBUG"
            "echo.*TODO"
            "echo.*FIXME"
            "echo.*XXX"
            "set -x"
            "PS4="
            "BASH_XTRACEFD"
            "# DEBUG"
            "# TEMP"
            "# TEMPORARY"
            "# REMOVE"
            "# DELETE"
        )
    fi
    
    # Load TODO patterns from config
    if ! cfg_get_array "tests.cruft.todo_patterns" TODO_PATTERNS; then
        # Default TODO patterns
        TODO_PATTERNS=(
            "TODO:"
            "TODO\\("
            "FIXME:"
            "FIXME\\("
            "XXX:"
            "XXX\\("
            "HACK:"
            "HACK\\("
            "BUG:"
            "BUG\\("
            "BROKEN:"
            "REFACTOR:"
        )
    fi
    
    # Load thresholds
    FAIL_ON_DEBUG="$(cfg_get_or "tests.cruft.fail_on_debug" "true")"
    FAIL_ON_TODO="$(cfg_get_or "tests.cruft.fail_on_todo" "false")"
    MAX_TODOS="$(cfg_get_or "tests.cruft.max_todos" "10")"
}

# =============================================================================
# CRUFT PATTERNS (built from config)
# =============================================================================

# Combined pattern for comments (case-insensitive search)
# Note: These patterns are designed to catch actual deprecation/backwards-compat markers
# while avoiding false positives on legitimate code comments like "# Remove duplicates"
# Patterns are intentionally specific to minimize false positives
COMMENT_PATTERN='(deprecated|backwards?.?compat(ibility)?|legacy[[:space:]]+(code|support|api)|obsolete[[:space:]]+(code|function|api)|todo[[:space:]]*:?[[:space:]]*remove|fixme[[:space:]]*:?[[:space:]]*remove|to[[:space:]]+be[[:space:]]+removed|will[[:space:]]+be[[:space:]]+removed|remove[[:space:]]+in[[:space:]]+(future|v[0-9])|temporary[[:space:]]+fix|temp[[:space:]]+fix|hack[[:space:]]*:?[[:space:]]*remove|workaround[[:space:]]+for[[:space:]]+old|shim[[:space:]]+for|compat[[:space:]]*\.?[[:space:]]*layer|compatibility[[:space:]]+layer|for[[:space:]]+backwards[[:space:]]+compat|old[[:space:]]+api|old[[:space:]]+interface|superseded[[:space:]]+by|replaced[[:space:]]+by|use[[:space:]]+.+[[:space:]]+instead|don.?t[[:space:]]+use[[:space:]]+(this|anymore)|do[[:space:]]+not[[:space:]]+use[[:space:]]+(this|anymore)|no[[:space:]]+longer[[:space:]]+(used|supported)|not[[:space:]]+used[[:space:]]+anymore)'

# Pattern for function/variable names
NAME_PATTERN='(_deprecated|deprecated_|_legacy|legacy_|_old$|^old_|_compat$|compat_|_shim$|shim_|_obsolete|obsolete_)'

# =============================================================================
# DETECTION FUNCTIONS
# =============================================================================

# Build regex pattern from array
build_pattern() {
    local -n arr="$1"
    local pattern=""
    local first=1
    
    for p in "${arr[@]}"; do
        if [[ $first -eq 1 ]]; then
            pattern="$p"
            first=0
        else
            pattern="${pattern}|${p}"
        fi
    done
    
    echo "$pattern"
}

# Search for debug patterns in a file
find_debug_cruft() {
    local file="$1"
    local rel_path="${file#$REPO_ROOT/}"
    
    local pattern
    pattern=$(build_pattern DEBUG_PATTERNS)
    [[ -z "$pattern" ]] && return
    
    grep -niE "$pattern" "$file" 2>/dev/null | while IFS=: read -r line_num content; do
        echo "$rel_path|$line_num|debug|debug pattern|$content"
    done
}

# Search for TODO patterns in a file
find_todo_cruft() {
    local file="$1"
    local rel_path="${file#$REPO_ROOT/}"
    
    local pattern
    pattern=$(build_pattern TODO_PATTERNS)
    [[ -z "$pattern" ]] && return
    
    grep -niE "$pattern" "$file" 2>/dev/null | while IFS=: read -r line_num content; do
        # Determine which pattern matched
        local lower_content
        lower_content=$(echo "$content" | tr '[:upper:]' '[:lower:]')
        
        local matched_pattern="TODO"
        if echo "$lower_content" | grep -qE 'fixme'; then
            matched_pattern="FIXME"
        elif echo "$lower_content" | grep -qE 'xxx'; then
            matched_pattern="XXX"
        elif echo "$lower_content" | grep -qE 'hack'; then
            matched_pattern="HACK"
        elif echo "$lower_content" | grep -qE 'bug'; then
            matched_pattern="BUG"
        elif echo "$lower_content" | grep -qE 'broken'; then
            matched_pattern="BROKEN"
        elif echo "$lower_content" | grep -qE 'refactor'; then
            matched_pattern="REFACTOR"
        fi
        
        echo "$rel_path|$line_num|todo|$matched_pattern|$content"
    done
}

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
        elif echo "$lower_content" | grep -qE 'to[[:space:]]+be[[:space:]]+removed|will[[:space:]]+be[[:space:]]+removed|remove[[:space:]]+in[[:space:]]+future'; then
            matched_pattern="to be removed"
        elif echo "$lower_content" | grep -qE 'temporary[[:space:]]+fix|temp[[:space:]]+fix'; then
            matched_pattern="temporary fix"
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
    log_info "Fail on debug code: $FAIL_ON_DEBUG"
    log_info "Fail on TODOs: $FAIL_ON_TODO (max: $MAX_TODOS)"
    echo ""
    
    local files
    files=$(get_script_files)
    
    if [[ -z "$files" ]]; then
        log_fail "No .sh files found to test"
        return 1
    fi
    
    local file_count=0
    local debug_count=0
    local todo_count=0
    local cruft_count=0
    local -a debug_items=()
    local -a todo_items=()
    local -a cruft_items=()
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        file_count=$((file_count + 1))
        
        # Search for debug patterns
        while IFS='|' read -r filepath line_num cruft_type pattern content; do
            [[ -z "$filepath" ]] && continue
            debug_items+=("$filepath|$line_num|$cruft_type|$pattern|$content")
            debug_count=$((debug_count + 1))
        done <<< "$(find_debug_cruft "$file")"
        
        # Search for TODO patterns
        while IFS='|' read -r filepath line_num cruft_type pattern content; do
            [[ -z "$filepath" ]] && continue
            todo_items+=("$filepath|$line_num|$cruft_type|$pattern|$content")
            todo_count=$((todo_count + 1))
        done <<< "$(find_todo_cruft "$file")"
        
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
    
    local total_issues=$((debug_count + todo_count + cruft_count))
    local error_count=0
    local warn_count=0
    
    # Report debug code
    if [[ $debug_count -gt 0 ]]; then
        log_section "Debug Code Found: $debug_count items"
        echo ""
        
        local current_file=""
        for entry in "${debug_items[@]}"; do
            IFS='|' read -r filepath line_num cruft_type pattern content <<< "$entry"
            
            if [[ "$filepath" != "$current_file" ]]; then
                if [[ -n "$current_file" ]]; then
                    echo ""
                fi
                echo -e "${CYAN}$filepath${NC}"
                current_file="$filepath"
            fi
            
            if is_truthy "$FAIL_ON_DEBUG"; then
                log_fail "Line $line_num: Debug code detected"
                error_count=$((error_count + 1))
            else
                log_test_warn "Line $line_num: Debug code detected"
                warn_count=$((warn_count + 1))
            fi
            
            # Show the content (truncated if too long)
            local display_content="$content"
            display_content="${display_content#"${display_content%%[![:space:]]*}"}"
            if [[ ${#display_content} -gt 80 ]]; then
                display_content="${display_content:0:77}..."
            fi
            echo -e "       ${MAGENTA}${display_content}${NC}"
        done
    fi
    
    # Report TODOs
    if [[ $todo_count -gt 0 ]]; then
        log_section "TODOs Found: $todo_count items"
        echo ""
        
        local current_file=""
        for entry in "${todo_items[@]}"; do
            IFS='|' read -r filepath line_num cruft_type pattern content <<< "$entry"
            
            if [[ "$filepath" != "$current_file" ]]; then
                if [[ -n "$current_file" ]]; then
                    echo ""
                fi
                echo -e "${CYAN}$filepath${NC}"
                current_file="$filepath"
            fi
            
            # TODOs fail if fail_on_todo is true OR if we exceed max_todos
            if is_truthy "$FAIL_ON_TODO" || [[ $todo_count -gt $MAX_TODOS ]]; then
                log_fail "Line $line_num: $pattern"
                error_count=$((error_count + 1))
            else
                log_test_warn "Line $line_num: $pattern"
                warn_count=$((warn_count + 1))
            fi
            
            local display_content="$content"
            display_content="${display_content#"${display_content%%[![:space:]]*}"}"
            if [[ ${#display_content} -gt 80 ]]; then
                display_content="${display_content:0:77}..."
            fi
            echo -e "       ${MAGENTA}${display_content}${NC}"
        done
        
        if [[ $todo_count -gt $MAX_TODOS ]]; then
            echo ""
            echo -e "${RED}TODOs exceed maximum of $MAX_TODOS - treat as errors${NC}"
        fi
    fi
    
    # Report cruft
    if [[ $cruft_count -gt 0 ]]; then
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
            error_count=$((error_count + 1))
            
            local display_content="$content"
            display_content="${display_content#"${display_content%%[![:space:]]*}"}"
            if [[ ${#display_content} -gt 80 ]]; then
                display_content="${display_content:0:77}..."
            fi
            echo -e "       ${MAGENTA}${display_content}${NC}"
        done
    fi
    
    # Summary
    if [[ $total_issues -eq 0 ]]; then
        log_pass "No cruft found - codebase is clean"
        TESTS_PASSED=1
        TESTS_RUN=1
        return 0
    fi
    
    echo ""
    if [[ $error_count -gt 0 ]]; then
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║                          CRUFT DETECTED                               ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${RED}Found $error_count errors that must be fixed.${NC}"
    fi
    
    if [[ $warn_count -gt 0 ]]; then
        echo -e "${YELLOW}Found $warn_count warnings to review.${NC}"
    fi
    
    echo ""
    echo "Why this matters:"
    echo "  - Debug code should never be committed"
    echo "  - TODOs should be tracked in issue tracker, not code"
    echo "  - Deprecated code is dead weight that confuses maintainers"
    echo "  - Backwards compatibility layers accumulate tech debt"
    echo ""
    echo "What to do:"
    echo "  1. Remove debug code before committing"
    echo "  2. Convert TODOs to issues and remove from code"
    echo "  3. Remove deprecated/legacy code - git has history"
    
    TESTS_RUN=$total_issues
    TESTS_FAILED=$error_count
    TESTS_WARNED=$warn_count
    TESTS_PASSED=$((total_issues - error_count - warn_count))
    [[ $TESTS_PASSED -lt 0 ]] && TESTS_PASSED=0
    
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
    test_no_cruft
    local result=$?
    
    # Print summary and exit
    print_summary "Cruft Detection"
    exit_with_status
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
