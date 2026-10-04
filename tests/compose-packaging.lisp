;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(require :asdf)
(asdf:load-asd (truename "evergreen-compose-build.asd"))
(asdf:load-system "evergreen-compose-build")
(let ((bytes (evergreen-compose-build::compose-manifest :package "org.example.one")))
  (assert (> (length bytes) 100))
  (assert (= 1 (evergreen-compose-build::code-attribute-count bytes #xffffffff)))
  ;; API 33's public attribute must be in the resource map, and the application
  ;; must opt in to dispatch Back to Compose instead of the legacy key path.
  (assert (search #(108 6 1 1) bytes))
  (let ((egcl-apk::*android-attributes*
          (append egcl-apk::*android-attributes* '(("enableOnBackInvokedCallback" . #x0101066c)))))
    (assert (= 1 (evergreen-compose-build::manifest-attribute-count bytes "enableOnBackInvokedCallback" #xffffffff)))))
(handler-case (progn (evergreen-compose-build::compose-manifest :package "bad") (error "Accepted bad package"))
  (error (e) (assert (search "Invalid Android package" (princ-to-string e)))))
(format t "Compose manifest checks passed~%")

;; An invalid override must fail closed before APK assembly or signing.
(let* ((root (merge-pathnames (format nil "evergreen-compose-bundle-test-~A/" (gensym)) (uiop:temporary-directory)))
       (evergreen-compose-build:*compose-runtime-directory* root))
  (unwind-protect
       (progn
         (ensure-directories-exist (merge-pathnames "bundle.sexp" root))
         (labels ((reject (spec message)
                    (with-open-file (out (merge-pathnames "bundle.sexp" root) :direction :output :if-exists :supersede)
                      (prin1 spec out))
                    (assert (handler-case (progn (evergreen-compose-build::bundle-entries) nil)
                              (error (e) (search message (princ-to-string e)))))))
           (reject '(:protocol 99 :min-sdk 28) "Unsupported Compose runtime")
           (reject '(:protocol 1 :min-sdk 28 :files (("../classes.dex" "bad"))) "Unsupported Compose bundle entry")
           (reject '(:protocol 1 :min-sdk 28 :files nil) "lacks classes.dex")
           (with-open-file (out (merge-pathnames "classes.dex" root) :direction :output) (write-string "corrupt" out))
           (reject '(:protocol 1 :min-sdk 28 :files (("classes.dex" "bad"))) "checksum mismatch")))
    (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore)))
(format t "Compose bundle rejection checks passed~%")

(let* ((entries '(("classes.dex" . #(1))
                  ("lib/arm64-v8a/libmaplibre.so" . #(2))
                  ("lib/x86_64/libmaplibre.so" . #(3))))
       (runtime '(("lib/arm64-v8a/libegcl_android.so" . #(4))))
       (selected (evergreen-compose-build::compose-entries-for-runtimes entries runtime)))
  (assert (= 2 (length selected)))
  (assert (assoc "classes.dex" selected :test #'equal))
  (assert (assoc "lib/arm64-v8a/libmaplibre.so" selected :test #'equal))
  (assert (not (assoc "lib/x86_64/libmaplibre.so" selected :test #'equal))))
(format t "Compose bundle ABI selection checks passed~%")
