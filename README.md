Toy implementation of the [calculus of (inductive) constructions](https://rocq-prover.org/doc/v8.9/refman/language/cic.html).

Usage: `coc.lua [-i] [-v] [-h] [<file>]`

| option | meaning |
|-|-|
| `-v` | verbose mode, report all definitions from files |
| `-i` | interactive mode, start REPL after executing `<file>` |
| `-h` | show help |
| `<file>` | coc file to run. if no file is given, a REPL is started. |

The REPL can optionally make use of the `readline` package if it is installed.

LuaJIT is supported.

[base.coc](base.coc) contains some basic data types and functions.

[theorems.coc](theorems.coc) contains proofs for some example theorems.

The [bugs](bugs) directory contains test files for various bugs that have been found and fixed.

Type universes are TODO. This means that right now the logic is inconsistent, since type-in-type allows for paradoxes. See [hurkens.coc](hurkens.coc) for an implementation of Hurken's paradox.

Some helpful papers used:
- https://pauillac.inria.fr/~herbelin/publis/univalgcci.pdf
- https://people.csail.mit.edu/jgross/personal-website/papers/academic-papers-local/1-s2.0-030439759090108T-main.pdf
- https://raw.githubusercontent.com/Garbaz/seminar-dependent-types/master/elaboration/elaboration.latex.pdf
