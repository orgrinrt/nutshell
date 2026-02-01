# nutshell TODO

## ✅ Completed

### Config-Driven QA Test Suite
- [x] Rewrite `test_trivial_wrappers.sh` to be fully config-driven
  - All thresholds loaded from `nut.toml` via `cfg_get`
  - Test enable/disable controlled by `cfg_is_true "tests.trivial_wrappers"`
  - Annotation patterns read from config, not hardcoded
- [x] Framework properly loads canonical defaults from `templates/empty.nut.toml`
- [x] User `nut.toml` overrides defaults correctly

### Annotation System Cleanup
- [x] Remove ambiguous `#@@ALLOW_TRIVIAL_WRAPPER@@` pattern
- [x] Establish semantic annotations:
  - `@@PUBLIC_API@@` - function is part of public interface, must be documented
  - `@@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@` - intentional thin wrapper for API consistency
  - `@@ALLOW_LOC_NNN@@` - file allowed to exceed size limit with explicit justification
- [x] Update `core/os.sh` with proper annotations
- [x] Update `core/xdg.sh` with proper annotations
- [x] Update `core/validate.sh` with proper annotations

### Repository Setup
- [x] Create nutshell repository on GitHub
- [x] Create the-whole-shebang repository on GitHub
- [x] Add both repos to `.control-center/worktree/@orgrinrt/inventory.toml`
- [x] Initialize `.repos/` structure
- [x] Move nutshell to `.repos/@orgrinrt/shell-libs/nutshell`
- [x] Clone the-whole-shebang to `.repos/@orgrinrt/shell-libs/the-whole-shebang`

## High Priority

### Remaining Config-Driven QA Tests
- [ ] Update `test_syntax.sh` to be fully config-driven
- [ ] Update `test_file_size.sh` to be fully config-driven
- [ ] Update `test_function_duplication.sh` to be fully config-driven
- [ ] Update `test_no_cruft.sh` to be fully config-driven
- [ ] Add new `test_public_api_docs.sh` - verify all `@@PUBLIC_API@@` functions have `Usage:` docs

### Dependency System Redesign (`core/deps.sh`)
- [ ] Implement capability-based approach instead of tool-specific
- [ ] Define capability groups:
  - `stream_edit` - sed, perl, awk (in preference order)
  - `pattern_match` - grep, perl, awk
  - `text_process` - awk, perl, sed
  - `file_stat` - stat, perl, ls -l
  - `json_parse` - jq, python, perl (for future use)
- [ ] For each capability, detect what's available and pick best option
- [ ] Provide portable functions that abstract tool differences:
  - `deps_stream_edit "pattern" input.txt > output.txt`
  - `deps_stream_edit_inplace "pattern" file.txt`
  - `deps_grep "pattern" file.txt`
  - `deps_file_size file.txt`
  - `deps_file_mtime file.txt`
- [ ] All modules (fs.sh, text.sh, etc.) should use deps.sh capabilities
- [ ] Make fallback selection configurable via `nut.toml`

### Annotations Coverage
- [ ] Audit all public functions and add `@@PUBLIC_API@@` where missing
- [ ] Ensure all `@@PUBLIC_API@@` functions have proper `Usage:` documentation
- [ ] Add documentation generation script that extracts from annotations

## Medium Priority

### the-whole-shebang Repository
- [ ] Create initial repo structure with README, LICENSE (MPL-2.0)
- [ ] Add nutshell as git submodule
- [ ] Port infra modules from explore.ikiuni.dev:
  - [ ] `template.sh` - template processing
  - [ ] `ui.sh` - user interface primitives
  - [ ] `cache.sh` - caching layer (make generic, remove hardcoded app name)
  - [ ] `state.sh` - state management (make generic, remove hardcoded app name)
- [ ] Port service modules:
  - [ ] `git.sh` - git operations
  - [ ] `docker.sh` - docker operations
- [ ] Create entry point `the-whole-shebang.sh`
- [ ] Add QA config (`nut.toml`) using tough template

### Agent Skill File
- [ ] Create skill file for agents documenting nutshell/the-whole-shebang
- [ ] Document submodule workflow
- [ ] Document contribution workflow (branch, PR, pin commit)
- [ ] Include API quick reference
- [ ] Place in `.control-center/shared/skills/shell-libs.md`

### Control Center Migration
- [ ] Add the-whole-shebang as submodule to `.control-center`
- [ ] Rewrite `test_toml_assembly.py` in bash using the-whole-shebang
- [ ] Update `assemble_agent_rules.sh` to use library functions
- [ ] Update other control-center scripts to use library

## Low Priority

### Documentation
- [ ] Add `examples/` directory with usage examples
- [ ] Add `CONTRIBUTING.md`
- [ ] Generate API docs from `@@PUBLIC_API@@` annotations

### Testing
- [ ] Add unit tests for each core module
- [ ] Add integration tests
- [ ] CI/CD setup (GitHub Actions)
- [ ] Pre-commit hooks using QA tests

### Future Modules
- [ ] `http.sh` - curl/wget abstraction with retry, timeout, auth
- [ ] `json.sh` - jq/python/perl abstraction for JSON parsing
- [ ] `yaml.sh` - yq abstraction for YAML (or recommend TOML)
- [ ] `semver.sh` - semantic version parsing and comparison

## Design Decisions Documented

See `DESIGN.md` for:
- Layered architecture (Layer -1 Foundation, Layer 0 Core)
- `ensure_*` vs `require_*` semantics
- Capability-based dependency system design
- Annotation system rationale
- QA philosophy (config-first, no hardcoded values)
