# nutshell Design Document

## Overview

nutshell is a minimal bash utility library providing core primitives for shell scripting. This document captures architectural decisions, rationale, and design principles.

## Core Principles

### 1. No Magic, No Lies

- **Honest about dependencies**: We use external tools (sed, awk, grep, etc.). We document them, detect them, and provide fallbacks.
- **No hidden behavior**: Every function does exactly what its documentation says.
- **Fail loudly**: When something is wrong, we say so. No silent failures.

### 2. Layered Architecture

```
Layer -1 (Foundation): Zero internal dependencies
├── os.sh      - OS detection
├── log.sh     - Logging
└── deps.sh    - Dependency detection and capabilities

Layer 0 (Core): May depend on foundation
├── validate.sh - Input validation (depends on log.sh)
├── string.sh   - String manipulation
├── array.sh    - Array operations
├── fs.sh       - Filesystem primitives
├── text.sh     - Text file processing
├── toml.sh     - TOML parsing (depends on string.sh, fs.sh, validate.sh)
└── xdg.sh      - XDG directories (depends on os.sh, validate.sh)
```

### 3. Configuration Over Convention

- All behavior controlled by `nut.toml` configuration
- No hardcoded values - defaults come from `templates/empty.nut.toml`
- Users can override anything

### 4. Self-Documenting Code

- Every public function marked with `@@PUBLIC_API@@`
- Every public function has `Usage:` documentation
- Annotations are semantic and serve multiple purposes:
  - `@@PUBLIC_API@@` - Part of public interface, must be documented
  - `@@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@` - Intentionally simple for API consistency

## Dependency System Design

### Current State

Basic tool detection with BSD/GNU variant awareness.

### Target Design: Capability-Based

Instead of "do we have sed?", ask "can we do stream editing?"

#### Capability Groups

| Capability | Primary | Fallback 1 | Fallback 2 | Notes |
|------------|---------|------------|------------|-------|
| `stream_edit` | sed | perl | awk | In-place editing, substitution |
| `pattern_match` | grep | perl | awk | Line matching, regex |
| `text_process` | awk | perl | sed | Field extraction, transformation |
| `file_stat` | stat | perl | ls -l | File size, mtime |
| `temp_files` | mktemp | manual | - | Secure temp file creation |
| `json_parse` | jq | python | perl | JSON manipulation (future) |

#### How It Works

1. At load time, detect available tools for each capability
2. Select best available tool (respecting user overrides)
3. Provide portable functions that use selected tool
4. Downstream code uses portable functions only

```bash
# Instead of:
sed -i 's/foo/bar/' file.txt  # Breaks on BSD

# Use:
deps_stream_edit_inplace 's/foo/bar/' file.txt  # Works everywhere
```

#### Portable Function Examples

```bash
# Stream editing with automatic tool selection
deps_stream_edit "s/old/new/g" input.txt > output.txt
deps_stream_edit_inplace "s/old/new/g" file.txt

# Pattern matching
deps_grep "pattern" file.txt
deps_grep_count "pattern" file.txt

# File information
deps_file_size file.txt      # Returns bytes
deps_file_mtime file.txt     # Returns epoch seconds

# Text processing
deps_extract_field ":" 2 file.txt  # Get field 2, colon-delimited
```

#### Configuration

```toml
# nut.toml
[deps]
# Override tool paths
sed = "/opt/gnu/bin/sed"
awk = "/opt/gnu/bin/gawk"

# Force specific tool for capability (skip detection)
stream_edit = "perl"  # Always use perl for stream editing

# Disable fallbacks (fail if primary not found)
fallbacks = false
```

## Annotation System

### Purpose

Annotations serve multiple purposes:
1. **QA enforcement** - Tests check for proper annotation usage
2. **Documentation generation** - Extract public API automatically
3. **Self-documentation** - Reading code, you know what's intentional

### Defined Annotations

| Annotation | Meaning |
|------------|---------|
| `@@PUBLIC_API@@` | Function is part of public interface. Must have documentation. |
| `@@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@` | Function is intentionally simple for API consistency. |
| `@@ALLOW_LOC_NNN@@` | File allowed to exceed normal size limit (NNN lines). |

### Rules

1. Every public function MUST have `@@PUBLIC_API@@`
2. Every `@@PUBLIC_API@@` function MUST have `Usage:` in its comment block
3. Trivial wrappers (1-2 line functions) MUST either:
   - Be used frequently enough to justify existence, OR
   - Have `@@PUBLIC_API@@` or `@@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@`

## QA System Design

### Philosophy

- **Configuration-first**: All tests driven by `nut.toml`
- **No hardcoded values**: Defaults from `templates/empty.nut.toml`
- **Strict by choice**: Users opt into strictness level

### Config Templates

| Template | Philosophy |
|----------|------------|
| `empty.nut.toml` | All disabled, fully documented (schema reference) |
| `default.nut.toml` | Sensible defaults, catches obvious issues |
| `tough.nut.toml` | No compromises, no technical debt |

### Test Categories

1. **Syntax** - Basic bash syntax validation
2. **Trivial Wrappers** - Detect unjustified thin wrappers
3. **File Size** - Enforce small, focused modules
4. **Function Duplication** - DRY enforcement
5. **Cruft** - Debug code, excessive TODOs
6. **Public API Docs** - All `@@PUBLIC_API@@` must be documented

## Relationship to the-whole-shebang

```
nutshell (this repo)
├── Core primitives
├── Foundation layer
└── QA system

the-whole-shebang
├── nutshell (as submodule)
├── infra/
│   ├── template.sh
│   ├── ui.sh
│   ├── cache.sh
│   └── state.sh
└── services/
    ├── git.sh
    └── docker.sh
```

nutshell is "everything you need, in a nutshell" - the minimal core.

the-whole-shebang is "when you need the whole shebang" - full toolkit.

## Guard Variables

All modules use inclusion guards to prevent double-sourcing:

```bash
[[ -n "${_NUTSHELL_CORE_MODULENAME_SH:-}" ]] && return 0
readonly _NUTSHELL_CORE_MODULENAME_SH=1
```

Naming convention: `_NUTSHELL_CORE_<MODULE>_SH`

## Error Handling

### ensure_ vs require_

- **`ensure_*`** - Soft check. Logs warning, returns 1. Caller handles.
- **`require_*`** - Hard check. Logs fatal, exits. No recovery.

```bash
# Soft: Let me check, you decide what to do
ensure_command "git" "Git not found" || {
    log_warn "Falling back to manual method"
    do_manual_thing
}

# Hard: I absolutely need this, fail if missing
require_command "git" "Git is required for this operation"
# If we get here, git exists
```

## Future Considerations

### Potential New Modules

- `http.sh` - curl/wget abstraction
- `json.sh` - jq/python/perl JSON parsing
- `yaml.sh` - YAML support (or just use TOML everywhere)
- `semver.sh` - Semantic version parsing and comparison

### Potential Features

- Shell completion generation from `@@PUBLIC_API@@` functions
- Man page generation from documentation
- Automated changelog from git history
