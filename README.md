# `nutshell`

> A bash library and the interpreter that finds it, with lists, maps, toml, http, tests and some thirty other modules, and a `nut-lower` that flattens a script into plain POSIX sh.

`nutshell` is one shared installation of a standard library for shell scripts, plus an interpreter on `PATH` that a script names in its shebang. A script says `#!/usr/bin/env nutshell`, pulls in modules with `use`, and gets them from the installation instead of from a copy in each project. A project that needs a particular version says so in `nut.toml` and the launcher fetches that one into a store shared by everything on the machine.

It needs bash 4.0 or newer to run, which matters on macOS since `/bin/bash` there is 3.2. What it produces does not have to be bash, because `nut-lower` resolves a script's modules ahead of time and writes the library half out as a single file, which with the right features turned off is POSIX `sh`.

## Usage

```bash
git clone https://github.com/orgrinrt/nutshell.git
./nutshell/install
```

The installer links the interpreter into `~/.local/bin` and a second time into a directory on sudo's own `secure_path`, which needs root once. Without the second link `sudo` can't find `nutshell` and any script run through it fails with `No such file or directory`. `./install ~/bin` picks another directory, `--no-system` skips the sudo link and `--uninstall` removes both.

```bash
#!/usr/bin/env nutshell

use os log

log_info "building on $(os_name)"
```

`use` takes any number of modules and loads each one once. What exists is whatever is in `lib/`, among them `log`, `os`, `fs`, `string`, `array`, `list`, `map`, `json`, `toml`, `http`, `hash`, `prompt`, `git`, `bench` and `test`, and a module is one file with its public functions marked `#[pub]` and its tests beside it.

To pin a version, put it at the root of `nut.toml`, above the first table, because a bare key after a table header belongs to that table and a pin nobody reads does not complain.

```toml
nutshell_branch = "dev"       # or nutshell_version = "0.7.0" for a release
```

If a pin can't be resolved the ambient nutshell stays in place and the project runs on whatever the machine has, so a script that needs a minimum compares `NUTSHELL_VERSION` itself.

## Lowering and checks

`nut-lower scripts/build.sh -o lowered.sh` writes the library half of a script as one file with everything nothing calls removed, and a script can then source it from a plain `#!/bin/sh`. Features in `nut.toml` take cargo's shape, a row in `lib.nut` marked `#[feature(bash)]` is in when that feature is on, and `--features` and `--no-default-features` work the way they do in cargo.

`./check` runs the quality checks over a tree, configured under `[qa]` and `[tests.*]` in `nut.toml`, with `--list` naming them and `--builtins` running only the shipped ones. Among them are syntax, how much of the tree a POSIX shell can still read, duplicated functions, file size and the module graph.

## Status

Pre-1.0, so the module surface still moves. Function names within a module are stable in practice, a module gaining or losing one is a minor bump, and the shebang and the `use` line are not going to change.

## Contributing

A module is the unit worth proposing, and an issue first is cheaper for anything bigger. Forks are welcome, mind the licence.

## License

> The project is licensed under the **Mozilla Public License 2.0**.

`SPDX-License-Identifier: MPL-2.0`

> You can check out the full license [here](https://github.com/orgrinrt/nutshell/blob/main/LICENSE)
