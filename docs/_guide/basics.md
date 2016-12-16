---
title: Basics
order: 1
---

# Basics

## Introduction

Gaia is a programming language with a safe type system to help you prevent
programming errors as early as possible. But unlike most statically typed
languages, Gaia doesn't require you to write out the types of variables,
parameters, and return types. Instead, Gaia will infer these types for you
automatically based on the code that uses them. If it detects that you used an
invalid operation for a given type, you'll immediately get an error message. All
of this happens before your program starts execution, so you can be sure that
your code will not unexpectedly crash when you run it.

## REPL

When invoked without arguments, `gaia` acts as a REPL ([read–eval–print
loop](https://en.wikipedia.org/wiki/Read–eval–print_loop)). This is a quick way
to test simple code:

    $ gaia
    0> 1 + 2 * 3
    7
    1> min(-0.1, 0.1)
    -0.1
    2> print("yo")
    yo

You can exit the REPL with <kbd>ctrl</kbd><kbd>c</kbd> or
<kbd>ctrl</kbd><kbd>d</kbd>.

## Compiler

You can also invoke `gaia` by giving it a source file as an argument. `gaia`
will then compile _and_ execute the given file. For example:

    $ echo 'print("Hello, World!")' > my_script.gaia
    $ gaia my_script.gaia
    Hello, World!

You can also pass `gaia` multiple files. In this case, one of them must be named
`main.gaia`. This is the file that contains top-level code that you want the
program to execute. The rest of the files should contain functions that you can
use from `main.gaia` without explicitly importing those files in your code.

## Printing

As shown above, you can print text using the `print` function from the standard
library:

    print("Hello, World!")

This will print the given string, terminating it with a newline.

## Variables

    six = 6
    seven = 7
    answer = six * seven

Variables in Gaia are currently immutable (mutable variables might be added in
the future). Once a variable has been assigned a value, it cannot be
re-assigned. This makes code very easy to follow, because you know a variable
will always have the same value it started out with. (If it's a local variable,
i.e. declared inside a function, it can of course use a different value the next
time the function is called.)

## `if`-statement

The `if`-statement should look familiar to `if`-statements in C-based languages.
Two differences to note are that the parentheses around the condition are
optional, and that the braces around the bodies are mandatory.

    if 1 < 2 {
        print("yay")
    } else {
        print("weird")
    }

## `if`-expression

The `if`-expression is like the `if`-statement, but a bit more concise, and can
be used in places where an expression is required. Both branches must be
expressions of the same type. For example:

    print(if 1 == 1 then "correct" else "incorrect")

## Functions

Functions are declared using the `function` keyword, as follows:

    function guess(answer) {
        if answer == 42 {
            return "right!"
        } else {
            return "wrong..."
        }
    }

    print(guess(666))
    print(guess(42))

## Operator overloading

Some operators are overloadable. This includes `==`, `<`, `+` (both infix and
prefix), `-` (both infix and prefix), `*`, and `/`. The definition of an
operator overload looks the same as a function definition, except that the
function name is the operator symbol.
