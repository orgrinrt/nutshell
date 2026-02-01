# nutshell TODO

## v0.1.0 Release Checklist

- [x] Core library modules (os, log, deps, fs, text, json, http, etc.)
- [x] Lazy-init stub pattern for tool-dependent functions
- [x] New directory structure (init, bin/, lib/, qa/)
- [x] `init` entry point for sourcing
- [x] `bin/nutshell` interpreter for shebang support
- [x] `use` function for selective module loading
- [x] QA system with built-in checks
- [x] Config-driven via nut.toml
- [x] README with clear usage documentation
- [ ] Test the full workflow end-to-end
- [ ] Tag v0.1.0 release
- [ ] Create GitHub release with tarball

## High Priority

### Documentation
- [ ] Add `os_type` alias for `os_name` (consistency with docs)
- [ ] Update DESIGN.md to reflect new structure
- [ ] Add CHANGELOG.md
- [ ] Add CONTRIBUTING.md

### QA System
- [ ] Fix qa/check_*.sh scripts to use new paths (lib/ not core/)
- [ ] Fix qa/run_builtins.sh to work with new structure
- [ ] Ensure check.sh runs correctly from project root
- [ ] Add custom_checks support testing

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
- [x] Built-in QA checks (qa/check_*.sh)
- [x] Config templates (empty, default, tough)
- [x] JSON Schema for nut.toml
- [x] New init/use pattern for module loading
- [x] bin/nutshell interpreter
- [x] Restructured from core/ to lib/
- [x] Moved tests/ to qa/
- [x] README with usage patterns and examples
