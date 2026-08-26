# Modules

A module is a file. The file is its identity, and `lib.nut` says which files a
library offers and what to call them.

## Naming one

`::` separates every step, the whole way down:

```sh
use log                     # nutshell's own
use super::guard            # this unit's, from its own lib.nut
use shebang::tui::menu      # a declared dependency's
```

A `/` is refused. It used to work, because the part after `::` was handed to
the filesystem unchanged, so a nested module resolved without anyone having
designed one. Two separators in one path, one of them by accident.

## Declaring them

`lib.nut` sits at the root of a library. One module per line: the name a `use`
writes, then the file, then `internal` if it is not for anybody else.

```
# lib.nut - the modules shebang provides.

tui::term            libs/tui/term.sh
tui::menu            libs/tui/menu.sh
json::impl::jq       lib/json/impl/jq.sh      internal
```

It is a line format on purpose. `init` reads it before any module is loaded,
and the TOML parser is itself a module: a declaration file that needs a parser
you must load a module to obtain is a cycle at the bottom of the stack.

`internal` means the library's own file, reachable by `super::` from inside and
not by name from outside. The implementations under `impl/` are the case: the
module above them picks one at runtime by what the machine has, and a consumer
naming one directly is reaching past the thing whose job is to choose.

## Why a declaration and not a search

A module used to be found by trying `lib/<name>.sh`, then `libs/<name>.sh`,
then `<name>.sh`, and taking whichever answered. Three guesses, in order.

That has two costs. A file findable in more than one place resolves to
whichever came first, which is not necessarily the one meant. And nothing can
say in advance that a name will not resolve, so a missing module is found at
the moment it is reached, mid-run, under `set -eo pipefail`, with the shell
exiting and nothing on screen explaining why.

A declaration makes the set of modules a fact rather than a search result. A
name is in the tree or it is not, and both directions are checkable before
anything runs.

## Moving a library onto it

`nut-declare` writes the declaration a library was already implying. It runs
the old resolution backwards: every file those three layouts would have found,
under the name that would have found it. What it writes therefore resolves
exactly what resolved before.

```sh
nut-declare                  # write ./lib.nut
nut-declare path/to/lib      # write one elsewhere
nut-declare --print          # see it first
nut-declare --check          # what disagrees, write nothing
```

It never overwrites. A `lib.nut` that exists is the library's own statement
about itself; run against one, it prints the difference against a fresh one,
which is also how to check a hand-edited file still covers every file.

`--check` reports both directions: a declaration whose file is gone, and a file
nothing declares. The second is the one a search could never report, because
the file resolves perfectly well under a name the library never meant to offer.

## Loading happens once per file

A module reachable by two names is one module. Its own unit calls it
`super::tui::key` and a consumer calls it `shebang::tui::key`; loading is keyed
on the resolved file, so the second name is a no-op rather than a second
source. `nutshell_loaded` answers by either name.
