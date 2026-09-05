# `nutshell`

<div align="center" style="text-align: center;">

[![GitHub Stars](https://img.shields.io/github/stars/orgrinrt/nutshell.svg)](https://github.com/orgrinrt/nutshell/stargazers)
[![GitHub Issues](https://img.shields.io/github/issues/orgrinrt/nutshell.svg)](https://github.com/orgrinrt/nutshell/issues)
![License](https://img.shields.io/github/license/orgrinrt/nutshell?color=%23009689)

> A bash library and the interpreter that finds it. Ships lists, maps, toml, http, tests and about thirty other modules, and a `nut-lower` that flattens a script to plain POSIX sh.

</div>

Shell scripts grow the same way everywhere: a helper here, a copy of it in the
next project, and eventually four versions of the same argument parser that
disagree about edge cases. `nutshell` is the library that stops that, plus the
piece that makes a library reachable at all, which is an interpreter on `PATH`
that a script names in its shebang.

The trade it makes is one shared installation rather than a copy in each tree. A
script says `#!/usr/bin/env nutshell` and gets the modules; a project that needs
a particular version says so in one line of `nut.toml` and gets that instead,
fetched into a store shared by everything on the machine. There is no vendored
resolver, no per-project dependency tree, and no boilerplate at the top of a
file.

It needs bash 4.0 or newer to run, which is worth saying because macOS ships 3.2
at `/bin/bash` and that is the machine this is most often reached from. What it
produces need not be bash at all: `nut-lower` resolves a script's modules ahead
of time and writes the library half as one file, and with the right features off
that file is POSIX `sh`.

## Usage

One `nutshell` on the machine, shared by everything that uses it:

```bash
git clone https://github.com/orgrinrt/nutshell.git
./nutshell/install
```

That links the interpreter onto `PATH`. A script then needs no boilerplate, and
the shebang is the whole of it:

```bash
#!/usr/bin/env nutshell

use os log

log_info "building on $(os_name)"
```

`use` takes any number of modules and loads each once however many times it is
asked for. The list is in `### Modules` below.

A project that needs a nutshell the machine does not have says so in `nut.toml`,
at the root of the file, above the first table:

```toml
nutshell_branch = "dev"       # or nutshell_version = "0.7.0" for a release
```

The launcher reads the manifest above the script, resolves the pin, and execs
into that nutshell before the first line runs. Root level matters: a bare key
after a table header belongs to that table, so `nutshell_branch` under `[meta]`
is a pin nothing reads and nothing complains about.

A pin that cannot be resolved is not fatal by default, which is the one sharp
edge here. The ambient nutshell stays in place and the project runs on whatever
the machine has, so when that is older the failures land on the project's own
tests and read as a defect there. `NUTSHELL_VERSION` is exported, so one
comparison in the entry point says it out loud instead:

```bash
#!/usr/bin/env nutshell
: "${NUTSHELL_ROOT:?run this through the nutshell launcher, or install nutshell}"
_min="0.7.0"
if [[ "$(printf '%s\n%s\n' "$_min" "${NUTSHELL_VERSION:-0.0.0}" | sort -V | head -1)" != "$_min" ]]; then
    printf 'needs nutshell %s or newer, resolved %s\n' "$_min" "$NUTSHELL_VERSION" >&2
    exit 1
fi
```

## Example

A release script that reads its own manifest, asks a registry what is published,
and refuses before it does anything irreversible:

```bash
#!/usr/bin/env nutshell
# scripts/release.sh

use toml http json log deps git

deps_require git curl

version=$(toml_get nut.toml version)
name=$(toml_get nut.toml name)

if [[ -n "$(git_changed_files)" ]]; then
    log_error "the tree is dirty; commit or stash first"
    exit 1
fi

published=$(http_get "https://registry.example/api/v1/${name}" | json_get '.max_version')
if [[ "$published" == "$version" ]]; then
    log_warn "${name} ${version} is already published; nothing to do"
    exit 0
fi

log_info "releasing ${name} ${version}, over ${published}"
git tag -a "v${version}" -m "release ${version}"
```

Nothing above is a wrapper around a wrapper: `toml_get` reads the file, `http_get`
is curl with the flags nobody remembers, and `git_changed_files`
is the porcelain call plus the parsing. The point is that the script reads as
what it does.

## Motivation

The reason there is an interpreter at all, rather than a library to source, is
that sourcing needs a path and a path needs somebody to have put the library
somewhere. Every answer to that except a shared installation ends in a copy: a
copy of nutshell in the tree, or a copy of a resolver that fetches nutshell.

A copy is a second version, and it drifts from the machine's without saying so.
It resolves the modules that existed when it was added and none added since, so
what surfaces is an error naming a missing function rather than one naming a
stale copy. A pin is one line in a manifest and its value is on that line; a
copied resolver is several hundred lines with its version in a variable default.

What that costs is the install step, once per machine. After it, a fresh clone
of anything needs nothing at all: its `nut.toml` names the nutshell it wants and
the launcher fetches that into the store on first run.

## Extras

### Status

Pre-1.0 and the module surface still moves. Function names within a module are
stable in practice; a module gaining or losing one is a minor bump, and the
`use` line and the shebang have not changed and are not going to.

### Modules

| Module | What it carries |
|---|---|
| `os` | `os_name`, `os_is_macos`, `os_is_linux` |
| `log` | `log_info`, `log_warn`, `log_error`, `log_success` |
| `deps` | `deps_has`, `deps_require`, `deps_path` |
| `fs` | `fs_exists`, `fs_mkdir`, `fs_temp_file`, `fs_size` |
| `string` | `str_upper`, `str_lower`, `str_trim`, `str_contains` |
| `array` | over arguments, `arr_contains`, `arr_index`, `arr_filter`; over a `list` in place, `arr_unique`, `arr_reverse`, `arr_sort` |
| `list` | an ordered list needing no bash array: `list_push`, `list_get`, `list_each`, `list_len` |
| `map` | a key to value table needing no associative array: `map_set`, `map_get`, `map_has`, `map_keys` |
| `text` | `text_grep`, `text_replace`, `text_count_matches` |
| `json` | `json_get`, `json_set`, `json_valid`, `json_pretty` |
| `http` | `http_get`, `http_post`, `http_download` |
| `toml` | `toml_get`, `toml_get_or`, `toml_is_true`, `toml_array` |
| `toml::write` | changing a file in place: `toml_set`, `toml_unset` |
| `toml::json` | `toml_to_json` |
| `hash` | `hash_impl`, and reading a published sums file, `hash_sums_get`, `hash_sums_pick` |
| `prompt` | `prompt_confirm`, `prompt_input`, `prompt_select` |
| `color` | `color_red`, `color_green`, `color_bold` |
| `validate` | `is_set`, `is_integer`, `require_command` |
| `xdg` | `xdg_config_home`, `xdg_data_home`, `xdg_app_cache` |
| `test` | `assert_eq`, `assert_ok`, `assert_fails`, `test_run`, `test_summary` |
| `check-runner` | `cfg_get`, `log_pass`, `log_fail` |
| `attr` | attributes on definitions: `attr_has`, `attr_arg`, `attr_find` |
| `cli` | subcommand dispatch with did-you-mean: `cli_command`, `cli_run` |
| `srcfile` | a source file read once: `nut_load_file`, `nut_defined_at`, `nut_body_of` |
| `checkcache` | a check's answer kept until it can change: `nut_cache_hit`, `nut_cache_read` |
| `priv` | elevating for one step and stepping back: `priv_run`, `priv_as_user` |
| `git` | reading a repository: `git_trunk`, `git_changed_files`, `git_trailers` |
| `modgraph` | the module graph and its violations: `modgraph_build`, `modgraph_audit` |
| `extern` | libraries from elsewhere: `extern_path`, `extern_resolve` |

### Writing a module

A module is a file in `lib/`. It guards against being sourced twice, declares
what it needs, and marks what it offers:

```bash
# lib/mymodule.sh
nut_once || return 0

use log string

# my_function <name>
#
# Greets somebody.
#[pub]
my_function() {
    log_info "hello, $(str_trim "$1")"
}
```

`nut_once` is the include guard and returns non-zero the second time the file is
read. `use` at the top of a module declares its dependencies the same way a
script does, and `modgraph` audits those: a cycle, a call into a module nobody
declared, and a call to something not marked `#[pub]` are all findings. Tests go
in `tests/<module>_test.sh` on the `test` module, and functions marked `#[test]`
are what the runner collects.

### The store

Fetched dependencies live in one place shared by every project on the machine,
keyed by url and commit, so two projects on the same commit of the same library
have one copy between them.

The interpreter is one of those dependencies rather than a special case.
Versions sit side by side, a tool asks for the one it needs, and a version not
on the machine yet is fetched at its tag rather than being a failure. A machine
carrying four of them is the ordinary state.

```
<store>/
  externs/       one directory per url and commit
  toolchains/    one directory per version
  toolchains/branches/<ref>/<revision>/
```

`XDG_DATA_HOME` names the store wherever it is set, on any platform. Unset, it
is `~/.local/share/nutshell` on Linux and `~/Library/Application Support/nutshell`
on macOS, which is where each puts application data rather than cache: a cache is
something a cleaner is entitled to delete, and this is where every project's
dependencies actually live. `NUTSHELL_STORE` moves the root and
`NUTSHELL_TOOLCHAINS` just the toolchains.

A version pin gets a directory named for the version; a branch pin gets one
named for the revision that branch resolved to. The second is what makes the
store safe to share, since a revision directory is written once and never
replaced, so somebody else's push cannot delete the tree a running interpreter
is reading out of.

The two pins resolve by different routes, because they are different questions.
A version is a floor: `NUTSHELL_HOME`, then an installed interpreter if it
satisfies, then the store, then a fetch, then whatever the project vendored. A
branch is an identity, so `dev` means the head of dev today and nothing already
on the machine can be assumed to be that: `NUTSHELL_HOME`, then the branch's
head, then vendored. The remote is asked at most once an hour, and when it
cannot be reached the last known revision runs and says which one it is.

### Lowering and features

`nut-lower` resolves a script's `use` lines ahead of time and writes the library
half as one file, with everything nothing calls removed:

```bash
nut-lower scripts/build.sh -o lowered.sh
```

```bash
#!/bin/sh
. ./lowered.sh
```

It is the library half rather than a runnable copy of the script, so the output
is a file to source and carries no executable bit.

Two things decide what goes into it. A gate asks about the machine doing the
lowering, which shell is running and whether a binary is on `PATH`. A feature is
a choice about the machine that will run the result. That difference is what
lets a POSIX artifact come off a host that has bash.

Features live in `nut.toml` and take cargo's shape:

```toml
[features]
default = ["bash"]
bash    = []
```

A row in `lib.nut` carrying `#[feature(bash)]` is in when that feature is on.
`--features a,b` adds to what is enabled and `--no-default-features` drops the
default set, both the way cargo means them.

### Checks

`./check` runs the quality checks over a tree, configured under `[qa]` and
`[tests.*]` in `nut.toml`. `--builtins` runs only the shipped ones, `--list`
names them. The templates in `examples/configs/` are a documented empty one, a
recommended default, and a strict one.

| Check | What it looks for |
|---|---|
| `syntax` | bash syntax |
| `file_size` | file size and line count limits |
| `function_duplication` | copy-pasted functions |
| `trivial_wrappers` | wrappers that add nothing |
| `no_cruft` | debug code and leftover markers |
| `public_api_docs` | a documented surface |
| `config_schema` | the shape of `nut.toml` |
| `module_contract` | cycles, undeclared calls, private calls, unreachable modules |

### Limitations

Bash 4.0 is the floor for running nutshell itself, and the refusal is loud
rather than a confusing failure further in. A lowered artifact has no such
floor and is only as constrained as the features left on.

## Support

Feel free to contribute! If unsure about wasting work, the best practice is to throw in an issue describing what you'd do, and only then commit to writing a big PR, because chances are, it might not be something that belongs here. However, forks are always a valid choice and we'd encourage everyone to experiment and have their own takes on this. When doing this, do mind the license(s) though!

A module is the unit worth proposing: one file in `lib/`, its `#[pub]` surface, and its tests beside it.

Whether you use this project, have learned something from it, or just like it, please consider supporting it by buying me a coffee, so I can dedicate more time on open-source projects like this :)

<a href="https://buymeacoffee.com/orgrinrt" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Coffee" style="height: auto !important;width: auto !important;" ></a>

## License

> The project is licensed under the **Mozilla Public License 2.0**.

`SPDX-License-Identifier: MPL-2.0`

> You can check out the full license [here](https://github.com/orgrinrt/nutshell/blob/main/LICENSE)
