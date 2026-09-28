(in-package :bliss)

;;; Colours are packed into one fixnum rather than a struct: a display list for a
;;; busy frame holds thousands of them, and the rasterizer reads each one per
;;; pixel. A struct would put an allocation and a pointer chase on that path.
;;; Layout is #xRRGGBBAA, which reads the way it is written in CSS.

(declaim (inline rgba rgb colour-red colour-green colour-blue colour-alpha))

(defun rgba (r g b a)
  (logior (ash (logand r 255) 24) (ash (logand g 255) 16)
          (ash (logand b 255) 8) (logand a 255)))

(defun rgb (r g b) (rgba r g b 255))

(defun colour-red   (c) (ldb (byte 8 24) c))
(defun colour-green (c) (ldb (byte 8 16) c))
(defun colour-blue  (c) (ldb (byte 8 8) c))
(defun colour-alpha (c) (ldb (byte 8 0) c))

(defparameter +transparent+ (rgba 0 0 0 0))
(defparameter +black+ (rgb 0 0 0))
(defparameter +white+ (rgb 255 255 255))

(defun colour (designator)
  "A colour from DESIGNATOR: a packed integer as-is, or \"#rgb\", \"#rrggbb\" or
\"#rrggbbaa\". Strings exist so a view tree can be written and read as plain
data -- a literal that survives PRINT and READ, which a packed integer also
does but nobody can read."
  (etypecase designator
    (integer designator)
    (string
     (let* ((text (string-left-trim "#" designator))
            (n (length text))
            (digits (parse-integer text :radix 16)))
       (ecase n
         (3 (rgba (* 17 (ldb (byte 4 8) digits))
                  (* 17 (ldb (byte 4 4) digits))
                  (* 17 (ldb (byte 4 0) digits))
                  255))
         (6 (rgba (ldb (byte 8 16) digits) (ldb (byte 8 8) digits)
                  (ldb (byte 8 0) digits) 255))
         (8 digits))))))

(defun blend (over under)
  "OVER composited onto UNDER, both packed. Source-over with 8-bit alpha.
The two common cases -- fully opaque and fully transparent -- are branches
rather than arithmetic, because most pixels in a UI are one of them."
  (let ((alpha (colour-alpha over)))
    (cond ((= alpha 255) over)
          ((zerop alpha) under)
          (t (flet ((mix (o u) (floor (+ (* o alpha) (* u (- 255 alpha))) 255)))
               (rgba (mix (colour-red over) (colour-red under))
                     (mix (colour-green over) (colour-green under))
                     (mix (colour-blue over) (colour-blue under))
                     (max alpha (colour-alpha under))))))))
