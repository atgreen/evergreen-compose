;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; One load order for desktop tests and flat APK assets.
(:host ("package" "ffi" "state" "live" "utf8" "compose" "services")
 :target ("jni" "java" "android-services" "compose-host"))
