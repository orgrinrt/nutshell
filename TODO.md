# nutshell TODO

## High Priority

### Dependency System Redesign (`core/deps.sh`)
- [ ] Implement capability-based approach instead of tool-specific
- [ ] Define capability groups:
  - `stream_edit` - sed, perl, awk (in preference order)
  - `pattern_match` - grep, perl, awk
  - `text_process` - awk, perl, sed
  - `json_parse` - jq, python, perl (for future use)
- [ ] For each capability, detect what's available and pick best option
- [ ] Provide portable functions that abstract tool differences
- [ ] Downstream code should use portable functions, not raw tools
- [ ] All modules (fs.sh, text.sh, etc.) should use deps.sh capabilities

### QA Test Suite
- [ ] Update test_trivial_wrappers.sh to be fully config-driven
- [ ] Update test_file_size.sh to be fully config-driven
- [ ] Update test_function_duplication.sh to be fully config-driven
- [ ] Update test_no_cruft.sh to be fully config-driven
- [ ] Update test_syntax.sh to be fully config-driven
- [ ] Update run_all.sh to use framework properly
- [ ] Add test for public API documentation (@@PUBLIC_API@@ must have Usage:)

### Annotations
- [ ] Add @@PUBLIC_API@@ to all remaining public functions in:
  - [ ] text.sh
  - [ ] os.sh
  - [ ] log.sh
  - [ ] validate.sh (partially done)
  - [ ] xdg.sh (partially done)
- [ ] Ensure all @@PUBLIC_API@@ functions have `Usage:` documentation

## Medium Priority

### the-whole-shebang Repository
- [ ] Create repo structure
- [ ] Add nutshell as git submodule
- [ ] Port infra modules from explore.ikiuni.dev:
  - [ ] template.sh
  - [ ] ui.sh
  - [ ] cache.sh (make generic, remove hardcoded app name)
  - [ ] state.sh (make generic, remove hardcoded app name)
- [ ] Port service modules:
  - [ ] git.sh
  - [ ] docker.sh

### Agent Skill File
- [ ] Create skill file for agents documenting nutshell/the-whole-shebang
- [ ] Document submodule workflow
- [ ] Document contribution workflow (branch, PR, pin commit)
- [ ] Include API quick reference

### Control Center Migration
- [ ] Add the-whole-shebang as submodule to .control-center
- [ ] Rewrite test_toml_assembly.py in bash using the-whole-shebang
- [ ] Update assemble_agent_rules.sh to use library

## Low Priority

### Documentation
- [ ] Add examples/ directory with usage examples
- [ ] Add CONTRIBUTING.md
- [ ] Generate API docs from @@PUBLIC_API@@ annotations

### Testing
- [ ] Add unit tests for each module
- [ ] Add integration tests
- [ ] CI/CD setup (GitHub Actions)

### Future Modules
- [ ] http.sh - curl/wget abstraction
- [ ] json.sh - jq/python/perl abstraction for JSON parsing
- [ ] yaml.sh - yq abstraction for YAML (maybe, or just use TOML)
