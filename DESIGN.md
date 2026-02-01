# nutshell Design Document

## Overview

nutshell is a minimal bash utility library providing core primitives for shell scripting. This document captures architectural decisions, rationale, and design principles.

## Core Principles

### 1. No Magic, No Lies

- We use external tools (sed, awk, grep, etc.). We document them, detect them, and provide fallbacks.
- Every function does exactly what its documentation says.
- When something is wrong, we say so. No silent failures.

### 2. Efficiency Through Lazy Initialization

- Public functions start as stubs that, on first call, determine the best implementation, source it, and redefine themselves.
- After first call, functions execute directly with no switch/case or delegation.
- Impl files are sourced lazily, not eagerly.

### 3. Detection Without Assumptions

- deps.sh collects what tools are available, their paths, their variants (GNU/BSD), their capabilities.
- Modules make their own decisions about which tool to use for each operation.
- No centralized "best tool" logic; the code doing the work knows what it needs.

### 4. Configuration Over Convention

- All behavior controlled by `nut.toml` configuration.
- No hardcoded values; defaults come from `templates/empty.nut.toml`.
- Users can override anything.

### 5. Self-Documenting Code

- Every public function marked with `@@PUBLIC_API@@`.
- Every public function has `Usage:` documentation.
- Annotations are semantic and serve multiple purposes.

## Architecture

### Layered Structure

```
Layer -1 (Foundation): Zero internal dependencies
  os.sh      - OS detection (pure bash)
  log.sh     - Logging (pure bash)
  deps.sh    - Tool detection, builds environment info

Layer 0 (Core): May depend on foundation, uses external tools
  validate.sh - Input validation (depends on log.sh)
  string.sh   - String manipulation (pure bash)
  array.sh    - Array operations (pure bash)
  fs.sh       - Filesystem primitives (uses stat, etc.)
  text.sh     - Text file processing (uses sed, grep, awk, perl)
  toml.sh     - TOML parsing (depends on string.sh, fs.sh)
  xdg.sh      - XDG directories (depends on os.sh, validate.sh)
```

### Module File Structure

```
nutshell/
  nutshell.sh              # Main entrypoint
  core/
    deps.sh                # Environment detection
    os.sh
    log.sh
    text.sh                # Public API + stubs
    text/
      impl/
        sed_replace.sh
        perl_replace.sh
        awk_replace.sh
        grep_match.sh
        ...
    fs.sh                  # Public API + stubs
    fs/
      impl/
        stat_gnu.sh
        stat_bsd.sh
        perl_stat.sh
```

## Tool Detection

### Path Resolution

deps.sh finds tools using this order:

1. Check user config in `nut.toml` for explicit paths
2. If `which` is available, use it to find tools
3. If `which` is not available, check common locations in order:
   - `/usr/bin/<tool>`
   - `/bin/<tool>`
   - `/usr/local/bin/<tool>`
   - `/opt/homebrew/bin/<tool>` (macOS)
4. Verify the binary exists and is executable before accepting
5. If not found anywhere, mark as unavailable

```bash
_find_tool_path() {
    local tool="$1"
    local user_path
    
    # 1. Check user config first
    user_path=$(cfg_get_or "deps.paths.${tool}" "")
    if [[ -n "$user_path" ]] && [[ -x "$user_path" ]]; then
        echo "$user_path"
        return 0
    fi
    
    # 2. Try which if available
    if command -v which &>/dev/null; then
        local found
        found=$(which "$tool" 2>/dev/null)
        if [[ -n "$found" ]] && [[ -x "$found" ]]; then
            echo "$found"
            return 0
        fi
    fi
    
    # 3. Check common locations
    local locations=(
        "/usr/bin/${tool}"
        "/bin/${tool}"
        "/usr/local/bin/${tool}"
        "/opt/homebrew/bin/${tool}"
    )
    
    for loc in "${locations[@]}"; do
        if [[ -x "$loc" ]]; then
            echo "$loc"
            return 0
        fi
    done
    
    # Not found
    return 1
}
```

### Environment Info Structure

```bash
# Available tools (space-separated list)
readonly _TOOLS_AVAILABLE="sed perl awk grep stat find mktemp"

# Tool paths (associative array)
declare -A _TOOL_PATH=(
    [sed]="/usr/bin/sed"
    [perl]="/usr/bin/perl"
    [awk]="/usr/bin/awk"
    [grep]="/usr/bin/grep"
    [stat]="/usr/bin/stat"
    [find]="/usr/bin/find"
)
readonly _TOOL_PATH

# Tool variants (associative array)
declare -A _TOOL_VARIANT=(
    [sed]="gnu"       # "gnu" or "bsd"
    [awk]="gawk"      # "gawk", "mawk", "nawk", or "bsd"
    [grep]="gnu"      # "gnu" or "bsd"
    [stat]="gnu"      # "gnu" or "bsd"
)
readonly _TOOL_VARIANT

# Capability flags
declare -A _TOOL_CAN=(
    [sed_inplace]=1       # Can sed do in-place editing?
    [sed_extended]=1      # Does sed support -E for extended regex?
    [grep_pcre]=1         # Does grep support -P for PCRE?
    [grep_extended]=1     # Does grep support -E?
    [stat_format]=1       # Does stat support format strings?
)
readonly _TOOL_CAN
```

### Why Modules Decide

Consider `text_replace`; it needs stream editing. But:
- For simple patterns, GNU sed is fastest
- For complex regex, perl might be better
- For field-based replacement, awk works well
- BSD sed needs different flags than GNU sed

Only `text.sh` knows what `text_replace` actually needs. So `deps.sh` just says "here's what you have" and lets `text.sh` decide.

## The Lazy-Init Stub Pattern

### Problem

Eager initialization wastes resources:
```bash
# Bad: sources ALL impls even if only one is used
source impl/sed.sh
source impl/perl.sh
source impl/awk.sh
```

Switch-case on every call wastes cycles:
```bash
# Bad: runs switch on EVERY call
text_replace() {
    case "$_BEST_TOOL" in
        sed)  _text_replace_sed "$@" ;;
        perl) _text_replace_perl "$@" ;;
    esac
}
```

### Solution: Self-Replacing Stubs

Public functions start as stubs that:
1. On first call, examine the environment info
2. Decide which implementation to use
3. Source only that implementation
4. The impl file overwrites the stub with the real function
5. Call the now-real function

```bash
# text.sh - initial stub

text_replace() {
    # First call: decide, source, delegate
    local tool
    
    # Module-specific decision logic
    if [[ " $_TOOLS_AVAILABLE " == *" sed "* ]]; then
        if [[ "${_TOOL_VARIANT[sed]}" == "gnu" ]]; then
            tool="sed"
        elif [[ " $_TOOLS_AVAILABLE " == *" perl "* ]]; then
            tool="perl"  # Prefer perl over BSD sed
        else
            tool="sed"   # BSD sed; impl handles quirks
        fi
    elif [[ " $_TOOLS_AVAILABLE " == *" perl "* ]]; then
        tool="perl"
    elif [[ " $_TOOLS_AVAILABLE " == *" awk "* ]]; then
        tool="awk"
    else
        log_error "No tool available for text_replace"
        return 1
    fi
    
    # Source impl - it OVERWRITES this function
    source "${_TEXT_IMPL_DIR}/${tool}_replace.sh"
    
    # Call the now-replaced function
    text_replace "$@"
}
```

### The Impl File

```bash
# text/impl/sed_replace.sh

# This REPLACES the stub when sourced
text_replace() {
    local pattern="$1"
    local replacement="$2"
    local file="$3"
    
    # Use environment info to handle variants
    if [[ "${_TOOL_VARIANT[sed]}" == "gnu" ]]; then
        "${_TOOL_PATH[sed]}" -i "s/${pattern}/${replacement}/g" "$file"
    else
        # BSD sed requires '' after -i
        "${_TOOL_PATH[sed]}" -i '' "s/${pattern}/${replacement}/g" "$file"
    fi
}
```

### Call Flow

```
First call:  text_replace "foo" "bar" file.txt
             |
             Stub executes
             |
             Examines environment, picks "sed"
             |
             Sources sed_replace.sh
             |
             sed_replace.sh defines text_replace() - OVERWRITES stub
             |
             Stub calls text_replace "$@" (now the real function)
             |
             sed executes

Second call: text_replace "x" "y" other.txt
             |
             Directly calls real text_replace (stub is gone)
             |
             sed executes
```

No overhead after first call.

### Impl Files as Standalone Scripts

Impl files can work both when sourced AND when executed directly:

```bash
# text/impl/sed_replace.sh

_sed_replace_impl() {
    local pattern="$1"
    local replacement="$2"
    local file="$3"
    
    if [[ "${_TOOL_VARIANT[sed]:-gnu}" == "gnu" ]]; then
        "${_TOOL_PATH[sed]:-sed}" -i "s/${pattern}/${replacement}/g" "$file"
    else
        "${_TOOL_PATH[sed]:-sed}" -i '' "s/${pattern}/${replacement}/g" "$file"
    fi
}

# When sourced: define public function
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    text_replace() { _sed_replace_impl "$@"; }
fi

# When executed directly: run with args
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _sed_replace_impl "$@"
fi
```

This enables:
- Direct testing of impl files
- Use as standalone scripts if needed
- Normal sourced operation

## Tool Combos

Some operations work best with multiple tools. The stub pattern handles this:

```bash
# text.sh

text_search_and_transform() {
    # Check for optimal combo: grep (fast filter) + sed (transform)
    if [[ " $_TOOLS_AVAILABLE " == *" grep "* ]] && \
       [[ " $_TOOLS_AVAILABLE " == *" sed "* ]]; then
        source "${_TEXT_IMPL_DIR}/combo/grep_sed_search_transform.sh"
    elif [[ " $_TOOLS_AVAILABLE " == *" perl "* ]]; then
        source "${_TEXT_IMPL_DIR}/perl_search_transform.sh"
    else
        source "${_TEXT_IMPL_DIR}/awk_search_transform.sh"
    fi
    
    text_search_and_transform "$@"
}
```

The combo impl:
```bash
# text/impl/combo/grep_sed_search_transform.sh

text_search_and_transform() {
    local search="$1"
    local transform="$2"
    local file="$3"
    
    # grep is optimized for matching, sed for transforming
    "${_TOOL_PATH[grep]}" -E "$search" "$file" | \
        "${_TOOL_PATH[sed]}" "$transform"
}
```

## Module Status Tracking

Modules set status variables after initialization:

```bash
# Set by module init
_TEXT_READY=1           # 1 = ready, 0 = failed
_TEXT_ERROR=""          # Error message if failed

# User code can check:
if [[ "$_TEXT_READY" != "1" ]]; then
    echo "Text module unavailable: $_TEXT_ERROR" >&2
    exit 1
fi
```

## Annotation System

### Defined Annotations

| Annotation | Meaning |
|------------|---------|
| `@@PUBLIC_API@@` | Function is part of public interface. Must have documentation. |
| `@@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@` | Function is intentionally simple for API consistency. |
| `@@ALLOW_LOC_NNN@@` | File allowed to exceed normal size limit (NNN lines). |

### Rules

1. Every public function MUST have `@@PUBLIC_API@@`
2. Every `@@PUBLIC_API@@` function MUST have `Usage:` in its comment block
3. Trivial wrappers (1-2 line functions) MUST have appropriate annotation

## QA System Design

### Philosophy

- Configuration-first: All tests driven by `nut.toml`
- No hardcoded values: Defaults from `templates/empty.nut.toml`
- Strict by choice: Users opt into strictness level

### Config Templates

| Template | Philosophy |
|----------|------------|
| `empty.nut.toml` | All disabled, fully documented (schema reference) |
| `default.nut.toml` | Sensible defaults, catches obvious issues |
| `tough.nut.toml` | No compromises, no technical debt |

## Error Handling

### ensure_ vs require_

- `ensure_*` - Soft check. Logs warning, returns 1. Caller handles.
- `require_*` - Hard check. Logs fatal, exits. No recovery.

```bash
# Soft: Let me check, you decide what to do
ensure_command "git" "Git not found" || {
    log_warn "Falling back to manual method"
    do_manual_thing
}

# Hard: I absolutely need this, fail if missing
require_command "git" "Git is required for this operation"
```

## Guard Variables

All modules use inclusion guards:

```bash
[[ -n "${_NUTSHELL_CORE_MODULENAME_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_MODULENAME_SH=1
```

## Relationship to the-whole-shebang

```
nutshell (this repo)
  Core primitives
  Foundation layer (deps, os, log)
  Tool-using layer (text, fs)
  QA system

the-whole-shebang
  nutshell (as submodule)
  infra/
    template.sh
    ui.sh
    cache.sh
    state.sh
  services/
    git.sh
    docker.sh
```

nutshell is "everything you need, in a nutshell" - the minimal core.

the-whole-shebang is "when you need the whole shebang" - full toolkit.

## Performance Considerations

### Why This Architecture?

| Approach | First Call | Subsequent Calls | Memory |
|----------|------------|------------------|--------|
| Eager source all | Slow (parse all) | Fast | High (all loaded) |
| Switch every call | Fast | Slow (switch) | Medium |
| Lazy stub (ours) | Medium (source one) | Fastest (direct) | Low (only needed) |

### Memoization

The stub pattern is memoization; after first call, the decision is "cached" in the function definition itself. No lookup, no switch, just the implementation.

## Future Considerations

### Potential New Modules

- `http.sh` - curl/wget abstraction
- `json.sh` - jq/python/perl JSON parsing
- `semver.sh` - Semantic version parsing and comparison

### Potential Features

- Shell completion generation from `@@PUBLIC_API@@` functions
- Benchmark suite for tool selection optimization
- Man page generation from documentation
