# Bliss

A UI framework for [EGCL](https://github.com/atgreen/bliss), for Android.

A view is a list:

```lisp
(column (:padding 6 :gap 5 :background "#101820")
  (label (:text "BLISS" :size 3 :colour "#ffffff"))
  (row (:gap 3)
    (box (:width 14 :height 14 :fill "#e04040"))
    (box (:width 14 :height 14 :fill "#40c040"))))
```

Not a list that *describes* widgets — a list that *is* the interface. It can be
quoted, built with backquote, transformed with `mapcar`, produced by a macro,
printed, read back, and diffed. A user grows a vocabulary for their own domain by
writing functions that return lists; the framework offers no extension point
because it does not need one.

## How it fits together

```
view tree  ──layout──▶  absolute frames  ──render──▶  display list  ──▶  backend
 (data)                  (laid-out)                   (data)            (pixels)
```

The display list is the whole contract with a backend: a flat, ordered sequence
of absolute rectangles, painted back to front. Flat and absolute, so a backend
needs no tree walk and no transform stack. `FLATTEN-TO-RECTS` reduces even text
to rectangles, which is why a backend can be small:

* **`backend/software`** — a plain RGBA buffer with no dependencies at all. This
  is what makes the framework testable on any machine, with no GPU, no window
  system, no emulator and no phone. It writes PPM, and prints frames as ASCII so
  a rendering bug is visible in a terminal or a test failure.
* **`backend/gles`** — six GL entry points. Every operation is an axis-aligned
  rectangle of solid colour, and a scissored clear *is* "fill this rectangle", so
  there is no shader, no texture, no vertex buffer and no glyph atlas. It scales
  with ink rather than with area: the right trade for a UI, the wrong one for a
  photograph.

## Running it

On a desktop, with no Android anything:

```sh
egcl --load run-tests.lisp                       # 455 checks
egcl --load examples/run.lisp                    # prints a frame as ASCII art
```

On a phone, as a real APK, with no Android SDK, JDK or Make -- just `egcl` and
its `egcl-target-android` package:

```sh
egcl --eval '(require :asdf)' \
     --eval '(asdf:load-asd (truename "bliss.asd"))' \
     --eval '(asdf:make "bliss/apk")'
adb install -r --user 0 build/bliss.apk
adb shell am start -n org.bliss.demo/android.app.NativeActivity
```

`assets/app.lisp` names the demo; every `examples/android-*.lisp` is in the APK,
so switching is one line. The load order lives in `load-order.sexp`, which is
also an asset: the device loads what `bliss.asd` packaged and the two cannot
disagree.

`--user 0` is deliberate and is not a default you should drop: on a device with a
work profile, an unqualified `adb install` can put the app under a user you did
not choose.

## The primitives

Five, and only five: `label`, `image`, `box`, `row` and `column`. A `box` with no
children is a rectangle; a `box` with children **stacks** them on the z axis,
which is the one arrangement `row` and `column` cannot express between them — a
badge over an icon, a scrim over a sheet, a spinner centred on a panel.

Everything else is a function. `button` is a `column` with a `label` in it;
`switch`, `progress`, `scroll`, `virtual-list` and the rest are the same. A
handler is a *property*, not a widget, so any node is touchable:

```lisp
(column (:on-press #'choose) …)
```

Icons are path data, converted from Material's SVG sources offline by
`tools/make-icons.sh` — so an icon is Lisp you can print and diff, not an opaque
glyph, and an application ships the ones it names rather than a whole font.

Adding a genuinely new primitive means a `measure-kind` and a `render-kind`
method. Adding a widget means writing a function, and the framework does not need
to be told.

## What this is not, yet

Text is a 5x7 bitmap font in the software rasterizer. On a phone the Canvas
backend draws through `android.graphics.Paint` — Skia, and therefore HarfBuzz and
ICU — so shaping is real there, but line breaking, wrapping and bidi paragraphs
are not: those want `android.text.StaticLayout`.

There is no accessibility, no widget set to speak of (twelve, against Material
3's hundred), no shadows and so no elevation, no icons, and the whole view tree
is rebuilt every frame rather than recomposed. Scrolling has no fling and nothing
survives a rotation. Those are known, not overlooked, and they are filed.

## Licence

MIT OR Apache-2.0.

Bliss also ships geometry generated from [Material Design
Icons](https://github.com/google/material-design-icons), which is Apache-2.0 and
Copyright Google. See [LICENSES.md](LICENSES.md).
