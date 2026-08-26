# nutshell

> Everything you need, in a nutshell.

A minimal bash library for shell scripting. Requires bash 4.0 or newer;
macOS ships 3.2 at `/bin/bash`, so install a current bash there first.

---

## Installation

Add nutshell to your project:

```bash
# Option A: Git submodule (recommended)
git submodule add https://github.com/orgrinrt/nutshell.git scripts/lib/nutshell

# Option B: Download a source archive (releases ship no built artifacts).
# 0.3.0 is the latest tag; check the releases page for newer ones.
mkdir -p scripts/lib/nutshell
curl -L https://github.com/orgrinrt/nutshell/archive/refs/tags/0.3.0.tar.gz \
    | tar -xz --strip-components=1 -C scripts/lib/nutshell
```

That's it. No global install required. Nutshell lives in your project.

Optionally, link the interpreter onto PATH so standalone scripts can use the
`#!/usr/bin/env nutshell` shebang:

```bash
./scripts/lib/nutshell/install
```

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
├── tests/                 # The suite, run by ./test
├── schemas/               # JSON schema for nut.toml
├── docs/                  # Design notes
├── install                # Link bin/nutshell onto PATH
├── release                # Cut a release: gate, tag, publish
├── test                   # Test entry point (executable)
├── nutshell.sh            # Alternative: load ALL modules at once
├── README.md
└── nut.toml               # Nutshell's own config
```

A `nut.lock` appears next to `nut.toml` once a declared dependency first
resolves; it records the commit each dependency pinned to.

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
# scripts/internal/build.sh - clean shebang, no init line
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
| `array` | Array operations (`arr_contains`, `arr_unique`, `arr_length`) |
| `text` | Text processing (`text_grep`, `text_replace`, `text_count_matches`) |
| `json` | JSON parsing (`json_get`, `json_set`, `json_valid`, `json_pretty`) |
| `http` | HTTP requests (`http_get`, `http_post`, `http_download`) |
| `toml` | TOML reading (`toml_get`, `toml_get_or`, `toml_is_true`, `toml_array`) |
| `toml::write` | Changing a TOML file in place (`toml_set`, `toml_unset`) |
| `toml::json` | TOML as JSON (`toml_to_json`) |
| `prompt` | User prompts (`prompt_confirm`, `prompt_input`, `prompt_select`) |
| `color` | Terminal colors (`color_red`, `color_green`, `color_bold`) |
| `validate` | Validation (`is_set`, `is_integer`, `require_command`) |
| `xdg` | XDG directories (`xdg_config_home`, `xdg_data_home`, `xdg_app_cache`) |
| `check-runner` | QA framework (`cfg_get`, `log_pass`, `log_fail`) |
| `test` | Test harness (`assert_eq`, `test_run`, `test_summary`) |
| `attr` | Attributes on definitions (`attr_has`, `attr_arg`, `attr_find`) |
| `cli` | Subcommand dispatch with did-you-mean (`cli_command`, `cli_run`) |
| `git` | Reading a repository (`git_trunk`, `git_changed_files`, `git_trailers`) |
| `modgraph` | The module graph and its violations (`modgraph_build`, `modgraph_audit`) |
| `extern` | Libraries from elsewhere (`extern_path`, `extern_resolve`) |

---

## For Module Authors

A module is a file in `lib/`. It guards against being sourced twice, declares
what it needs, and marks what it offers.

```bash
#!/usr/bin/env bash
# lib/mymodule.sh

nut_once || return 0

use log fs

#[pub]
# Usage: my_function -> greets
my_function() {
    log_info "Hello from mymodule!"
}
```

### The include guard

`nut_once` returns 0 the first time a given file calls it and non-zero after,
so the idiom reads as "carry on, or stop". It derives its key from the calling
file, which is why there is no name to invent and no name to type twice.

### Declaring dependencies

`use` at the top of a module says what it cannot work without. It is the same
`use` a script writes, because it is the same act.

This is worth more than convenience. Bash has one global function table: once a
module is sourced, everything it defined is callable from anywhere, whether the
caller declared it or not. So a module that reaches into another without saying
so works, right up until load order changes. `toml.sh` called `str_trim` for
its whole life while declaring nothing, and `toml_get` returned either an
answer or silence depending on whether something else had loaded `string`
first. Nothing reported it, because from inside bash a function that is present
is present.

The `module_contract` check reads these declarations and reports the calls no
declaration covers. It cannot make the boundary real, and it says so; what it
can do is make crossing one visible.

### Attributes

An attribute is a comment, which is the whole reason for the shape. `#` is
already bash's comment character, so `#[pub]` needs no cooperation from the
parser: `bash -n`, shellcheck and editors keep working, and a file using
attributes is still an ordinary shell file.

```bash
#[pub]                       # part of the module's surface
#[allow(loc = 400)]          # with an argument
#[test]                      # a test, found by the harness
```

They attach downward to the next definition and accumulate, and a doc comment
between an attribute and its definition does not break the run.

### Tests

A test is a function marked `#[test]`. Nothing registers it and there is no
naming convention to remember, so a test that exists cannot be missing from the
run and a renamed one cannot leave a stale entry behind.

```bash
#!/usr/bin/env bash
# tests/string_test.sh

use string test

#[test]
it_trims_both_ends() {
    assert_eq "$(str_trim "  x  ")" "x"
}
```

Run them with `./test`. Each runs in its own subshell, failures do not stop the
run, and every assertion counts rather than only the last one the function
happened to evaluate.

The assertions are `assert_eq`, `assert_ne`, `assert_contains`, `assert_empty`,
`assert_ok`, `assert_fails` and `assert_exits`. Each prints what it expected
against what it got, because a bare "assertion failed" sends the reader back to
the source to work out what the values even were.

### Reaching your own modules

A module you wrote lives in your `lib/`, and `super::` is how you name it:

```bash
use super::attribution
```

Three namespaces, and they answer three different questions:

| Written | Resolves to |
|---|---|
| `use log` | nutshell's own module |
| `use shebang::tui::term` | a module in a library declared in `nut.toml` |
| `use super::mine` | `lib/mine.sh` in **this** unit, found from its `nut.toml` |

`super::` is anchored on the manifest rather than on the running script, so a
module three directories down reaches `lib/` the same way the entry script does,
and moving the entry script changes nothing.

It does not fall through. `use super::string` in a project with no
`lib/string.sh` is an error naming the module, not a silent load of nutshell's
`string`, because a unit that gets handed a module it did not write has no way
to tell.

### Where am I: the current file against the entry point

Two different questions, and reaching for the wrong one is the mistake this
section exists to prevent.

```bash
nut_dir      # the directory of the file calling it
nut_file     # that file, absolute
```

Those name the **current file**, the way Deno's `import.meta.dirname` and Rust's
`file!()` do. A module that wants a sibling wants `nut_dir`.

`NUTSHELL_SCRIPT` and `NUTSHELL_SCRIPT_DIR` name the **entry point**: the script
the interpreter was handed. They stay the same in every file the run loads, so a
module that builds a path from them is describing somebody else's location and
breaks the moment the entry point moves. That is not hypothetical; it took a
whole test suite down when a runner moved from `tests/` to the repository root.

The whole exported environment, which is five things:

| Variable | What it is | Set by |
|---|---|---|
| `NUTSHELL_SCRIPT` | The entry script, absolute | `bin/nutshell` |
| `NUTSHELL_SCRIPT_DIR` | Its directory | `bin/nutshell` |
| `NUTSHELL_PIN_ROOT` | The pinned checkout, when a project pins one | `bin/nutshell` |
| `NUTSHELL_ROOT` | The nutshell checkout in use | `init` |
| `NUTSHELL_VERSION` | The version string | `init` |

`NUTSHELL_PIN_TTL` is read rather than exported: set it to change how long a
pinned branch head is reused before re-resolving.

Names beginning with a single underscore are internal and are not listed,
because they are not the interface. An earlier version of this table had six
entries that do not exist, produced by a grep for `NUTSHELL_[A-Z_]+` which
matched those private names inside their own underscore prefix, and it swapped
the meanings of two of them on the way. In the section whose whole purpose was
that a reader kept getting these wrong.

### Depending on another library

A dependency is declared in `nut.toml`, not in the script that wants it:

```toml
[deps.shebang]
git = "https://github.com/orgrinrt/the-whole-shebang.git"
ref = "main"
```

and a module inside it is reached by namespacing the `use`:

```bash
use shebang::tui::term
```

Declared in the manifest because a script that fetches its own dependencies
decides for the whole project where code comes from, and does it somewhere
nobody looks. One file answers "what does this project pull in".

Resolution is cached globally by url and ref, so several projects naming the
same ref share one checkout and the second pays nothing.

`nut.lock` records the commit each dependency resolved to, and is written on
first resolution and obeyed from then on. `ref = "main"` names a branch, and a
branch moves; without the lock two checkouts of one project can be running
different code and neither can say so. Commit it. Taking a newer commit means
deleting the entry, which is a thing somebody does rather than a thing that
happens.

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
    count=$(json_length "$users")
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
- `.` sources a file (same as `source`)
- `"${0%/*}"` is the directory containing this script
- `/lib/nutshell/init` is the path to nutshell's init file

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
- `empty.nut.toml` - Every option documented, all checks disabled
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
| `module_contract` | Cycles, undeclared calls, private calls, unreachable modules |

---

## Why This Design?

**Q: Why not a global install?**  
A: Nutshell is designed to be bundled with your project. When someone clones your repo and runs `npm run build`, it should just work, with no "please install nutshell first".

**Q: Why not `#!/usr/bin/env nutshell` everywhere?**  
A: That requires `nutshell` to be on PATH. `./install` links it there in one step, but the source line works on a fresh clone with no setup at all, so it stays the default.

**Q: Can I use the pretty shebang?**  
A: Yes. The `init` file adds nutshell's `bin/` to PATH, so any scripts called after sourcing init can use `#!/usr/bin/env nutshell`, and `./install` makes it resolve everywhere else. This suits internal scripts in larger script suites.

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
json_length '[1,2,3]'                           # "3"
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
str_distance "build" "buidl"         # 2
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

## A note on coding agents

We do not recommend using coding agents with this codebase.

If you still choose to use a coding agent:

- Be aware of the environmental and social impact of large-scale model inference.
  Minimise agent use where it is not needed. Be responsible.
- Only use an agent if you yourself understand the architecture. Do not use an
  agent because you do not understand; you will waste time and energy, both
  yours and the planet's.
- This repository provides agent instructions for GitHub Copilot
  (`.github/copilot-instructions.md`) that help, but they do not eliminate the
  problem. You will still need to correct the agent frequently.

The recommendation stands: do this work yourself unless you know what you are doing
and why.

---

## License

MPL-2.0
