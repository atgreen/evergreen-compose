;;;; Load Bliss inside an APK.
;;;;
;;;; The order comes from load-order.sexp, which ships as an asset beside this
;;;; file, so the device loads what bliss.asd packaged and the two cannot
;;;; disagree. APK assets are one flat directory, so a "backend/software" in
;;;; that list is "software.lisp" here.
(dolist (name (let ((order (with-open-file (s "load-order.sexp") (read s))))
                (append (getf order :host) (getf order :target))))
  (let ((slash (position #\/ name :from-end t)))
    (load (concatenate 'string (if slash (subseq name (1+ slash)) name) ".lisp"))))
