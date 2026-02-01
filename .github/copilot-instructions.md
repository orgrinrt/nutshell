# Copilot Instructions for nutshell

Core bash utility library providing primitives for shell scripting. Language: Bash (POSIX-compatible where possible).

## Project Context

nutshell is a minimal bash library that provides:
- Core utilities (os, log, deps, fs, text, json, http, etc.)
- Lazy-init stub pattern for efficient tool-dependent functions
- QA system with configurable checks
- Config-driven behavior via `nut.toml`

## CRITICAL: Read First

- **Read DESIGN.md**: Comprehensive architecture documentation
- **Read TODO.md**: Current tasks and priorities
- **Understand the lazy-init pattern**: Functions are stubs that self-replace on first call

## Project Structure

```
nutshell/
├── init                    # Entry point for sourcing
├── nutshell.sh            # Main library loader
├── check                  # QA check runner
├── bin/
│   └── nutshell          # Interpreter for shebang support
├── lib/
│   ├── os.sh             # OS detection (pure bash)
│   ├── log.sh            # Logging (pure bash)
│   ├── deps.sh           # Tool detection
│   ├── string.sh         # String manipulation
│   ├── array.sh          # Array operations
│   ├── fs.sh             # Filesystem primitives
│   ├── text.sh           # Text file processing
│   ├── toml.sh           # TOML parsing
│   ├── json.sh           # JSON operations
│   ├── http.sh           # HTTP operations
│   ├── validate.sh       # Input validation
│   ├── color.sh          # Terminal colors
│   ├── prompt.sh         # User prompts
│   ├── xdg.sh            # XDG directories
│   ├── text/             # Text impl files
│   │   └── impl/
│   └── fs/               # FS impl files
│       └── impl/
├── examples/
│   ├── checks/           # Example custom checks
│   └── configs/          # Config templates
├── schemas/              # JSON schemas for config
├── DESIGN.md             # Architecture documentation
├── TODO.md               # Task list
└── nut.toml              # Project's own QA config
```

## Core Principles

### 1. The Lazy-Init Stub Pattern

**This is the core architecture pattern - understand it before making changes**

Functions start as stubs that:
1. On first call, determine the best implementation
2. Source the impl file
3. Redefine themselves to the implementation
4. Call the implementation

```bash
# Stub (in text.sh)
text_replace() {
  local impl
  impl=$(_text_select_replace_impl)
  source "${NUTSHELL_ROOT}/lib/text/impl/${impl}.sh"
  text_replace "$@"  # Now calls the real impl
}
```

### 2. No Magic, No Lies

- Document external tool dependencies
- Detect tools at runtime
- Provide fallbacks where possible
- Never fail silently

### 3. Detection Without Assumptions

- `deps.sh` detects available tools
- Each module decides which tool to use
- No centralized "best tool" logic

### 4. Configuration Over Convention

- All behavior controlled by `nut.toml`
- No hardcoded values
- Sensible defaults in templates

## Coding Standards

### Bash

- Use `#!/usr/bin/env bash` shebang
- Set strict mode: `set -euo pipefail`
- Quote all variables: `"$var"` not `$var`
- Use `[[ ]]` for tests, not `[ ]`
- Use `local` for function variables
- Prefer `$(command)` over backticks

### Naming

- Functions: `module_name_action` (e.g., `text_replace`, `fs_exists`)
- Local variables: `snake_case`
- Global variables: `SCREAMING_SNAKE_CASE`
- Guard variables: `__NUTSHELL_MODULE_LOADED__`
- Private functions: prefix with `_`

### Documentation

- Every public function needs `@@PUBLIC_API@@` annotation
- Include `Usage:` comment with signature and description
- Document side effects and exit codes

```bash
# @@PUBLIC_API@@
# Usage: text_replace <pattern> <replacement> <file>
#   Replace all occurrences of pattern with replacement in file.
#   Uses sed, perl, or awk depending on availability.
#   Returns 0 on success, 1 on failure.
text_replace() {
  # ...
}
```

### Error Handling

- Use `ensure_` for soft checks (warn and continue)
- Use `require_` for hard checks (error and exit)
- Always provide meaningful error messages

```bash
require_tool() {
  local tool="$1"
  if ! command -v "$tool" &>/dev/null; then
    log_error "Required tool not found: $tool"
    exit 1
  fi
}

ensure_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    log_warn "File not found: $file"
    return 1
  fi
}
```

## Workflow

### Before Starting

1. Read DESIGN.md thoroughly
2. Read TODO.md for current tasks
3. Check existing module patterns
4. Understand the lazy-init stub pattern

### Adding a New Function

1. Add stub to the module file (e.g., `lib/text.sh`)
2. Add selector function `_module_select_action_impl`
3. Create impl file in `lib/module/impl/`
4. Add `@@PUBLIC_API@@` annotation
5. Add tests if QA system supports it

### Adding a New Module

1. Create `lib/module.sh` with guard and annotations
2. Add module to the layer structure in DESIGN.md
3. Register in `nutshell.sh` for `use module`
4. Add QA check if applicable

### Before Marking Done

1. Test with `./check` from project root
2. Verify on both Linux and macOS if possible
3. Update DESIGN.md if architecture changed
4. Update TODO.md to mark completion

## Commits

Format: `type: lowercase message`

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

### Good Examples

- `feat: add json_parse function`
- `fix: handle spaces in filenames in fs_list`
- `docs: update DESIGN.md with new module structure`
- `test: add qa checks for string module`

### Bad Examples

- `Added feature` (no type)
- `WIP` (not descriptive)
- `Fix stuff` (not specific, not lowercase)

## Don't

- Use `eval` unless absolutely necessary (security risk)
- Assume tool availability without checking deps.sh
- Add external dependencies without documenting
- Break POSIX compatibility without good reason
- Use bashisms where POSIX works
- Leave TODO comments without task reference
- Modify stub pattern without updating DESIGN.md
- Ignore shellcheck warnings

## Testing

### Running QA Checks

```bash
./check                    # Run all enabled checks
./check -c specific_check  # Run specific check
./check -v                 # Verbose output
```

### Manual Testing

```bash
# Source the library
source ./init

# Use specific modules
use text fs json

# Test functions
text_replace "foo" "bar" test.txt
```

## QA Check Development

Custom checks go in `examples/checks/` or a project's `checks/` directory.

```bash
#!/usr/bin/env bash
# check_my_convention.sh

check_name="my-convention"
check_description="Checks for my convention"

run_check() {
  local file="$1"
  # Return 0 for pass, 1 for fail
  # Use log_check_fail for failures
}
```

## Code Constraints

| Rule | Limit | Reason |
|------|-------|--------|
| Function length | <50 lines | Readability |
| File size | <500 lines | Maintainability |
| Nesting depth | <4 levels | Complexity |
| External deps | Document all | Portability |

## Shell Compatibility

Target shells (in order of priority):
1. bash 4.0+ (primary)
2. bash 3.2 (macOS default)
3. POSIX sh (where feasible)

When using bash-specific features:
- Document the requirement
- Provide POSIX fallback if critical
- Test on bash 3.2 (macOS)

## Review Checklist

Before marking work complete:

- [ ] Functions have `@@PUBLIC_API@@` annotation
- [ ] Functions have `Usage:` documentation
- [ ] Variables are quoted properly
- [ ] Local variables use `local`
- [ ] Error handling is present
- [ ] No shellcheck warnings (or justified ignores)
- [ ] Works on both Linux and macOS
- [ ] DESIGN.md updated if needed
- [ ] TODO.md updated if needed
