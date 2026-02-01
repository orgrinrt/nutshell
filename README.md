# nutshell

> Everything you need, in a nutshell.

A minimal, portable bash library for shell scripting.

**Version**: 0.1.0

---

## Installation

Add nutshell to your project:

```bash
# Option A: Git submodule (recommended)
git submodule add https://github.com/orgrinrt/nutshell.git scripts/lib/nutshell

# Option B: Download a release
curl -L https://github.com/orgrinrt/nutshell/releases/latest/download/nutshell.tar.gz | tar -xz -C scripts/lib/
```

That's it. No global install required. Nutshell lives in your project.

---

## Quick Start

Every script that uses nutshell needs **one line** at the top:

```bash
#!/usr/bin/env bash
. "${0%/*}/lib/nutshell/init"

use os log

log_info "Hello from nutshell!"
```

The `. "${0%/*}/lib/nutshell/init"` line is the **only boilerplate**. Copy it exactly.

> **What does `${0%/*}` mean?**  
> It's bash for "directory containing this script". It ensures the script works regardless of where it's called from.

---

## Project Structure

```
nutshell/
├── init                    # Source this: . "${0%/*}/lib/nutshell/init"
├── check                   # Main QA entry point (executable)
├── bin/
│   └── nutshell           # Interpreter for #!/usr/bin/env nutshell
├── lib/                   # All modules
│   ├── os.sh, log.sh, deps.sh, ...
│   ├── json.sh, http.sh, prompt.sh, ...
│   └── check-runner.sh    # QA/check framework
├── examples/
│   ├── configs/           # Configuration templates
│   │   ├── default.nut.toml
│   │   ├── empty.nut.toml
│   │   └── tough.nut.toml
│   └── checks/            # Built-in QA checks
│       ├── run_builtins.sh
│       └── check_*.sh
├── schemas/               # JSON schema for nut.toml
├── nutshell.sh            # Alternative: load ALL modules at once
├── README.md
└── nut.toml               # Nutshell's own config
```

A typical project setup:

```
myproject/
├── scripts/
│   ├── lib/
│   │   └── nutshell/          # ← Nutshell lives here
│   │       ├── init           # ← The file you source
│   │       ├── bin/
│   │       └── lib/
│   ├── build.sh               # Your scripts
│   ├── check.sh
│   └── deploy.sh
├── src/
├── deno.json                  # (or package.json, Makefile, etc.)
└── ...
```

---

## Usage Patterns

### Pattern 1: Standalone Scripts (Most Common)

Each script is independent. Each one has the init line:

```bash
#!/usr/bin/env bash
# scripts/build.sh
. "${0%/*}/lib/nutshell/init"

use os log fs

log_info "Building for $(os_name)..."
fs_mkdir dist
# ...
```

**When to use:** Most projects. Simple, each script works on its own.

### Pattern 2: Entry Point + Internal Scripts

One script bootstraps, others use the clean shebang:

```bash
#!/usr/bin/env bash
# scripts/main.sh - The entry point
. "${0%/*}/lib/nutshell/init"

# PATH is already set by init, so internal scripts can use nutshell shebang
"${0%/*}/internal/build.sh" "$@"
```

```bash
#!/usr/bin/env nutshell
# scripts/internal/build.sh - Clean shebang!
use os log

log_info "Building..."
```

**When to use:** Complex script suites where you want cleaner internal files.

---

## Integrating with Task Runners

Nutshell scripts work with any task runner. The scripts bootstrap themselves:

**deno.json:**
```json
{
  "tasks": {
    "build": "./scripts/build.sh",
    "check": "./scripts/lib/nutshell/check"
  }
}
```

**package.json:**
```json
{
  "scripts": {
    "build": "./scripts/build.sh",
    "check": "./scripts/lib/nutshell/check"
  }
}
```

**Makefile:**
```makefile
build:
	./scripts/build.sh

check:
	./scripts/lib/nutshell/check
```

Anyone can run `deno task build` or `npm run check` without knowing nutshell exists.

---

## Available Modules

Load modules with `use`:

```bash
use os log json http
```

| Module | Description |
|--------|-------------|
| `os` | OS detection (`os_name`, `os_is_macos`, `os_is_linux`) |
| `log` | Logging (`log_info`, `log_warn`, `log_error`, `log_success`) |
| `deps` | Tool detection (`deps_has`, `deps_require`, `deps_path`) |
| `fs` | Filesystem (`fs_exists`, `fs_mkdir`, `fs_temp_file`, `fs_size`) |
| `string` | String manipulation (`str_upper`, `str_lower`, `str_trim`, `str_contains`) |
| `array` | Array operations (`arr_contains`, `arr_unique`, `arr_join`) |
| `text` | Text processing (`text_grep`, `text_replace`, `text_count_matches`) |
| `json` | JSON parsing (`json_get`, `json_set`, `json_valid`, `json_pretty`) |
| `http` | HTTP requests (`http_get`, `http_post`, `http_download`) |
| `toml` | TOML parsing (`toml_get`, `toml_get_or`, `toml_is_true`) |
| `prompt` | User prompts (`prompt_confirm`, `prompt_input`, `prompt_select`) |
| `color` | Terminal colors (`color_red`, `color_green`, `color_bold`) |
| `validate` | Validation (`is_set`, `is_integer`, `require_command`) |
| `xdg` | XDG directories (`xdg_config`, `xdg_data`, `xdg_cache`) |
| `check-runner` | Testing framework (`cfg_get`, `log_pass`, `log_fail`) |

---

## For Module Authors

### The `module` Function

When creating new modules, use the `module` function to handle boilerplate:

```bash
#!/usr/bin/env bash
# lib/mymodule.sh

# This handles:
# - Guard variable to prevent double-sourcing
# - Creates MYMODULE_ERROR variable for error tracking
# - Creates MYMODULE_INIT variable (1 = ready, 0 = error)
# - Registers module in nutshell's loaded modules list
module mymodule || return 0

# Your module code here...

my_function() {
    echo "Hello from mymodule!"
}

# If something goes wrong during init:
# module_error mymodule "Failed to initialize: reason"
```

The `module` function replaces this manual boilerplate:

```bash
# OLD WAY (manual):
[[ -n "${_NUTSHELL_MODULE_MYMODULE_LOADED:-}" ]] && return 0
declare -g _NUTSHELL_MODULE_MYMODULE_LOADED=1
declare -g MYMODULE_ERROR=""
declare -g MYMODULE_INIT=1
```

### Module Helper Functions

```bash
# Check if a module is ready
module_ready mymodule && echo "Ready!"

# Get a module's error message
error=$(module_get_error mymodule)

# Set an error (marks module as not ready)
module_error mymodule "Something went wrong"
```

### The `impl` Function

For modules with multiple implementations (e.g., using sed vs perl):

```bash
#!/usr/bin/env bash
# lib/text/impl/sed_grep.sh

# Check if required tools are available
# Returns 0 if all deps available, 1 if not
impl sed,grep || return 1

# Implementation using sed and grep
text_replace() {
    # ...
}
```

With explicit impl name:

```bash
impl sed,grep sed_grep_combo || return 1
```

---

## Examples

### Example: Build Script

```bash
#!/usr/bin/env bash
# scripts/build.sh
. "${0%/*}/lib/nutshell/init"

use os log deps fs

# Check requirements
deps_require "cargo"

# Build based on OS
log_info "Building for $(os_name)..."

if os_is_macos; then
    cargo build --release --target aarch64-apple-darwin
else
    cargo build --release
fi

fs_mkdir dist
cp target/release/myapp dist/

log_success "Build complete!"
```

### Example: API Client

```bash
#!/usr/bin/env bash
# scripts/fetch-data.sh
. "${0%/*}/lib/nutshell/init"

use log http json

API_URL="https://api.example.com"

http_get_json "$API_URL/users"

if http_ok; then
    users=$(http_body)
    count=$(json_get "$users" "length")
    log_success "Fetched $count users"
else
    log_error "API request failed: $(http_status)"
    exit 1
fi
```

### Example: Interactive Installer

```bash
#!/usr/bin/env bash
# scripts/install.sh
. "${0%/*}/lib/nutshell/init"

use log prompt fs color

color_bold "=== My App Installer ==="
echo

if ! prompt_confirm "Install My App?" "y"; then
    log_info "Installation cancelled"
    exit 0
fi

install_dir=$(prompt_dir "Installation directory:" "$HOME/.local/share/myapp")
log_info "Installing to: $install_dir"

fs_mkdir "$install_dir"
cp -r ./dist/* "$install_dir/"

log_success "Installation complete!"
```

---

## The Init Line Explained

Every script needs this line:

```bash
. "${0%/*}/lib/nutshell/init"
```

Breaking it down:
- `.` — Source a file (same as `source`)
- `"${0%/*}"` — Directory containing this script
- `/lib/nutshell/init` — Path to nutshell's init file

This works regardless of:
- Where the script is called from (`./scripts/build.sh` or `scripts/build.sh`)
- The current working directory
- Whether called directly or via a task runner

**Just copy the line. Don't modify it.**

---

## QA / Check System

Nutshell includes a QA system for checking your shell scripts:

```bash
./lib/nutshell/check
```

Or with options:

```bash
./lib/nutshell/check --builtins      # Only built-in checks
./lib/nutshell/check --list          # List available checks
./lib/nutshell/check --help          # Show help
```

### Configuration

Configure via `nut.toml` in your project root:

```toml
[qa]
run_builtins = true

[tests.syntax]
shell = "bash"

[tests.file_size]
max_loc = 300
```

See `examples/configs/` for configuration templates:
- `empty.nut.toml` - Minimal defaults
- `default.nut.toml` - Recommended settings
- `tough.nut.toml` - Strict settings for quality-conscious projects

### Built-in Checks

| Check | Description |
|-------|-------------|
| `syntax` | Bash syntax validation |
| `file_size` | File size / LOC limits |
| `function_duplication` | Detect copy-pasted functions |
| `trivial_wrappers` | Find unnecessary wrapper functions |
| `no_cruft` | Detect debug code, TODOs |
| `public_api_docs` | Validate API documentation |
| `config_schema` | Validate nut.toml structure |

---

## Why This Design?

**Q: Why not a global install?**  
A: Nutshell is designed to be bundled with your project. When someone clones your repo and runs `npm run build`, it should just work—no "please install nutshell first".

**Q: Why not `#!/usr/bin/env nutshell` everywhere?**  
A: That requires `nutshell` to be in PATH, which means global installation or setup steps for every developer. The source line is self-contained.

**Q: Can I use the pretty shebang?**  
A: Yes! The `init` file adds nutshell's `bin/` to PATH, so any scripts called after sourcing init can use `#!/usr/bin/env nutshell`. This is great for internal scripts in complex projects.

**Q: What if I have many scripts?**  
A: Each standalone script needs the init line. It's one line of boilerplate per file. For large script suites, consider Pattern 2 (entry point + internal scripts).

---

## Module Reference

### Logging (`use log`)

```bash
log_debug "Debug info"      # Only shown if LOG_LEVEL=debug
log_info "Information"      # Blue
log_warn "Warning"          # Yellow
log_error "Error"           # Red
log_success "Success!"      # Green
log_fatal "Fatal error"     # Red, then exits
```

### OS Detection (`use os`)

```bash
os_name        # "linux", "macos", "windows", "unknown"
os_arch        # "x86_64", "arm64", etc.
os_is_linux    # Returns 0 (true) or 1 (false)
os_is_macos    # Returns 0 or 1
os_is_wsl      # Returns 0 or 1
os_is_windows  # Returns 0 or 1
```

### HTTP (`use http`)

```bash
http_get "https://example.com"
http_post "https://example.com" "data=value"
http_get_json "https://api.example.com/data"
http_post_json "https://api.example.com/data" '{"key":"value"}'

http_body      # Response body
http_status    # HTTP status code
http_ok        # True if 2xx status

http_download "https://example.com/file.zip" "./file.zip"
```

### JSON (`use json`)

```bash
json_get '{"name":"alice"}' "name"              # "alice"
json_get '{"user":{"id":1}}' "user.id"          # "1"
json_set '{"a":1}' "b" "2"                      # '{"a":1,"b":2}'
json_valid '{"a":1}'                            # Returns 0 (valid)
json_pretty '{"a":1}'                           # Formatted output
json_keys '{"a":1,"b":2}'                       # "a" and "b"
```

### Filesystem (`use fs`)

```bash
fs_exists "path"           # True if exists
fs_is_file "path"          # True if regular file
fs_is_dir "path"           # True if directory
fs_mkdir "path"            # Create directory (with parents)
fs_size "file"             # Size in bytes
fs_temp_file "prefix"      # Create temp file, print path
fs_temp_dir "prefix"       # Create temp dir, print path
```

### Prompts (`use prompt`)

```bash
prompt_confirm "Continue?" "y"                    # Yes/no, default yes
name=$(prompt_input "Name:" "default")            # Text input
pass=$(prompt_password "Password:")               # Hidden input
choice=$(prompt_select "Pick:" "A" "B" "C")       # Selection
count=$(prompt_int "Count:" 1 100)                # Integer with range
```

### Strings (`use string`)

```bash
str_upper "hello"                    # "HELLO"
str_lower "HELLO"                    # "hello"
str_trim "  hello  "                 # "hello"
str_contains "hello" "ell"           # Returns 0 (true)
str_replace "hello" "l" "L"          # "heLLo"
str_split ":" "a:b:c" arr            # arr=("a" "b" "c")
str_join "," "a" "b" "c"             # "a,b,c"
```

### Dependencies (`use deps`)

```bash
deps_has "git"                       # True if available
deps_require "git"                   # Exit if missing
deps_require_all "git" "curl"        # Exit if any missing
deps_path "git"                      # "/usr/bin/git"
deps_is_gnu "sed"                    # True if GNU variant
```

---

## License

MPL-2.0
