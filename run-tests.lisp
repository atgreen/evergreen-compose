;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(load (merge-pathnames "load.lisp" *load-truename*))
(load (merge-pathnames "tests/tests.lisp" *load-truename*))
(let ((failures (evergreen-compose::run-tests)))
  (if (zerop failures)
      (format t "EVERGREEN-COMPOSE-TESTS-PASS~%")
      (progn
        (format t "EVERGREEN-COMPOSE-TESTS-FAIL~%")
        (error "~D Evergreen Compose checks failed" failures))))
