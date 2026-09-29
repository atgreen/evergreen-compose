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

;;; ── Breaking a paragraph into lines ───────────────────────────────────

(defvar *wrap-cache* (make-hash-table :test #'equal)
  "(text scale width) -> lines. Breaking is done twice per paragraph per frame
-- once to measure, once to render -- and both passes ask the backend to measure
every word, which on Android is a JNI crossing apiece.")

(defparameter *wrap-cache-limit* 512
  "Entries kept before the cache is emptied. A paragraph whose text changes every
frame -- a clock, a counter -- would otherwise grow this without bound.")

(defun %fit-prefix (word scale max-width)
  "How many leading characters of WORD fit in MAX-WIDTH. At least one.

At least one because returning zero cannot make progress, and a word narrower
than a single character means the container is narrower than a character: that
is a caller's problem, and looping forever is not the way to report it."
  (let ((n (length word)))
    (loop for i from 1 to n
          when (> (text-extent (subseq word 0 i) scale) max-width)
            do (return (max 1 (1- i)))
          finally (return n))))

(defun %break-line (words scale max-width)
  "Greedily take words into one line. Returns the line and what is left.

Greedy, not Knuth-Plass: the difference shows in justified print and is
invisible in a ragged-right column on a phone."
  (let ((line "") (rest words))
    (loop while rest
          do (let ((candidate (if (string= line "")
                                  (first rest)
                                  (concatenate 'string line " " (first rest)))))
               (cond ((<= (text-extent candidate scale) max-width)
                      (setf line candidate rest (cdr rest)))
                     ;; The first word of a line does not fit at all, so it has
                     ;; to be split -- the alternative is a word running off the
                     ;; edge, which is what not wrapping looked like.
                     ((string= line "")
                      (let* ((word (first rest))
                             (take (%fit-prefix word scale max-width)))
                        (setf line (subseq word 0 take)
                              rest (cons (subseq word take) (cdr rest)))
                        (return)))
                     (t (return)))))
    (values line rest)))

(defun %split-words (text)
  "TEXT split on spaces, empties dropped."
  (let ((words '()) (start 0))
    (dotimes (i (length text))
      (when (char= (char text i) #\Space)
        (when (> i start) (push (subseq text start i) words))
        (setf start (1+ i))))
    (when (> (length text) start) (push (subseq text start) words))
    (nreverse words)))

(defun %split-lines (text)
  "TEXT split on newlines, empties KEPT -- a blank line is a paragraph break and
the one thing a writer will certainly notice being eaten."
  (let ((lines '()) (start 0))
    (dotimes (i (length text))
      (when (char= (char text i) #\Newline)
        (push (subseq text start i) lines)
        (setf start (1+ i))))
    (push (subseq text start) lines)
    (nreverse lines)))

(defun wrap-text (text scale max-width &key max-lines (ellipsis "..."))
  "TEXT broken into lines that each fit MAX-WIDTH, as a list of strings.

Newlines in TEXT are honoured and break a line wherever they appear. A NIL
MAX-WIDTH means unbounded, so only those breaks apply.

MAX-LINES cuts the result and marks the last line with ELLIPSIS, shortened until
the line with the ellipsis on it fits -- a truncation that itself overflows is
worse than no truncation, because it looks deliberate."
  (let ((key (list text scale max-width max-lines ellipsis)))
    (or (gethash key *wrap-cache*)
        (progn
          (when (> (hash-table-count *wrap-cache*) *wrap-cache-limit*)
            (clrhash *wrap-cache*))
          (setf (gethash key *wrap-cache*)
                (%wrap-text text scale max-width max-lines ellipsis))))))

(defun %wrap-text (text scale max-width max-lines ellipsis)
  (let ((lines '()))
    (dolist (paragraph (%split-lines text))
      (let ((words (%split-words paragraph)))
        (cond ((null words) (push "" lines))
              ((null max-width) (push paragraph lines))
              (t (loop while words
                       do (multiple-value-bind (line rest)
                              (%break-line words scale max-width)
                            (push line lines)
                            (setf words rest)))))))
    (let ((lines (nreverse lines)))
      (if (and max-lines (> (length lines) max-lines))
          (let ((kept (subseq lines 0 max-lines)))
            (setf (car (last kept))
                  (%with-ellipsis (car (last kept)) scale max-width ellipsis))
            kept)
          lines))))

(defun %with-ellipsis (line scale max-width ellipsis)
  "LINE with ELLIPSIS appended, shortened until the whole thing fits."
  (if (null max-width)
      (concatenate 'string line ellipsis)
      (loop for n downfrom (length line) downto 0
            for candidate = (concatenate 'string (subseq line 0 n) ellipsis)
            when (or (zerop n) (<= (text-extent candidate scale) max-width))
              do (return candidate)
            finally (return ellipsis))))

(defun wrapped-extent (lines scale)
  "The block size of LINES: the widest line, and their total height."
  (let ((width 0) (height 0))
    (dolist (line lines (values width height))
      (multiple-value-bind (w h) (text-extent line scale)
        (setf width (max width w))
        (incf height h)))))
