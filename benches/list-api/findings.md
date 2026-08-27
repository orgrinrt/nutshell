# What the shipped list costs, floor against bash

`benches/array-api` priced the techniques. This prices what got built on top of
one, both arms driving the shipped surface so the number carries the function
boundary and the `eval` a named list needs.

## The result

| load | floor against bash, 400 | at 2000 |
|---|---|---|
| walked with `list_each` | 123% | 132% |
| walked by the caller over `list_ref` | 148% | 357% |

**Use `list_each`.** It is cheaper at both sizes and the gap widens with the
list, which is the opposite of what was expected when the surface was designed.

## The bench overturned the technique bench, and the reason is worth keeping

`benches/array-api` concluded that the list should be one string with the shell
field-splitting it, at 117% of bash's own `declare -a`. Built that way, the
shipped floor measured **165% at four hundred elements and 468% at two
thousand**: superlinear, on code whose technique had measured flat.

The cause is one thing that bench could not see. It measured a list held in a
**local variable**, where appending is `s+=` and bash extends the string in
place. A list with a **name** cannot use `+=`, because the assignment has to go
through `eval`, and that rebuilds the whole string on every push. Appending
becomes quadratic and the technique's headline number stops applying.

So the storage was inverted: one variable per position, with the string built on
demand for a caller that wants to walk it. Push, index and length are each one
operation regardless of length, and the same code then measured **123% and
132%**, roughly flat.

**A technique measured on a local does not transfer to the same technique on a
named thing**, and the name is not a detail: it is what forces the `eval`, and
the `eval` is what changes the complexity.

## What is still quadratic, and why it stays

`list_ref` builds the string by concatenating, which is the same O(n) copy per
element the string storage had. Measured directly under `dash`, appending to a
plain variable takes 7ms at 500 elements, 13 at 1000, 37 at 2000 and 123 at
4000, roughly quadrupling per doubling.

There is no POSIX way around it. `+=` is bash, and every route that would build
the string in one pass needs the elements in the positional parameters first,
which is itself quadratic to fill one at a time.

So the string is the interchange form and not the walking form, and the surface
says so: `list_each` walks the slots directly and builds no string at all.

## An earlier fix, kept because it is the same lesson one rung down

Before the storage was inverted, `list_read` re-split the whole list on every
call. Two hundred reads over four hundred elements is eighty thousand field
splits to answer two hundred questions, and it was the entire gap between the
technique's 117% and the shipped 282%. Splitting once and fanning out into
slots took it to 165%.

That fix is gone, because inverting the storage made the fan-out the storage.
It is recorded here because it is the same mistake in miniature: work that does
not change between calls, done at every call.

## These numbers were re-taken

A name check was later added to every entry point of both halves, and the
tables above are from after it. The earlier ones, 128% and 141%, measured code
that no longer exists. A number without its conditions does not travel, and the
code it was taken against is one of its conditions.

## What is not established here

**Whether any of this matters where it is paid**, which is a question about
nutshell's own hot paths and needs a bench per path.

**What it costs under a real POSIX shell.** Both arms run under bash, so the
technique is the variable rather than the shell. The concat measurement above is
the one number here taken under `dash`, and it is a fact about the shell rather
than about the surface.

**The separator limit.** A value holding `\037` is refused rather than escaped,
on both halves, so a caller that needs one has no route. Escaping costs a pass
over every element in each direction and nobody has measured it, because no list
in nutshell has ever carried that character.

Every number is single-threaded, on one host, at the sizes stated.
