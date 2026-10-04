;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;; Regenerate native test fixtures from the actual Lisp application, with EGCL.
(load "load.lisp")
(let ((*package* (find-package :cl-user)))
  (with-open-file (in "examples/catalog/app.lisp")
    (read in)
    (loop for form = (read in nil :eof) until (eq form :eof) do (eval form))))
(with-open-file (out "android/compose/src/androidTest/assets/catalog.jsonl"
                     :direction :output :if-exists :supersede)
  (labels ((snapshot (name)
             (write-string "{\"name\":" out)
             (evergreen-compose::compose-json-string name out)
             (write-string ",\"snapshot\":" out)
             (write-string (evergreen-compose::compose-snapshot (evergreen-compose::make-compose-session) (evergreen-compose-catalog::view)) out)
             (write-line "}" out)))
    (dolist (section evergreen-compose-catalog::*sections*)
      (setf evergreen-compose-catalog::*section* section)
      (snapshot section))
    (dolist (overlay '(:date :date-range :time :dialog :alert :sheet))
      (setf evergreen-compose-catalog::*overlay* overlay)
      (snapshot (string-downcase overlay)))))
(format t "Exported catalog device fixtures.~%")
