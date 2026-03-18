This is a work-in-progress bytecode compiler for the Lox programming language
from [_Crafting Interpreters_](https://www.craftinginterpreters.com/) by Robert Nystrom.
It's based on `clox`, the bytecode interpreter written in C and described in the book,
but using idiomatic Zig features where possible; e.g. the scanner uses `std.io.{Reader,Writer}`
in place of pointers (or slices).

I also wrote a tree-walking interpreter for Lox in Janet: https://github.com/pvsr/janet-lox.
