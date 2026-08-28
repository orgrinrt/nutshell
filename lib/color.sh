#!/usr/bin/env bash
# =============================================================================
# nutshell/core/color.sh - Terminal colors and formatting
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Layer 0 (Core): No dependencies on other nutshell modules
#
# Provides terminal color codes and formatting utilities. Automatically detects
# whether colors should be used based on terminal capabilities and environment.
#
# Features:
#   - Standard 16 colors (8 normal + 8 bright)
#   - 256-color support detection and usage
#   - True color (24-bit) support detection and usage
#   - Text formatting (bold, dim, italic, underline, etc.)
#   - Automatic NO_COLOR and TERM detection
#   - Functions for colorizing text
# =============================================================================

# Prevent multiple inclusion
# A guard of its own rather than `nut_once`, which reads `BASH_SOURCE` and uses
# `printf -v`. A file on the floor cannot ask a bash-only function whether it
# has been loaded: under a POSIX shell `nut_once` is not found, the `|| return
# 0` returns from the whole file, and the module then defines nothing while
# reporting success. That is worse than failing, because the caller has no way
# to tell.
[ -n "${_NUTSHELL_COLOR_SH:-}" ] && return 0
_NUTSHELL_COLOR_SH=1

# =============================================================================
# Color Support Detection
# =============================================================================

# Detect terminal color capabilities
# Sets: _COLOR_SUPPORT (none, basic, 256, truecolor)
_detect_color_support() {
    _COLOR_SUPPORT="none"
    
    # Check for explicit disable
    [ -n "${NO_COLOR:-}" ] && return
    
    # Check if stdout is a terminal
    [ ! -t 1 ] && return
    
    # Check TERM
    case "${TERM:-}" in
        dumb|"") return ;;
    esac
    
    # Basic color support
    _COLOR_SUPPORT="basic"
    
    # Check for 256 color support
    case "${TERM:-}" in
        *-256color|*-256*) _COLOR_SUPPORT="256" ;;
        xterm*|screen*|tmux*|rxvt*|linux|cygwin)
            # These typically support 256 colors
            _COLOR_SUPPORT="256"
            ;;
    esac
    
    # Check for true color support
    if [ "${COLORTERM:-}" = "truecolor" ] || [ "${COLORTERM:-}" = "24bit" ]; then
        _COLOR_SUPPORT="truecolor"
    fi
}

# Initialize color support detection
_detect_color_support

# =============================================================================
# ANSI Escape Sequences
# =============================================================================

# The escape character
# `$'\033'` is bash's. A substitution costs one fork, once, at load.
_ESC="$(printf '\033')"
readonly _ESC

# =============================================================================
# Standard Colors (Foreground)
# =============================================================================

# Reset all formatting
NC=""
RESET=""

# Regular colors
BLACK=""
RED=""
GREEN=""
YELLOW=""
BLUE=""
MAGENTA=""
CYAN=""
WHITE=""

# Bright/Bold colors
BRIGHT_BLACK=""
BRIGHT_RED=""
BRIGHT_GREEN=""
BRIGHT_YELLOW=""
BRIGHT_BLUE=""
BRIGHT_MAGENTA=""
BRIGHT_CYAN=""
BRIGHT_WHITE=""

# Aliases for bright colors (often called "light" or used as bold)
GRAY=""
LIGHT_RED=""
LIGHT_GREEN=""
LIGHT_YELLOW=""
LIGHT_BLUE=""
LIGHT_MAGENTA=""
LIGHT_CYAN=""
LIGHT_WHITE=""

# =============================================================================
# Background Colors
# =============================================================================

BG_BLACK=""
BG_RED=""
BG_GREEN=""
BG_YELLOW=""
BG_BLUE=""
BG_MAGENTA=""
BG_CYAN=""
BG_WHITE=""

BG_BRIGHT_BLACK=""
BG_BRIGHT_RED=""
BG_BRIGHT_GREEN=""
BG_BRIGHT_YELLOW=""
BG_BRIGHT_BLUE=""
BG_BRIGHT_MAGENTA=""
BG_BRIGHT_CYAN=""
BG_BRIGHT_WHITE=""

# =============================================================================
# Text Formatting
# =============================================================================

BOLD=""
DIM=""
ITALIC=""
UNDERLINE=""
BLINK=""
REVERSE=""
HIDDEN=""
STRIKETHROUGH=""

# Reset specific formatting
RESET_BOLD=""
RESET_DIM=""
RESET_ITALIC=""
RESET_UNDERLINE=""
RESET_BLINK=""
RESET_REVERSE=""
RESET_HIDDEN=""
RESET_STRIKETHROUGH=""

# =============================================================================
# Initialize Color Variables
# =============================================================================

_init_colors() {
    if [ "$_COLOR_SUPPORT" = "none" ]; then
        # All variables remain empty
        return
    fi
    
    # Reset
    NC="${_ESC}[0m"
    RESET="${_ESC}[0m"
    
    # Regular foreground colors
    BLACK="${_ESC}[30m"
    RED="${_ESC}[31m"
    GREEN="${_ESC}[32m"
    YELLOW="${_ESC}[33m"
    BLUE="${_ESC}[34m"
    MAGENTA="${_ESC}[35m"
    CYAN="${_ESC}[36m"
    WHITE="${_ESC}[37m"
    
    # Bright foreground colors
    BRIGHT_BLACK="${_ESC}[90m"
    BRIGHT_RED="${_ESC}[91m"
    BRIGHT_GREEN="${_ESC}[92m"
    BRIGHT_YELLOW="${_ESC}[93m"
    BRIGHT_BLUE="${_ESC}[94m"
    BRIGHT_MAGENTA="${_ESC}[95m"
    BRIGHT_CYAN="${_ESC}[96m"
    BRIGHT_WHITE="${_ESC}[97m"
    
    # Aliases
    GRAY="$BRIGHT_BLACK"
    LIGHT_RED="$BRIGHT_RED"
    LIGHT_GREEN="$BRIGHT_GREEN"
    LIGHT_YELLOW="$BRIGHT_YELLOW"
    LIGHT_BLUE="$BRIGHT_BLUE"
    LIGHT_MAGENTA="$BRIGHT_MAGENTA"
    LIGHT_CYAN="$BRIGHT_CYAN"
    LIGHT_WHITE="$BRIGHT_WHITE"
    
    # Background colors
    BG_BLACK="${_ESC}[40m"
    BG_RED="${_ESC}[41m"
    BG_GREEN="${_ESC}[42m"
    BG_YELLOW="${_ESC}[43m"
    BG_BLUE="${_ESC}[44m"
    BG_MAGENTA="${_ESC}[45m"
    BG_CYAN="${_ESC}[46m"
    BG_WHITE="${_ESC}[47m"
    
    BG_BRIGHT_BLACK="${_ESC}[100m"
    BG_BRIGHT_RED="${_ESC}[101m"
    BG_BRIGHT_GREEN="${_ESC}[102m"
    BG_BRIGHT_YELLOW="${_ESC}[103m"
    BG_BRIGHT_BLUE="${_ESC}[104m"
    BG_BRIGHT_MAGENTA="${_ESC}[105m"
    BG_BRIGHT_CYAN="${_ESC}[106m"
    BG_BRIGHT_WHITE="${_ESC}[107m"
    
    # Text formatting
    BOLD="${_ESC}[1m"
    DIM="${_ESC}[2m"
    ITALIC="${_ESC}[3m"
    UNDERLINE="${_ESC}[4m"
    BLINK="${_ESC}[5m"
    REVERSE="${_ESC}[7m"
    HIDDEN="${_ESC}[8m"
    STRIKETHROUGH="${_ESC}[9m"
    
    # Reset specific formatting
    RESET_BOLD="${_ESC}[22m"
    RESET_DIM="${_ESC}[22m"
    RESET_ITALIC="${_ESC}[23m"
    RESET_UNDERLINE="${_ESC}[24m"
    RESET_BLINK="${_ESC}[25m"
    RESET_REVERSE="${_ESC}[27m"
    RESET_HIDDEN="${_ESC}[28m"
    RESET_STRIKETHROUGH="${_ESC}[29m"
}

# Initialize on load
_init_colors

# =============================================================================
# Public API - Query Functions
# =============================================================================

#[pub]
# Check if colors are enabled
# Usage: color_enabled -> returns 0 if colors enabled, 1 otherwise
color_enabled() {
    [ "$_COLOR_SUPPORT" != "none" ]
}

#[pub]
# Get the color support level
# Usage: color_support -> "none" | "basic" | "256" | "truecolor"
color_support() {
    echo "$_COLOR_SUPPORT"
}

#[pub]
# Check if 256-color mode is supported
# Usage: color_has_256 -> returns 0 if supported, 1 otherwise
color_has_256() {
    [ "$_COLOR_SUPPORT" = "256" ] || [ "$_COLOR_SUPPORT" = "truecolor" ]
}

#[pub]
# Check if true color (24-bit) is supported
# Usage: color_has_truecolor -> returns 0 if supported, 1 otherwise
color_has_truecolor() {
    [ "$_COLOR_SUPPORT" = "truecolor" ]
}

# =============================================================================
# Public API - Enable/Disable
# =============================================================================

#[pub]
# Force enable colors (ignores NO_COLOR and terminal detection)
# Usage: color_enable -> prints nothing; forces colour on regardless of what was detected
color_enable() {
    _COLOR_SUPPORT="basic"
    _init_colors
}

#[pub]
# Force disable colors
# Usage: color_disable -> prints nothing; forces colour off regardless of what was detected
color_disable() {
    _COLOR_SUPPORT="none"
    _init_colors
}

#[pub]
# Re-detect color support (useful after changing TERM or NO_COLOR)
# Usage: color_redetect -> prints nothing; re-runs detection, for a terminal that changed under us
color_redetect() {
    _detect_color_support
    _init_colors
}

# =============================================================================
# Public API - Colorize Functions
# =============================================================================

#[pub]
# Wrap text in a color and reset
# Usage: color_wrap "color_var" "text" -> prints colored text
# Example: color_wrap RED "Error!" -> "\e[31mError!\e[0m"
color_wrap() {
    local color_var="${1:-}"
    local text="${2:-}"
    
    # `${!name}` is bash's indirect expansion and a fatal `Bad substitution`
    # under a POSIX shell, which is worse than it sounds here: the file parses,
    # so it counted as floor-ready, and every `color_wrap` call returned the
    # empty string while the shell carried on at exit zero.
    #
    # The name is checked before it reaches `eval`, because it comes from the
    # caller and `color_wrap 'X}; rm -rf /; :' ...` would otherwise be a command
    # rather than a lookup.
    local color=""
    case "$color_var" in
        ''|*[!A-Za-z0-9_]*|[0-9]*) color="" ;;
        *) eval "color=\${${color_var}:-}" ;;
    esac
    
    if [ -n "$color" ]; then
        printf '%s' "${color}${text}${NC}"
    else
        printf '%s' "$text"
    fi
}

#[pub]
# Print text in red
# Usage: color_red "text" -> prints red text with newline
color_red() {
    printf '%b\n' "${RED}${1:-}${NC}"
}

#[pub]
# Print text in green
# Usage: color_green "text" -> prints green text with newline
color_green() {
    printf '%b\n' "${GREEN}${1:-}${NC}"
}

#[pub]
# Print text in yellow
# Usage: color_yellow "text" -> prints yellow text with newline
color_yellow() {
    printf '%b\n' "${YELLOW}${1:-}${NC}"
}

#[pub]
# Print text in blue
# Usage: color_blue "text" -> prints blue text with newline
color_blue() {
    printf '%b\n' "${BLUE}${1:-}${NC}"
}

#[pub]
# Print text in magenta
# Usage: color_magenta "text" -> prints magenta text with newline
color_magenta() {
    printf '%b\n' "${MAGENTA}${1:-}${NC}"
}

#[pub]
# Print text in cyan
# Usage: color_cyan "text" -> prints cyan text with newline
color_cyan() {
    printf '%b\n' "${CYAN}${1:-}${NC}"
}

#[pub]
# Print text in bold
# Usage: color_bold "text" -> prints bold text with newline
color_bold() {
    printf '%b\n' "${BOLD}${1:-}${NC}"
}

#[pub]
# Print text in dim
# Usage: color_dim "text" -> prints dim text with newline
color_dim() {
    printf '%b\n' "${DIM}${1:-}${NC}"
}

# =============================================================================
# Public API - 256 Color Functions
# =============================================================================

#[pub]
# Get ANSI escape for a 256-color foreground
# Usage: color_fg256 "color_num" -> prints escape sequence
# color_num: 0-255
color_fg256() {
    local n="${1:-0}"
    if color_has_256; then
        printf '%s' "${_ESC}[38;5;${n}m"
    fi
}

#[pub]
# Get ANSI escape for a 256-color background
# Usage: color_bg256 "color_num" -> prints escape sequence
color_bg256() {
    local n="${1:-0}"
    if color_has_256; then
        printf '%s' "${_ESC}[48;5;${n}m"
    fi
}

#[pub]
# Print text with 256-color foreground
# Usage: color_text256 "color_num" "text" -> prints colored text
color_text256() {
    local n="${1:-0}"
    local text="${2:-}"
    
    if color_has_256; then
        printf '%b\n' "${_ESC}[38;5;${n}m${text}${NC}"
    else
        printf '%b\n' "$text"
    fi
}

# =============================================================================
# Public API - True Color (24-bit) Functions
# =============================================================================

#[pub]
# Get ANSI escape for RGB foreground color
# Usage: color_fg_rgb "r" "g" "b" -> prints escape sequence
# r, g, b: 0-255
color_fg_rgb() {
    local r="${1:-0}"
    local g="${2:-0}"
    local b="${3:-0}"
    
    if color_has_truecolor; then
        printf '%s' "${_ESC}[38;2;${r};${g};${b}m"
    elif color_has_256; then
        # Fall back to nearest 256 color
        local n=$(( 16 + 36 * (r / 51) + 6 * (g / 51) + (b / 51) ))
        printf '%s' "${_ESC}[38;5;${n}m"
    fi
}

#[pub]
# Get ANSI escape for RGB background color
# Usage: color_bg_rgb "r" "g" "b" -> prints escape sequence
color_bg_rgb() {
    local r="${1:-0}"
    local g="${2:-0}"
    local b="${3:-0}"
    
    if color_has_truecolor; then
        printf '%s' "${_ESC}[48;2;${r};${g};${b}m"
    elif color_has_256; then
        local n=$(( 16 + 36 * (r / 51) + 6 * (g / 51) + (b / 51) ))
        printf '%s' "${_ESC}[48;5;${n}m"
    fi
}

#[pub]
# Print text with RGB foreground color
# Usage: color_text_rgb "r" "g" "b" "text" -> prints colored text
color_text_rgb() {
    local r="${1:-0}"
    local g="${2:-0}"
    local b="${3:-0}"
    local text="${4:-}"
    
    if color_has_truecolor; then
        printf '%b\n' "${_ESC}[38;2;${r};${g};${b}m${text}${NC}"
    elif color_has_256; then
        local n=$(( 16 + 36 * (r / 51) + 6 * (g / 51) + (b / 51) ))
        printf '%b\n' "${_ESC}[38;5;${n}m${text}${NC}"
    else
        printf '%b\n' "$text"
    fi
}

#[pub]
# Parse hex color and get RGB foreground escape
# Usage: color_fg_hex "#RRGGBB" -> prints escape sequence
# Example: color_fg_hex "#FF5500"
color_fg_hex() {
    local hex="${1:-#000000}"
    hex="${hex#\#}"  # Remove leading #
    
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    
    color_fg_rgb "$r" "$g" "$b"
}

#[pub]
# Parse hex color and get RGB background escape
# Usage: color_bg_hex "#RRGGBB" -> prints escape sequence
color_bg_hex() {
    local hex="${1:-#000000}"
    hex="${hex#\#}"
    
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    
    color_bg_rgb "$r" "$g" "$b"
}

#[pub]
# Print text with hex foreground color
# Usage: color_text_hex "#RRGGBB" "text" -> prints colored text
color_text_hex() {
    local hex="${1:-#000000}"
    local text="${2:-}"
    hex="${hex#\#}"
    
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    
    color_text_rgb "$r" "$g" "$b" "$text"
}

# =============================================================================
# Public API - Utility Functions
# =============================================================================

#[pub]
# Strip all ANSI escape sequences from text
# Usage: color_strip "colored text" -> prints plain text
color_strip() {
    local text="${1:-}"
    # Remove all ANSI escape sequences
    # `printf '%b'`, not `echo -e`: POSIX `echo` has no `-e` and prints it.
    printf '%b\n' "$text" | sed 's/\x1b\[[0-9;]*m//g'
}

#[pub]
# Get the visible length of text (excluding ANSI escapes)
# Usage: color_strlen "colored text" -> prints length as number
color_strlen() {
    local text="${1:-}"
    local stripped
    stripped=$(color_strip "$text")
    echo "${#stripped}"
}

#[pub]
# Pad text to a fixed width (accounting for colors)
# Usage: color_pad "text" "width" ["char"] -> prints padded text
# Default pad char is space
color_pad() {
    local text="${1:-}"
    local width="${2:-0}"
    local pad_char="${3:- }"
    
    local visible_len
    visible_len=$(color_strlen "$text")
    
    printf '%s' "$text"
    
    local padding=$((width - visible_len))
    if [ "$padding" -gt 0 ]; then
        printf "%${padding}s" "" | tr ' ' "$pad_char"
    fi
}

#[pub]
# Center text within a fixed width
# Usage: color_center "text" "width" -> prints centered text
color_center() {
    local text="${1:-}"
    local width="${2:-0}"
    
    local visible_len
    visible_len=$(color_strlen "$text")
    
    local total_padding=$((width - visible_len))
    [ "$total_padding" -lt 0 ] && total_padding=0
    
    local left_pad=$((total_padding / 2))
    local right_pad=$((total_padding - left_pad))
    
    printf "%${left_pad}s" ""
    printf '%s' "$text"
    printf "%${right_pad}s" ""
}

# =============================================================================
# Semantic Color Aliases (for common use cases)
# =============================================================================

# These provide semantic meaning to colors - can be customized by user

#[pub]
# Print success message (green)
# Usage: color_success "message" -> prints green message
color_success() {
    printf '%b\n' "${GREEN}${1:-}${NC}"
}

#[pub]
# Print error message (red)
# Usage: color_error "message" -> prints red message
color_error() {
    printf '%b\n' "${RED}${1:-}${NC}"
}

#[pub]
# Print warning message (yellow)
# Usage: color_warning "message" -> prints yellow message
color_warning() {
    printf '%b\n' "${YELLOW}${1:-}${NC}"
}

#[pub]
# Print info message (blue)
# Usage: color_info "message" -> prints blue message
color_info() {
    printf '%b\n' "${BLUE}${1:-}${NC}"
}

#[pub]
# Print debug message (dim)
# Usage: color_debug "message" -> prints dim message
color_debug() {
    printf '%b\n' "${DIM}${1:-}${NC}"
}

#[pub]
# Print highlighted/important message (bold + cyan)
# Usage: color_highlight "message" -> prints highlighted message
color_highlight() {
    printf '%b\n' "${BOLD}${CYAN}${1:-}${NC}"
}
