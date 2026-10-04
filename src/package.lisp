;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; Evergreen Compose: Lisp applications, shared native Compose controls.
(defpackage :evergreen-compose
  (:use :cl)
  (:export :ui :run-compose-app :invalidate
           :http-get :fetch-feed :open-url
           :*state-store* :save-state :restore-state
           :start-live-repl :stop-live-repl :live-repl-poll :*live-log* :*slynk-port*)
  (:documentation "Immutable Lisp UI trees rendered by the shared Android Compose runtime."))
