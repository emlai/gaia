# Gaia

Gaia is a statically duck-typed general-purpose programming language, currently
in very early stages of development. For an introduction, check out the
[language guide](https://emlai.github.io/gaia/guide/basics.html).

## 📖 Usage

- `make` compiles the project.
- `make test` runs the tests.

These are just wrappers around `swift build` and `swift test` that pass the
required flags and environment variables.

To run `gaia` or `gaiac`, the `GAIA_HOME` environment variable needs to point to
the root directory of this project. This can be achieved e.g. with:

    GAIA_HOME=. .build/debug/gaia

## 💕 Contributing

Contributions are welcome and encouraged! Open an issue to start a discussion on
a feature or other non-trivial change. For bug fixes and trivial enhancements
you can skip this step and just submit a pull request.
