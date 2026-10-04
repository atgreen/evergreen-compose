# Bliss

A UI framework for [Evergreen Common Lisp](https://github.com/atgreen/evergreen), for Android.

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
of absolute operations, painted back to front -- rectangles, rounded
rectangles, shadows, outlines, glyph runs, paths, images and a clip stack. Flat
and absolute, so a backend needs no tree walk and no transform stack. There are
three:

* **`backend/canvas`** -- the one a phone uses. It draws through
  `android.graphics.Canvas`, which is Skia, reached over JNI from Lisp with no
  Java in the application: real text shaping, antialiasing and blur, through
  one foreign call per operation.
* **`backend/software`** -- a plain RGBA buffer with no dependencies at all.
  `FLATTEN-TO-RECTS` reduces even text to rectangles, which is what makes the
  framework testable on any machine with no GPU, no window system, no emulator
  and no phone. It writes PPM and prints frames as ASCII, so a rendering bug is
  visible in a terminal or a test failure.
* **`backend/gles`** -- six GL entry points, every operation an axis-aligned
  rectangle of solid colour. It predates the Canvas backend and is kept for
  the two examples that use it.

Layout is memoised across frames by node identity: a subtree the application
hands back unchanged is not measured again. Each frame is diffed against the
last as operations, and only the operations inside the damaged rectangle
reach the backend -- the cost of a frame is what changed, not what is on
screen.

## Running it

On a desktop, with no Android anything:

```sh
egcl --load run-tests.lisp                       # 463 checks
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
adb logcat -s egcl
```

`assets/app.lisp` names the demo; every `examples/android-*.lisp` is in the APK,
so switching is one line. The load order lives in `load-order.sexp`, which is
also an asset: the device loads what `bliss.asd` packaged and the two cannot
disagree. `EGCL_APK_RUNTIME` points the build at a runtime other than the
installed one.

`--user 0` is deliberate and is not a default you should drop: on a device with a
work profile, an unqualified `adb install` can put the app under a user you did
not choose.

The kitchen-sink demo logs, every ten frames, where the time went -- build,
layout, render, present by operation kind, and the loop's own polling -- and
`examples/android-bench.lisp` times each thing the frame loop does, loaded on
request. Numbers in the source comments are measurements on a Pixel 10 Pro
XL, and they are what the design decisions rest on.

## The primitives

Eight: `label`, `paragraph`, `image`, `path`, `box`, `row`, `column` and
`platform-view`. A `box` with no children is a rectangle; a `box` with children
**stacks** them on the z axis, which is the one arrangement `row` and `column`
cannot express between them -- a badge over an icon, a scrim over a sheet, a
spinner centred on a panel. A `paragraph` is text broken to the width it is
given; a `path` is vector geometry in its own coordinate space; a
`platform-view` is a real `android.view.View` -- a WebView, say -- placed by
the layout and moved when it moves.

Everything else is a function. `button` is a `column` with a `label` in it;
`card`, `app-bar`, `scaffold`, `list-item`, `chip`, `checkbox`, `radio`,
`switch`, `slider`, `tabs`, `snackbar`, `dialog`, `text-field`, `progress`,
`scroll` and `virtual-list` are the same, drawn from a theme with two colour
schemes, a type scale and a spacing scale. A handler is a *property*, not a
widget, so any node is touchable, draggable, flingable, long-pressable:

```lisp
(column (:on-press #'choose :on-drag #'scroll-it) ...)
```

Icons are path data, converted from Material's SVG sources offline by
`tools/make-icons.sh` -- so an icon is Lisp you can print and diff, not an
opaque glyph, and an application ships the ones it names rather than a whole
font.

Adding a genuinely new primitive means a `measure-kind` and a `render-kind`
method. Adding a widget means writing a function, and the framework does not need
to be told.

## On the phone

Beyond drawing, and all without a line of Java or a DEX file: the soft
keyboard and a text field that stays in view when it opens; window insets;
touch with slop, drag chains that hand leftover movement to the scroller
behind, fling with velocity, long press and double tap; what a screen reader
can be told without a view hierarchy to give it (announcements and a screen
description); state that survives the process being killed; and a REPL into
the running application over `adb forward`.

## What this is not, yet

Text wraps, but there is no bidi and no `StaticLayout`, so a paragraph is a
run of lines, not a layout. Accessibility is announcements, not
explore-by-touch: that needs a Java class, and there is none. Touch is one
finger. Rotation is pinned off. The widget set is thirty against Material 3's
hundred. And the whole view tree is rebuilt every frame rather than
recomposed, which the layout memo makes cheap but not free -- on the Pixel a
scroll frame is still tens of milliseconds of layout, and that is the current
front.

## Licence

MIT OR Apache-2.0.

Bliss also ships geometry generated from [Material Design
Icons](https://github.com/google/material-design-icons), which is Apache-2.0 and
Copyright Google. See [LICENSES.md](LICENSES.md).
