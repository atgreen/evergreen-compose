;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(asdf:defsystem "evergreen-chat")
(asdf:defsystem "evergreen-chat/apk"
  :defsystem-depends-on ("evergreen-compose-build")
  :class "evergreen-compose-build:compose-apk"
  :build-operation "egcl-apk-asdf:apk-op"
  :version "0.0.1"
  :apk-package "dev.egcl.compose.evergreenchat"
  :apk-label "Evergreen Chat"
  :apk-debuggable t
  :components ((:static-file "app.lisp")
               (:static-file "NOTICE")
               (:static-file "ali.png")
               (:static-file "cupcake.jpg")
               (:static-file "someone_else.jpg")
               (:static-file "sticker.png")))
