#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/check-runner.sh - Check/QA Test Framework
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Provides common utilities and test runner infrastructure for all QA checks.
# All behavior is driven by nut.toml configuration - nothing is hardcoded.
#
# Usage:
#   use check-runner
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

_CHECK_RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUTSHELL_ROOT="${NUTSHELL_ROOT:-$(cd "$_CHECK_RUNNER_DIR/.." && pwd)}"

# The canonical defaults file - this is the ONLY source of defaults
NUTSHELL_DEFAULTS_FILE="${NUTSHELL_ROOT}/examples/configs/empty.nut.toml"

# We eat our own dogfood: the check framework loads its dependencies the way
# every other module does. Sourcing the paths by hand worked, and hid the
# dependency from the module-contract check, which reads `use` lines. A module
# that loads its dependencies invisibly is exactly the case that check exists
# to catch, so the framework running it must not be the one exception.
use log validate toml attr string

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
declare -ga NUT_EXCLUDE_PATHS=() 2>/dev/null || declare -a NUT_EXCLUDE_PATHS=()
declare -ga NUT_INCLUDE_PATTERNS=() 2>/dev/null || declare -a NUT_INCLUDE_PATTERNS=()

# =============================================================================
# CONFIG ACCESS - All config access goes through toml.sh
# =============================================================================

# Get a config value with fallback to defaults
# Usage: cfg_get "key" -> prints value
# Resolved configuration values, and keys already known to be absent.
#
# Every lookup used to re-parse the whole file, in a subshell, twice: once for
# the user config and once for the defaults. `toml_get` reads line by line in
# bash, so a run cost functions x lookups x file length, and the check that
# analyses every function in lib/ paid it for each one. Adding two modules took
# that from slow to minutes.
#
# Absence is cached as well as presence. A miss is the expensive case, since it
# parses both files to the end before giving up, and a key absent once is
# absent for the rest of the run.
declare -gA _CFG_CACHE=()
declare -gA _CFG_MISS=()

cfg_get() {
    local key="$1"
    local value=""

    [[ -n "${_CFG_MISS[$key]:-}" ]] && return 1
    if [[ -n "${_CFG_CACHE[$key]+set}" ]]; then
        printf '%s\n' "${_CFG_CACHE[$key]}"
        return 0
    fi
    
    # Try user config first
    if [[ -n "$CONFIG_FILE" ]] && [[ -f "$CONFIG_FILE" ]]; then
        value="$(toml_get "$CONFIG_FILE" "$key" 2>/dev/null)" && {
            _CFG_CACHE[$key]="$value"
            echo "$value"
            return 0
        }
    fi
    
    # Fall back to defaults
    if [[ -f "$NUTSHELL_DEFAULTS_FILE" ]]; then
        value="$(toml_get "$NUTSHELL_DEFAULTS_FILE" "$key" 2>/dev/null)" && {
            _CFG_CACHE[$key]="$value"
            echo "$value"
            return 0
        }
    fi

    # Remember the miss. Reaching here means both files were parsed to the end.
    _CFG_MISS[$key]=1
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
# For test sections: a table without explicit boolean is considered "true"
# Usage: cfg_is_true "key"
cfg_is_true() {
    local key="$1"
    local value
    
    # First check if user config has a section for this key
    # If user has [tests.foo] section, that means they want it enabled,
    # even if defaults file has "foo = false"
    if [[ -n "$CONFIG_FILE" ]] && [[ -f "$CONFIG_FILE" ]]; then
        if toml_has_section "$CONFIG_FILE" "$key"; then
            return 0  # User has section, treat as enabled
        fi
        
        # Check if user config has explicit boolean for this key
        if value="$(toml_get "$CONFIG_FILE" "$key" 2>/dev/null)"; then
            is_truthy "$value"
            return $?
        fi
    fi
    
    # Fall back to defaults file
    if [[ -f "$NUTSHELL_DEFAULTS_FILE" ]]; then
        # Check for section in defaults
        if toml_has_section "$NUTSHELL_DEFAULTS_FILE" "$key"; then
            return 0  # Defaults has section, treat as enabled
        fi
        
        # Check for explicit boolean
        if value="$(toml_get "$NUTSHELL_DEFAULTS_FILE" "$key" 2>/dev/null)"; then
            is_truthy "$value"
            return $?
        fi
    fi
    
    # Not found anywhere - default to false
    return 1
}

# Check if a section exists in the config
# The hand-rolled `grep -qE "^\[${section}\]"` this replaced interpolated the
# name into a regex, so every `.` in a section name matched any character:
# asking for `a.b` found `[axb]`. It also had no end anchor, so `check` matched
# `[checkers]`, and it missed a header carrying a trailing comment.
# Usage: cfg_section_exists "section.name" -> returns 0 (true) or 1 (false)
cfg_section_exists() {
    local section="$1"

    if [[ -n "$CONFIG_FILE" ]] && [[ -f "$CONFIG_FILE" ]]; then
        toml_has_section "$CONFIG_FILE" "$section" && return 0
    fi
    if [[ -f "$NUTSHELL_DEFAULTS_FILE" ]]; then
        toml_has_section "$NUTSHELL_DEFAULTS_FILE" "$section" && return 0
    fi
    return 1
}

# Check if a test is enabled
# Usage: cfg_test_enabled "syntax" -> returns 0 when the test is enabled, 1 when it is not
#[pub]
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

# Walk up from a directory to the first repository marker above it.
_walk_to_marker() {
    local dir="${1:-}"
    [[ -d "$dir" ]] || return 1
    dir="$(cd "$dir" && pwd)" || return 1

    while [[ -n "$dir" && "$dir" != "/" ]]; do
        if [[ -d "$dir/.git" ]] || [[ -f "$dir/nut.toml" ]] \
           || [[ -f "$dir/Cargo.toml" ]] || [[ -f "$dir/package.json" ]]; then
            printf '%s' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# The repository being checked.
#
# From where the check was invoked, not from where this file happens to sit.
# Walking up from this file finds whichever nutshell is running the check, so
# every consumer was having nutshell's own source graded against the
# consumer's thresholds. It looked like a passing gate and no consumer's code
# had ever been read. `paths.exclude` could not help: the walk started inside
# the directory the consumer was excluding.
#
# It is not only a vendoring problem. A consumer resolving nutshell out of the
# store gets the same answer, because a store checkout carries a `.git` too.
_find_repo_root() {
    local root

    # What the caller named. A config file states which repository it is the
    # config for, and its directory is that repository.
    if [[ -n "${NUTSHELL_CONFIG:-}" ]] && [[ -f "$NUTSHELL_CONFIG" ]]; then
        root="$(cd "$(dirname "$NUTSHELL_CONFIG")" && pwd)" && {
            printf '%s' "$root"; return 0
        }
    fi

    # Where the check was run from. `./check` at a project root, or anywhere
    # inside it, both mean that project.
    root="$(_walk_to_marker "$PWD")" && { printf '%s' "$root"; return 0; }

    # Nothing above the invocation directory says it is a repository, so there
    # is nothing to check but the interpreter itself.
    root="$(_walk_to_marker "$_CHECK_RUNNER_DIR")" && { printf '%s' "$root"; return 0; }
    printf '%s' "$NUTSHELL_ROOT"
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

declare -ga FAILED_TESTS=() 2>/dev/null || declare -a FAILED_TESTS=()
declare -ga WARNED_TESTS=() 2>/dev/null || declare -a WARNED_TESTS=()

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
#[pub]
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
#[pub]
# Usage: get_script_files -> prints file paths, one per line
get_script_files() {
    get_lib_files
}

# =============================================================================
# ANNOTATION CHECKING
# =============================================================================

# Check if a function has a specific annotation
#[pub]
# Usage: has_annotation "file" "func_name" "annotation_pattern" -> returns 0/1
# attr_name_of <annotation>
#
# The attribute name inside a configured marker: `#[pub]` gives `pub`. Prints
# nothing when the marker is not in attribute shape, which is how a caller
# tells that it has to match the string literally instead.
#
# Here rather than in each check because two of them needed it and each got it
# wrong in its own way: both interpolated the marker straight into a regex,
# where `[pub]` is a bracket expression matching one character out of p, u and
# b, so one check exempted almost nothing and the other found no public
# functions at all in a library with more than a hundred of them.
attr_name_of() {
    [[ "$1" =~ ^#\[([a-z_][a-z0-9_]*)(\((.*)\))?\]$ ]] || return 1
    # Name, then a tab, then the argument if there was one. The argument is
    # part of the identity: `#[allow(trivial_wrapper)]` and `#[allow(loc = 400)]`
    # are not the same marker, and matching on the name alone would let a size
    # exemption excuse a wrapper.
    printf '%s\t%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]:-}"
}

# has_annotation <file> <function> <annotation>
#
# Whether that definition carries that annotation.
#
# Through the attr module, which is what reads attributes. The shape here was a
# grep of the ten lines above the definition for `#.*${annotation}`, with the
# annotation interpolated into an extended regular expression. `#[pub]` is a
# valid ERE that matches a `#`, then anything, then a `#`, then one character
# out of p, u and b, so it matched almost nothing it was meant to and the odd
# thing it was not. Every function in the library was marked and every one of
# them still counted as unannotated.
#
# The window was a second, quieter bug: ten lines is enough for a terse
# function and not for a documented one, so whether an annotation was seen
# depended on how much prose sat under it.
has_annotation() {
    local file="$1" func_name="$2" annotation="$3"

    # The configured form is the written form, `#[pub]`. attr works in names.
    local parsed name arg
    if parsed="$(attr_name_of "$annotation")"; then
        name="${parsed%%$'\t'*}"
        arg="${parsed#*$'\t'}"
        attr_has "$file" "$func_name" "$name" || return 1
        [[ -z "$arg" ]] && return 0
        [[ "$(attr_arg "$file" "$func_name" "$name")" == "$arg" ]]
        return $?
    fi

    # Anything not in attribute shape is matched literally as a whole line, so
    # a project naming its own marker still works and no metacharacter in it is
    # read as one.
    local line_num
    line_num=$(grep -n "^[[:space:]]*${func_name}[[:space:]]*()[[:space:]]*{" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    [[ -z "$line_num" || "$line_num" -lt 1 ]] && return 1

    local start_line=$((line_num - 10))
    [[ $start_line -lt 1 ]] && start_line=1
    sed -n "${start_line},${line_num}p" "$file" 2>/dev/null \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
        | grep -qxF -- "$annotation"
}

# Check if function has any of the configured exempt annotations for trivial wrappers
#[pub]
# Usage: has_trivial_wrapper_exemption "file" "func_name" -> returns 0/1
has_trivial_wrapper_exemption() {
    local file="$1"
    local func_name="$2"
    
    local public_api_annotation
    local ergonomics_annotation
    
    public_api_annotation="$(cfg_get_or "annotations.public_api" "#[pub]")"
    ergonomics_annotation="$(cfg_get_or "annotations.allow_trivial_wrapper_ergonomics" "DISABLED_ANNOTATION")"
    
    has_annotation "$file" "$func_name" "$public_api_annotation" && return 0
    has_annotation "$file" "$func_name" "$ergonomics_annotation" && return 0
    
    return 1
}

# =============================================================================
# CODE ANALYSIS UTILITIES
# =============================================================================

# Extract function names from a shell script
#[pub]
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
#[pub]
# Usage: count_code_lines "file" -> prints number
count_code_lines() {
    local file="$1"
    grep -v '^\s*$' "$file" 2>/dev/null | \
        grep -v '^\s*#' | \
        wc -l | \
        tr -d ' '
}

# Count total lines in a file
#[pub]
# Usage: count_total_lines "file" -> prints number
count_total_lines() {
    local file="$1"
    wc -l < "$file" 2>/dev/null | tr -d ' '
}

# Calculate similarity score (0.0 to 1.0) based on Levenshtein distance
#[pub]
# Usage: similarity_score "string1" "string2" -> prints score (e.g., "0.850")
similarity_score() {
    local s1="$1"
    local s2="$2"
    local len1=${#s1}
    local len2=${#s2}
    local max_len=$((len1 > len2 ? len1 : len2))
    
    [[ $max_len -eq 0 ]] && { echo "1.0"; return; }
    
    local distance
    distance=$(str_distance "$s1" "$s2")
    
    awk -v dist="$distance" -v maxlen="$max_len" 'BEGIN {
        printf "%.3f", 1 - (dist / maxlen)
    }'
}

# Strip module prefix from function name
#[pub]
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
#[pub]
# Usage: print_summary ["Test Suite Name"] -> prints the totals block; returns 0 always
print_summary() {
    local test_name="${1:-Test Suite}"
    
    # In quiet mode (called from main check runner), skip verbose output
    # The main runner handles its own summary
    if [[ "${NUTSHELL_CHECK_QUIET:-0}" == "1" ]]; then
        [[ $TESTS_FAILED -gt 0 ]] && return 1
        return 0
    fi
    
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
#[pub]
# Usage: exit_with_status -> does not return; exits 0 clean, 1 on failures, 2 on warnings only
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
