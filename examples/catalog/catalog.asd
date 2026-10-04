;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(asdf:defsystem "catalog")
(asdf:defsystem "catalog/apk"
  :defsystem-depends-on ("evergreen-compose-build")
  :class "evergreen-compose-build:compose-apk"
  :build-operation "egcl-apk-asdf:apk-op"
  :version "0.0.1"
  :apk-package "dev.egcl.compose.catalog"
  :apk-label "Evergreen Controls"
  :apk-debuggable t
  :apk-permissions ("android.permission.INTERNET" "android.permission.ACCESS_NETWORK_STATE" "android.permission.CAMERA")
  :components ((:static-file "app.lisp") (:static-file "sample.png") (:static-file "sample.wav")))
