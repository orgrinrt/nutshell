#!/usr/bin/env nutshell
# =============================================================================
# check_config_schema.sh - Configuration Schema Validation Check
# =============================================================================
# Validates that the nut.toml configuration file has valid structure.
# Uses nutshell's own toml.sh - no external dependencies.
#
# Usage: ./examples/checks/check_config_schema.sh
#
# Exit codes:
#   0 - Configuration is valid
#   1 - Configuration has errors
# =============================================================================

set -uo pipefail

# Load the check-runner framework (provides cfg_*, log_*, etc.)
use check-runner

# =============================================================================
# SCHEMA DEFINITION
# =============================================================================

# Valid top-level sections
VALID_SECTIONS="meta paths deps annotations tests output"

# Valid keys per section
declare -A VALID_KEYS
VALID_KEYS[meta]="version name description"
VALID_KEYS[paths]="lib_dir exclude include"
VALID_KEYS[deps.paths]="*"  # Any tool name allowed
VALID_KEYS[annotations]="public_api allow_trivial_wrapper_ergonomics allow_large_file"
VALID_KEYS[tests]="syntax trivial_wrappers file_size function_duplication cruft public_api_docs"
VALID_KEYS[tests.syntax]="shell fail_on_error"
VALID_KEYS[tests.trivial_wrappers]="max_lines local_usage_threshold global_usage_threshold min_vars_for_ergonomic token_complexity_warn token_complexity_pass warn_threshold fail_threshold exempt_annotations exclude_patterns"
VALID_KEYS[tests.file_size]="max_loc max_total_lines exempt_annotation_pattern exempt_patterns"
VALID_KEYS[tests.function_duplication]="similarity_threshold min_lines_to_check ignore_name_patterns exclude_patterns"
VALID_KEYS[tests.cruft]="debug_patterns todo_patterns fail_on_debug fail_on_todo max_todos"
VALID_KEYS[tests.public_api_docs]="public_api_annotation required_elements recommended_elements min_doc_lines"
VALID_KEYS[output]="color verbosity format show_passing show_summary"

# Valid enum values
declare -A VALID_ENUMS
VALID_ENUMS[tests.syntax.shell]="bash sh zsh"
VALID_ENUMS[output.color]="auto always never"
VALID_ENUMS[output.verbosity]="quiet normal verbose"
VALID_ENUMS[output.format]="human json tap"

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Check if a value is in a space-separated list
_in_list() {
    local needle="$1"
    local haystack="$2"
    [[ " $haystack " == *" $needle "* ]]
}

# Validate a section exists and has valid keys
validate_section() {
    local file="$1"
    local section="$2"
    local errors=0
    
    # Get valid keys for this section
    local valid_keys="${VALID_KEYS[$section]:-}"
    
    # If no valid keys defined, skip validation
    [[ -z "$valid_keys" ]] && return 0
    
    # Wildcard means any key is valid
    [[ "$valid_keys" == "*" ]] && return 0
    
    # Get actual keys in section
    local keys
    keys=$(toml_keys "$file" "$section" 2>/dev/null) || return 0
    
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        
        if ! _in_list "$key" "$valid_keys"; then
            log_test_warn "Unknown key '$key' in section [$section]"
            ((errors++))
        fi
    done <<< "$keys"
    
    return $errors
}

# Validate enum values
validate_enums() {
    local file="$1"
    local errors=0
    
    for key in "${!VALID_ENUMS[@]}"; do
        local value
        value=$(toml_get "$file" "$key" 2>/dev/null) || continue
        
        local valid_values="${VALID_ENUMS[$key]}"
        if ! _in_list "$value" "$valid_values"; then
            log_fail "Invalid value '$value' for '$key' (must be one of: $valid_values)"
            ((errors++))
        fi
    done
    
    return $errors
}

# Validate numeric values are actually numbers
validate_numbers() {
    local file="$1"
    local errors=0
    
    local numeric_keys=(
        "tests.trivial_wrappers.max_lines"
        "tests.trivial_wrappers.local_usage_threshold"
        "tests.trivial_wrappers.global_usage_threshold"
        "tests.trivial_wrappers.min_vars_for_ergonomic"
        "tests.trivial_wrappers.token_complexity_warn"
        "tests.trivial_wrappers.token_complexity_pass"
        "tests.trivial_wrappers.warn_threshold"
        "tests.trivial_wrappers.fail_threshold"
        "tests.file_size.max_loc"
        "tests.file_size.max_total_lines"
        "tests.function_duplication.min_lines_to_check"
        "tests.cruft.max_todos"
        "tests.public_api_docs.min_doc_lines"
    )
    
    for key in "${numeric_keys[@]}"; do
        local value
        value=$(toml_get "$file" "$key" 2>/dev/null) || continue
        
        if ! [[ "$value" =~ ^[0-9]+$ ]]; then
            log_fail "'$key' must be a non-negative integer, got '$value'"
            ((errors++))
        fi
    done
    
    # Float check for similarity_threshold
    local sim_threshold
    sim_threshold=$(toml_get "$file" "tests.function_duplication.similarity_threshold" 2>/dev/null) || true
    if [[ -n "$sim_threshold" ]]; then
        if ! [[ "$sim_threshold" =~ ^[0-9]*\.?[0-9]+$ ]]; then
            log_fail "'tests.function_duplication.similarity_threshold' must be a number, got '$sim_threshold'"
            ((errors++))
        fi
    fi
    
    return $errors
}

# Validate boolean values
validate_booleans() {
    local file="$1"
    local errors=0
    
    local bool_keys=(
        "tests.syntax.fail_on_error"
        "tests.cruft.fail_on_debug"
        "tests.cruft.fail_on_todo"
        "output.show_passing"
        "output.show_summary"
    )
    
    for key in "${bool_keys[@]}"; do
        local value
        value=$(toml_get "$file" "$key" 2>/dev/null) || continue
        
        if [[ "$value" != "true" && "$value" != "false" ]]; then
            log_fail "'$key' must be true or false, got '$value'"
            ((errors++))
        fi
    done
    
    return $errors
}

# Validate array values are arrays
validate_arrays() {
    local file="$1"
    local errors=0
    
    local array_keys=(
        "paths.exclude"
        "paths.include"
        "tests.trivial_wrappers.exempt_annotations"
        "tests.trivial_wrappers.exclude_patterns"
        "tests.file_size.exempt_patterns"
        "tests.function_duplication.ignore_name_patterns"
        "tests.function_duplication.exclude_patterns"
        "tests.cruft.debug_patterns"
        "tests.cruft.todo_patterns"
        "tests.public_api_docs.required_elements"
        "tests.public_api_docs.recommended_elements"
    )
    
    for key in "${array_keys[@]}"; do
        local value
        value=$(toml_get "$file" "$key" 2>/dev/null) || continue
        
        # Check if it starts with [ (array syntax)
        if [[ ! "$value" =~ ^\[.*\]$ ]]; then
            log_fail "'$key' must be an array, got '$value'"
            ((errors++))
        fi
    done
    
    return $errors
}

# =============================================================================
# MAIN TEST
# =============================================================================

test_config_schema() {
    log_header "Configuration Schema Validation Test"
    
    # Find config file
    if [[ -z "${CONFIG_FILE:-}" ]] || [[ ! -f "$CONFIG_FILE" ]]; then
        log_info "No user config file to validate"
        TESTS_RUN=1
        TESTS_PASSED=1
        return 0
    fi
    
    log_info "Validating: $CONFIG_FILE"
    echo ""
    
    local total_errors=0
    
    # 1. Check file is readable TOML
    log_test "Checking TOML syntax..."
    local sections
    if ! sections=$(toml_sections "$CONFIG_FILE" 2>/dev/null); then
        log_fail "Failed to parse TOML file"
        TESTS_RUN=1
        TESTS_FAILED=1
        return 1
    fi
    log_pass "TOML syntax valid"
    
    # 2. Check for unknown top-level sections
    log_test "Checking section names..."
    local section_errors=0
    while IFS= read -r section; do
        [[ -z "$section" ]] && continue
        
        # Get top-level section name
        local top_section="${section%%.*}"
        
        if ! _in_list "$top_section" "$VALID_SECTIONS"; then
            log_test_warn "Unknown top-level section: [$section]"
            ((section_errors++))
        fi
    done <<< "$sections"
    
    if [[ $section_errors -eq 0 ]]; then
        log_pass "All sections valid"
    else
        TESTS_WARNED=$((TESTS_WARNED + 1))
    fi
    
    # 3. Validate keys in each section
    log_test "Checking keys in sections..."
    local key_errors=0
    for section in meta paths annotations output; do
        validate_section "$CONFIG_FILE" "$section" || ((key_errors+=$?))
    done
    for section in tests.syntax tests.trivial_wrappers tests.file_size tests.function_duplication tests.cruft tests.public_api_docs; do
        validate_section "$CONFIG_FILE" "$section" || ((key_errors+=$?))
    done
    
    if [[ $key_errors -eq 0 ]]; then
        log_pass "All keys valid"
    else
        TESTS_WARNED=$((TESTS_WARNED + key_errors))
    fi
    
    # 4. Validate enum values
    log_test "Checking enum values..."
    if validate_enums "$CONFIG_FILE"; then
        log_pass "All enum values valid"
    else
        ((total_errors+=$?))
    fi
    
    # 5. Validate numeric values
    log_test "Checking numeric values..."
    if validate_numbers "$CONFIG_FILE"; then
        log_pass "All numeric values valid"
    else
        ((total_errors+=$?))
    fi
    
    # 6. Validate boolean values
    log_test "Checking boolean values..."
    if validate_booleans "$CONFIG_FILE"; then
        log_pass "All boolean values valid"
    else
        ((total_errors+=$?))
    fi
    
    # 7. Validate array values
    log_test "Checking array values..."
    if validate_arrays "$CONFIG_FILE"; then
        log_pass "All array values valid"
    else
        ((total_errors+=$?))
    fi
    
    # Summary
    TESTS_RUN=7
    if [[ $total_errors -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_RUN - TESTS_WARNED))
        return 0
    else
        TESTS_FAILED=$total_errors
        TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED - TESTS_WARNED))
        return 1
    fi
}

# =============================================================================
# RUN TEST
# =============================================================================

main() {
    test_config_schema
    local result=$?
    print_summary "Configuration Schema Validation"
    exit_with_status
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
