;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(in-package :evergreen-compose)

(defvar *java* (make-hash-table :test #'equal)
  "Resolved classes and method IDs, which cost ~35us each to look up and never
change. Keyed by name so the call sites read as the Java they are.")

(defun java-class (name)
  (or (gethash name *java*)
      (setf (gethash name *java*) (jni-find-class name))))

(defun java-method (class-name name signature)
  (let ((key (list class-name name signature)))
    (or (gethash key *java*)
        (setf (gethash key *java*)
              (jni-method (java-class class-name) name signature)))))

(defun java-activity ()
  "The Java NativeActivity object: the fourth pointer of the ANativeActivity."
  (let ((native (android:activity)))
    (when (egcl-ffi:null-pointer-p native)
      (error "There is no ANativeActivity yet"))
    (word-at native 3)))
