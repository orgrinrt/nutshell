# nutshell TODO

## High Priority

### Config Schema Validation
- [ ] Create JSON Schema for `nut.toml` in `schemas/nut.toml.schema.json`
- [ ] Add `test_config_schema.sh` to validate config against schema
- [ ] Document schema in `templates/empty.nut.toml`

### Impl Combo Support
- [ ] Implement `combo/grep_sed.sh` for search-and-transform operations
- [ ] Add combo selection logic to stubs

### QA Test Improvements
- [ ] Update individual tests to be fully config-driven
- [ ] Add `test_public_api_docs.sh` to verify documentation
- [ ] Audit all public functions for `@@PUBLIC_API@@` annotation

## Medium Priority

### the-whole-shebang Repository
- [ ] Create initial repo structure with README, LICENSE (MPL-2.0)
- [ ] Add nutshell as git submodule
- [ ] Port infra modules: `template.sh`, `ui.sh`, `cache.sh`, `state.sh`
- [ ] Port service modules: `git.sh`, `docker.sh`

### Documentation
- [ ] Create skill file for agents in `.control-center/shared/skills/shell-libs.md`
- [ ] Add `examples/` directory with usage examples
- [ ] Add `CONTRIBUTING.md`

### Control Center Integration
- [ ] Add the-whole-shebang as submodule to `.control-center`
- [ ] Update control-center scripts to use library

## Low Priority

### Testing and CI
- [ ] Add unit tests for each core module
- [ ] CI/CD setup (GitHub Actions)
- [ ] Pre-commit hooks using QA tests

### Benchmark Suite
- [ ] Create `benchmarks/` directory
- [ ] Benchmark sed vs perl vs awk for common operations
- [ ] Use results to inform default tool selection

### Future Modules
- [ ] `http.sh` - curl/wget abstraction
- [ ] `json.sh` - jq/python/perl abstraction
- [ ] `semver.sh` - semantic version parsing

## Completed

### Core Architecture
- [x] Lazy-init stub pattern for tool-dependent functions
- [x] deps.sh with associative arrays (`_TOOL_PATH`, `_TOOL_VARIANT`, `_TOOL_CAN`)
- [x] Path resolution: config -> which -> common locations
- [x] Capability detection (grep_pcre, sed_extended, etc.)

### text.sh Implementation
- [x] Self-replacing stubs for `text_replace`, `text_grep`, `text_contains`, `text_count_matches`
- [x] Impl files: `sed_replace.sh`, `perl_replace.sh`, `awk_replace.sh`, `grep_match.sh`, `perl_match.sh`
- [x] Module status: `_TEXT_READY`, `text_ready()`, `text_error()`

### fs.sh Implementation
- [x] Self-replacing stubs for `fs_size`, `fs_mtime`
- [x] Impl files: `stat_gnu.sh`, `stat_bsd.sh`, `perl_stat.sh`
- [x] Module status: `_FS_READY`, `fs_ready()`, `fs_error()`

### QA System
- [x] Config-driven test framework
- [x] Clean tree-structured diagnostic output
- [x] Output level filtering (`--level=error|warn|info|debug`)
- [x] Annotation system (`@@PUBLIC_API@@`, `@@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@`, `@@ALLOW_LOC_NNN@@`)

### Repository Setup
- [x] nutshell repository on GitHub
- [x] the-whole-shebang repository on GitHub (empty)
- [x] Inventory updated in `.control-center`
