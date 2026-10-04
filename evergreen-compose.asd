;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(in-package :asdf-user)
(let ((host (getf (with-open-file (in (merge-pathnames "load-order.sexp" *load-truename*))
                   (read in)) :host)))
  (eval `(defsystem "evergreen-compose"
           :description "Evergreen Compose: native Android UI from Common Lisp"
           :license "GPL-3.0-or-later WITH Classpath-exception-2.0" :version "0.0.1" :serial t
           :perform (test-op (operation system)
                      (declare (ignore operation))
                      (load (system-relative-pathname system "tests/tests.lisp"))
                      (unless (zerop (uiop:symbol-call :evergreen-compose :run-tests))
                        (error "Evergreen Compose tests failed")))
           :components ((:module "src" :serial t
                         :components ,(mapcar (lambda (name) (list :file name)) host))))))
(defsystem "evergreen-compose/tests"
  :depends-on ("evergreen-compose")
  :components ((:static-file "tests/tests.lisp") (:static-file "tests/compose.lisp")
               (:static-file "tests/samples.lisp") (:static-file "tests/services.lisp")
               (:static-file "tests/sketchbook.lisp"))
  :perform (test-op (operation system)
             (declare (ignore system))
             ;; Dependencies are loaded; share the test performer without
             ;; starting a nested ASDF operation from inside an operation.
             (perform operation (find-system "evergreen-compose"))))
(load-asd (merge-pathnames "evergreen-compose-build.asd" *load-truename*))
(load-system "evergreen-compose-build")
(defsystem "evergreen-compose/apk"
  :defsystem-depends-on ("evergreen-compose-build")
  :class "evergreen-compose-build:compose-apk"
  :build-operation "egcl-apk-asdf:apk-op"
  :version "0.0.1" :apk-package "dev.egcl.compose.demo"
  :apk-label "Evergreen Compose" :apk-version-code 3 :apk-debuggable t
  :components ((:static-file "app" :pathname "examples/hello/app.lisp")))
