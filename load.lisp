;;;; Load Bliss without ASDF, for a bare `egcl --load load.lisp'.
;;;; The order comes from load-order.sexp, so there is nothing here to keep in
;;;; step with bliss.asd.
(let* ((here (make-pathname :name nil :type nil :defaults *load-truename*))
       (order (with-open-file (s (merge-pathnames "load-order.sexp" here))
                (read s))))
  (dolist (name (getf order :host))
    (load (merge-pathnames (concatenate 'string "src/" name ".lisp") here))))
