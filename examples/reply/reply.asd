;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(asdf:defsystem "reply")
(asdf:defsystem "reply/apk"
  :defsystem-depends-on ("evergreen-compose-build")
  :class "evergreen-compose-build:compose-apk"
  :build-operation "egcl-apk-asdf:apk-op"
  :version "0.0.1"
  :apk-package "dev.egcl.compose.reply"
  :apk-label "Reply"
  :apk-debuggable t
  :components ((:static-file "app.lisp")
               (:static-file "data.lisp")
               (:static-file "NOTICE")
               (:static-file "ASSETS_LICENSE")
               (:static-file "avatar_0.jpg")
               (:static-file "avatar_1.jpg")
               (:static-file "avatar_10.jpg")
               (:static-file "avatar_2.jpg")
               (:static-file "avatar_3.jpg")
               (:static-file "avatar_4.jpg")
               (:static-file "avatar_5.jpg")
               (:static-file "avatar_6.jpg")
               (:static-file "avatar_7.jpg")
               (:static-file "avatar_8.jpg")
               (:static-file "avatar_9.jpg")
               (:static-file "avatar_express.png")
               (:static-file "paris_1.jpg")
               (:static-file "paris_2.jpg")
               (:static-file "paris_3.jpg")
               (:static-file "paris_4.jpg")))
