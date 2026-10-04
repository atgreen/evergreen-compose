;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(asdf:defsystem "evergreen-snack")
(asdf:defsystem "evergreen-snack/apk"
  :defsystem-depends-on ("evergreen-compose-build")
  :class "evergreen-compose-build:compose-apk"
  :build-operation "egcl-apk-asdf:apk-op"
  :version "0.0.1"
  :apk-package "dev.egcl.compose.evergreensnack"
  :apk-label "Evergreen Snack"
  :apk-debuggable t
  :components ((:static-file "app.lisp")
               (:static-file "data.lisp")
               (:static-file "NOTICE")
               (:static-file "almonds.jpg")
               (:static-file "apple_chips.jpg")
               (:static-file "apple_juice.jpg")
               (:static-file "apple_pie.jpg")
               (:static-file "apple_sauce.jpg")
               (:static-file "apples.jpg")
               (:static-file "cheese.jpg")
               (:static-file "chips.jpg")
               (:static-file "cupcake.jpg")
               (:static-file "desserts.jpg")
               (:static-file "donut.jpg")
               (:static-file "eclair.jpg")
               (:static-file "froyo.jpg")
               (:static-file "fruit.jpg")
               (:static-file "gingerbread.jpg")
               (:static-file "gluten_free.jpg")
               (:static-file "grapes.jpg")
               (:static-file "honeycomb.jpg")
               (:static-file "ice_cream_sandwich.jpg")
               (:static-file "jelly_bean.jpg")
               (:static-file "kitkat.jpg")
               (:static-file "kiwi.jpg")
               (:static-file "lollipop.jpg")
               (:static-file "mango.jpg")
               (:static-file "marshmallow.jpg")
               (:static-file "nougat.jpg")
               (:static-file "nuts.jpg")
               (:static-file "oreo.jpg")
               (:static-file "organic.jpg")
               (:static-file "paleo.jpg")
               (:static-file "pie.jpg")
               (:static-file "placeholder.jpg")
               (:static-file "popcorn.jpg")
               (:static-file "pretzels.jpg")
               (:static-file "smoothies.jpg")
               (:static-file "vegan.jpg")))
