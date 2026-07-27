# nutshell TODO

## v0.2.0

- [x] Core library modules (os, log, deps, fs, text, json, http, etc.)
- [x] Lazy-init stub pattern for tool-dependent functions
- [x] Directory structure (init, bin/, lib/, examples/, tests/)
- [x] `init` entry point, `bin/nutshell` interpreter, `use` for loading
- [x] QA system with built-in checks, config-driven via nut.toml
- [x] Attributes (`#[pub]`, `#[test]`, `#[allow(...)]`), read by `attr`
- [x] Test harness: `#[test]` functions, assertions, `./test`
- [x] Module graph with cycle, declaration, visibility and reachability checks
- [x] `cli` subcommand dispatch, `git` repository reading
- [x] External libraries via `nut.toml` deps, pinned by `nut.lock`
- [ ] Tag v0.2.0 release
- [ ] Create GitHub release with tarball

## High Priority

### Documentation
- [ ] Add `os_type` alias for `os_name` (consistency with docs)
- [ ] Update DESIGN.md to reflect new structure
- [ ] Add CHANGELOG.md
- [ ] Add CONTRIBUTING.md

### QA System
- [x] Checks live in examples/checks/ and run from the project root
- [ ] Add custom_checks support testing
- [x] Split lib/json.sh along its backend seam into json/impl/
- [ ] Six modules sit between 336 and 426 LOC against a 300 warn: check-runner,
      color, deps, http, prompt, toml. Each wants its own seam followed.

### Testing
- [ ] Add integration tests for the init/use workflow
- [ ] Test shebang pattern (#!/usr/bin/env nutshell)
- [ ] Test from different CWD scenarios
- [ ] Test with task runners (deno, npm, make)

## Medium Priority

### New Modules
- [ ] `semver.sh` - Semantic version parsing and comparison
- [ ] `git.sh` - Git operations abstraction
- [ ] `template.sh` - Simple template rendering

### CI/CD
- [ ] GitHub Actions workflow for running QA checks
- [ ] Automated release workflow
- [ ] Matrix testing (Linux, macOS)

### the-whole-shebang Integration
- [ ] Create initial repo structure
- [ ] Add nutshell as git submodule
- [ ] Port infrastructure modules

## Low Priority

### Future Enhancements
- [ ] Benchmark suite for impl selection heuristics
- [ ] Optional global install script
- [ ] Shell completion generation
- [ ] Consider compiled runner (Rust/Go) for performance

### Control Center Integration
- [ ] Add to .control-center as submodule
- [ ] Create skill file for agents

## Completed

### v0.1.0 Milestones
- [x] Core architecture with lazy-init stubs
- [x] deps.sh with tool detection and capabilities
- [x] All core modules: os, log, deps, color, validate, string, array, fs, text, toml, json, http, prompt, xdg
- [x] QA framework (lib/qa.sh)
- [x] Built-in QA checks (examples/checks/check_*.sh)
- [x] Config templates (empty, default, tough)
- [x] JSON Schema for nut.toml
- [x] New init/use pattern for module loading
- [x] bin/nutshell interpreter
- [x] Restructured from core/ to lib/
- [x] Moved tests/ to qa/
- [x] README with usage patterns and examples
