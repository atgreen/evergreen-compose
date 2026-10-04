;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; Load Evergreen Compose without ASDF, for a bare `egcl --load load.lisp'.
;;;; The order comes from load-order.sexp, so there is nothing here to keep in
;;;; step with evergreen-compose.asd.
(let* ((here (make-pathname :name nil :type nil :defaults *load-truename*))
       (order (with-open-file (s (merge-pathnames "load-order.sexp" here))
                (read s))))
  (dolist (name (getf order :host))
    (load (merge-pathnames (concatenate 'string "src/" name ".lisp") here))))
