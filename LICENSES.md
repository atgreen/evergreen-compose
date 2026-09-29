# Third-party material

## Material Design Icons

`src/icons-material.lisp` is generated from [Material Design
Icons](https://github.com/google/material-design-icons) by `tools/make-icons.sh`.

Those icons are Copyright Google, licensed under the **Apache License, Version
2.0**. The full text is at <https://www.apache.org/licenses/LICENSE-2.0>.

The generated file contains the icons' path geometry, converted from the
project's 24px SVG sources into Bliss path commands. Nothing else in Bliss is
derived from it.

Regenerating, with a checkout of that repository:

```sh
tools/make-icons.sh ~/git/mobile/material-design-icons src/icons-material.lisp \
    search menu close check add remove …
```

Only the icons named on the command line are converted, so an application ships
the ones it uses rather than all two thousand.
