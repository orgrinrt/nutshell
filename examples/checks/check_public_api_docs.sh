#!/usr/bin/env nutshell
# =============================================================================
# check_public_api_docs.sh - Public API Documentation Validation Check
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Verifies that all functions marked with #[pub] annotation have
# proper documentation including usage examples.
#
# FULLY CONFIG-DRIVEN: All settings come from nut.toml.
# See examples/configs/empty.nut.toml for all available options.
#
# Checks:
#   - Functions with #[pub] must have a Usage: line
#   - Optionally checks for return value documentation (->)
#
# Usage: ./examples/checks/check_public_api_docs.sh
#
# Exit codes:
#   0 - All public API functions are documented
#   1 - One or more functions missing documentation, or test disabled
# =============================================================================

set -uo pipefail

# Load the check-runner framework (provides cfg_*, log_*, etc.)
use check-runner
use attr

# =============================================================================
# CONFIG-DRIVEN PARAMETERS
# =============================================================================

# Settings (will be loaded from config)
PUBLIC_API_ANNOTATION="#[pub]"
declare -a REQUIRED_ELEMENTS=()
declare -a RECOMMENDED_ELEMENTS=()
MIN_DOC_LINES=1

load_config() {
    # Check if test is enabled
    if ! cfg_is_true "tests.public_api_docs"; then
        log_info "Public API docs test is disabled in config"
        exit 0
    fi
    
    # Load settings from config
    PUBLIC_API_ANNOTATION="$(cfg_get_or "tests.public_api_docs.public_api_annotation" "#[pub]")"
    MIN_DOC_LINES="$(cfg_get_or "tests.public_api_docs.min_doc_lines" "1")"
    
    # Load required elements
    if ! cfg_get_array "tests.public_api_docs.required_elements" REQUIRED_ELEMENTS; then
        REQUIRED_ELEMENTS=("Usage:")
    fi
    
    # Load recommended elements
    if ! cfg_get_array "tests.public_api_docs.recommended_elements" RECOMMENDED_ELEMENTS; then
        RECOMMENDED_ELEMENTS=("->" "Returns" "returns" "Prints" "prints")
    fi
}

# =============================================================================
# DOCUMENTATION CHECKING FUNCTIONS
# =============================================================================

# The file, once, as an array of lines.
#
# The scan below walks backwards from a definition and used to run `sed -n Np`
# for each line it looked at, plus an `echo | grep` to decide what the line
# was. That is three processes per line of every docblock in the library, and
# it is why this check took most of a minute. Bash can hold the file and match
# a line itself, which also means this needs no `sed` and no `grep` and works
# on a machine that has neither.
declare -gA _PAD_LINES=()
declare -gA _PAD_LOADED=()
declare -gA _PAD_AT=()
declare -g  PAD_DOCBLOCK=""

_pad_load() {
    local file="$1"
    [[ -n "${_PAD_LOADED[$file]:-}" ]] && return 0
    local -a lines=()
    # `mapfile` is a bash builtin and needs nothing installed, but it arrived
    # in bash 4 and this reads a file a checker has to read. The loop below is
    # the same thing on any bash, and no external tool is involved either way.
    if [[ "$(type -t mapfile)" == "builtin" ]]; then
        mapfile -t lines < "$file" 2>/dev/null || return 1
    else
        local __l
        while IFS= read -r __l || [[ -n "$__l" ]]; do lines+=("$__l"); done < "$file" \
            || return 1
    fi
    local i line
    for (( i = 0; i < ${#lines[@]}; i++ )); do
        line="${lines[$i]}"
        _PAD_LINES["${file}:$((i + 1))"]="$line"
        # Where each function is defined, recorded on the one pass rather than
        # searched for per lookup. Searching was 440 functions times 376 lines
        # of regex per file, which is the same shape as the greps it replaced.
        # `ATTR_DEFINES_PATTERN`, so this agrees with `attr` and `srcfile`
        # about what a definition is. The pattern here was its own, and it
        # required parentheses, so `function name {` was invisible to it: a
        # `#[pub]` on one of those was never looked up at all and the check
        # passed over it in silence. That is the same drift the shared pattern
        # was made to end, in a third reader nobody moved across.
        if [[ "$line" =~ $ATTR_DEFINES_PATTERN ]]; then
            local n="${BASH_REMATCH[2]:-${BASH_REMATCH[3]}}"
            [[ -n "${_PAD_AT["${file}:${n}"]:-}" ]] || _PAD_AT["${file}:${n}"]=$((i + 1))
        fi
    done
    _PAD_LOADED[$file]="${#lines[@]}"
    return 0
}

# One line of a loaded file, by number.
_pad_line() { printf '%s' "${_PAD_LINES["${1}:${2}"]:-}"; }

# Where a function is defined in a loaded file, or nothing.
_pad_defined_at() {
    local at="${_PAD_AT["${1}:${2}"]:-}"
    [[ -n "$at" ]] || return 1
    printf '%s' "$at"
}

# Extract the docblock before a function definition
# Returns: the comment lines before the function (if any)
get_function_docblock() {
    local file="$1"
    local func_name="$2"

    PAD_DOCBLOCK=""
    _pad_load "$file" || return 1

    local func_line
    func_line="${_PAD_AT["${file}:${func_name}"]:-}"
    [[ -n "$func_line" ]] || return 1
    [[ "$func_line" -lt 2 ]] && return 1

    # Look backwards from the function definition to find comment block
    local docblock="" current_line=$(( func_line - 1 )) line prev

    while [[ $current_line -gt 0 ]]; do
        line="${_PAD_LINES["${file}:${current_line}"]}"

        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            docblock="${line}"$'\n'"${docblock}"
            current_line=$(( current_line - 1 ))
        elif [[ -z "${line// /}" ]]; then
            # A blank line is part of the block only when a comment is above it.
            prev="${_PAD_LINES["${file}:$(( current_line - 1 ))"]:-}"
            if [[ "$prev" =~ ^[[:space:]]*# ]]; then
                current_line=$(( current_line - 1 ))
            else
                break
            fi
        else
            break
        fi
    done

    PAD_DOCBLOCK="$docblock"
    printf '%s\n' "$docblock"
}

# Check if docblock contains an element
docblock_has_element() {
    local docblock="$1" element="$2"
    # Literal and case-insensitive, the way `grep -qiF` was, without the two
    # processes. `->` and the other markers carry characters a pattern would
    # read as its own, so the needle is lowered and compared as text.
    local hay="${docblock,,}" needle="${element,,}"
    [[ "$hay" == *"$needle"* ]]
}

# Whether a docblock belongs to the function it landed on.
#
# Attributes attach downward, so a `#[pub]` block sitting above a private
# helper documents the helper. Where a docblock's `Usage:` names some other
# function that is defined *later in the same file*, the block was written for
# that one and something got inserted between them.
#
# Two things go wrong at once and neither is visible on its own. The named
# function ends up undocumented, and the helper ends up marked public. Both
# read as fine, because each of the two lines involved is correct where it sits.
#
# Only a `Usage:` whose first token is a bare name counts. `Usage: exit
# "$(doctor_exit)"` is an invocation example and names `exit`, which defines
# nothing, so it is not a mismatch.
#
# Prints the name the block was written for, and returns 0, when it is orphaned.
docblock_orphaned_from() {
    local file="$1" landed_on="$2" docblock="$3"
    local line named at_named at_landed
    local -a mentions=()

    # Collected first, because a block may carry several `Usage:` lines and one
    # of them naming this definition settles it. Deciding on the first line
    # that did not match would call a two-form block an orphan of its own
    # alternative spelling.
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*#[[:space:]]*Usage:[[:space:]]*([a-zA-Z_][a-zA-Z0-9_-]*)([[:space:]]|$) ]] \
            || continue
        named="${BASH_REMATCH[1]}"
        [[ "$named" == "$landed_on" ]] && return 1
        mentions+=("$named")
    done <<< "$docblock"

    for named in ${mentions[@]+"${mentions[@]}"}; do
        at_named="$(_pad_defined_at "$file" "$named")" || continue
        at_landed="$(_pad_defined_at "$file" "$landed_on")" || continue
        # Later in the file, so the block was passed over on its way down.
        # Earlier means the block refers back to something, which is prose.
        [[ "$at_named" -gt "$at_landed" ]] || continue

        printf '%s' "$named"
        return 0
    done
    return 1
}

# Count comment lines in docblock
count_doc_lines() {
    local docblock="$1" line n=0
    # Counted here rather than through `echo | grep -c`, which is two processes
    # per public function for a string this shell is already holding.
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && n=$(( n + 1 ))
    done <<< "$docblock"
    printf '%s' "$n"
}

# Find all functions marked with public API annotation
find_public_api_functions() {
    local file="$1"
    local rel_path="${file#$REPO_ROOT/}"
    
    # Through attr, which parses attributes, rather than a grep for the marker.
    # The grep interpolated `#[pub]` into a basic regular expression, where
    # `[pub]` is a bracket expression matching one character out of p, u and b.
    # It found no public functions in a library with more than a hundred, and
    # the check reported a pass on every one of them.
    local name func_name func_line
    name="$(attr_name_of "$PUBLIC_API_ANNOTATION")" || return
    name="${name%%$'\t'*}"

    _pad_load "$file" || return
    while IFS= read -r func_name; do
        [[ -z "$func_name" ]] && continue
        # Out of the loaded file rather than a `grep | head | cut`, which is
        # three processes per public function and answers a question the file
        # already in memory can answer.
        func_line="$(_pad_defined_at "$file" "$func_name")" || func_line=0
        echo "${func_name}|${func_line:-0}|${rel_path}"
    done < <(attr_find "$file" "$name")
}

# =============================================================================
# MAIN TEST
# =============================================================================

test_public_api_docs() {
    log_header "Public API Documentation Validation"
    log_info "Checking functions marked with $PUBLIC_API_ANNOTATION"
    log_info "Required elements: ${REQUIRED_ELEMENTS[*]}"
    log_info "Recommended elements: ${RECOMMENDED_ELEMENTS[*]}"
    log_info "Minimum doc lines: $MIN_DOC_LINES"
    echo ""
    
    local files
    files=$(get_script_files)
    
    if [[ -z "$files" ]]; then
        log_fail "No .sh files found to test"
        return 1
    fi
    
    local file_count=0
    local func_count=0
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
        
        # Find all public API functions in this file
        local public_functions
        # Loaded here, in this shell, before anything reads it through a
        # command substitution. A substitution is a subshell: it inherits what
        # is already loaded and throws away anything it loads itself, so the
        # cache below was being rebuilt once per function rather than once per
        # file. That was most of this check's time.
        _pad_load "$file" || true
        public_functions=$(find_public_api_functions "$file")
        
        while IFS='|' read -r func_name func_line func_file; do
            [[ -z "$func_name" ]] && continue
            func_count=$((func_count + 1))
            
            # Get the docblock for this function
            local docblock
            get_function_docblock "$file" "$func_name"
            docblock="$PAD_DOCBLOCK"
            
            local has_error=0
            local has_warn=0
            local missing_required=""
            local missing_recommended=""

            # A block that documents a different function is worse than a
            # missing one, because it reads as present from either end.
            local orphan_of=""
            if orphan_of="$(docblock_orphaned_from "$file" "$func_name" "$docblock")"; then
                has_error=1
                missing_required="the docblock is written for ${orphan_of}(), which is defined below this"
            fi

            # Check minimum doc lines
            local doc_lines
            doc_lines=$(count_doc_lines "$docblock")
            
            if [[ -n "$orphan_of" ]]; then
                : # already reported, and the count below would overwrite why
            elif [[ $doc_lines -lt $MIN_DOC_LINES ]]; then
                has_error=1
                missing_required="insufficient documentation ($doc_lines lines, need $MIN_DOC_LINES)"
            else
                # Check required elements
                for element in "${REQUIRED_ELEMENTS[@]}"; do
                    if ! docblock_has_element "$docblock" "$element"; then
                        has_error=1
                        if [[ -z "$missing_required" ]]; then
                            missing_required="$element"
                        else
                            missing_required="$missing_required, $element"
                        fi
                    fi
                done
                
                # Check recommended elements (only warn, don't fail)
                local has_any_recommended=0
                for element in "${RECOMMENDED_ELEMENTS[@]}"; do
                    if docblock_has_element "$docblock" "$element"; then
                        has_any_recommended=1
                        break
                    fi
                done
                
                if [[ $has_any_recommended -eq 0 ]] && [[ ${#RECOMMENDED_ELEMENTS[@]} -gt 0 ]]; then
                    has_warn=1
                    missing_recommended="none of: ${RECOMMENDED_ELEMENTS[*]}"
                fi
            fi
            
            # Report results
            if [[ $has_error -eq 1 ]]; then
                if [[ $file_has_issues -eq 0 ]]; then
                    echo -e "${CYAN}$rel_path${NC}"
                    file_has_issues=1
                fi
                log_fail "${func_name}() - missing required: $missing_required"
                errors+=("${rel_path}:${func_line} ${func_name}() - missing: $missing_required")
                error_count=$((error_count + 1))
            elif [[ $has_warn -eq 1 ]]; then
                if [[ $file_has_issues -eq 0 ]]; then
                    echo -e "${CYAN}$rel_path${NC}"
                    file_has_issues=1
                fi
                log_test_warn "${func_name}() - missing recommended: $missing_recommended"
                warnings+=("${rel_path}:${func_line} ${func_name}() - missing: $missing_recommended")
                warn_count=$((warn_count + 1))
            else
                log_pass "${func_name}()"
            fi
        done <<< "$public_functions"
        
        if [[ $file_has_issues -eq 1 ]]; then
            echo ""
        fi
        
    done <<< "$files"
    
    echo ""
    log_info "Scanned $file_count files, found $func_count public API functions"
    echo ""
    
    # Summary
    if [[ $error_count -eq 0 ]] && [[ $warn_count -eq 0 ]]; then
        log_pass "All public API functions are properly documented"
    else
        if [[ $error_count -gt 0 ]]; then
            echo -e "${RED}Found $error_count functions missing required documentation${NC}"
        fi
        if [[ $warn_count -gt 0 ]]; then
            echo -e "${YELLOW}Found $warn_count functions missing recommended documentation${NC}"
        fi
        echo ""
        echo "Required documentation elements:"
        for element in "${REQUIRED_ELEMENTS[@]}"; do
            echo "  - $element"
        done
        echo ""
        echo "Recommended documentation elements (any one of):"
        for element in "${RECOMMENDED_ELEMENTS[@]}"; do
            echo "  - $element"
        done
        echo ""
        echo "Example of well-documented public API function:"
        echo ""
        echo "  # #[pub]"
        echo "  # Brief description of what the function does"
        echo "  # Usage: function_name \"arg1\" \"arg2\" -> \"result\""
        echo "  function_name() {"
        echo "      ..."
        echo "  }"
    fi
    
    # Set test counters
    TESTS_RUN=$func_count
    if [[ $func_count -eq 0 ]]; then
        TESTS_RUN=1
        TESTS_PASSED=1
    else
        TESTS_PASSED=$((func_count - error_count))
    fi
    TESTS_FAILED=$error_count
    TESTS_WARNED=$warn_count
    FAILED_TESTS=("${errors[@]}")
    WARNED_TESTS=("${warnings[@]}")
    
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
    test_public_api_docs
    local result=$?
    
    # Print summary and exit
    print_summary "Public API Documentation"
    exit_with_status
}

# `NUT_CHECK_LOAD_ONLY` is the one way in for a test that wants the docblock
# readers without a whole run over a repository, the same door
# `check_function_duplication.sh` carries for the same reason.
#
# A check script is an entry point, so it runs.
#
# This used to be guarded by `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`, the ordinary
# "executed, not sourced" test. Under nutshell it is never true: the `#!/usr/bin/env
# nutshell` shebang runs the interpreter, and the interpreter *sources* the
# script, which is what makes `use` available from its first line. So `$0` is
# the interpreter and `BASH_SOURCE[0]` is this file, and `main` was never
# called. Six of the eight built-in checks exited 0 having done nothing, and
# `./check` read that as a pass and printed one.
[[ -n "${NUT_CHECK_LOAD_ONLY:-}" ]] || main "$@"
