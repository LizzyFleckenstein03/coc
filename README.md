Toy implementation of the [calculus of (inductive) constructions](https://en.wikipedia.org/wiki/Calculus_of_constructions).

Usage: `lua coc.lua [-i] <file>` or `lua coc.lua` for a REPL.

The REPL can optionally make use of the `readline` package if it is installed.

LuaJIT is supported.

[base.coc](base.coc) contains some basic data types and functions.

[theorems.coc](theorems.coc) contains proofs for some theorems.

The [bugs](bugs) directory contains test files for various bugs that have been found and fixed.

Type universes are TODO. This means that right now the logic is inconsistent, since type-in-type allows for paradoxes. See [hurkens.coc](hurkens.coc) for an implementation of Hurken's paradox.

Some helpful papers used:
- https://pauillac.inria.fr/~herbelin/publis/univalgcci.pdf
- https://people.csail.mit.edu/jgross/personal-website/papers/academic-papers-local/1-s2.0-030439759090108T-main.pdf
- https://raw.githubusercontent.com/Garbaz/seminar-dependent-types/master/elaboration/elaboration.latex.pdf
