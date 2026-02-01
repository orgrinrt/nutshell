# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-02-01

### Added

- Core library modules: os, log, deps, fs, text, json, http, color, validate, string, array, toml, prompt, xdg
- Lazy-init stub pattern for efficient tool-dependent function loading
- `init` entry point for sourcing the library
- `bin/nutshell` interpreter for shebang support (`#!/usr/bin/env nutshell`)
- `use` function for selective module loading
- QA system with built-in checks:
  - Syntax validation
  - File size limits
  - Function duplication detection
  - Trivial wrapper detection
  - Cruft detection (debug code, TODOs)
  - Public API documentation validation
  - Config schema validation
- Config-driven behavior via `nut.toml`
- Configuration templates: empty, default, tough
- JSON Schema for `nut.toml` validation
- Comprehensive documentation:
  - README with usage patterns and examples
  - DESIGN.md with architectural decisions
  - TODO.md for tracking development progress
- `os_type` alias for `os_name` (consistency with documentation)
- Support for both Linux and macOS
- Tool detection system with GNU/BSD variant support
- Portable implementation selection based on available tools

### Changed

- Restructured from `core/` to `lib/` directory
- Moved `tests/` to `qa/` (now in examples/checks/)
- Updated all documentation to reflect new structure

### Fixed

- Path references in QA check scripts updated to use `lib/` instead of `core/`
- Consistent naming conventions across modules

[unreleased]: https://github.com/orgrinrt/nutshell/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/orgrinrt/nutshell/releases/tag/v0.1.0
