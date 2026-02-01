# nutshell

> Everything you need, in a nutshell.

A minimal bash utility library providing core primitives for shell scripting.

## Philosophy

- **Minimal dependencies**: Uses standard Unix tools (see below)
- **Lazy initialization**: Functions load implementations on first call only
- **Cross-platform**: Handles BSD/GNU tool differences transparently
- **Self-documenting**: Every public function is annotated and documented
- **Quality-first**: Ships with its own QA test suite

## Installation

### As a git submodule (recommended)

```bash
git submodule add https://github.com/orgrinrt/nutshell.git lib/nutshell
```

### Direct clone

```bash
git clone https://github.com/orgrinrt/nutshell.git
```

## Quick Start

```bash
#!/usr/bin/env bash
source "path/to/nutshell/nutshell.sh"

log_info "Hello from nutshell!"
str_upper "hello"  # -> "HELLO"

# Check module readiness
if text_ready; then
    text_replace "foo" "bar" file.txt
fi
```

## Dependencies

Nutshell uses standard Unix tools with automatic BSD/GNU detection:

| Tool | Purpose | Variants Detected |
|------|---------|-------------------|
| `bash` | Shell (4.0+) | Required for associative arrays |
| `sed` | Stream editing | gnu, bsd |
| `awk` | Text processing | gawk, mawk, nawk, bsd |
| `grep` | Pattern matching | gnu, bsd |
| `perl` | Fallback processing | standard |
| `stat` | File information | gnu, bsd |
| `find` | File discovery | gnu, bsd |

### Custom Tool Paths

Override tool paths in `nut.toml`:

```toml
[deps.paths]
sed = "/opt/gnu/bin/sed"
awk = "/opt/gnu/bin/gawk"
```

### Checking Dependencies

```bash
source nutshell/core/deps.sh

deps_info              # Print tool paths, variants, and capabilities
deps_check             # Check all required tools, returns 0/1
deps_require_all "sed" "awk" "grep"  # Exit if any missing

# Query specific tools
deps_has "perl"        # -> 0 (true) or 1 (false)
deps_path "sed"        # -> "/usr/bin/sed"
deps_variant "sed"     # -> "gnu" or "bsd"
deps_is_gnu "grep"     # -> 0 (true) or 1 (false)

# Query capabilities
deps_can "grep_pcre"   # -> 0 if grep supports -P
deps_can "sed_extended" # -> 0 if sed supports -E
```

## Modules

### Layer -1 (Foundation)

Zero internal dependencies:

| Module | Description |
|--------|-------------|
| `core/os.sh` | OS detection (linux/macos/windows/wsl) |
| `core/log.sh` | Logging with levels and colors |
| `core/deps.sh` | Tool detection, variants, and capabilities |

### Layer 0 (Core)

May depend on foundation:

| Module | Description |
|--------|-------------|
| `core/validate.sh` | Input validation, type checks |
| `core/string.sh` | String manipulation (pure bash) |
| `core/array.sh` | Array operations (pure bash) |
| `core/fs.sh` | Filesystem primitives |
| `core/text.sh` | Text file processing |
| `core/toml.sh` | TOML parsing |
| `core/xdg.sh` | XDG Base Directory support |

## API Reference

### Logging (`core/log.sh`)

```bash
log_debug "Debug message"      # Gray, only if LOG_LEVEL=debug
log_info "Info message"        # Blue
log_warn "Warning message"     # Yellow, to stderr
log_error "Error message"      # Red, to stderr
log_success "Success!"         # Green
log_fatal "Fatal error"        # Red, exits with code 1
```

### Validation (`core/validate.sh`)

```bash
# Type checks (return 0/1)
is_set "VAR_NAME"              # Variable is set and non-empty
is_integer "42"                # Is an integer
is_truthy "yes"                # Is truthy (1/true/yes/on/y)

# Soft checks (warn and return 1)
ensure_command "git" "message" # Warn if missing

# Hard checks (exit on failure)
require_command "git" "msg"    # Exit if missing
require_file "path" "msg"      # Exit if not found
```

### Strings (`core/string.sh`)

```bash
str_lower "HELLO"              # -> "hello"
str_upper "hello"              # -> "HELLO"
str_trim "  hello  "           # -> "hello"
str_replace "hi world" "hi" "hello"  # -> "hello world"
str_contains "hello" "ell"     # -> 0 (true)
str_split ":" "a:b:c" arr      # arr=("a" "b" "c")
str_join "," "a" "b" "c"       # -> "a,b,c"
```

### Arrays (`core/array.sh`)

```bash
arr_contains "needle" "${arr[@]}"   # Check if contains
arr_unique arr                       # Remove duplicates in place
arr_sort arr                         # Sort in place
arr_length "${arr[@]}"              # Get length
```

### Filesystem (`core/fs.sh`)

```bash
fs_exists "path"               # Path exists (file or dir)
fs_is_file "path"              # Is a regular file
fs_mkdir "path"                # Create directory (with parents)
fs_realpath "relative"         # Get absolute path
fs_extension "file.txt"        # -> "txt"
fs_size "file"                 # Size in bytes
fs_mtime "file"                # Modification time (epoch)
fs_temp_file "prefix"          # Create temp file

# Module status
fs_ready                       # -> 0 if module is ready
fs_error                       # -> error message if not ready
```

### Text Processing (`core/text.sh`)

```bash
text_grep "pattern" "file"     # Find matching lines
text_contains "pattern" "file" # Check if pattern exists
text_replace "old" "new" "file" # In-place replacement
text_line "file" 5             # Get line 5
text_lines "file" 5 10         # Get lines 5-10

# Module status
text_ready                     # -> 0 if module is ready
text_error                     # -> error message if not ready
```

### Dependencies (`core/deps.sh`)

```bash
# Availability
deps_has "sed"                 # Tool is available
deps_has_all "sed" "awk"       # All tools available
deps_has_any "perl" "python"   # At least one available
deps_available                 # List all available tools

# Paths and variants
deps_path "awk"                # -> "/usr/bin/awk"
deps_variant "sed"             # -> "gnu" or "bsd"
deps_is_gnu "grep"             # Check if GNU variant
deps_is_bsd "stat"             # Check if BSD variant

# Capabilities
deps_can "grep_pcre"           # grep supports -P
deps_can "sed_extended"        # sed supports -E
deps_can "awk_gensub"          # awk has gensub()
deps_caps                      # List all capabilities

# Requirements
deps_require "git"             # Exit if missing
deps_require_all "sed" "awk"   # Exit if any missing
deps_require_cap "grep_pcre"   # Exit if capability missing

# Portable wrappers
deps_sed_inplace "s/a/b/" file # BSD/GNU compatible
deps_stat_size "file"          # File size in bytes
deps_stat_mtime "file"         # Modification time
```

### TOML Parsing (`core/toml.sh`)

```bash
toml_get "file.toml" "key"           # Get value
toml_get "file.toml" "section.key"   # Get from [section]
toml_get_or "file.toml" "key" "def"  # Get with default
toml_is_true "file.toml" "key"       # Check if truthy
toml_array "file.toml" "key" arr     # Parse into array
```

### XDG Directories (`core/xdg.sh`)

```bash
xdg_set_app_name "my-app"
xdg_app_data                   # ~/.local/share/my-app
xdg_app_config                 # ~/.config/my-app
xdg_app_cache                  # ~/.cache/my-app
```

## QA Test Suite

Nutshell ships with a configurable QA test suite:

```bash
# Run all tests
./nutshell/tests/run_all.sh

# With options
./nutshell/tests/run_all.sh --level=error  # Only show errors
./nutshell/tests/run_all.sh --level=info   # Show all diagnostics
```

### Config Templates

Copy a template to your repo root as `nut.toml`:

| Template | Description |
|----------|-------------|
| `empty.nut.toml` | All tests disabled (schema reference) |
| `default.nut.toml` | Sensible defaults |
| `tough.nut.toml` | Strict, no compromises |

### Example Output

```
nutshell QA

  Syntax                         ✓
  File Size                      ⚠
  Duplication                    ✓
  Trivial Wrappers               ✓
  Cruft                          ✓

Diagnostics:

  core/
    large_file.sh
      ⚠ 421 LOC
        └─ consider splitting or add @@ALLOW_LOC_421@@

PASSED (5/5 tests, 1 with warnings)
```

## Architecture

Nutshell uses a lazy-init stub pattern for tool-dependent functions:

1. Public functions start as stubs
2. On first call, the stub selects the best implementation
3. The impl file is sourced, replacing the stub
4. Subsequent calls go directly to the implementation

This gives fast startup (no eager loading) and zero overhead after first call.

See [DESIGN.md](DESIGN.md) for details.

## Related

- **[the-whole-shebang](https://github.com/orgrinrt/the-whole-shebang)**: Full bash library building on nutshell with infrastructure, services, and more.

## License

MIT
