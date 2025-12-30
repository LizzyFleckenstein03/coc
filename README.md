Toy implementation of the [calculus of constructions](https://en.wikipedia.org/wiki/Calculus_of_constructions).

TODO: Inductive types, Type universes.

See example.coc for examples.

See hurkens.coc for an implementation of Hurken's paradox, which is currently possible due to lack of type universes.

The [bugs]() directory contains test files for various bugs that have been found and fixed.

Usage: `lua coc.lua <file>`

Works in luajit.


Some helpful papers used:
- https://pauillac.inria.fr/~herbelin/publis/univalgcci.pdf
- https://people.csail.mit.edu/jgross/personal-website/papers/academic-papers-local/1-s2.0-030439759090108T-main.pdf
- https://raw.githubusercontent.com/Garbaz/seminar-dependent-types/master/elaboration/elaboration.latex.pdf
