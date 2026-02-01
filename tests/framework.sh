#!/usr/bin/env bash
# =============================================================================
# nutshell/tests/framework.sh - Config-driven Test Framework
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Provides common utilities and test runner infrastructure for all QA tests.
# All behavior is driven by nut.toml configuration - nothing is hardcoded.
#
# Usage (in test files):
#   source "$(dirname "${BASH_SOURCE[0]}")/framework.sh"
#
# Config discovery order:
#   1. $NUTSHELL_CONFIG (environment variable)
#   2. ./nut.toml
#   3. ./tests/nut.toml
#   4. ./scripts/nut.toml
#   5. Falls back to empty.nut.toml (the canonical defaults)
# =============================================================================

set -uo pipefail

# =============================================================================
# BOOTSTRAP - Find ourselves and load nutshell core
# =============================================================================

FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUTSHELL_ROOT="$(cd "$FRAMEWORK_DIR/.." && pwd)"

# The canonical defaults file - this is the ONLY source of defaults
NUTSHELL_DEFAULTS_FILE="${NUTSHELL_ROOT}/templates/empty.nut.toml"

# Source nutshell core modules
# We eat our own dogfood - the test framework uses nutshell itself
source "${NUTSHELL_ROOT}/core/os.sh"
source "${NUTSHELL_ROOT}/core/log.sh"
source "${NUTSHELL_ROOT}/core/fs.sh"
source "${NUTSHELL_ROOT}/core/string.sh"
source "${NUTSHELL_ROOT}/core/validate.sh"
source "${NUTSHELL_ROOT}/core/toml.sh"

# =============================================================================
# PATHS - Determined after config is loaded
# =============================================================================

# These are set by _framework_init after config discovery
REPO_ROOT=""
LIB_DIR=""
CONFIG_FILE=""

# =============================================================================
# CONFIGURATION STATE
# =============================================================================

# The loaded config file (defaults or user's)
_ACTIVE_CONFIG_FILE=""

# Cached values from config (for performance)
declare -a NUT_EXCLUDE_PATHS=()
declare -a NUT_INCLUDE_PATTERNS=()

# =============================================================================
# CONFIG ACCESS - All config access goes through toml.sh
# =============================================================================

# Get a config value with fallback to defaults
# Usage: cfg_get "key" -> prints value
cfg_get() {
    local key="$1"
    local value=""
    
    # Try user config first
    if [[ -n "$CONFIG_FILE" ]] && [[ -f "$CONFIG_FILE" ]]; then
        value="$(toml_get "$CONFIG_FILE" "$key" 2>/dev/null)" && {
            echo "$value"
            return 0
        }
    fi
    
    # Fall back to defaults
    if [[ -f "$NUTSHELL_DEFAULTS_FILE" ]]; then
        value="$(toml_get "$NUTSHELL_DEFAULTS_FILE" "$key" 2>/dev/null)" && {
            echo "$value"
            return 0
        }
    fi
    
    return 1
}

# Get a config value with explicit default if not found anywhere
# Usage: cfg_get_or "key" "default"
cfg_get_or() {
    local key="$1"
    local default="$2"
    local value
    
    if value="$(cfg_get "$key")"; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Check if a config value is truthy
# Usage: cfg_is_true "key"
cfg_is_true() {
    local key="$1"
    local value
    value="$(cfg_get_or "$key" "false")"
    is_truthy "$value"
}

# Check if a test is enabled
# Usage: cfg_test_enabled "syntax"
cfg_test_enabled() {
    local test_name="$1"
    cfg_is_true "tests.${test_name}"
}

# Get array from config
# Usage: cfg_get_array "key" arr
cfg_get_array() {
    local key="$1"
    local -n _out_arr="$2"
    _out_arr=()
    
    # Try user config first
    if [[ -n "$CONFIG_FILE" ]] && [[ -f "$CONFIG_FILE" ]]; then
        if toml_has "$CONFIG_FILE" "$key"; then
            toml_array "$CONFIG_FILE" "$key" _out_arr
            return 0
        fi
    fi
    
    # Fall back to defaults
    if [[ -f "$NUTSHELL_DEFAULTS_FILE" ]]; then
        if toml_has "$NUTSHELL_DEFAULTS_FILE" "$key"; then
            toml_array "$NUTSHELL_DEFAULTS_FILE" "$key" _out_arr
            return 0
        fi
    fi
    
    return 1
}

# =============================================================================
# CONFIG DISCOVERY
# =============================================================================

# Find the config file following discovery order
_find_config_file() {
    local search_root="$1"
    
    # 1. Environment variable
    if [[ -n "${NUTSHELL_CONFIG:-}" ]] && [[ -f "$NUTSHELL_CONFIG" ]]; then
        echo "$NUTSHELL_CONFIG"
        return 0
    fi
    
    # 2. Repo root
    if [[ -f "${search_root}/nut.toml" ]]; then
        echo "${search_root}/nut.toml"
        return 0
    fi
    
    # 3. tests/ directory
    if [[ -f "${search_root}/tests/nut.toml" ]]; then
        echo "${search_root}/tests/nut.toml"
        return 0
    fi
    
    # 4. scripts/ directory
    if [[ -f "${search_root}/scripts/nut.toml" ]]; then
        echo "${search_root}/scripts/nut.toml"
        return 0
    fi
    
    # Not found - will use defaults
    return 1
}

# Find repo root by looking for common markers
_find_repo_root() {
    local dir="$FRAMEWORK_DIR"
    
    while [[ "$dir" != "/" ]]; do
        # Check for repo markers
        if [[ -d "$dir/.git" ]] || [[ -f "$dir/nut.toml" ]] || [[ -f "$dir/Cargo.toml" ]] || [[ -f "$dir/package.json" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    
    # Fall back to nutshell root if nothing else found
    echo "$NUTSHELL_ROOT"
}

# =============================================================================
# FRAMEWORK INITIALIZATION
# =============================================================================

_framework_initialized=0

_framework_init() {
    [[ $_framework_initialized -eq 1 ]] && return 0
    
    # Verify defaults file exists - this is critical
    if [[ ! -f "$NUTSHELL_DEFAULTS_FILE" ]]; then
        echo "[FATAL] Defaults file not found: $NUTSHELL_DEFAULTS_FILE" >&2
        echo "[FATAL] The nutshell installation appears to be corrupted." >&2
        exit 1
    fi
    
    # Find repo root
    REPO_ROOT="$(_find_repo_root)"
    
    # Try to find user config
    if CONFIG_FILE="$(_find_config_file "$REPO_ROOT")"; then
        log_debug "Loaded config from: $CONFIG_FILE"
    else
        CONFIG_FILE=""
        log_debug "No user config found, using defaults from: $NUTSHELL_DEFAULTS_FILE"
    fi
    
    # Set lib directory relative to repo root
    local lib_dir_config
    lib_dir_config="$(cfg_get_or "paths.lib_dir" ".")"
    if [[ "$lib_dir_config" == "." ]]; then
        LIB_DIR="$REPO_ROOT"
    else
        LIB_DIR="${REPO_ROOT}/${lib_dir_config}"
    fi
    
    # Cache exclude paths
    cfg_get_array "paths.exclude" NUT_EXCLUDE_PATHS || NUT_EXCLUDE_PATHS=()
    
    # Cache include patterns
    cfg_get_array "paths.include" NUT_INCLUDE_PATTERNS || NUT_INCLUDE_PATTERNS=("*.sh")
    
    _framework_initialized=1
}

# =============================================================================
# COLORS - Respect config and environment
# =============================================================================

# Default colors (will be overridden by _setup_colors)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

_setup_colors() {
    local color_mode
    color_mode="$(cfg_get_or "output.color" "auto")"
    
    local use_color=0
    case "$color_mode" in
        always) use_color=1 ;;
        never)  use_color=0 ;;
        auto)   [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && use_color=1 ;;
    esac
    
    if [[ $use_color -eq 1 ]]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        MAGENTA='\033[0;35m'
        CYAN='\033[0;36m'
        BOLD='\033[1m'
        NC='\033[0m'
    else
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        MAGENTA=''
        CYAN=''
        BOLD=''
        NC=''
    fi
}

# =============================================================================
# TEST COUNTERS
# =============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

declare -a FAILED_TESTS=()
declare -a WARNED_TESTS=()

# Reset counters (useful when running multiple test files)
reset_counters() {
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_WARNED=0
    FAILED_TESTS=()
    WARNED_TESTS=()
}

# =============================================================================
# TEST LOGGING
# =============================================================================

log_header() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $*${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

log_section() {
    echo ""
    echo -e "${CYAN}───────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  $*${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────────────${NC}"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $*"
}

log_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local show_passing
    show_passing="$(cfg_get_or "output.show_passing" "true")"
    
    if is_truthy "$show_passing"; then
        echo -e "${GREEN}  ✓${NC} $*"
    fi
}

log_fail() {
    echo -e "${RED}  ✗${NC} $*"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    FAILED_TESTS+=("$*")
}

log_test_warn() {
    echo -e "${YELLOW}  ⚠${NC} $*"
    TESTS_WARNED=$((TESTS_WARNED + 1))
    WARNED_TESTS+=("$*")
}

log_test_info() {
    echo -e "${BLUE}  ℹ${NC} $*"
}

log_skip() {
    echo -e "${MAGENTA}  ○${NC} $* (skipped)"
}

# =============================================================================
# FILE DISCOVERY
# =============================================================================

# Check if a path should be excluded based on config
_is_excluded() {
    local path="$1"
    local exclude_pattern
    
    for exclude_pattern in "${NUT_EXCLUDE_PATHS[@]}"; do
        if [[ "$path" == *"$exclude_pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

# Get all files matching include patterns, excluding configured paths
# @@PUBLIC_API@@
# Usage: get_lib_files -> prints file paths, one per line
get_lib_files() {
    _framework_init
    
    local pattern file
    for pattern in "${NUT_INCLUDE_PATTERNS[@]}"; do
        while IFS= read -r -d '' file; do
            _is_excluded "$file" && continue
            echo "$file"
        done < <(find "$LIB_DIR" -name "$pattern" -type f -print0 2>/dev/null)
    done | sort -u
}

# Get all script files (same as lib files for nutshell)
# @@PUBLIC_API@@
# Usage: get_script_files -> prints file paths, one per line
get_script_files() {
    get_lib_files
}

# =============================================================================
# ANNOTATION CHECKING
# =============================================================================

# Check if a function has a specific annotation
# @@PUBLIC_API@@
# Usage: has_annotation "file" "func_name" "annotation_pattern" -> returns 0/1
has_annotation() {
    local file="$1"
    local func_name="$2"
    local annotation="$3"
    
    # Find the line number of the function definition
    local line_num
    line_num=$(grep -n "^[[:space:]]*${func_name}[[:space:]]*()[[:space:]]*{" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    
    if [[ -z "$line_num" ]]; then
        # Try alternate function syntax
        line_num=$(grep -n "^[[:space:]]*function[[:space:]]\+${func_name}[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    fi
    
    [[ -z "$line_num" ]] && return 1
    [[ "$line_num" -lt 1 ]] && return 1
    
    # Check the 10 lines before the function definition
    local start_line=$((line_num - 10))
    [[ $start_line -lt 1 ]] && start_line=1
    
    if sed -n "${start_line},${line_num}p" "$file" 2>/dev/null | grep -qE "#.*${annotation}"; then
        return 0
    fi
    
    return 1
}

# Check if function has any of the configured exempt annotations for trivial wrappers
# @@PUBLIC_API@@
# Usage: has_trivial_wrapper_exemption "file" "func_name" -> returns 0/1
has_trivial_wrapper_exemption() {
    local file="$1"
    local func_name="$2"
    
    local public_api_annotation
    local ergonomics_annotation
    
    public_api_annotation="$(cfg_get_or "annotations.public_api" "@@PUBLIC_API@@")"
    ergonomics_annotation="$(cfg_get_or "annotations.allow_trivial_wrapper_ergonomics" "@@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@")"
    
    has_annotation "$file" "$func_name" "$public_api_annotation" && return 0
    has_annotation "$file" "$func_name" "$ergonomics_annotation" && return 0
    
    return 1
}

# =============================================================================
# CODE ANALYSIS UTILITIES
# =============================================================================

# Extract function names from a shell script
# @@PUBLIC_API@@
# Usage: extract_functions "file" -> prints function names, one per line
extract_functions() {
    local file="$1"
    grep -E '^\s*(function\s+)?[a-zA-Z_][a-zA-Z0-9_]*\s*\(\s*\)\s*\{?' "$file" 2>/dev/null | \
        awk '{
            gsub(/^[[:space:]]*(function[[:space:]]+)?/, "")
            gsub(/[[:space:]]*\(.*/, "")
            print
        }' | \
        sort -u
}

# Count lines of code (excluding comments and empty lines)
# @@PUBLIC_API@@
# Usage: count_code_lines "file" -> prints number
count_code_lines() {
    local file="$1"
    grep -v '^\s*$' "$file" 2>/dev/null | \
        grep -v '^\s*#' | \
        wc -l | \
        tr -d ' '
}

# Count total lines in a file
# @@PUBLIC_API@@
# Usage: count_total_lines "file" -> prints number
count_total_lines() {
    local file="$1"
    wc -l < "$file" 2>/dev/null | tr -d ' '
}

# Calculate Levenshtein distance between two strings
# @@PUBLIC_API@@
# Usage: levenshtein_distance "string1" "string2" -> prints distance
levenshtein_distance() {
    local s1="$1"
    local s2="$2"
    local len1=${#s1}
    local len2=${#s2}
    
    # Quick shortcuts
    [[ "$s1" == "$s2" ]] && { echo 0; return; }
    [[ $len1 -eq 0 ]] && { echo "$len2"; return; }
    [[ $len2 -eq 0 ]] && { echo "$len1"; return; }
    
    # Use awk for the matrix computation
    awk -v s1="$s1" -v s2="$s2" 'BEGIN {
        len1 = length(s1)
        len2 = length(s2)
        
        for (i = 0; i <= len1; i++) d[i "_" 0] = i
        for (j = 0; j <= len2; j++) d[0 "_" j] = j
        
        for (i = 1; i <= len1; i++) {
            c1 = substr(s1, i, 1)
            for (j = 1; j <= len2; j++) {
                c2 = substr(s2, j, 1)
                cost = (c1 == c2) ? 0 : 1
                
                del = d[(i-1) "_" j] + 1
                ins = d[i "_" (j-1)] + 1
                repl = d[(i-1) "_" (j-1)] + cost
                
                min = del
                if (ins < min) min = ins
                if (repl < min) min = repl
                d[i "_" j] = min
            }
        }
        print d[len1 "_" len2]
    }'
}

# Calculate similarity score (0.0 to 1.0) based on Levenshtein distance
# @@PUBLIC_API@@
# Usage: similarity_score "string1" "string2" -> prints score (e.g., "0.850")
similarity_score() {
    local s1="$1"
    local s2="$2"
    local len1=${#s1}
    local len2=${#s2}
    local max_len=$((len1 > len2 ? len1 : len2))
    
    [[ $max_len -eq 0 ]] && { echo "1.0"; return; }
    
    local distance
    distance=$(levenshtein_distance "$s1" "$s2")
    
    awk -v dist="$distance" -v maxlen="$max_len" 'BEGIN {
        printf "%.3f", 1 - (dist / maxlen)
    }'
}

# Strip module prefix from function name
# @@PUBLIC_API@@
# Usage: strip_prefix "git_check_valid" -> "check_valid"
strip_prefix() {
    local name="$1"
    name="${name#_}"
    if [[ "$name" == *_* ]]; then
        echo "${name#*_}"
    else
        echo "$name"
    fi
}

# =============================================================================
# TEST RESULT SUMMARY
# =============================================================================

# Print test summary
# @@PUBLIC_API@@
# Usage: print_summary ["Test Suite Name"]
print_summary() {
    local test_name="${1:-Test Suite}"
    
    local show_summary
    show_summary="$(cfg_get_or "output.show_summary" "true")"
    
    if ! is_truthy "$show_summary"; then
        # Still return appropriate exit code
        [[ $TESTS_FAILED -gt 0 ]] && return 1
        return 0
    fi
    
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $test_name - Summary${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "  Total tests:  ${BOLD}$TESTS_RUN${NC}"
    echo -e "  ${GREEN}Passed:${NC}       ${BOLD}$TESTS_PASSED${NC}"
    echo -e "  ${RED}Failed:${NC}       ${BOLD}$TESTS_FAILED${NC}"
    echo -e "  ${YELLOW}Warnings:${NC}     ${BOLD}$TESTS_WARNED${NC}"
    echo ""
    
    if [[ -n "$CONFIG_FILE" ]]; then
        echo -e "  ${BLUE}Config:${NC}       ${CONFIG_FILE}"
    else
        echo -e "  ${BLUE}Config:${NC}       (defaults from empty.nut.toml)"
    fi
    echo ""
    
    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo -e "${RED}Failed tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $test"
        done
        echo ""
    fi
    
    if [[ ${#WARNED_TESTS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Warnings:${NC}"
        for test in "${WARNED_TESTS[@]}"; do
            echo -e "  ${YELLOW}⚠${NC} $test"
        done
        echo ""
    fi
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}${BOLD}FAILED${NC} - $TESTS_FAILED test(s) failed"
        echo ""
        echo -e "${RED}Please fix all errors before committing.${NC}"
        echo -e "${YELLOW}Review all warnings and fix them if possible.${NC}"
        return 1
    elif [[ $TESTS_WARNED -gt 0 ]]; then
        echo -e "${YELLOW}${BOLD}PASSED WITH WARNINGS${NC}"
        echo ""
        echo -e "${YELLOW}Review warnings and consider fixing them.${NC}"
        return 0
    else
        echo -e "${GREEN}${BOLD}PASSED${NC} - All tests passed"
        return 0
    fi
}

# Exit with appropriate code based on test results
# @@PUBLIC_API@@
# Usage: exit_with_status
exit_with_status() {
    [[ $TESTS_FAILED -gt 0 ]] && exit 1
    exit 0
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Auto-initialize when sourced
_framework_init
_setup_colors
