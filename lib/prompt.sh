#!/usr/bin/env bash
# =============================================================================
# nutshell/lib/prompt.sh - User prompts and input handling
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): Depends on color.sh for terminal colors
#
# Provides functions for interactive user prompts:
#   - Yes/No confirmation
#   - Text input with validation
#   - Selection from options
#   - Password input (hidden)
#   - Multi-select
#
# All prompts respect non-interactive mode (when stdin is not a terminal).
# =============================================================================

# Prevent multiple inclusion
[[ -n "${_NUTSHELL_CORE_PROMPT_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_PROMPT_SH=1

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

_NUTSHELL_PROMPT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_NUTSHELL_PROMPT_DIR" == "${BASH_SOURCE[0]}" ]] && _NUTSHELL_PROMPT_DIR="."
source "${_NUTSHELL_PROMPT_DIR}/color.sh"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Default values for non-interactive mode
PROMPT_DEFAULT_CONFIRM="n"
PROMPT_DEFAULT_INPUT=""

# Timeout for prompts (0 = no timeout)
PROMPT_TIMEOUT=0

# -----------------------------------------------------------------------------
# Internal Helpers
# -----------------------------------------------------------------------------

# Check if we're in interactive mode
_prompt_is_interactive() {
    [[ -t 0 && -t 1 ]]
}

# Read with optional timeout
_prompt_read() {
    local var_name="$1"
    shift
    
    if [[ "$PROMPT_TIMEOUT" -gt 0 ]]; then
        read -t "$PROMPT_TIMEOUT" "$@" "$var_name"
    else
        read "$@" "$var_name"
    fi
}

# -----------------------------------------------------------------------------
# Public API - Basic Input
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Prompt for yes/no confirmation
# Usage: prompt_confirm "Continue?" -> returns 0 for yes, 1 for no
# Usage: prompt_confirm "Delete?" "y" -> default is yes
# Returns: 0 if user confirms, 1 if user declines
prompt_confirm() {
    local message="${1:-Confirm?}"
    local default="${2:-n}"
    
    # Non-interactive: use default
    if ! _prompt_is_interactive; then
        [[ "${default,,}" == "y"* ]] && return 0
        return 1
    fi
    
    local prompt_text
    if [[ "${default,,}" == "y"* ]]; then
        prompt_text="${message} ${DIM}[Y/n]${NC} "
    else
        prompt_text="${message} ${DIM}[y/N]${NC} "
    fi
    
    local response
    while true; do
        echo -n -e "$prompt_text"
        _prompt_read response -r
        local status=$?
        
        # Timeout or EOF - use default
        if [[ $status -ne 0 ]]; then
            echo ""
            response="$default"
        fi
        
        # Empty response - use default
        [[ -z "$response" ]] && response="$default"
        
        case "${response,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)
                echo -e "${YELLOW}Please answer yes or no.${NC}"
                ;;
        esac
    done
}

# @@PUBLIC_API@@
# Prompt for text input
# Usage: prompt_input "Enter name:" -> prints user input
# Usage: prompt_input "Enter name:" "default" -> default value if empty
# Returns: User input or default (prints to stdout)
prompt_input() {
    local message="${1:-Input:}"
    local default="${2:-}"
    
    # Non-interactive: use default
    if ! _prompt_is_interactive; then
        echo "$default"
        return 0
    fi
    
    local prompt_text="$message "
    if [[ -n "$default" ]]; then
        prompt_text+="${DIM}[$default]${NC} "
    fi
    
    local response
    echo -n -e "$prompt_text"
    _prompt_read response -r
    
    # Empty response - use default
    [[ -z "$response" ]] && response="$default"
    
    echo "$response"
}

# @@PUBLIC_API@@
# Prompt for password (hidden input)
# Usage: prompt_password "Password:" -> prints password (not echoed)
# Returns: Password (prints to stdout)
prompt_password() {
    local message="${1:-Password:}"
    
    # Non-interactive: read from stdin anyway (for piped input)
    if ! _prompt_is_interactive; then
        local password
        read -r password
        echo "$password"
        return 0
    fi
    
    local password
    echo -n -e "$message "
    _prompt_read password -rs
    echo "" # New line after hidden input
    
    echo "$password"
}

# @@PUBLIC_API@@
# Prompt for input with validation
# Usage: prompt_validated "Email:" "^[^@]+@[^@]+$" -> keeps asking until valid
# Returns: Validated input (prints to stdout)
prompt_validated() {
    local message="${1:-Input:}"
    local pattern="${2:-.*}"
    local error_msg="${3:-Invalid input. Please try again.}"
    local default="${4:-}"
    
    # Non-interactive: return default (may not be valid, but that's the user's problem)
    if ! _prompt_is_interactive; then
        echo "$default"
        return 0
    fi
    
    local response
    while true; do
        response=$(prompt_input "$message" "$default")
        
        if [[ "$response" =~ $pattern ]]; then
            echo "$response"
            return 0
        fi
        
        echo -e "${RED}${error_msg}${NC}" >&2
    done
}

# @@PUBLIC_API@@
# Prompt for integer input
# Usage: prompt_int "Count:" -> prints integer
# Usage: prompt_int "Count:" 1 100 -> enforces range
# Returns: Integer value (prints to stdout)
prompt_int() {
    local message="${1:-Number:}"
    local min="${2:-}"
    local max="${3:-}"
    local default="${4:-}"
    
    local error_msg="Please enter a valid integer"
    if [[ -n "$min" && -n "$max" ]]; then
        error_msg+=" between $min and $max"
    elif [[ -n "$min" ]]; then
        error_msg+=" >= $min"
    elif [[ -n "$max" ]]; then
        error_msg+=" <= $max"
    fi
    error_msg+="."
    
    # Non-interactive
    if ! _prompt_is_interactive; then
        echo "${default:-0}"
        return 0
    fi
    
    local response
    while true; do
        response=$(prompt_input "$message" "$default")
        
        # Check if integer
        if ! [[ "$response" =~ ^-?[0-9]+$ ]]; then
            echo -e "${RED}${error_msg}${NC}" >&2
            continue
        fi
        
        # Check range
        if [[ -n "$min" && "$response" -lt "$min" ]]; then
            echo -e "${RED}${error_msg}${NC}" >&2
            continue
        fi
        if [[ -n "$max" && "$response" -gt "$max" ]]; then
            echo -e "${RED}${error_msg}${NC}" >&2
            continue
        fi
        
        echo "$response"
        return 0
    done
}

# -----------------------------------------------------------------------------
# Public API - Selection
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Prompt user to select from numbered options
# Usage: prompt_select "Choose:" "Option A" "Option B" "Option C" -> prints selected option
# Returns: Selected option text (prints to stdout)
prompt_select() {
    local message="${1:-Select:}"
    shift
    local options=("$@")
    
    if [[ ${#options[@]} -eq 0 ]]; then
        echo "No options provided" >&2
        return 1
    fi
    
    # Non-interactive: return first option
    if ! _prompt_is_interactive; then
        echo "${options[0]}"
        return 0
    fi
    
    echo -e "$message"
    
    local i
    for i in "${!options[@]}"; do
        echo -e "  ${CYAN}$((i + 1))${NC}) ${options[$i]}"
    done
    
    local selection
    while true; do
        echo -n -e "${DIM}Enter number [1-${#options[@]}]:${NC} "
        _prompt_read selection -r
        
        # Validate selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && \
           [[ "$selection" -ge 1 ]] && \
           [[ "$selection" -le ${#options[@]} ]]; then
            echo "${options[$((selection - 1))]}"
            return 0
        fi
        
        echo -e "${RED}Invalid selection. Please enter a number between 1 and ${#options[@]}.${NC}" >&2
    done
}

# @@PUBLIC_API@@
# Prompt user to select from options using arrow keys (if supported)
# Falls back to numbered selection if not interactive
# Usage: prompt_menu "Choose:" "Option A" "Option B" -> prints selected option
# Returns: Selected option text (prints to stdout)
prompt_menu() {
    local message="${1:-Select:}"
    shift
    local options=("$@")
    
    if [[ ${#options[@]} -eq 0 ]]; then
        echo "No options provided" >&2
        return 1
    fi
    
    # Non-interactive or no cursor control: fall back to numbered select
    if ! _prompt_is_interactive || [[ "${TERM:-}" == "dumb" ]]; then
        prompt_select "$message" "${options[@]}"
        return $?
    fi
    
    local selected=0
    local key
    
    # Hide cursor
    echo -n -e "\033[?25l"
    
    # Cleanup on exit
    trap 'echo -n -e "\033[?25h"' RETURN
    
    # Draw menu
    _prompt_draw_menu() {
        # Move cursor up and clear (if not first draw)
        if [[ "${1:-}" == "redraw" ]]; then
            echo -n -e "\033[$((${#options[@]} + 1))A"
        fi
        
        echo -e "$message"
        
        local i
        for i in "${!options[@]}"; do
            if [[ $i -eq $selected ]]; then
                echo -e "  ${BG_CYAN}${BLACK} > ${options[$i]} ${NC}"
            else
                echo -e "    ${options[$i]}"
            fi
        done
    }
    
    _prompt_draw_menu
    
    # Read keys
    while true; do
        read -rsn1 key
        
        case "$key" in
            $'\x1b')  # Escape sequence
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A')  # Up arrow
                        ((selected--))
                        [[ $selected -lt 0 ]] && selected=$((${#options[@]} - 1))
                        ;;
                    '[B')  # Down arrow
                        ((selected++))
                        [[ $selected -ge ${#options[@]} ]] && selected=0
                        ;;
                esac
                _prompt_draw_menu redraw
                ;;
            '')  # Enter
                # Show cursor
                echo -n -e "\033[?25h"
                echo "${options[$selected]}"
                return 0
                ;;
            q|Q)  # Quit
                echo -n -e "\033[?25h"
                return 1
                ;;
        esac
    done
}

# @@PUBLIC_API@@
# Multi-select: user can select multiple options
# Usage: prompt_multiselect "Select:" "Option A" "Option B" "Option C"
# Returns: Selected options, one per line (prints to stdout)
prompt_multiselect() {
    local message="${1:-Select (space to toggle, enter to confirm):}"
    shift
    local options=("$@")
    
    if [[ ${#options[@]} -eq 0 ]]; then
        echo "No options provided" >&2
        return 1
    fi
    
    # Non-interactive: return all options
    if ! _prompt_is_interactive; then
        printf '%s\n' "${options[@]}"
        return 0
    fi
    
    # Track selected items (0 = not selected, 1 = selected)
    local -a selected=()
    for i in "${!options[@]}"; do
        selected[$i]=0
    done
    
    local cursor=0
    local key
    
    # Hide cursor
    echo -n -e "\033[?25l"
    trap 'echo -n -e "\033[?25h"' RETURN
    
    _prompt_draw_multiselect() {
        if [[ "${1:-}" == "redraw" ]]; then
            echo -n -e "\033[$((${#options[@]} + 1))A"
        fi
        
        echo -e "$message"
        
        local i
        for i in "${!options[@]}"; do
            local marker="[ ]"
            [[ ${selected[$i]} -eq 1 ]] && marker="${GREEN}[✓]${NC}"
            
            if [[ $i -eq $cursor ]]; then
                echo -e "  ${REVERSE}${marker} ${options[$i]}${NC}"
            else
                echo -e "  ${marker} ${options[$i]}"
            fi
        done
    }
    
    _prompt_draw_multiselect
    
    while true; do
        read -rsn1 key
        
        case "$key" in
            $'\x1b')
                read -rsn2 -t 0.1 key
                case "$key" in
                    '[A')  # Up
                        ((cursor--))
                        [[ $cursor -lt 0 ]] && cursor=$((${#options[@]} - 1))
                        ;;
                    '[B')  # Down
                        ((cursor++))
                        [[ $cursor -ge ${#options[@]} ]] && cursor=0
                        ;;
                esac
                _prompt_draw_multiselect redraw
                ;;
            ' ')  # Space - toggle selection
                if [[ ${selected[$cursor]} -eq 0 ]]; then
                    selected[$cursor]=1
                else
                    selected[$cursor]=0
                fi
                _prompt_draw_multiselect redraw
                ;;
            '')  # Enter - confirm
                echo -n -e "\033[?25h"
                for i in "${!options[@]}"; do
                    [[ ${selected[$i]} -eq 1 ]] && echo "${options[$i]}"
                done
                return 0
                ;;
            q|Q)
                echo -n -e "\033[?25h"
                return 1
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Public API - Special Prompts
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Prompt for a file path with completion hint
# Usage: prompt_file "Config file:" -> prints file path
# Returns: File path (prints to stdout)
prompt_file() {
    local message="${1:-File:}"
    local default="${2:-}"
    local must_exist="${3:-false}"
    
    if ! _prompt_is_interactive; then
        echo "$default"
        return 0
    fi
    
    local response
    while true; do
        response=$(prompt_input "$message" "$default")
        
        # Expand ~ to home directory
        response="${response/#\~/$HOME}"
        
        if [[ "$must_exist" == "true" && ! -f "$response" ]]; then
            echo -e "${RED}File not found: $response${NC}" >&2
            continue
        fi
        
        echo "$response"
        return 0
    done
}

# @@PUBLIC_API@@
# Prompt for a directory path
# Usage: prompt_dir "Output directory:" -> prints directory path
# Returns: Directory path (prints to stdout)
prompt_dir() {
    local message="${1:-Directory:}"
    local default="${2:-}"
    local must_exist="${3:-false}"
    
    if ! _prompt_is_interactive; then
        echo "$default"
        return 0
    fi
    
    local response
    while true; do
        response=$(prompt_input "$message" "$default")
        
        # Expand ~ to home directory
        response="${response/#\~/$HOME}"
        
        if [[ "$must_exist" == "true" && ! -d "$response" ]]; then
            echo -e "${RED}Directory not found: $response${NC}" >&2
            continue
        fi
        
        echo "$response"
        return 0
    done
}

# @@PUBLIC_API@@
# Wait for user to press any key
# Usage: prompt_pause -> waits for keypress
# Usage: prompt_pause "Press any key to continue..."
prompt_pause() {
    local message="${1:-Press any key to continue...}"
    
    if ! _prompt_is_interactive; then
        return 0
    fi
    
    echo -n -e "${DIM}${message}${NC}"
    read -rsn1
    echo ""
}

# @@PUBLIC_API@@
# Countdown with option to cancel
# Usage: prompt_countdown 5 "Starting in" -> returns 0 if completed, 1 if cancelled
# Returns: 0 if countdown completed, 1 if user pressed key to cancel
prompt_countdown() {
    local seconds="${1:-5}"
    local message="${2:-Continuing in}"
    
    if ! _prompt_is_interactive; then
        sleep "$seconds"
        return 0
    fi
    
    local i
    for ((i = seconds; i > 0; i--)); do
        echo -n -e "\r${message} ${CYAN}${i}${NC} seconds... (press any key to cancel)"
        
        if read -rsn1 -t 1; then
            echo -e "\r${message} ${RED}Cancelled${NC}                              "
            return 1
        fi
    done
    
    echo -e "\r${message} ${GREEN}Done${NC}                                        "
    return 0
}

# @@PUBLIC_API@@
# Ask user to choose between two options (like a vs b)
# Usage: prompt_choice "Keep?" "local" "remote" -> prints chosen option
# Returns: First or second option (prints to stdout)
prompt_choice() {
    local message="${1:-Choose:}"
    local option1="${2:-a}"
    local option2="${3:-b}"
    
    if ! _prompt_is_interactive; then
        echo "$option1"
        return 0
    fi
    
    local response
    while true; do
        echo -n -e "${message} ${CYAN}[${option1}]${NC}/${MAGENTA}[${option2}]${NC}: "
        _prompt_read response -r
        
        case "${response,,}" in
            "$option1"|"${option1,,}"|"1"|"a")
                echo "$option1"
                return 0
                ;;
            "$option2"|"${option2,,}"|"2"|"b")
                echo "$option2"
                return 0
                ;;
            "")
                echo "$option1"  # Default to first option
                return 0
                ;;
            *)
                echo -e "${YELLOW}Please choose ${option1} or ${option2}.${NC}" >&2
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Public API - Utility Functions
# -----------------------------------------------------------------------------

# @@PUBLIC_API@@
# Check if running in interactive mode
# Usage: prompt_interactive -> returns 0 if interactive, 1 otherwise
prompt_interactive() {
    _prompt_is_interactive
}

# @@PUBLIC_API@@
# Set the timeout for prompts (0 = no timeout)
# Usage: prompt_set_timeout 30 -> sets 30 second timeout
prompt_set_timeout() {
    PROMPT_TIMEOUT="${1:-0}"
}

# @@PUBLIC_API@@
# Set default value for confirm prompts in non-interactive mode
# Usage: prompt_set_default_confirm "y" -> defaults to yes
prompt_set_default_confirm() {
    PROMPT_DEFAULT_CONFIRM="${1:-n}"
}
