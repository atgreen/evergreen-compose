;;;; Load Bliss without ASDF, for a bare `torcl --load load.lisp`.
;;;; The component order here and in bliss.asd must agree.
(dolist (name '("src/package" "src/geometry" "src/paint" "src/font"
                "src/view" "src/layout" "src/input" "src/widgets"
                "src/display" "src/backend/software"))
  (load (merge-pathnames (concatenate 'string name ".lisp") *load-truename*)))
