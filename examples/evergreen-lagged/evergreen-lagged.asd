;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(asdf:defsystem "evergreen-lagged")
(asdf:defsystem "evergreen-lagged/apk"
  :defsystem-depends-on ("evergreen-compose-build")
  :class "evergreen-compose-build:compose-apk"
  :build-operation "egcl-apk-asdf:apk-op"
  :version "0.0.1"
  :apk-package "dev.egcl.compose.evergreenlagged"
  :apk-label "Evergreen Lagged"
  :apk-debuggable t
  :components ((:static-file "app.lisp")
               (:static-file "data.lisp")
               (:static-file "NOTICE")))
