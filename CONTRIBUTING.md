# Contributing to nutshell

Thank you for considering contributing to nutshell! This document provides guidelines and instructions for contributing.

## Before You Start

1. **Read the Documentation**
   - [README.md](README.md) - Usage and quick start
   - [docs/DESIGN.md](docs/DESIGN.md) - Architecture and design principles
   - [docs/TODO.md](docs/TODO.md) - Current tasks and priorities
   - [.github/copilot-instructions.md](.github/copilot-instructions.md) - Development guidelines

2. **Understand the Core Principles**
   - No magic, no lies - document dependencies, detect tools, provide fallbacks
   - Lazy initialization pattern - understand before modifying
   - Configuration over convention - everything controlled by `nut.toml`
   - POSIX compatibility where feasible

## Development Setup

### Prerequisites

- Bash 4.0+ (bash 3.2 on macOS is also supported)
- Git
- Standard Unix tools (sed, awk, grep, etc.)
- shellcheck (recommended for linting)

### Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/nutshell.git
   cd nutshell
   ```
3. Create a branch:
   ```bash
   git checkout -b feat/your-feature-name
   ```

## Coding Standards

### Bash Style

- Use `#!/usr/bin/env bash` shebang
- Set strict mode: `set -euo pipefail`
- Quote all variables: `"$var"` not `$var`
- Use `[[ ]]` for tests, not `[ ]`
- Use `local` for function variables
- Prefer `$(command)` over backticks

### Naming Conventions

- Functions: `module_name_action` (e.g., `text_replace`, `fs_exists`)
- Local variables: `snake_case`
- Global variables: `SCREAMING_SNAKE_CASE`
- Guard variables: `__NUTSHELL_MODULE_LOADED__`
- Private functions: prefix with `_`

### Documentation

Every public function needs:
- `@@PUBLIC_API@@` annotation
- `Usage:` comment with signature and description
- Documentation of side effects and exit codes

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

- Use `ensure_*` for soft checks (warn and continue)
- Use `require_*` for hard checks (error and exit)
- Always provide meaningful error messages

## Making Changes

### Adding a New Function

1. Add stub to the module file (e.g., `lib/text.sh`)
2. Add selector function `_module_select_action_impl`
3. Create impl file in `lib/module/impl/`
4. Add `@@PUBLIC_API@@` annotation
5. Update documentation

### Adding a New Module

1. Create `lib/module.sh` with guard and annotations
2. Add module to the layer structure in DESIGN.md
3. Register in `nutshell.sh` for `use module`
4. Add QA check if applicable

### Testing Your Changes

Before committing, always:

1. **Run QA checks**:
   ```bash
   ./check
   ```

2. **Test manually**:
   ```bash
   source ./init
   use your_module
   # Test your functions
   ```

3. **Check for shellcheck warnings**:
   ```bash
   shellcheck lib/*.sh
   ```

4. **Test on both Linux and macOS** (if possible)

## Commit Guidelines

### Commit Message Format

```
type: lowercase message
```

Types:
- `feat` - New feature
- `fix` - Bug fix
- `refactor` - Code refactoring
- `docs` - Documentation changes
- `test` - Test additions or changes
- `chore` - Maintenance tasks

### Good Examples

- `feat: add json_parse function`
- `fix: handle spaces in filenames in fs_list`
- `docs: update DESIGN.md with new module structure`
- `test: add qa checks for string module`

### Bad Examples

- `Added feature` (no type)
- `WIP` (not descriptive)
- `Fix stuff` (not specific, not lowercase)

## Pull Request Process

1. **Update documentation** if you've changed behavior or added features
2. **Run all QA checks** and ensure they pass
3. **Update TODO.md** to mark completed tasks
4. **Create a pull request** with:
   - Clear title describing the change
   - Description of what changed and why
   - References to related issues
   - Test results

5. **Wait for review** - maintainers will review your PR and may request changes

## Code Review Checklist

Before submitting, ensure:

- [ ] Functions have `@@PUBLIC_API@@` annotation
- [ ] Functions have `Usage:` documentation
- [ ] Variables are quoted properly
- [ ] Local variables use `local`
- [ ] Error handling is present
- [ ] No shellcheck warnings (or justified ignores)
- [ ] Works on both Linux and macOS
- [ ] DESIGN.md updated if needed
- [ ] TODO.md updated if needed
- [ ] All QA checks pass (`./check`)

## Code Constraints

| Rule | Limit | Reason |
|------|-------|--------|
| Function length | <50 lines | Readability |
| File size | <500 lines | Maintainability |
| Nesting depth | <4 levels | Complexity |
| External deps | Document all | Portability |

## Don't

- Use `eval` unless absolutely necessary (security risk)
- Assume tool availability without checking deps.sh
- Add external dependencies without documenting
- Break POSIX compatibility without good reason
- Leave TODO comments without task reference
- Modify stub pattern without updating DESIGN.md
- Ignore shellcheck warnings

## Getting Help

- **Issues**: Open an issue for bugs or feature requests
- **Discussions**: Use GitHub Discussions for questions
- **Documentation**: Check docs/ directory for detailed information

## License

By contributing, you agree that your contributions will be licensed under the project's MIT License.

## Thank You!

Your contributions make nutshell better for everyone. Thank you for taking the time to contribute!
