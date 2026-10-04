;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(asdf:defsystem "evergreen-news")
(asdf:defsystem "evergreen-news/apk"
  :defsystem-depends-on ("evergreen-compose-build")
  :class "evergreen-compose-build:compose-apk"
  :build-operation "egcl-apk-asdf:apk-op"
  :version "0.0.1"
  ;; Keep the installed sample identity so this build updates it in place.
  :apk-package "dev.egcl.compose.jetnews"
  :apk-label "Evergreen News"
  :apk-debuggable t
  :apk-permissions ("android.permission.INTERNET")
  :components ((:static-file "app.lisp")
               (:static-file "data.lisp")
               (:static-file "feed.lisp")
               (:static-file "NOTICE")
               (:static-file "post_1.png")
               (:static-file "post_1_thumb.png")
               (:static-file "post_2.png")
               (:static-file "post_2_thumb.png")
               (:static-file "post_3.png")
               (:static-file "post_3_thumb.png")
               (:static-file "post_4.png")
               (:static-file "post_4_thumb.png")
               (:static-file "post_5.png")
               (:static-file "post_5_thumb.png")
               (:static-file "post_6.png")
               (:static-file "post_6_thumb.png")))
