;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; Load Evergreen Compose inside an APK.
;;;;
;;;; The order comes from load-order.sexp, which ships as an asset beside this
;;;; file, so the device loads what evergreen-compose.asd packaged and the two cannot
;;;; disagree. APK assets are one flat directory.
(dolist (name (let ((order (with-open-file (s "load-order.sexp") (read s))))
                (append (getf order :host) (getf order :target))))
  (let ((slash (position #\/ name :from-end t)))
    (load (concatenate 'string (if slash (subseq name (1+ slash)) name) ".lisp"))))
