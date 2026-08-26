# nutshell TODO

## Release blockers, from the 2026-08-14 dev-to-main readiness review

Four items block a release. `./release` already refuses on the third. Findings are a reviewer's and the
two probes behind items 1 and 2 were written read-only, so **commit them alongside the fix**: until then
these are reproducible claims rather than repo evidence.

- [ ] **`init:47`: bash 4+ is required, declared nowhere, and the failure is silent with exit 0.**
      `declare -gA` needs bash 4.0. `bin/nutshell:1` is `#!/usr/bin/env bash`, which takes the first
      `bash` on `PATH`, and macOS ships 3.2 at `/bin/bash`. Under a default
      `PATH=/usr/bin:/bin` the script body never runs and the caller reads success:

      ```
      init: line 47: declare: -A: invalid option
      init: line 93: log: unbound variable
      EXIT=0          # stdout empty: the script body never ran
      ```

      Fix is a `BASH_VERSINFO[0] -ge 4` guard in `init` and `bin/nutshell` that exits **non-zero**,
      plus a README line. Not a port: the dependency is pervasive (`declare -A` in 10+ files,
      `mapfile` in `lib/array.sh`, `${v,,}` in `lib/{validate,string,prompt}.sh`). `README.md:5`
      currently advertises "portable" and names no version requirement.

- [ ] **`lib/extern.sh:283`: a dead lock holder is never reclaimed, so the suite sleeps ten minutes
      and then reports green.** `_extern_guard` writes `$$`, but it is reached only through command
      substitution (`extern.sh:159` to `:335`), and `$$` in a subshell is the **parent's** pid. So a
      dead holder names a live process, `kill -0` at `extern.sh:266` says alive, the corpse-reclaim
      never fires, and the waiter sits in `sleep 1` at `:278` until the age check at `:271` clears it
      and **succeeds**. `_EXTERN_LOCK_WAIT_SECONDS` defaults to 660 (`:249`), and a clean run is 25.3s
      wall against 9.57s user, which closes the arithmetic on the reported 11m28s: 688 minus 660 is
      the real work. Intermittent: it needs an interrupted holder.

      Fix is one word, `$BASHPID` rather than `$$`. **Do not lengthen a timeout.**

- [ ] **`tests/extern_test.sh:263` feeds the one input the code handles.**
      `it_takes_over_a_lock_whose_holder_died` reaps a real child and writes a genuinely dead pid,
      which is the branch that works. The branch production actually produces, a live-parent pid
      written by a dead subshell, is never entered. Add that case as a test that fails before the fix
      above.

- [ ] **`init:29`: bump `NUTSHELL_VERSION`, and `README.md:7` with it.** Still `0.2.0` while the slice
      adds `toml_has_section` and `toml_subsections`. `release:50-53` refuses when the tag exists.

- [ ] **`README.md:19`: the documented install path 404s.** Option B fetches
      `releases/latest/download/nutshell.tar.gz`, and `release:83-86` uploads no asset, which
      `release:15-17` states outright ("No built artifacts"). Fix or delete it, and add `./install` as
      a documented step: it exists (`install:5-13`) but appears only as a filename in the tree listing
      at `:69`.

## Follow-ups from the same review, not release blockers

- [ ] **12 of 21 modules have zero tests**: `array, check-runner, color, fs, http, log, os, prompt,
      string, text, xdg`, and `test` beyond its harness file. 316 `#[pub]` functions against ~109
      `#[test]`. `string`, `text`, `fs`, `array` are core primitives, and `lib/test.sh:12` uses
      `str_trim` as its worked example while `string` has no tests. The suite only ever runs under
      bash 5, so the whole failure region of the first blocker is untested by construction. This is
      the reason both of the blockers above survived to a review rather than a coverage gap to
      schedule.
- [ ] **`README.md:488-492` describes the world before `./install` shipped**, presenting
      `#!/usr/bin/env nutshell` as needing "global installation or setup steps for every developer" and
      offering that as a reason not to use it. That shebang is how this library's most prominent
      consumers run.
- [ ] **`lib/toml.sh:8` and `lib/deps.sh:8` declare a line ceiling nothing enforces.**
      `check_file_size.sh:84` greps for `#[[:space:]]*#\[allow\(loc = ([0-9]+)\)\]`, requiring two
      hashes, while both files use the one-hash attribute form. So `toml.sh` declares 400 and is 546,
      `deps.sh` declares 450 and is 780, and either number could be anything. The repo already ships a
      correct reader for the one-hash form (`attr_arg`); the check hand-rolls a grep instead.
- [ ] **`./check` exits 0 with three warnings** (`file_size`, `function_duplication`,
      `public_api_docs`) at 5m29s and 95% CPU, and `release:57` gates on it. Warnings that cannot fail
      are not gates.
- [ ] **README carries no "A note on coding agents"** while the repo ships
      `.github/copilot-instructions.md`.
- [ ] **Operational, outside this repo:** `~/.local/bin/nutshell` symlinks into a working tree, so
      every consumer using the shebang executes whatever branch that checkout happens to sit on.

## Open, and not the reviewer's to decide

- [ ] **The version scheme.** `0.2.0` reads as a semver stability claim this repo does not make, where
      the workspace convention puts pre-1.0 at `0.0.0-dNN` with the first stable at `0.0.1`. Either
      keep `0.2.0` as a declared exception or renumber before more tags accrue. Cheaper now than per
      release.

## v0.2.0

- [x] Core library modules (os, log, deps, fs, text, json, http, etc.)
- [x] Lazy-init stub pattern for tool-dependent functions
- [x] Directory structure (init, bin/, lib/, examples/, tests/)
- [x] `init` entry point, `bin/nutshell` interpreter, `use` for loading
- [x] QA system with built-in checks, config-driven via nut.toml
- [x] Attributes (`#[pub]`, `#[test]`, `#[allow(...)]`), read by `attr`
- [x] Test harness: `#[test]` functions, assertions, `./test`
- [x] Module graph with cycle, declaration, visibility and reachability checks
- [x] `cli` subcommand dispatch, `git` repository reading
- [x] External libraries via `nut.toml` deps, pinned by `nut.lock`
- [ ] Tag v0.2.0 release
- [ ] `cli` and `git` ship with no consumer in this repository. They exist for
      the pr-review and work-in-mockspace tools being built on nutshell, which
      is where they get one. `bin/nutshell` is not that consumer: it takes a
      script path and flags, not subcommands, and routing it through a
      subcommand dispatcher would be a worse interface, not dogfood.
- [ ] Create GitHub release with tarball

## High Priority

### Documentation
- [ ] Add `os_type` alias for `os_name` (consistency with docs)
- [ ] Update DESIGN.md to reflect new structure
- [ ] Add CHANGELOG.md
- [ ] Add CONTRIBUTING.md

### QA System
- [x] Checks live in examples/checks/ and run from the project root
- [ ] Add custom_checks support testing
- [x] Split lib/json.sh along its backend seam into json/impl/
- [ ] Six modules sit between 336 and 426 LOC against a 300 warn: check-runner,
      color, deps, http, prompt, toml. Each wants its own seam followed.

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
- [x] QA framework (lib/check-runner.sh)
- [x] Built-in QA checks (examples/checks/check_*.sh)
- [x] Config templates (empty, default, tough)
- [x] JSON Schema for nut.toml
- [x] New init/use pattern for module loading
- [x] bin/nutshell interpreter
- [x] Restructured from core/ to lib/
- [x] Checks in examples/checks/, tests in tests/
- [x] README with usage patterns and examples

## Where the linting goes, and what the attributes are

op, verbatim:

> I also notice the current nut.toml has duplicated patterns for detecting
> allowing bypassing the loc stuff. I think we want to write a
> viola-config-compliant linting engine into the nutshell (optionally sourced),
> so machines that can just call viola from path can, but those that don't have
> it, can run the nutshell's own linting engine specifically for bash and
> nutshell, that only allows or works with bash and nutshell syntax and is
> perhaps simplified too, but is viola compliant in config shape as well as
> behaviour (in terms of output from input, not in terms of the same internal
> steps to get there). Then the lintings and such move on to viola.toml (and if
> viola doesn't yet support toml, it should, so that's a thing you should add
> to agenda for someone to pick up later; it already has and supports json
> format though, pretty sure, so that same schema should translate painlessly
> into toml). This way the nut.toml is a bit cleaner and doesn't include
> linting things. Also, I think the #[pub] etc should be some reusable nutshell
> plugin/extension so depending on some workflow lib could give them, and
> having [plugins] or [extensions] with default-attributes = enabled or
> something like that could just make all that boilerplate happen, which all my
> nutshell libs pretty much use by default anyway

The duplication he spotted is real: `nut.toml:48` and `nut.toml:115` carry the
same regex for the loc escape hatch, and `trivial_wrapper` is named at both
`:45` and `:101`. One pattern, two homes, and nothing keeps them in step.

- [ ] **A linting engine in nutshell, optional to source, viola-compliant by
      config and by behaviour.** Same config in, same findings out; the steps
      between are its own. It handles bash and nutshell only, and may be
      simpler for it. A machine with `viola` on PATH calls that instead.
- [ ] **Lint configuration moves to `viola.toml`.** `nut.toml` keeps what it is
      for and stops carrying two copies of one pattern.
- [ ] **Attributes become a plugin.** `#[pub]`, `#[allow(...)]` and the rest are
      a reusable extension rather than something every library restates.
      `[plugins]` or `[extensions]` with something like
      `default-attributes = enabled` turns the boilerplate on, since every
      nutshell library here wants it anyway.

### For whoever picks up viola

- [ ] **viola should read TOML.** It has JSON already, so the schema carries
      over without redesign. Filed here because there is no agenda tool on this
      machine to file it in; move it when there is.

## Left from the module-system review

Acted on: the stub recursion, the two guards keyed differently, super:: cached
globally, the bare-`use` bypass, the missing third layout, the two precedence
orders, the checker's second parser, the symlink key. Written down instead:

- [ ] **`extern_resolve` runs inside a command substitution, so its memo dies
      in the subshell.** `lib/extern.sh` writes `_EXTERN_RESOLVED[...]` and
      `use` calls it as `$( )`, so every resolution pays full price. Measured
      at 421ms for eight modules in the review. The fix is a resolver that
      returns through a variable rather than through stdout, which touches
      every caller.
- [ ] **A declared path is not confined to the library root.** `../../etc/x`
      in a `lib.nut` resolves. A declaration is written by the library's own
      author, so this is not a trust boundary, but it should still refuse.
- [ ] **Duplicate names inside one `lib.nut` are accepted, first wins.** The
      migration refuses to write one; a hand-edited file can still have it.
- [ ] **`nutshell_modules` changed its output from names to paths.** Nothing
      in the tree reads it. Decide which it is and say so.

## Pinning, as op wants it

op, verbatim:

> imports, as well as the nutshell binary itself, should be pinnable by git ref
> (if a git dep), or a version (basically a git ref; tag). So if `dev` branch
> is pinned, that means it's always the remote head on dev. So if the current
> one is stale, it's evident on each call and will be fetched and updated as
> per the pin. We should do the same thing as `renki` does, but just in bash.

### The intent

**A branch pin is a moving pin.** `ref = "dev"` means the remote head of `dev`,
now, on every call: staleness is visible each time and the dependency is
fetched and updated to match. A tag or a sha is the fixed kind. Both are "a git
ref", and the distinction is whether the ref moves, not a separate concept.

**Nutshell itself is pinnable the same way.** The interpreter is a dependency
like any other and takes the same declaration.

**`renki` is the reference**, in bash rather than whatever it is written in.
The intent is the semantics; how much of renki's shape carries over is a
judgement to make after reading it.

op, on what the lockfile is then for:

> lockfile should hold back. But if the pin is the branch itself, it's
> implicitly meaning its head. If the pin is a specific commit or tag, then
> that's actually something that needs to be held back by the lockfile. And
> lockfile itself should obviously update to match each time the head moves and
> the pinned branch head is something new

So the lockfile has two jobs and which one it is doing depends on the pin. On a
commit or a tag it holds the checkout back, which is what a lockfile is for. On
a branch it records what the head resolved to and is rewritten every time that
moves, which makes it a report rather than a pin.

## A library that is not at the root of its repository

op:

> also that means nutshell should be able to depend on a nut library that is
> not in the root of the repo, but has a path from the root. I think git has a
> standard notation for this which should be expressible and respected on
> nutshell's side

### The intent

**A dependency is a directory, not necessarily a repository.** One repository
may carry several nut libraries and a consumer names the one it wants.

On the notation: git itself has none. There is no URL form git understands that
means "this subdirectory of that repository", because git clones repositories
and nothing smaller. What exists is a convention borrowed by other tools, the
double slash of go-getter and Terraform, `https://host/repo.git//sub/dir`, and
it is theirs rather than git's. So the choice is between adopting that
convention because people recognise it, and a second key beside `git` because
it cannot be mistaken for something git will parse. Worth settling before it is
built, and worth checking my claim about git rather than taking it: `git help
clone` and `git help submodule` are where the answer is if there is one.

## A shell renki

op, thinking aloud rather than deciding:

> I wonder if we shouldn't have a renki-sh or some subdir in the renki repo,
> that would contain both a nut.toml for the same concept, same design, same
> impl, but in posix compliant sh/bash. And also a raw entrypoint to source for
> those that don't use nutshell. Could we even write attribute macros in fact,
> on the renki rust side itself, to generate the sh version?

Recorded as a question, not a mandate. What is being asked: whether the pin and
launcher concept should exist twice, in rust and in shell, from one design; and
whether the shell half could be generated from the rust half rather than
written twice. The second is the interesting half and the risky one, since a
generator that produces shell from rust attributes is a project of its own.

Nothing here is scheduled.

## Do not vendor the interpreter

op:

> Hmm. I don't think we should vendor in nutshell in the libs, honestly. Or at
> least if there is a global nutshell interp / bin instance in path, or
> otherwise reachable, it should be used as opposed to the vendored one, which
> avoids random version differences between libs

and, on the guard-every-call shape that comes out of it:

> This problem seems like we shouldn't even have it...
>
> How do things like yarn 2, pnpm, cargo, deno, solve this very problem?

### What those four actually do

None of them keeps a per-project physical copy of anything, and none of them
degrades when a version is wrong.

**cargo** separates the toolchain from the libraries. The toolchain is resolved
by rustup from `rust-toolchain.toml`; the libraries live in one shared
`~/.cargo/registry` and are selected by a lockfile. A crate states the minimum
compiler it needs with `rust-version`, and an older one is a refusal naming the
version, never a build that half works.

**pnpm** keeps one content-addressed store and makes `node_modules` a tree of
links into it, so a version exists once on the machine however many projects
want it. It is strict about declarations: a package may import what it declared
and nothing else.

**yarn 2** goes further and has no `node_modules` at all. One map from every
import to a zip in the shared cache, and an undeclared import is an error.

**deno** has one global cache keyed by URL with a lockfile of hashes, and the
runtime is a single binary the project names.

The two properties they share, and the two we do not have:

1. **One copy per version on the machine, shared, never a copy per project.**
   nutshell already does this for externs: `~/.cache/nutshell/externs/<key>` is
   content-addressed by url and commit. The submodule is the exception, and it
   is the thing that goes stale.
2. **A wrong version is a refusal, not a degradation.** `declare -F thing ||
   skip` at every call site is what a project writes when it does not know what
   version it has. With a declared minimum and honest resolution the guard is
   dead code.

### The intent

**The interpreter is resolved like any other dependency.** A library declares
which nutshell it needs and a launcher on PATH finds or fetches it, the way
rustup does for cargo and the way renki already does for its engine. A global
one that satisfies the declaration is used in preference to anything vendored.

**A dependency declares a minimum, and too old is an error at startup**, naming
the dependency and the pin, rather than a missing function at line 426 of
something the reader was in the middle of.

Both are the same fix from two directions, and both make the guards go away.

## Elevation is one step, not a mode

op:

> in general, I think the elevation should be nutshell api and abstracted so
> that it only ever does a single disjoint thing elevated, then returns back to
> original user. So it's really suDO, not just switching to su like it
> presently behaves
>
> And the reason for being nutshell is that this should apply elsewhere, so we
> don't accidentally end up writing things I expect in my home, to root's home
> etc

### The intent

**One elevated step, then back.** The unit is a single thing that needs root,
run as root, and everything around it stays the user who asked. Not a mode the
process enters and stays in, which is what running a whole task under `sudo`
is: `su` with extra steps.

**It belongs in nutshell**, because the failure it prevents is not one tool's.
Anything that elevates and then keeps going writes the user's files as root:
their state directory, their cache, their config, their journal.

### The evidence, from the machine, today

Fetching an image needs the stick mounted, mounting needs root, so the whole
task ran under `sudo`. The result, on the lifebook:

    ~/.local/state/hulilupteri/journal        orgrinrt orgrinrt   22 lines
    /run/hulilupteri/home/journal             root     root       10 lines

Two histories of one tool, split by which user happened to run it, and the
second one the user can no longer write: `test -w` says no. The next ordinary
run either fails to record what it did or silently does not.

Nothing was misconfigured. The tool asked for root for a reason and then kept
it, which is the whole of the defect.

### What the API has to do

- run one command as root and return, with the caller's identity unchanged
- try `sudo -n` first, so a machine needing no password never shows a prompt
- refuse rather than hang where there is no terminal to answer a prompt on
- name what is being elevated, so the sudo prompt and the log both say it
- give a caller the real user's home, name and id even while the one step runs,
  so nothing computes a path from `$HOME` at the wrong moment
- say plainly when it cannot elevate, rather than falling back to trying anyway

## The store, and versions coexisting

> As for the versions of nutshell. We should have it similar as rustup or
> pretty much any similar. Several versions can and will coexist on one machine
> and instead of failing, we download the correct one and store it as a
> "toolchain". Same as renki does. Unless this is how it works already. If so,
> I don't understand how the versions can give so much trouble?

> Really seems to me we should keep the libs anything depends on centrally too
> like pnpm or yarn2. Nutshell itself just as one of them.

**The intent: one central store, versions coexist, a missing one is a download
rather than a failure, and the interpreter is an entry in that store like
anything else.** The rustup and renki comparisons are the shape being asked
for, not a requirement to copy either.

It was not how it worked. Externs were already central and content-addressed;
the interpreter was the exception, resolved by picking from what the machine
happened to have and never fetching. That is the whole of the version trouble:
`0.4.0` exists only on `dev`, nothing has tagged it, so no amount of resolving
could find it and the fallback to the vendored copy fired every run.

Settled by this work: a toolchain store keyed by version, a fetch when the
asked-for version is not there, and both externs and toolchains under one store
root. The externs moved from the cache directory to the data directory in the
same change, because a cache is something a cleaner may delete at any moment
and this is where every project's dependencies actually live.

## renki-sh, or generating shell from the Rust

> You know I feel more and more stern about us doing renki-sh or make nutshell
> build a copy of the rust one natively and use that. It's no sense to reinvent
> the wheel here. Nutshells idea is platform agnostic form that should
> technically run anywhere with posix compliant or close enough shell and
> utils. So this is why I have been and still am hesitant to introduce rust
> into the mix. But if generating the bash-y version isn't likely to work from
> the rust source, I don't know what to say here. It's just redundancy to
> reinvent this specific wheel here

**Two intents, and they are both mandates.** One: nutshell stays runnable on a
POSIX-ish shell with no Rust anywhere in its chain. Two: the pin and lock
semantics are not to be invented twice and left to drift apart. The vehicles
offered, a `renki-sh` subdirectory and Rust attribute macros emitting shell, are
proposals rather than either intent.

### What the overlap actually is

Counting non-comment lines, renki is 1500 of source across ten modules. What
touches this problem at all:

| module | lines | overlaps |
| --- | --- | --- |
| `pin.rs` | 171 | branch to rev via `git ls-remote`, TTL cached |
| `manifest.rs` | 72 | the pin schema, a TOML shape |
| `discover.rs` | 132 | walk up for the config file |
| `cache.rs` | 147 | key to directory, payload is a cargo build |

`tool.rs`, `engine.rs`, `registry.rs` and `selfupdate.rs`, 940 lines between
them, are about cargo, crates.io, Rust toolchains and keeping a launcher binary
current. None of it has a nutshell counterpart. Of the four above, `cache.rs`
produces `cargo install` argument lists and `pin.rs` produces build attempts, so
the shared part of each is smaller than its line count.

The shared idea is about a hundred lines: branch resolves to its head, a rev or
tag is held by the lock, resolution is cached with a TTL, the manifest is found
by walking up. `lib/extern.sh` is 311 lines and already implements it.

### On generating the shell from the Rust

It does not pay, and the reason is not effort. The annotated functions would
have to avoid generics, traits, iterators, `?`, `Result`, borrows, `PathBuf`,
`SystemTime` and everything else in `std` with no shell counterpart. What
remains is not Rust: it is a small language written inside Rust, compiled by a
backend nobody else maintains, and every future edit to those functions has to
stay inside a subset the compiler enforces nowhere. That is a compiler backend
built to avoid a hundred lines of shell.

### What to do instead: share the spec, not the code

The redundancy that costs anything is semantic, not textual. Two
implementations of one spec is ordinary. Two implementations that quietly
disagree about what a branch pin means is the failure, and it is invisible until
somebody's build resolves differently on two machines.

So: the pin semantics get written down once, in renki, as prose plus a
table-driven fixture set. Inputs to expected resolution, including the awkward
ones: an annotated tag that has to peel, a branch head that moved since the
lock, a TTL that has expired with no network, a rev pin the lock holds back, a
tag that moved under a lock. Renki reads the fixtures in a Rust test; nutshell
reads the same file in a shell test. Divergence is a red test in whichever one
drifted, on the day it drifts.

No Rust in nutshell's chain, no codegen backend, and the part with the real
value, the settled semantics and the edge cases somebody had to think of once,
is shared as data rather than copied as prose in two languages.

A `renki-sh` subdirectory remains reasonable on top of that if a Rust project
ever wants the launcher half in shell. It is a second consumer of the same
fixtures, not a way of avoiding the second implementation.
