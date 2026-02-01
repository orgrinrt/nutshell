# nutshell TODO

## Completed

### Config-Driven QA Test Suite
- [x] Rewrite `test_trivial_wrappers.sh` to be fully config-driven
- [x] Framework loads canonical defaults from `templates/empty.nut.toml`
- [x] User `nut.toml` overrides defaults correctly

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

## High Priority

### Implement Lazy-Init Stub Architecture

#### deps.sh - Environment Detection
- [ ] Refactor to collect available tools without deciding "best"
- [ ] Implement path resolution:
  - [ ] Check user config for explicit paths first
  - [ ] Use `which` if available
  - [ ] Fall back to checking common locations (`/usr/bin`, `/bin`, `/usr/local/bin`, `/opt/homebrew/bin`)
  - [ ] Verify binary exists and is executable before accepting
- [ ] Implement `_TOOLS_AVAILABLE` detection
- [ ] Implement `_TOOL_PATH` associative array
- [ ] Implement `_TOOL_VARIANT` detection (gnu/bsd/gawk/mawk/etc.)
- [ ] Implement `_TOOL_CAN` capability flags:
  - [ ] `sed_inplace` - can sed do -i properly?
  - [ ] `sed_extended` - does sed support -E?
  - [ ] `grep_pcre` - does grep support -P?
  - [ ] `grep_extended` - does grep support -E?
  - [ ] `stat_format` - does stat support format strings?
- [ ] Cache all info in readonly vars on first source
- [ ] Add user preference overrides from `nut.toml` `[deps]` section

#### text.sh - Stub + Impl Refactor
- [ ] Create `text/impl/` directory structure
- [ ] Implement self-replacing stub for `text_replace`:
  - [ ] `sed_replace.sh` (handles GNU/BSD variants)
  - [ ] `perl_replace.sh`
  - [ ] `awk_replace.sh`
- [ ] Implement self-replacing stub for `text_grep`:
  - [ ] `grep_match.sh`
  - [ ] `perl_match.sh`
  - [ ] `awk_match.sh`
- [ ] Implement self-replacing stub for `text_contains`
- [ ] Implement self-replacing stub for `text_count_matches`
- [ ] Implement combo impls:
  - [ ] `combo/grep_sed.sh` for search-and-transform operations
- [ ] Add module status vars: `_TEXT_READY`, `_TEXT_ERROR`

#### fs.sh - Stub + Impl Refactor
- [ ] Create `fs/impl/` directory structure
- [ ] Implement self-replacing stub for `fs_size`:
  - [ ] `stat_gnu.sh`
  - [ ] `stat_bsd.sh`
  - [ ] `perl_stat.sh` (fallback)
- [ ] Implement self-replacing stub for `fs_mtime`
- [ ] Add module status vars: `_FS_READY`, `_FS_ERROR`

#### Impl File Standards
- [ ] Each impl works both sourced and standalone
- [ ] Impl overwrites public function when sourced
- [ ] Impl reads environment vars directly (no deps API calls)
- [ ] Document impl file contract

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
