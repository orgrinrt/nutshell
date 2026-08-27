# What a `when=` row costs at module resolve time

A predicate decides which file a module is sourced from, and it is evaluated on
every `use` of that module before anything is parsed. So it sits in front of the
whole library and anything it costs, everything pays.

## The result

A predicated row resolves at about **113%** of a plain one, and two joined by a
plus at about **117%**. Reproducible across runs; a row carrying only a
visibility is inside the noise, so the cost is the predicate rather than the
extra column.

At the sizes that matter this is nothing: a real manifest is around thirty rows
and a program does a handful of `use` calls. The number is here so that a later
change to the predicate vocabulary has something to move against.

## What the memo does and does not do

`_nut_when` remembers `have:` answers, because `command -v` is the only word in
the vocabulary that costs anything. `shell:` and `env:` are a `case` on a
variable and are deliberately not cached: both can change, and caching them made
a test that drives the bash floor through its branches read one answer for every
version it tried.

**The memo reaches one lookup and no further.** Every caller of
`_lib_nut_lookup` wraps it in a command substitution, so the cache is written in
a subshell and dies with it. A module with several predicated rows shares an
answer between them; two `use` calls of the same module do not.

That was written into the code as a 14%-to-noise improvement before it was
measured, and it is not one. The numbers here are the same with the memo and
without it.

## The larger cost, which is not the predicate

**The fork around the lookup.** Every resolve is a command substitution, paid by
every module whether it carries a predicate or not. Returning through a variable
instead of by printing would remove it, which is five call sites and its own
change, and this bench is the instrument to price it with.

## What is not established here

Anything about a shell that is not this one. Every number is bash 5.3 on one
host, and the whole point of the predicate is machines that are not this one.
POSIX `sh` has no associative array, so the memo above does not survive that
conversion in this form, and what replaces it wants measuring rather than
assuming.
