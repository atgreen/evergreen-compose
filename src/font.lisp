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

(defun text-extent (text scale)
  "The pixel size of TEXT at SCALE. Returns width and height.
The trailing letter-space of the last glyph is not counted, so a measured string
is flush against its own ink on both sides and centring it looks centred."
  (let ((n (length text)))
    (values (if (zerop n) 0 (* scale (- (* n +glyph-advance+) 1)))
            (* scale +glyph-height+))))
