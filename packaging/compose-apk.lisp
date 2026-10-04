;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(defpackage :evergreen-compose-build
  (:use :cl)
  (:export #:compose-apk #:*compose-runtime-directory*))
(in-package :evergreen-compose-build)

(defparameter *distribution-root*
  (asdf:system-source-directory "evergreen-compose-build"))
(defvar *compose-runtime-directory* nil)
(defclass compose-apk (egcl-apk-asdf:android-apk) ())

(defun manifest-attributes (bytes name function)
  ;; EGCL API 4 puts its Android attribute names first in the string pool.
  ;; Walk start tags; callbacks receive the typed value and tag header offsets.
  (let ((index (position name egcl-apk::*android-attributes* :key #'car :test #'equal)))
    (unless index (error "Unknown Android manifest attribute: ~A" name))
    (loop for offset = 8 then (+ offset size)
          while (< offset (length bytes))
          for size = (egcl-apk::read-le bytes (+ offset 4) 4)
          do (unless (and (>= size 8) (<= (+ offset size) (length bytes)))
               (error "Invalid manifest chunk"))
             (when (= #x0102 (egcl-apk::read-le bytes offset 2))
               (let* ((extension (+ offset 16))
                      (start (+ extension (egcl-apk::read-le bytes (+ extension 8) 2)))
                      (stride (egcl-apk::read-le bytes (+ extension 10) 2))
                      (count (egcl-apk::read-le bytes (+ extension 12) 2)))
                 (unless (and (= stride 20) (<= (+ start (* count stride)) (+ offset size)))
                   (error "Unsupported manifest attribute layout"))
                 (dotimes (i count)
                   (let ((at (+ start (* i stride))))
                     (when (= index (egcl-apk::read-le bytes (+ at 4) 4))
                       (funcall function bytes (+ at 16) offset extension)))))))))

(defun manifest-attribute-count (bytes name value)
  (let ((count 0))
    (manifest-attributes bytes name
      (lambda (data at tag extension)
        (declare (ignore tag extension))
        (when (= value (egcl-apk::read-le data at 4)) (incf count))))
    count))

(defun code-attribute-count (bytes value)
  (manifest-attribute-count bytes "hasCode" value))

(defun compose-manifest (&rest options)
  ;; Seed the additional public API 33 attribute before EGCL builds its string
  ;; pool/resource map. Append it to the application tag, after the lower IDs.
  (let* ((egcl-apk::*android-attributes*
           (append egcl-apk::*android-attributes* '(("enableOnBackInvokedCallback" . #x0101066c))))
         (bytes (apply #'egcl-apk::manifest options))
         (insert-at nil)
         (record nil))
    (unless (= 1 (code-attribute-count bytes 0))
      (error "Unsupported EGCL manifest layout; expected one hasCode=false attribute"))
    (manifest-attributes bytes "hasCode"
      (lambda (data at tag extension)
        (let ((size (egcl-apk::read-le data (+ tag 4) 4))
              (count (egcl-apk::read-le data (+ extension 12) 2)))
          (setf insert-at (+ tag size)
                record (egcl-apk::bytes
                         (subseq data (- at 16) (- at 12)) ; Android namespace
                         (egcl-apk::u32 (position "enableOnBackInvokedCallback"
                                                 egcl-apk::*android-attributes* :key #'car :test #'equal))
                         (egcl-apk::u32 #xffffffff) ; no raw string value
                         (egcl-apk::u16 8) #(0 18) (egcl-apk::u32 #xffffffff)))
          (replace data (egcl-apk::u32 #xffffffff) :start1 at) ; hasCode=true
          (replace data (egcl-apk::u32 (+ size 20)) :start1 (+ tag 4))
          (replace data (egcl-apk::u16 (1+ count)) :start1 (+ extension 12)))))
    (replace bytes (egcl-apk::u32 (+ (length bytes) 20)) :start1 4)
    (egcl-apk::bytes (subseq bytes 0 insert-at) record (subseq bytes insert-at))))

(defun bundle-entries ()
  (let* ((root (uiop:ensure-directory-pathname
                (or *compose-runtime-directory*
                    (merge-pathnames "runtime/compose-v1/" *distribution-root*))))
         (manifest (merge-pathnames "bundle.sexp" root))
         (spec (let ((*read-eval* nil)) (with-open-file (in manifest) (read in)))))
    (unless (and (= (getf spec :protocol 0) 1) (= (getf spec :min-sdk 0) 28))
      (error "Unsupported Compose runtime bundle ~A" manifest))
    (let ((entries
            (loop for (name checksum) in (getf spec :files)
                  collect
                  (progn
                    (unless (and (egcl-apk::safe-entry-name-p name)
                                 (or (and (uiop:string-prefix-p "classes" name)
                                          (uiop:string-suffix-p name ".dex"))
                                     (equal name "resources.arsc")
                                     (uiop:string-prefix-p "res/" name)
                                     (uiop:string-prefix-p "META-INF/" name)
                                     (member name '("lib/arm64-v8a/libmaplibre.so"
"lib/arm64-v8a/libandroidx.graphics.path.so"
"lib/arm64-v8a/libimage_processing_util_jni.so"
"lib/arm64-v8a/libsurface_util_jni.so"
"lib/armeabi-v7a/libmaplibre.so"
"lib/armeabi-v7a/libandroidx.graphics.path.so"
"lib/armeabi-v7a/libimage_processing_util_jni.so"
"lib/armeabi-v7a/libsurface_util_jni.so"
"lib/x86/libmaplibre.so"
"lib/x86/libandroidx.graphics.path.so"
"lib/x86/libimage_processing_util_jni.so"
"lib/x86/libsurface_util_jni.so"
"lib/x86_64/libmaplibre.so"
"lib/x86_64/libandroidx.graphics.path.so"
"lib/x86_64/libimage_processing_util_jni.so"
"lib/x86_64/libsurface_util_jni.so") :test #'equal)))
                      (error "Unsupported Compose bundle entry: ~S" name))
                    (let ((data (egcl-apk::read-bytes (merge-pathnames name root))))
                      (unless (string-equal checksum
                                (ironclad:byte-array-to-hex-string (egcl-apk::sha256 data)))
                        (error "Compose runtime checksum mismatch: ~A" name))
                      (cons name data))))))
      (dolist (required '("classes.dex" "resources.arsc"))
        (unless (assoc required entries :test #'equal)
          (error "Compose runtime lacks ~A" required)))
      entries)))

(defun framework-assets ()
  (let* ((root *distribution-root*)
         (order (with-open-file (s (merge-pathnames "load-order.sexp" root)) (read s)))
         (paths (append '("assets/evergreen-compose.lisp" "load-order.sexp" "LICENSE" "LICENSE.classpath-exception" "LICENSE-APACHE" "LICENSES.md")
                        (mapcar (lambda (name) (format nil "src/~A.lisp" name))
                                (append (getf order :host) (getf order :target))))))
    (mapcar (lambda (name)
              (egcl-apk::asset-entry (file-namestring name) (merge-pathnames name root))) paths)))

(defun compose-entries-for-runtimes (entries runtimes)
  "Ship native dependencies only for ABIs that include EGCL itself."
  (let ((prefixes (mapcar (lambda (entry)
                            (subseq (car entry) 0 (1+ (position #\/ (car entry) :from-end t))))
                          runtimes)))
    (remove-if (lambda (entry)
                 (and (uiop:string-prefix-p "lib/" (car entry))
                      (not (some (lambda (prefix) (uiop:string-prefix-p prefix (car entry))) prefixes))))
               entries)))

(defmethod asdf:perform ((operation egcl-apk-asdf:apk-op) (system compose-apk))
  (declare (ignore operation))
  (let* ((config (egcl-apk-asdf::apk-config system))
         ;; apk-config omits false; EGCL manifest defaults true. Set explicitly.
         (config (list* :debuggable (egcl-apk-asdf::apk-debuggable system) config))
         (runtime (egcl-apk-asdf::apk-runtime-directory))
         (metadata (egcl-apk::json-file (merge-pathnames "runtime.json" runtime)))
         (hosts (getf config :hosts))
         (root (asdf:system-source-directory system))
         (assets (append (framework-assets)
                         (mapcar (lambda (path) (egcl-apk::asset-entry (file-namestring path) path))
                                 (egcl-apk-asdf::system-asset-files system)))))
    (unless (and (= (egcl-apk::field "api" metadata) 4) (= (getf config :runtime-api) 4))
      (error "Compose packaging requires EGCL Android runtime API 4"))
    (when (and (getf config :runtime-version)
               (not (equal (getf config :runtime-version) (egcl-apk::field "version" metadata))))
      (error "Android runtime version differs from requested version"))
    (unless (and hosts (= (length hosts) (length (remove-duplicates hosts :test #'equal))))
      (error "APK hosts must be distinct and nonempty"))
    (unless (equal "app.lisp" (egcl-apk-asdf::apk-entry system))
      (error "EGCL API 4 requires :apk-entry app.lisp"))
    (let* ((options (loop for (key value) on config by #'cddr
                          unless (member key '(:hosts :runtime-api :runtime-version))
                            append (list key value)))
           (runtimes (mapcar (lambda (host) (egcl-apk::runtime-entry runtime metadata host)) hosts))
           (entries (append (list (cons "AndroidManifest.xml" (apply #'compose-manifest options)))
                            (compose-entries-for-runtimes (bundle-entries) runtimes)
                            runtimes
                            (egcl-apk::finish-assets assets runtime)))
           (identity-path (merge-pathnames (egcl-apk-asdf::apk-identity-path system) root))
           (identity (if (probe-file identity-path) (egcl-apk::load-identity identity-path)
                         (egcl-apk::create-identity identity-path)))
           (output (merge-pathnames
                    (or (egcl-apk-asdf::apk-output system)
                        (format nil "build/~A.apk" (asdf:primary-system-name system))) root)))
      (egcl-apk::write-apk output entries :identity identity)
      (format t "Compose APK: ~A~%" output))))
