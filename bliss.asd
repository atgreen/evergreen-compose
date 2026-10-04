;;;; Bliss, and the APK that ships it.
;;;;
;;;; Both component lists are computed from load-order.sexp. That file is the
;;;; only place the order is written down -- see its header for why.

(in-package :asdf-user)

(flet ((order (key)
         (getf (with-open-file (s (merge-pathnames "load-order.sexp" *load-truename*))
                 (read s))
               key))
       (asset (path)
         ;; An APK asset is named by its basename, wherever the file lives, so
         ;; the component name is only an identifier and the pathname is what
         ;; decides the asset. "backend/software" therefore ships as
         ;; software.lisp, which is why no two src/ files may share a basename.
         (list :static-file (pathname-name path) :pathname path)))
  (let* ((host (order :host))
         (target (order :target))
         (demos (mapcar (lambda (p) (format nil "examples/~A" (file-namestring p)))
                        (sort (directory (merge-pathnames "examples/android-*.lisp"
                                                          *load-truename*))
                              #'string< :key #'namestring))))

    (eval `(defsystem "bliss"
             :description "A UI framework for EGCL: view trees are Lisp data."
             :license "MIT OR Apache-2.0"
             :serial t
             ;; The host half only. The rest of load-order.sexp calls into a
             ;; runtime that exists inside an APK and nowhere else, so listing
             ;; it here would make this system unloadable on a desktop.
             :components ((:module "src" :serial t
                           :components ,(mapcar (lambda (n) (list :file n)) host)))))

    (eval `(defsystem "bliss/apk"
             :description "Bliss and a demo, as a signed APK: asdf:make \"bliss/apk\""
             :defsystem-depends-on ("egcl-apk-asdf")
             :class "egcl-apk-asdf:android-apk"
             :build-operation "egcl-apk-asdf:apk-op"
             :version "0.1"
             :apk-package "org.bliss.demo"
             :apk-label "Bliss"
             :apk-version-code 1
             :apk-debuggable t
             :apk-hosts ("aarch64-linux-android")
             :apk-runtime-api 4
             ;; These components ARE the APK's assets. app.lisp is the entry the
             ;; runtime loads; it names the demo, the demo loads bliss.lisp, and
             ;; bliss.lisp walks load-order.sexp.
             :components ((:static-file "app" :pathname "assets/app.lisp")
                          (:static-file "bliss" :pathname "assets/bliss.lisp")
                          (:static-file "load-order" :pathname "load-order.sexp")
                          ,@(mapcar #'asset
                                    (append (mapcar (lambda (n)
                                                      (format nil "src/~A.lisp" n))
                                                    (append host target))
                                            demos)))))))
