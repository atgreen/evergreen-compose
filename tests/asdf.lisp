;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; Run after installing egcl-target-android with the egcl-apk-asdf system.
(require :asdf)
(asdf:load-asd (truename (merge-pathnames "../evergreen-compose.asd" *load-truename*)))
(asdf:test-system "evergreen-compose")
(unless (plusp evergreen-compose::*checks*) (error "ASDF did not execute the test suite"))

(load (merge-pathnames "compose-packaging.lisp" *load-truename*))
(evergreen-compose-build::bundle-entries) ; verify every distributed runtime checksum

;; Verify the actual ASDF components against the loader, including the flat
;; names used in an APK. This catches packaging drift without a device.
(let* ((files (egcl-apk-asdf::system-asset-files (asdf:find-system "evergreen-compose/apk")))
       (names (append (mapcar #'file-namestring files)
                      (mapcar (lambda (entry) (subseq (car entry) 7))
                              (evergreen-compose-build::framework-assets))))
       (order (with-open-file (s (asdf:system-relative-pathname "evergreen-compose" "load-order.sexp"))
                (read s))))
  (unless (= (length names) (length (remove-duplicates names :test #'equal)))
    (error "APK assets have colliding basenames"))
  (dolist (file files)
    (unless (probe-file file) (error "Missing APK asset: ~A" file)))
  (dolist (name (append (getf order :host) (getf order :target)))
    (let ((asset (concatenate 'string (file-namestring name) ".lisp")))
      (unless (member asset names :test #'equal)
        (error "Loader references unpackaged asset: ~A" asset))))
  (dolist (name '("app.lisp" "evergreen-compose.lisp" "load-order.sexp" "LICENSE" "LICENSE.classpath-exception" "LICENSE-APACHE" "LICENSES.md"))
    (unless (member name names :test #'equal) (error "Missing distribution asset: ~A" name)))
  (format t "~D APK assets match the loader~%" (length names)))
