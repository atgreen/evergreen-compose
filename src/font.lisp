(in-package :bliss)

;;; A 5x7 bitmap font, enough to put readable text on a surface without pulling
;;; in a shaper. Glyphs are written as rows of characters so a human can check
;;; them by looking, and are compiled to bit rows once at load time.
;;;
;;; This is deliberately NOT the text story. Real text is Unicode segmentation,
;;; bidi, shaping, fallback and line breaking -- HarfBuzz and ICU through the
;;; FFI, the way egl.lisp already binds GLES. This font exists so the layout and
;;; raster layers can be built and tested against something legible first.

(defparameter *glyph-rows*
  '((#\Space "     " "     " "     " "     " "     " "     " "     ")
    (#\A "  #  " " # # " "#   #" "#   #" "#####" "#   #" "#   #")
    (#\B "#### " "#   #" "#   #" "#### " "#   #" "#   #" "#### ")
    (#\C " ### " "#   #" "#    " "#    " "#    " "#   #" " ### ")
    (#\D "#### " "#   #" "#   #" "#   #" "#   #" "#   #" "#### ")
    (#\E "#####" "#    " "#    " "#### " "#    " "#    " "#####")
    (#\F "#####" "#    " "#    " "#### " "#    " "#    " "#    ")
    (#\G " ### " "#   #" "#    " "#  ##" "#   #" "#   #" " ### ")
    (#\H "#   #" "#   #" "#   #" "#####" "#   #" "#   #" "#   #")
    (#\I " ### " "  #  " "  #  " "  #  " "  #  " "  #  " " ### ")
    (#\J "    #" "    #" "    #" "    #" "#   #" "#   #" " ### ")
    (#\K "#   #" "#  # " "# #  " "##   " "# #  " "#  # " "#   #")
    (#\L "#    " "#    " "#    " "#    " "#    " "#    " "#####")
    (#\M "#   #" "## ##" "# # #" "#   #" "#   #" "#   #" "#   #")
    (#\N "#   #" "##  #" "# # #" "#  ##" "#   #" "#   #" "#   #")
    (#\O " ### " "#   #" "#   #" "#   #" "#   #" "#   #" " ### ")
    (#\P "#### " "#   #" "#   #" "#### " "#    " "#    " "#    ")
    (#\Q " ### " "#   #" "#   #" "#   #" "# # #" "#  # " " ## #")
    (#\R "#### " "#   #" "#   #" "#### " "# #  " "#  # " "#   #")
    (#\S " ####" "#    " "#    " " ### " "    #" "    #" "#### ")
    (#\T "#####" "  #  " "  #  " "  #  " "  #  " "  #  " "  #  ")
    (#\U "#   #" "#   #" "#   #" "#   #" "#   #" "#   #" " ### ")
    (#\V "#   #" "#   #" "#   #" "#   #" "#   #" " # # " "  #  ")
    (#\W "#   #" "#   #" "#   #" "#   #" "# # #" "## ##" "#   #")
    (#\X "#   #" "#   #" " # # " "  #  " " # # " "#   #" "#   #")
    (#\Y "#   #" "#   #" " # # " "  #  " "  #  " "  #  " "  #  ")
    (#\Z "#####" "    #" "   # " "  #  " " #   " "#    " "#####")
    (#\0 " ### " "#   #" "#  ##" "# # #" "##  #" "#   #" " ### ")
    (#\1 "  #  " " ##  " "  #  " "  #  " "  #  " "  #  " " ### ")
    (#\2 " ### " "#   #" "    #" "   # " "  #  " " #   " "#####")
    (#\3 "#####" "   # " "  #  " "   # " "    #" "#   #" " ### ")
    (#\4 "   # " "  ## " " # # " "#  # " "#####" "   # " "   # ")
    (#\5 "#####" "#    " "#### " "    #" "    #" "#   #" " ### ")
    (#\6 "  ## " " #   " "#    " "#### " "#   #" "#   #" " ### ")
    (#\7 "#####" "    #" "   # " "  #  " " #   " " #   " " #   ")
    (#\8 " ### " "#   #" "#   #" " ### " "#   #" "#   #" " ### ")
    (#\9 " ### " "#   #" "#   #" " ####" "    #" "   # " " ##  ")
    (#\. "     " "     " "     " "     " "     " " ##  " " ##  ")
    (#\, "     " "     " "     " "     " " ##  " " ##  " "  #  ")
    (#\! "  #  " "  #  " "  #  " "  #  " "  #  " "     " "  #  ")
    (#\? " ### " "#   #" "    #" "   # " "  #  " "     " "  #  ")
    (#\: "     " " ##  " " ##  " "     " " ##  " " ##  " "     ")
    (#\- "     " "     " "     " "#####" "     " "     " "     ")
    (#\/ "    #" "    #" "   # " "  #  " " #   " "#    " "#    ")
    (#\' "  #  " "  #  " "     " "     " "     " "     " "     ")))

(defconstant +glyph-width+ 5)
(defconstant +glyph-height+ 7)
(defconstant +glyph-advance+ 6 "Glyph cell plus one column of letter spacing.")

(defparameter *glyphs*
  (let ((table (make-hash-table)))
    (dolist (entry *glyph-rows* table)
      ;; Each glyph becomes 7 small integers, one per row, bit N set when column
      ;; N is inked. Testing a pixel is then a LOGBITP rather than a string ref.
      (setf (gethash (first entry) table)
            (map 'vector
                 (lambda (row)
                   (let ((bits 0))
                     (dotimes (column +glyph-width+ bits)
                       (when (char= #\# (char row column))
                         (setf bits (logior bits (ash 1 column)))))))
                 (rest entry))))))

(defun glyph (character)
  "The bit rows for CHARACTER, upcased, or NIL when the font has no such glyph."
  (gethash (char-upcase character) *glyphs*))

(defun glyph-pixel-p (glyph column row)
  (logbitp column (aref glyph row)))

(defun bitmap-text-extent (text scale)
  "The pixel size of TEXT at SCALE in the built-in 5x7 font.
The trailing letter-space of the last glyph is not counted, so a measured string
is flush against its own ink on both sides and centring it looks centred."
  (let ((n (length text)))
    (values (if (zerop n) 0 (* scale (- (* n +glyph-advance+) 1)))
            (* scale +glyph-height+))))

(defparameter *measure-text* #'bitmap-text-extent
  "How TEXT-EXTENT measures a string: a function of (text scale) returning
width and height.

Indirect because measurement must come from whatever will DRAW the text. Layout
centres a label by the width it was told; if the backend then draws with a
different font, the label is centred for a font nobody is using. That was a real
bug -- boxes centred by 5x7 metrics, text drawn by Skia in Roboto -- and it is
invisible in the software backend, where the two are the same font by accident.")

(defun text-extent (text scale)
  "The pixel size of TEXT at SCALE, according to the installed metrics."
  (funcall *measure-text* text scale))
