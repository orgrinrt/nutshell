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
    PUBLIC_API_ANNOTATION="$(cfg_get_or "annotations.public_api" "#[pub]")"
    ERGONOMICS_ANNOTATION="$(cfg_get_or "annotations.allow_trivial_wrapper_ergonomics" "#[allow(trivial_wrapper)]")"
}

# =============================================================================
# FUNCTION ANALYSIS
# =============================================================================

# Which functions in a file carry an exempting annotation.
#
# Built once per file, in the shell that runs the loop. `analyze_function` is
# called through a command substitution, which is a subshell: anything it works
# out is thrown away when it returns, so asking per function meant walking the
# whole file per function, twice, and that was most of this check's time.
declare -gA _TW_EXEMPT=()
declare -gA _TW_EXEMPT_DONE=()

tw_load_exemptions() {
    local file="$1"
    [[ -n "${_TW_EXEMPT_DONE[$file]:-}" ]] && return 0
    _TW_EXEMPT_DONE[$file]=1
    local marker name fn
    for marker in "$(cfg_get_or "annotations.public_api" "#[pub]")" \
                  "$(cfg_get_or "annotations.allow_trivial_wrapper_ergonomics" "DISABLED_ANNOTATION")"; do
        [[ -n "$marker" ]] || continue
        name="$(attr_name_of "$marker")" || continue
        name="${name%%$'\t'*}"
        [[ -n "$name" ]] || continue
        while IFS= read -r fn; do
            [[ -n "$fn" ]] && _TW_EXEMPT["${file}:${fn}"]=1
        done < <(attr_find "$file" "$name" 2>/dev/null)
    done
    return 0
}

# Check if a function has an exempting annotation
# Returns 0 if exempt, 1 if not
has_exempt_annotation() {
    local file="$1" func_name="$2"
    [[ -n "${_TW_EXEMPT_DONE[$file]:-}" ]] || return 1
    [[ -n "${_TW_EXEMPT["${file}:${func_name}"]:-}" ]]
}

# How often every name appears, everywhere, counted once for the whole run.
#
# This was a `grep -c` per file per function. On 24 files and 440 functions
# that is 10,560 greps, and `analyze_function` runs in a command substitution,
# so nothing it worked out ever survived the return. Built here instead, in the
# shell that runs the loop, once.
#
# Counts are lines-containing rather than occurrences, because that is what
# `grep -c` gave and the thresholds were chosen against it.
#
# awk where there is one and the shell where there is not. This check needs awk
# elsewhere already, so it is not a new dependency; the fallback is here so a
# machine without it gets a slow answer rather than no answer.
declare -gA _TW_LOCAL=()
declare -gA _TW_GLOBAL=()
declare -gi _TW_USAGE_DONE=0
_TW_SEP=$'\034'

_tw_count_with_awk() {
    local key n
    while IFS=$'\t' read -r key n; do
        [[ -n "$key" ]] || continue
        case "$key" in
            G*) _TW_GLOBAL["${key#G}"]=$n ;;
            L*) _TW_LOCAL["${key#L}"]=$n ;;
        esac
    done < <(get_script_files | tr '\n' '\0' | xargs -0 awk '
        FNR == 1 { delete seen }
        {
            delete seen
            line = $0
            while (match(line, /[A-Za-z_][A-Za-z0-9_]*/)) {
                seen[substr(line, RSTART, RLENGTH)] = 1
                line = substr(line, RSTART + RLENGTH)
            }
            for (w in seen) { g[w]++; l[FILENAME "\034" w]++ }
        }
        END {
            for (w in g) printf "G%s\t%d\n", w, g[w]
            for (k in l) printf "L%s\t%d\n", k, l[k]
        }' 2>/dev/null)
}

_tw_count_in_shell() {
    local file line rest name n i
    local -A onthisline=()
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        nut_load_file "$file" || continue
        n="$(nut_file_lines "$file")"
        for (( i = 1; i <= n; i++ )); do
            line="$(nut_file_line "$file" "$i")"
            onthisline=()
            rest="$line"
            while [[ "$rest" =~ ([A-Za-z_][A-Za-z0-9_]*) ]]; do
                name="${BASH_REMATCH[1]}"
                onthisline["$name"]=1
                rest="${rest#*"$name"}"
            done
            for name in "${!onthisline[@]}"; do
                _TW_GLOBAL["$name"]=$(( ${_TW_GLOBAL["$name"]:-0} + 1 ))
                _TW_LOCAL["${file}${_TW_SEP}${name}"]=$(( ${_TW_LOCAL["${file}${_TW_SEP}${name}"]:-0} + 1 ))
            done
        done
    done < <(get_script_files)
}

tw_load_usages() {
    (( _TW_USAGE_DONE == 1 )) && return 0
    _TW_USAGE_DONE=1
    if command -v awk >/dev/null 2>&1 && command -v xargs >/dev/null 2>&1; then
        _tw_count_with_awk
    fi
    # Nothing came back, so either there was no awk or it could not run. A
    # count of zero everywhere would exempt every function in the library.
    (( ${#_TW_GLOBAL[@]} == 0 )) && _tw_count_in_shell
    return 0
}

# Count usages of a function in a specific file (excluding the definition)
# Name a variable and the answer goes there rather than to stdout, which is
# the whole cost: the lookup is one array read and the fork around it is a
# thousand times that.
count_local_usages() {
    local __tw_c="${_TW_LOCAL["${1}${_TW_SEP}${2}"]:-0}"
    __tw_c=$(( __tw_c - 1 ))
    (( __tw_c < 0 )) && __tw_c=0
    if [[ -n "${3:-}" ]]; then
        [[ "$3" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
        printf -v "$3" '%s' "$__tw_c"; return 0
    fi
    printf '%s' "$__tw_c"
}

# Count usages of a function across all files
count_global_usages() {
    local __tw_t="${_TW_GLOBAL["${1:-}"]:-0}"
    __tw_t=$(( __tw_t - 1 ))
    (( __tw_t < 0 )) && __tw_t=0
    if [[ -n "${2:-}" ]]; then
        [[ "$2" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
        printf -v "$2" '%s' "$__tw_t"; return 0
    fi
    printf '%s' "$__tw_t"
}

# Extract meaningful code lines from a function body
# Excludes: comments, blank lines, local declarations, opening/closing braces
get_meaningful_lines() {
    local -a __body=()
    nut_body_of "$1" "$2" __body || return
    (( ${#__body[@]} > 0 )) && printf '%s\n' "${__body[@]}"
    return 0
}

# Count meaningful lines in a function
# The three body measurements in one pass, into three variables.
#
# They were three functions, each read through a command substitution and each
# extracting the body again: three forks and three extractions per function,
# on every function in the library. Nothing about counting needed a subshell,
# and nothing needed the body three times.
#
# Sets TW_LINES, TW_VARS and TW_TOKENS.
_tw_measure_body() {
    local -a __tw_body=()
    TW_LINES=0; TW_VARS=0; TW_TOKENS=0
    nut_body_of "$1" "$2" __tw_body || return 0
    TW_LINES="${#__tw_body[@]}"

    # A five-stage pipeline per function, in the shell instead. `grep -oE`,
    # `sed`, `sort -u`, `wc` and `tr` is five processes to count distinct names
    # in a handful of lines the shell is already holding.
    local -A __tw_seen=()
    local __tw_line __tw_rest __tw_name __tw_n=0
    local -a __tw_words=()
    for __tw_line in "${__tw_body[@]}"; do
        __tw_rest="$__tw_line"
        while [[ "$__tw_rest" =~ \$\{?([a-zA-Z_][a-zA-Z0-9_]*) ]]; do
            __tw_name="${BASH_REMATCH[1]}"
            __tw_seen["$__tw_name"]=1
            __tw_rest="${__tw_rest#*"${BASH_REMATCH[0]}"}"
        done
        # Word splitting is the shell's own job; `tr | grep | wc | tr` is four
        # processes to ask it.
        # shellcheck disable=SC2206
        __tw_words=($__tw_line)
        __tw_n=$(( __tw_n + ${#__tw_words[@]} ))
    done
    TW_VARS="${#__tw_seen[@]}"
    TW_TOKENS="$__tw_n"
    return 0
}

count_meaningful_lines() {
    local -a __body=()
    nut_body_of "$1" "$2" __body || { printf '0'; return; }
    printf '%s' "${#__body[@]}"
}

# Count unique variables used in function body
count_variables_used() {
    local -a __body=()
    nut_body_of "$1" "$2" __body || { printf '0'; return; }
    # A five-stage pipeline per function, in the shell instead. `grep -oE`,
    # `sed`, `sort -u`, `wc` and `tr` is five processes to count distinct names
    # in a handful of lines the shell is already holding.
    local -A seen=()
    local line rest name
    for line in "${__body[@]}"; do
        rest="$line"
        while [[ "$rest" =~ \$\{?([a-zA-Z_][a-zA-Z0-9_]*) ]]; do
            name="${BASH_REMATCH[1]}"
            seen["$name"]=1
            rest="${rest#*"${BASH_REMATCH[0]}"}"
        done
    done
    printf '%s' "${#seen[@]}"
}

# Count tokens (complexity indicator) in function body
count_tokens() {
    local -a __body=()
    nut_body_of "$1" "$2" __body || { printf '0'; return; }
    # Word splitting is the shell's own job; `tr | grep | wc | tr` is four
    # processes to ask it.
    local line n=0
    local -a words=()
    for line in "${__body[@]}"; do
        # shellcheck disable=SC2206
        words=($line)
        n=$(( n + ${#words[@]} ))
    done
    printf '%s' "$n"
}

# Analyze a single function for trivial wrapper status
# Returns: pass, warn, or fail
declare -g TW_STATUS="" TW_DETAILS=""

# One place that splits "status:details" into the two globals.
_tw_set() {
    TW_STATUS="${1%%:*}"
    TW_DETAILS="${1#*:}"
    return 0
}


# Sets TW_STATUS and TW_DETAILS rather than printing them.
#
# It was read through a command substitution, which is a fork, once per
# function: 386 of them on this library and most of what the check still cost
# after the pipelines came out. Nothing about the analysis needed a subshell;
# it needed a return value with two parts in it.
analyze_function() {
    local file="$1"
    local func_name="$2"
    
    # Get metrics
    local line_count var_count token_count local_usages global_usages
    local TW_LINES=0 TW_VARS=0 TW_TOKENS=0
    _tw_measure_body "$file" "$func_name"
    line_count="$TW_LINES"
    
    # Not a trivial wrapper if more than MAX_LINES
    if [[ $line_count -gt $MAX_LINES ]]; then
        _tw_set "pass:not_trivial"
        return
    fi
    
    # Check for exempt annotation
    if has_exempt_annotation "$file" "$func_name"; then
        _tw_set "pass:annotated"
        return
    fi
    
    # Calculate other metrics
    var_count="$TW_VARS"
    token_count="$TW_TOKENS"
    count_local_usages "$file" "$func_name" local_usages
    count_global_usages "$func_name" global_usages
    
    # Check ergonomic passes (ANY of these = pass)
    if [[ $local_usages -ge $LOCAL_USAGE_THRESHOLD ]]; then
        _tw_set "pass:local_usage"
        return
    fi
    
    if [[ $global_usages -ge $GLOBAL_USAGE_THRESHOLD ]]; then
        _tw_set "pass:global_usage"
        return
    fi
    
    if [[ $var_count -ge $MIN_VARS_FOR_ERGONOMIC ]]; then
        _tw_set "pass:ergonomic_vars"
        return
    fi
    
    if [[ $token_count -ge $TOKEN_COMPLEXITY_PASS ]]; then
        _tw_set "pass:complex"
        return
    fi
    
    # Warn vs fail based on token complexity
    if [[ $token_count -ge $TOKEN_COMPLEXITY_WARN ]]; then
        _tw_set "warn:${line_count}:${local_usages}:${global_usages}:${var_count}:${token_count}"
        return
    fi
    
    _tw_set "fail:${line_count}:${local_usages}:${global_usages}:${var_count}:${token_count}"
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
        
        # What this file contributed last time, if nothing that could change
        # it has changed. One read for the whole file rather than one per
        # function: a lookup that forks costs more than the work it saves, and
        # the first attempt at this was measurably slower than no cache.
        local __blob __kind __text
        if nut_cache_hit "trivial_wrappers" "$file" 2>/dev/null \
           && __blob="$(nut_cache_read "trivial_wrappers" "$file" 2>/dev/null)"; then
            while IFS= read -r __line; do
                [[ -n "$__line" ]] || continue
                __kind="${__line%%$'\t'*}"; __text="${__line#*$'\t'}"
                case "$__kind" in
                    E) errors+=("$__text"); error_count=$((error_count + 1))
                       wrapper_count=$((wrapper_count + 1)) ;;
                    W) warnings+=("$__text"); warn_count=$((warn_count + 1))
                       wrapper_count=$((wrapper_count + 1)) ;;
                esac
            done <<< "$__blob"
            continue
        fi


        # In this shell, before anything reads it from a subshell.
        nut_load_file "$file" || true
        tw_load_exemptions "$file"
        tw_load_usages

        # Get all functions in this file
        local functions
        functions=$(extract_functions "$file")
        local __record=""

        while IFS= read -r func_name; do
            [[ -z "$func_name" ]] && continue
            
            analyze_function "$file" "$func_name"
            local status="$TW_STATUS"
            local details="$TW_DETAILS"
            
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
                    __record+="W"$'\t'"${func_name}() - ${lines} line(s), ${local_use} local / ${global_use} global usages, ${vars} vars, ${tokens} tokens"$'\n' 
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
                    __record+="E"$'\t'"${func_name}() - ${lines} line(s), ${local_use} local / ${global_use} global usages, ${vars} vars, ${tokens} tokens"$'\n' 
                    ;;
            esac
        done <<< "$functions"

        nut_cache_write "trivial_wrappers" "$file" "$__record" 2>/dev/null || true

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
