# nutshell

> Everything you need, in a nutshell.

A minimal bash utility library providing core primitives for shell scripting.

## Philosophy

- **Minimal dependencies** - Uses standard Unix tools (see below)
- **Layered architecture** - Clear dependency hierarchy
- **Self-documenting** - Every public function is annotated and documented
- **Quality-first** - Ships with its own QA test suite
- **Honest about requirements** - No hidden dependencies

## Dependencies

Nutshell requires standard Unix tools that are typically pre-installed on Linux and macOS systems. However, these tools have different implementations (BSD vs GNU) with subtle differences that nutshell abstracts away.

### Required Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `bash` | Shell (4.0+) | Required for associative arrays, `${var,,}`, etc. |
| `sed` | Stream editing | BSD/GNU differences handled |
| `awk` | Text processing | gawk/mawk/nawk/BSD awk supported |
| `grep` | Pattern matching | BSD/GNU differences handled |
| `stat` | File information | BSD/GNU have different flags |
| `find` | File discovery | BSD/GNU differences in some flags |
| `mktemp` | Temporary files | |
| `sort` | Sorting | |
| `wc` | Word/line count | |
| `tr` | Character translation | |
| `head` / `tail` | First/last lines | |
| `dirname` / `basename` | Path manipulation | |
| `uname` | System information | |

### Custom Tool Paths

If your tools are in non-standard locations, set environment variables:

```bash
export NUTSHELL_SED="/opt/gnu/bin/sed"
export NUTSHELL_AWK="/opt/gnu/bin/gawk"
export NUTSHELL_GREP="/opt/gnu/bin/grep"
export NUTSHELL_STAT="/opt/gnu/bin/stat"
export NUTSHELL_FIND="/opt/gnu/bin/find"
export NUTSHELL_MKTEMP="/opt/gnu/bin/mktemp"
```

### Checking Dependencies

```bash
source nutshell/core/deps.sh
deps_check_all    # Check all required tools
deps_info         # Print tool paths and variants
deps_require_all  # Exit if any missing
```

## Installation

### As a git submodule (recommended)

```bash
git submodule add https://github.com/orgrinrt/nutshell.git lib/nutshell
```

### Direct clone

```bash
git clone https://github.com/orgrinrt/nutshell.git
```

## Usage

### Source everything

```bash
#!/usr/bin/env bash
source "path/to/nutshell/nutshell.sh"

log_info "Hello from nutshell!"
str_upper "hello"  # -> "HELLO"
```

### Source specific modules

```bash
#!/usr/bin/env bash
NUTSHELL="path/to/nutshell"

source "$NUTSHELL/core/log.sh"
source "$NUTSHELL/core/string.sh"

log_info "Only what I need"
```

## Modules

### Layer -1 (Foundation)

These modules have zero dependencies and are the bedrock:

| Module | Description |
|--------|-------------|
| `core/os.sh` | OS detection (linux/macos/windows/wsl) |
| `core/log.sh` | Logging with levels and colors |
| `core/deps.sh` | Dependency checking and variant detection |

### Layer 0 (Core)

Core utilities that may depend on foundation:

| Module | Description |
|--------|-------------|
| `core/validate.sh` | Input validation, type checks, require/ensure functions |
| `core/string.sh` | String manipulation (trim, split, join, replace, etc.) |
| `core/array.sh` | Array operations (contains, unique, sort, filter, etc.) |
| `core/fs.sh` | Filesystem primitives (exists, mkdir, temp files, paths) |
| `core/text.sh` | Text file processing (grep, lines, replace) |
| `core/toml.sh` | TOML parsing (get, arrays, sections, booleans) |
| `core/xdg.sh` | XDG Base Directory support |

## Quick Reference

### Logging (`core/log.sh`)

```bash
log_debug "Debug message"      # Gray, only if LOG_LEVEL=debug
log_info "Info message"        # Blue
log_warn "Warning message"     # Yellow, to stderr
log_error "Error message"      # Red, to stderr
log_success "Success!"         # Green
log_step "Major step"          # Cyan with ==>
log_substep "Sub-step"         # Magenta with →
log_fatal "Fatal error"        # Red, exits with code 1
```

### Validation (`core/validate.sh`)

```bash
# Checks (return 0/1)
is_set "VAR_NAME"              # Variable is set and non-empty
has_command "git"              # Command exists
is_integer "42"                # Is an integer
is_truthy "yes"                # Is truthy (1/true/yes/on/y)
is_url "https://..."           # Valid URL
is_ipv4 "192.168.1.1"          # Valid IPv4

# Soft checks (warn and return 1)
ensure_set "VAR" "message"     # Warn if not set
ensure_command "git" "msg"     # Warn if missing
ensure_file "path" "msg"       # Warn if not found

# Hard checks (exit on failure)
require_set "VAR" "message"    # Exit if not set
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
str_starts_with "hello" "he"   # -> 0 (true)
str_split ":" "a:b:c" arr      # arr=("a" "b" "c")
str_join "," "a" "b" "c"       # -> "a,b,c"
str_length "hello"             # -> 5
```

### Arrays (`core/array.sh`)

```bash
arr_contains "needle" "${arr[@]}"   # Check if contains
arr_index "needle" "${arr[@]}"      # Find index (255 if not found)
arr_unique arr                       # Remove duplicates in place
arr_reverse arr                      # Reverse in place
arr_sort arr                         # Sort in place
arr_length "${arr[@]}"              # Get length
arr_first "${arr[@]}"               # Get first element
arr_last "${arr[@]}"                # Get last element
arr_filter "*.txt" "${arr[@]}"      # Filter by pattern
```

### Filesystem (`core/fs.sh`)

```bash
fs_exists "path"               # Path exists (file or dir)
fs_is_file "path"              # Is a regular file
fs_is_dir "path"               # Is a directory
fs_mkdir "path"                # Create directory (with parents)
fs_rm "path"                   # Remove (safe - no error if missing)
fs_realpath "relative"         # Get absolute path
fs_extension "file.txt"        # -> "txt"
fs_basename_no_ext "file.txt"  # -> "file"
fs_size "file"                 # Size in bytes
fs_temp_file "prefix"          # Create temp file
fs_temp_dir "prefix"           # Create temp directory
```

### XDG Directories (`core/xdg.sh`)

```bash
# Set your app name first
xdg_set_app_name "my-app"

# Then get standard directories
xdg_app_data                   # ~/.local/share/my-app
xdg_app_config                 # ~/.config/my-app
xdg_app_cache                  # ~/.cache/my-app
xdg_app_state                  # ~/.local/state/my-app
```

### TOML Parsing (`core/toml.sh`)

```bash
toml_get "file.toml" "key"           # Get root-level value
toml_get "file.toml" "section.key"   # Get value from [section]
toml_get_or "file.toml" "key" "def"  # Get with default
toml_has "file.toml" "key"           # Check if key exists
toml_is_true "file.toml" "key"       # Check if value is truthy
toml_sections "file.toml"            # List all section names
toml_keys "file.toml" "section"      # List keys in section
toml_array "file.toml" "key" arr     # Parse array into bash array
```

### Dependencies (`core/deps.sh`)

```bash
deps_has "sed"                       # Check if tool available
deps_path "awk"                      # Get path to tool
deps_variant "sed"                   # Get variant (gnu/bsd)
deps_is_gnu "grep"                   # Check if GNU variant
deps_is_bsd "stat"                   # Check if BSD variant
deps_check_all                       # Check all required tools
deps_require "git"                   # Exit if tool missing
deps_info                            # Print debug information

# Portable wrappers for BSD/GNU differences
deps_sed_inplace "s/a/b/" file.txt   # In-place sed edit
deps_stat_size "file"                # File size in bytes
deps_stat_mtime "file"               # Modification time (epoch)
```

## QA Test Suite

Nutshell ships with a configurable QA test suite. Copy a template config:

```bash
cp nutshell/templates/tough.nut.toml ./nut.toml
```

Run tests:

```bash
./nutshell/tests/run_all.sh
```

### Config Templates

| Template | Description |
|----------|-------------|
| `empty.nut.toml` | All tests disabled, fully documented (schema reference) |
| `default.nut.toml` | Sensible defaults for general use |
| `tough.nut.toml` | Strict conventions, no compromises |

## Related

- **[the-whole-shebang](https://github.com/orgrinrt/the-whole-shebang)** - Full bash library that builds on nutshell with infrastructure, services, and more.

## License

MIT
