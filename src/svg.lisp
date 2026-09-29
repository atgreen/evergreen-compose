(in-package :bliss)

;;;; SVG path data, as Bliss path commands.
;;;;
;;;; Not a general SVG reader -- it reads the `d` attribute of a <path> and
;;;; nothing else, which is the only part an icon needs. Counted across 800
;;;; Material icons: M m L l H h V v C c S s Z z and nothing more. No
;;;; quadratics appear at all, and arcs appear in eleven of the first two
;;;; thousand, so those signal rather than being silently wrong.
;;;;
;;;; Meant to be run OFFLINE, by tools/make-icons.lisp, which writes the result
;;;; into a Lisp file. A phone should not parse SVG at startup, and a path is a
;;;; constant that belongs in the image. It ships anyway because it is small and
;;;; because an application with an icon of its own should not need a toolchain.

(defun %svg-number-end (text start)
  "Where the number beginning at START ends. SVG packs them: -.79.5 is two."
  (let ((i start) (n (length text)) (dot nil) (digit nil))
    (when (and (< i n) (member (char text i) '(#\- #\+))) (incf i))
    (loop while (< i n)
          for c = (char text i)
          do (cond ((digit-char-p c) (setf digit t) (incf i))
                   ((and (char= c #\.) (not dot)) (setf dot t) (incf i))
                   ((and (member c '(#\e #\E)) digit)
                    (incf i)
                    (when (and (< i n) (member (char text i) '(#\- #\+))) (incf i)))
                   (t (return))))
    i))

(defun %svg-tokens (text)
  "TEXT as a list of command characters and numbers."
  (let ((tokens '()) (i 0) (n (length text)))
    (loop while (< i n)
          do (let ((c (char text i)))
               (cond ((member c '(#\Space #\, #\Newline #\Tab #\Return)) (incf i))
                     ((alpha-char-p c) (push c tokens) (incf i))
                     (t (let* ((end (%svg-number-end text i))
                               (raw (subseq text i end)))
                          (when (= end i)
                            (error "Cannot read SVG path data at ~S" (subseq text i)))
                          ;; CL will read .5 and -.79, but not every reader is
                          ;; asked to; a leading zero costs nothing and removes
                          ;; the question.
                          (push (read-from-string
                                 (cond ((and (> (length raw) 0) (char= (char raw 0) #\.))
                                        (concatenate 'string "0" raw))
                                       ((and (> (length raw) 1) (string= (subseq raw 0 2) "-."))
                                        (concatenate 'string "-0" (subseq raw 1)))
                                       (t raw)))
                                tokens)
                          (setf i end))))))
    (nreverse tokens)))

(defun parse-svg-path (data)
  "The `d` attribute of an SVG <path> as Bliss :PATH commands.

Relative commands become absolute, H and V become lines, and S reflects the
previous control point -- so what comes out uses only :MOVE :LINE :CUBIC and
:CLOSE, which is what the display list has."
  (let ((tokens (%svg-tokens data))
        (out '()) (x 0) (y 0) (start-x 0) (start-y 0)
        (command nil) (control nil))
    (labels ((number! ()
               (let ((value (pop tokens)))
                 (unless (numberp value)
                   (error "SVG path: expected a number, found ~S" value))
                 value))
             (emit (op) (push op out))
             (reflected ()
               ;; S continues the curvature of the C before it: its first
               ;; control is the previous control mirrored through the point
               ;; they share. With no curve before it, there is nothing to
               ;; mirror and the point itself is used.
               (if control
                   (values (- (* 2 x) (car control)) (- (* 2 y) (cdr control)))
                   (values x y))))
      (loop while tokens
            do (when (characterp (first tokens)) (setf command (pop tokens)))
               (unless command (error "SVG path data does not begin with a command"))
               (let ((relative (lower-case-p command)))
                 (ecase (char-downcase command)
                   (#\m (let ((nx (number!)) (ny (number!)))
                          (setf x (if relative (+ x nx) nx)
                                y (if relative (+ y ny) ny)
                                start-x x start-y y control nil)
                          (emit (list :move x y))
                          ;; Further pairs after an M are lines, not moves.
                          (setf command (if relative #\l #\L))))
                   (#\l (let ((nx (number!)) (ny (number!)))
                          (setf x (if relative (+ x nx) nx)
                                y (if relative (+ y ny) ny)
                                control nil)
                          (emit (list :line x y))))
                   (#\h (let ((nx (number!)))
                          (setf x (if relative (+ x nx) nx) control nil)
                          (emit (list :line x y))))
                   (#\v (let ((ny (number!)))
                          (setf y (if relative (+ y ny) ny) control nil)
                          (emit (list :line x y))))
                   (#\c (let* ((ax (number!)) (ay (number!))
                               (bx (number!)) (by (number!))
                               (nx (number!)) (ny (number!))
                               (ax (if relative (+ x ax) ax)) (ay (if relative (+ y ay) ay))
                               (bx (if relative (+ x bx) bx)) (by (if relative (+ y by) by))
                               (nx (if relative (+ x nx) nx)) (ny (if relative (+ y ny) ny)))
                          (emit (list :cubic ax ay bx by nx ny))
                          (setf control (cons bx by) x nx y ny)))
                   (#\s (multiple-value-bind (ax ay) (reflected)
                          (let* ((bx (number!)) (by (number!))
                                 (nx (number!)) (ny (number!))
                                 (bx (if relative (+ x bx) bx)) (by (if relative (+ y by) by))
                                 (nx (if relative (+ x nx) nx)) (ny (if relative (+ y ny) ny)))
                            (emit (list :cubic ax ay bx by nx ny))
                            (setf control (cons bx by) x nx y ny))))
                   (#\z (emit (list :close))
                        (setf x start-x y start-y control nil))
                   ((#\a #\q #\t)
                    (error "SVG path uses ~:@(~A~), which this does not read. ~
                            Arcs appear in about one icon in two hundred and ~
                            quadratics in none; convert the path or skip it."
                           command))))))
    (nreverse out)))

(defun svg-path-strings (text)
  "The `d` of every <path> in TEXT that is actually painted.

Skipping fill=\"none\" is not tidiness. Every Material icon opens with
<path d=\"M0 0h24v24H0z\" fill=\"none\"/>, a full 24x24 box, and an importer
that draws it turns every icon into a solid square."
  (let ((paths '()) (i 0))
    (loop for start = (search "<path" text :start2 i)
          while start
          do (let* ((end (or (position #\> text :start start) (length text)))
                    (tag (subseq text start end))
                    (d (let ((at (search "d=\"" tag)))
                         (when at
                           (let ((close (position #\" tag :start (+ at 3))))
                             (subseq tag (+ at 3) close))))))
               (when (and d (not (search "fill=\"none\"" tag)))
                 (push d paths))
               (setf i end)))
    (nreverse paths)))
