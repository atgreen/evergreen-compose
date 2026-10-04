;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(asdf:defsystem "evergreen-caster")
(asdf:defsystem "evergreen-caster/apk"
  :defsystem-depends-on ("evergreen-compose-build")
  :class "evergreen-compose-build:compose-apk"
  :build-operation "egcl-apk-asdf:apk-op"
  :version "0.0.1"
  :apk-package "dev.egcl.compose.evergreencaster"
  :apk-label "Evergreen Caster"
  :apk-debuggable t
  :apk-permissions ("android.permission.INTERNET")
  :components ((:static-file "app.lisp")
               (:static-file "data.lisp")
               (:static-file "feed.lisp")
               (:static-file "NOTICE")
               (:static-file "cover_1.png")
               (:static-file "cover_2.png")
               (:static-file "cover_3.png")
               (:static-file "episode_1.txt")
               (:static-file "episode_1.wav")
               (:static-file "episode_2.txt")
               (:static-file "episode_2.wav")
               (:static-file "episode_3.txt")
               (:static-file "episode_3.wav")
               (:static-file "episode_4.txt")
               (:static-file "episode_4.wav")
               (:static-file "episode_5.txt")
               (:static-file "episode_5.wav")
               (:static-file "episode_6.txt")
               (:static-file "episode_6.wav")))
