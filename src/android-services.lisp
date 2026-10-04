;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(in-package :evergreen-compose)

(setf *live-log* (lambda (message) (android:log message)))

(defun start-live-repl-from-environment ()
  "Opt in with EG_COMPOSE_LIVE_REPL=4005 in egcl.env; a REPL failure leaves the app running."
  (let ((want (egcl-ext:getenv "EG_COMPOSE_LIVE_REPL")))
    (when (and want (plusp (length want)) (null *slynk-listener*))
      (handler-case
          (let ((port (start-live-repl :port (or (parse-integer want :junk-allowed t) 4005))))
            (live-log (format nil "live repl on ~D -- adb forward tcp:~D tcp:~D" port port port)))
        (error (e) (live-log (format nil "live repl failed to start: ~A" e)))))))

(setf *state-store*
      (list :read (lambda () (android:saved-state))
            :write (lambda (text) (android:save-state text))))
