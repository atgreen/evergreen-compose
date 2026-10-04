;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(asdf:defsystem "evergreen-compose-build"
  :description "Compose APK packaging in Common Lisp; no Android build tools required"
  :license "GPL-3.0-or-later WITH Classpath-exception-2.0"
  :version "0.0.1"
  :depends-on ("egcl-apk-asdf")
  :components ((:file "packaging/compose-apk")))
