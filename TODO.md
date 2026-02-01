# nutshell TODO

## Completed

### Config-Driven QA Test Suite
- [x] Rewrite `test_trivial_wrappers.sh` to be fully config-driven
- [x] Framework loads canonical defaults from `templates/empty.nut.toml`
- [x] User `nut.toml` overrides defaults correctly
- [x] Clean tree-structured diagnostic output in `run_all.sh`
- [x] Output level filtering (error, warn, info, debug)

### Annotation System Cleanup
- [x] Remove ambiguous `#@@ALLOW_TRIVIAL_WRAPPER@@` pattern
- [x] Establish semantic annotations (`@@PUBLIC_API@@`, `@@ALLOW_TRIVIAL_WRAPPER_FOR_ERGONOMICS@@`)
- [x] Update core modules with proper annotations

### Repository Setup
- [x] Create nutshell repository on GitHub
- [x] Create the-whole-shebang repository on GitHub
- [x] Add both repos to `.control-center/worktree/@orgrinrt/inventory.toml`

### Architecture Design
- [x] Design lazy-init stub pattern (see DESIGN.md)
- [x] Design environment detection system (see DESIGN.md)
- [x] Document tool combo support (see DESIGN.md)

### deps.sh - Environment Detection
- [x] Refactor to collect available tools without deciding "best"
- [x] Implement path resolution:
  - [x] Check user config for explicit paths first
  - [x] Use `which` if available
  - [x] Fall back to checking common locations (`/usr/bin`, `/bin`, `/usr/local/bin`, `/opt/homebrew/bin`)
  - [x] Verify binary exists and is executable before accepting
- [x] Implement `_TOOLS_AVAILABLE` detection
- [x] Implement `_TOOL_PATH` associative array
- [x] Implement `_TOOL_VARIANT` detection (gnu/bsd/gawk/mawk/etc.)
- [x] Implement `_TOOL_CAN` capability flags:
  - [x] `sed_inplace`, `sed_extended`, `sed_regex_r`
  - [x] `grep_pcre`, `grep_extended`, `grep_include`, `grep_only_matching`
  - [x] `awk_regex`, `awk_nextfile`, `awk_strftime`, `awk_gensub`
  - [x] `stat_format`
  - [x] `perl_regex`, `perl_inplace`, `perl_json`
  - [x] `find_maxdepth`, `find_printf`
- [x] Cache all info in readonly vars on first source
- [x] Add user preference overrides from `nut.toml` `[deps.paths]` section

### text.sh - Stub + Impl Refactor
- [x] Create `text/impl/` directory structure
- [x] Implement self-replacing stub for `text_replace`:
  - [x] `sed_replace.sh` (handles GNU/BSD variants)
  - [x] `perl_replace.sh`
  - [x] `awk_replace.sh`
- [x] Implement self-replacing stub for `text_grep`:
  - [x] `grep_match.sh`
  - [x] `perl_match.sh`
- [x] Implement self-replacing stub for `text_contains`
- [x] Implement self-replacing stub for `text_count_matches`
- [x] Add module status vars: `_TEXT_READY`, `_TEXT_ERROR`
- [x] Add `text_ready()` and `text_error()` functions

### fs.sh - Stub + Impl Refactor
- [x] Create `fs/impl/` directory structure
- [x] Implement self-replacing stub for `fs_size`:
  - [x] `stat_gnu.sh`
  - [x] `stat_bsd.sh`
  - [x] `perl_stat.sh` (fallback)
- [x] Implement self-replacing stub for `fs_mtime`
- [x] Add module status vars: `_FS_READY`, `_FS_ERROR`
- [x] Add `fs_ready()` and `fs_error()` functions

### Impl File Standards
- [x] Each impl works both sourced and standalone
- [x] Impl overwrites public function when sourced
- [x] Impl reads environment vars directly (no deps API calls)

## High Priority

### Impl Combo Support
- [ ] Implement combo impls:
  - [ ] `combo/grep_sed.sh` for search-and-transform operations
- [ ] Document impl file contract in DESIGN.md

### Remaining Config-Driven QA Tests
- [ ] Update `test_syntax.sh` to check enable flag
- [ ] Update `test_file_size.sh` to be fully config-driven
- [ ] Update `test_function_duplication.sh` to be fully config-driven
- [ ] Update `test_no_cruft.sh` to be fully config-driven
- [ ] Add new `test_public_api_docs.sh`

### Annotations Coverage
- [ ] Audit all public functions for `@@PUBLIC_API@@`
- [ ] Ensure all `@@PUBLIC_API@@` functions have `Usage:` docs

## Medium Priority

### the-whole-shebang Repository
- [ ] Create initial repo structure with README, LICENSE (MPL-2.0)
- [ ] Add nutshell as git submodule
- [ ] Port infra modules from explore.ikiuni.dev:
  - [ ] `template.sh`
  - [ ] `ui.sh`
  - [ ] `cache.sh` (make generic)
  - [ ] `state.sh` (make generic)
- [ ] Port service modules:
  - [ ] `git.sh`
  - [ ] `docker.sh`
- [ ] Add QA config using tough template

### Agent Skill File
- [ ] Create skill file documenting nutshell/the-whole-shebang
- [ ] Document submodule workflow
- [ ] Document contribution workflow
- [ ] Include API quick reference
- [ ] Place in `.control-center/shared/skills/shell-libs.md`

### Control Center Migration
- [ ] Add the-whole-shebang as submodule to `.control-center`
- [ ] Update control-center scripts to use library

## Low Priority

### Documentation
- [ ] Add `examples/` directory
- [ ] Add `CONTRIBUTING.md`
- [ ] Generate API docs from annotations

### Testing and CI
- [ ] Add unit tests for each core module
- [ ] Add integration tests
- [ ] CI/CD setup (GitHub Actions)
- [ ] Pre-commit hooks using QA tests

### Benchmark Suite
- [ ] Create `benchmarks/` directory
- [ ] Benchmark sed vs perl vs awk for common operations
- [ ] Benchmark tool combos vs single-tool approaches
- [ ] Use results to inform default tool selection in stubs

### Future Modules
- [ ] `http.sh` - curl/wget abstraction
- [ ] `json.sh` - jq/python/perl abstraction
- [ ] `semver.sh` - semantic version parsing

## Design Decisions

See `DESIGN.md` for:
- Lazy-init stub pattern (self-replacing functions)
- Environment detection and path resolution
- Tool combo support
- Module status tracking
- Performance considerations
