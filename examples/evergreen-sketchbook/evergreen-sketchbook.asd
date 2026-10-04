;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; App developers package Lisp and the prebuilt runtime; no Android SDK needed.

(asdf:defsystem "evergreen-sketchbook")

(asdf:defsystem "evergreen-sketchbook/apk"
  :defsystem-depends-on ("evergreen-compose-build")
  :class "evergreen-compose-build:compose-apk"
  :build-operation "egcl-apk-asdf:apk-op"
  :version "0.0.1"
  :apk-package "dev.egcl.compose.evergreensketchbook"
  :apk-label "Evergreen Sketchbook"
  :apk-debuggable t
  :components ((:static-file "app.lisp")))
