# nutshell Design Document

## Overview

nutshell is a minimal bash utility library providing core primitives for shell scripting. This document captures architectural decisions, rationale, and design principles.

**Status**: The core architecture described here is fully implemented. See TODO.md for remaining work.

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

- Every public function marked with `#[pub]`.
- Every public function has `Usage:` documentation.
- Annotations are semantic and serve multiple purposes.

## Architecture

### Layered Structure

Every module is declared in `lib.nut`, one row per module, and loaded by `use`.
The rows below are the base of the stack and what each one `use`s.

```
Foundation: no other module
  os.sh       - OS detection
  log.sh      - Logging
  string.sh   - String manipulation (string.posix.sh where the shell is not bash)

Tools: what is on the machine
  key.sh      - The name encoding every table here is keyed by
  deps.sh     - Tool detection and variants (uses os, key); deps/pins.sh reads
                `[deps.paths]` through toml, loaded by init on the first pin
                asked for, so deps.sh itself still loads under a POSIX shell

Core: may use the two above
  validate.sh - Input validation (uses log, deps)
  array.sh    - Array operations (uses list)
  fs.sh       - Filesystem primitives (uses deps; fs/impl/ per stat variant)
  text.sh     - Text file processing (uses deps; text/impl/ per tool)
  toml.sh     - TOML reading (uses key; deps on its first pick of a reader,
                validate for `toml_is_true`). taplo or
                mikefarah yq where deps finds one, else the bash reader in
                toml/impl/, which needs nothing; toml/cache.sh keeps that
                reader's tree between processes, under the user's cache
                directory and only where nobody else can write it;
                toml/write.sh edits in place, rows of an array of tables
                included, toml/json.sh converts to JSON with toml/emit.sh,
                and a file of 64 KB or more by toml/large.sh: the JSON kept
                for its text, or taplo's own JSON where taplo is the
                reader, else the bash reader. toml/find.sh names
                the files of many where a key holds a value, toml/comment.sh
                gives a key's comments
  xdg.sh      - XDG directories (uses os, validate)
```

### Module File Structure

```
nutshell/
  init                     # Defines `use`; every script sources it
  nutshell.sh              # Loads every module at once
  lib.nut                  # Module name to file, with gates
  lib/
    deps.sh                # Tool detection
    deps/                  # config, pins, probe, state, variants
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

1. A pin in `[deps.paths]` of the `nut.toml` that applies: the first found
   walking up from the file asking, then from the script being run, then from
   the working directory, and nutshell's own as the last resort. The pin is
   read through the toml module, in any spelling TOML allows. A pin to
   something that is not an executable file is refused, said once on stderr,
   and never falls through to PATH. A manifest that is not TOML pins nothing,
   and that is said once.
2. Else walk `PATH` element by element, an empty element being the working
   directory, and take the first `<dir>/<tool>` that is an executable regular
   file. No `which` and no `command -v`: the walk is in the shell, with no fork
3. Else check common locations in order:
   - `/usr/bin/<tool>`
   - `/bin/<tool>`
   - `/usr/local/bin/<tool>`
   - `/opt/homebrew/bin/<tool>` (macOS)
4. Verify the binary exists and is executable before accepting
5. If not found anywhere, mark as unavailable

`_deps_find_tool` in `lib/deps/config.sh` is the code.

### Environment Info Structure

```bash
# Available tools (space-separated list)
_TOOLS_AVAILABLE="sed perl awk grep stat find mktemp sort wc tr head tail cut tee xargs"

# Tool paths (associative array)
declare -A _TOOL_PATH=(
    [sed]="/usr/bin/sed"
    [perl]="/usr/bin/perl"
    [awk]="/usr/bin/awk"
    [grep]="/usr/bin/grep"
    [stat]="/usr/bin/stat"
    [find]="/usr/bin/find"
    # ... and more
)

# Tool variants (associative array)
declare -A _TOOL_VARIANT=(
    [sed]="bsd"       # "gnu" or "bsd"
    [awk]="bsd"       # "gawk", "mawk", "nawk", or "bsd"
    [grep]="gnu"      # "gnu" or "bsd"
    [stat]="bsd"      # "gnu" or "bsd"
    [find]="bsd"      # "gnu" or "bsd"
)

# Capability flags (1 = available, 0 = not available)
declare -A _TOOL_CAN=(
    # sed capabilities
    [sed_inplace]=1       # Can do in-place editing
    [sed_extended]=1      # Supports -E for extended regex
    [sed_regex_r]=0       # Supports -r (GNU only, same as -E)
    
    # grep capabilities
    [grep_pcre]=0         # Supports -P for PCRE (GNU only)
    [grep_extended]=1     # Supports -E
    [grep_include]=0      # Supports --include/--exclude
    [grep_only_matching]=1 # Supports -o
    
    # awk capabilities
    [awk_regex]=1         # Basic regex (all awks)
    [awk_nextfile]=0      # nextfile statement (gawk)
    [awk_strftime]=0      # strftime function (gawk)
    [awk_gensub]=0        # gensub function (gawk)
    
    # perl capabilities
    [perl_regex]=1        # Perl regex
    [perl_inplace]=1      # In-place editing with -i
    [perl_json]=1         # JSON module available
    
    # stat capabilities
    [stat_format]=1       # Format string support
    
    # find capabilities
    [find_maxdepth]=1     # -maxdepth option
    [find_printf]=0       # -printf option (GNU only)
)
```

### Public API for Querying

```bash
# Check availability
deps_has "sed"                  # -> 0/1
deps_has_all "sed" "awk"        # -> 0/1
deps_has_any "perl" "python"    # -> 0/1
deps_available                  # -> "sed awk grep..."

# Get info
deps_path "sed"                 # -> "/usr/bin/sed"
deps_variant "sed"              # -> "gnu" or "bsd"
deps_is_gnu "grep"              # -> 0/1
deps_is_bsd "stat"              # -> 0/1

# Check capabilities
deps_can "grep_pcre"            # -> 0/1
deps_cap "grep_pcre"            # -> "1" or "0"
deps_caps                       # -> "cap=value\n..."

# Requirements
deps_require "git"              # exits if missing
deps_require_all "sed" "awk"    # exits if any missing
deps_require_cap "grep_pcre"    # exits if capability missing
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

## The Interpreter's Prelude Stubs

`bin/nutshell` loads no module for itself. It used to load `extern` and `log`
before every script, about 230ms and 22 files, and a script that called
`log_info` or `deps_has` with no `use` worked because of it. `prelude.nut` keeps
that working: one row per module, the name a `use` writes and then the public
functions that load put in reach, 165 of them. The table is read with `read`,
before any module is loaded, so it needs no parser.

For each function in it that is not already defined, the interpreter defines a
stub, all of them in one `eval`:

```bash
log_info() { _nut_prelude log log_info "$@"; }
```

The first call runs `use log`, which overwrites every stub of that module with
the real function, and then calls the function again by name. Where the `use`
loaded the module but the name is still the stub, `_nut_prelude` stops with
`[ERROR] log_info: use log loaded but did not define it` rather than calling
itself until the stack gives out. A script that calls none of them loads
nothing; the stubs cost about 2ms a start, measured in `benches/start-cost`.

Before the script runs, the interpreter reads its text once, cut at each `(`
and at each `function `, for two things the rules below use: the functions of
the table it defines (`name()`, `name ()`, `function name`), and those it calls
as the first word of a `$(`. That is about 0.2ms for a short script and 2.5ms
for a 13KB one. Text in a file the script sources is not read.

Three rules keep a script working as it did when both modules loaded first:

- A function already defined when the interpreter is sourced is the real one,
  and gets no stub.
- A function the script defines itself, in place of a stub, is not overwritten
  by a later `use` of its module, or of a module that loads it. Where the text
  defines one, `use` asks `_nut_prelude_keep`, before the module is first
  sourced, which of those are there and are not stubs, and puts them back
  afterwards; that is one fork. A script that defines none pays nothing. One
  defined in a sourced file is not seen, and a later `use` goes over it.
- A stub called inside `$(...)` loads its module in that subshell, and the load
  is lost with it, so every call pays the whole load again: twenty
  `$(fs_basename)` calls took 1508ms a start, some 75ms each, where with `fs`
  loaded first they take a few milliseconds. So a module whose function the
  text calls first in a `$(` is loaded once before the script runs, and the
  twenty calls take 79ms (`benches/start-cost`). A call reached through a pipe
  or a later word in the `$(`, or from a sourced file, is not seen, and still
  pays the load in each subshell; a script that wants none of this cost writes
  the `use`.

## Impl File Contract

Every impl file in `*/impl/` directories must follow this contract:

### Required Structure

```bash
#!/usr/bin/env bash
# =============================================================================
# module/impl/tool_operation.sh - Description
# =============================================================================
# Part of nutshell - Everything you need, in a nutshell.
# https://github.com/orgrinrt/nutshell
#
# Describe what this impl does and when it's selected.
# =============================================================================

# 1. Internal implementation function (prefixed with _)
_operation_tool_impl() {
    local arg1="${1:-}"
    # ... implementation using _TOOL_PATH and _TOOL_VARIANT
}

# 2. When sourced: redefine the public function
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    public_function() {
        _operation_tool_impl "$@"
    }
}

# 3. When executed directly: standalone mode
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Minimal setup if env vars not set
    if [[ -z "${_TOOL_PATH[tool]:-}" ]]; then
        declare -A _TOOL_PATH=()
        declare -A _TOOL_VARIANT=()
        _TOOL_PATH[tool]="$(command -v tool 2>/dev/null || echo "tool")"
        # Detect variant...
    fi
    
    _operation_tool_impl "$@"
fi
```

### Rules

1. **Naming**: File named `tool_operation.sh` (e.g., `sed_replace.sh`, `grep_match.sh`)
2. **Internal function**: Named `_operation_tool_impl` (e.g., `_text_replace_sed_impl`)
3. **Public function**: Must match the stub function name exactly
4. **Environment access**: Read `_TOOL_PATH` and `_TOOL_VARIANT` directly
5. **No deps.sh calls**: Impl files don't call `deps_*` functions; they use the cached arrays
6. **Standalone fallback**: When run directly, set up minimal environment
7. **Default values**: Use `${_TOOL_PATH[tool]:-tool}` for graceful fallback

### Example: Multiple Functions in One Impl

When one impl file provides multiple related functions:

```bash
# text/impl/grep_match.sh - provides text_grep, text_contains, text_count_matches

_text_grep_grep_impl() { ... }
_text_contains_grep_impl() { ... }
_text_count_matches_grep_impl() { ... }

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    text_grep() { _text_grep_grep_impl "$@"; }
    text_contains() { _text_contains_grep_impl "$@"; }
    text_count_matches() { _text_count_matches_grep_impl "$@"; }
fi
```

## Tool Combos

Some operations work best with multiple tools. The stub pattern handles this
by preferring combo implementations when multiple tools are available.

### Example: text_replace with grep+sed combo

```bash
# text.sh - stub prefers combo when both tools available

text_replace() {
    # Prefer combo when both grep and sed are available
    # The combo checks if pattern exists before invoking sed (optimization)
    if deps_has_all "grep" "sed"; then
        source "${_TEXT_COMBO_DIR}/grep_sed.sh"
        _TEXT_REPLACE_IMPL="grep_sed"
    elif deps_has "sed"; then
        source "${_TEXT_IMPL_DIR}/sed_replace.sh"
        _TEXT_REPLACE_IMPL="sed"
    elif deps_has "perl"; then
        source "${_TEXT_IMPL_DIR}/perl_replace.sh"
        _TEXT_REPLACE_IMPL="perl"
    # ...
    fi
    
    text_replace "$@"
}
```

### Combo Impl Structure

Combo impls live in `impl/combo/` and follow the same contract as single-tool impls:

```bash
# text/impl/combo/grep_sed.sh

# Optimized: check if pattern exists before running sed
_text_replace_grep_sed_impl() {
    local pattern="${1:-}"
    local replacement="${2:-}"
    local file="${3:-}"
    
    # Quick check: does the pattern even exist?
    if ! "${_TOOL_PATH[grep]}" -qE "$pattern" "$file" 2>/dev/null; then
        return 0  # Pattern not found, nothing to replace
    fi
    
    # Pattern exists, do the replacement
    "${_TOOL_PATH[sed]}" -i "s/${pattern}/${replacement}/g" "$file"
}

# When sourced: replace the stub
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    text_replace() {
        _text_replace_grep_sed_impl "$@"
    }
fi
```

### Combo-Only Functions

Some functions only make sense as combos:

- `text_filtered_replace "filter" "search" "replace" "file"` - Replace only in matching lines
- `text_extract_transform "pattern" "search" "replace" "file"` - Extract and transform (non-destructive)
- `text_count_in_matches "filter" "count_pattern" "file"` - Scoped counting

### Introspection

Modules expose which impl was selected (useful for debugging/testing):

```bash
text_replace "foo" "bar" file.txt
echo "Used impl: $(text_replace_impl)"  # -> "grep_sed" or "sed" or "perl"
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

| Annotation | Meaning | Example |
|------------|---------|---------|
| `#[pub]` | Function is part of public interface | `#[pub]` |
| `#[allow(trivial_wrapper)]` | Intentionally simple wrapper | `#[allow(trivial_wrapper)]` |
| `#[allow(loc = N)]` | File size exemption | `#[allow(loc = 450)]` |

Each annotation is a comment placed either on its own line directly above the function it applies to, or near the top of the file when it governs the whole module (the file-size exemption sits below the file's header comment block, before the first function).

### Rules

1. Every public function MUST have `#[pub]`
2. Every `#[pub]` function MUST have `Usage:` in its comment block
3. Trivial wrappers (1-2 line functions) need `#[pub]` or `#[allow(trivial_wrapper)]`
4. Files exceeding 300 LOC need `#[allow(loc = N)]` with the actual limit

### Example

```bash
#[pub]
# Check if a tool is available
# Usage: deps_has "sed" -> returns 0 (true) or 1 (false)
deps_has() {
    local tool="${1:-}"
    [[ -n "${_TOOL_PATH[$tool]:-}" ]]
}

#[pub]
#[allow(trivial_wrapper)]
# Check if path exists
# Usage: fs_exists "path" -> returns 0 (true) or 1 (false)
fs_exists() {
    [[ -e "${1:-}" ]]
}
```

## QA System Design

### Philosophy

- Configuration-first: All tests driven by `nut.toml`
- No hardcoded values: Defaults from `templates/empty.nut.toml`
- Strict by choice: Users opt into strictness level

### Config Templates

| Template | What it sets |
|----------|------------|
| `empty.nut.toml` | All disabled, fully documented (schema reference) |
| `default.nut.toml` | Sensible defaults, catches obvious issues |
| `tough.nut.toml` | Every gate on, every threshold at its tightest |

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

### Module Readiness

Modules that depend on external tools expose readiness status:

```bash
# Check before using
if text_ready; then
    text_replace "foo" "bar" file.txt
else
    echo "Text module unavailable: $(text_error)" >&2
fi

# Or require it
if ! text_ready; then
    log_fatal "$(text_error)"
fi
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

## QA Test Output

The test runner produces clean, tree-structured output:

```
nutshell QA

  Syntax                         ✓
  File Size                      ⚠
  Duplication                    ✓
  Trivial Wrappers               ✓
  Cruft                          ✓

Diagnostics:

  lib/
    deps.sh
      ⚠ 421 LOC
        └─ consider splitting or add #[allow(loc = 421)]

PASSED (5/5 tests, 1 with warnings)
```

Output level controlled with `--level=error|warn|info|debug`.

## Future Considerations

### Potential New Modules

- `semver.sh` - Semantic version parsing and comparison

### Potential Features

- Shell completion generation from `#[pub]` functions
- Benchmark suite for tool selection optimization
- Config schema validation (JSON Schema for nut.toml)
