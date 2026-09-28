# Bliss

A UI framework for [TorCL](https://github.com/atgreen/bliss), for Android.

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
torcl --load run-tests.lisp                       # 47 checks
torcl --load examples/run.lisp                    # prints a frame as ASCII art
```

On a phone, as a real APK:

```sh
torcl-android-new demo --template egl --package org.bliss.demo
tools/sync-assets.sh demo        # flattens src/ into demo/assets + bliss.lisp
make -C demo apk
adb install -r --user 0 demo/build/*/debug/app.apk
```

`--user 0` is deliberate and is not a default you should drop: on a device with a
work profile, an unqualified `adb install` can put the app under a user you did
not choose.

## What this is not, yet

Text is a 5x7 bitmap font. That is enough to build and test the layout and raster
layers against something legible, and it is **not** the text story — real text is
Unicode segmentation, bidi, shaping, fallback and line breaking, which means
HarfBuzz and ICU through the FFI.

There is no accessibility, no IME, no scrolling, no gesture recognition, no
animation, and layout is one pass of intrinsic sizing with no constraints
travelling down. Those are known, not overlooked.

## Licence

MIT OR Apache-2.0.
