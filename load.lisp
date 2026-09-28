;;;; Load Bliss without ASDF, for a bare `torcl --load load.lisp`.
;;;; The component order here and in bliss.asd must agree.
(dolist (name '("src/package" "src/geometry" "src/paint" "src/font"
                "src/view" "src/layout" "src/clock" "src/input" "src/text-input" "src/widgets"
                "src/display" "src/backend" "src/backend/software" "src/utf8"))
  (load (merge-pathnames (concatenate 'string name ".lisp") *load-truename*)))
