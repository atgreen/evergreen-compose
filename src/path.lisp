(in-package :bliss)

;;;; Filling a path.
;;;;
;;;; The display list could draw rectangles, rounded rectangles, glyphs and
;;;; bitmaps, and nothing else -- so an icon, a chart, a chevron, a triangle or
;;;; any shape at all was simply not expressible. This is the missing one.
;;;;
;;;; It reduces to SPANS, exactly as ROUND-RECT-SPANS does, and for the same
;;;; reason: a backend that can fill an axis-aligned rectangle then gets paths
;;;; for free, with no second rasterizer to write and no quality of its own to
;;;; get wrong. A backend that has real paths -- Canvas does -- should draw
;;;; :PATH itself and never come through here.
;;;;
;;;; Curves are flattened rather than solved. Sixteen segments is invisible at
;;;; icon sizes and the alternative is a curve rasterizer, which is a great deal
;;;; of code to make a 24-pixel chevron marginally rounder.

(defparameter +curve-steps+ 16
  "Line segments per curve. The error falls off with the square of this, and an
icon is two dozen pixels across, so it is already far below one of them.")

(defun %cubic (a b c d parameter)
  "A cubic Bezier at PARAMETER."
  (let* ((u (- 1 parameter)) (uu (* u u)) (tt (* parameter parameter)))
    (+ (* uu u a) (* 3 uu parameter b) (* 3 u tt c) (* tt parameter d))))

(defun %quadratic (a b c parameter)
  "A quadratic Bezier at PARAMETER.

Its own function, because the tempting shortcut is wrong: a quadratic is NOT a
cubic with its control point written twice. Raising the degree honestly puts the
two cubic controls a third of the way back from the ends, and getting that wrong
gives a curve that is close enough to look right and is not the curve."
  (let ((u (- 1 parameter)))
    (+ (* u u a) (* 2 u parameter b) (* parameter parameter c))))

(defun flatten-path (commands)
  "COMMANDS as a list of polygons, each a list of (X . Y).

A polygon is implicitly closed: a filled path has no open subpaths, so :CLOSE
says where one ENDS rather than adding an edge, and a subpath that forgets it is
closed anyway."
  (let ((polygons '()) (current '()) (pen-x 0) (pen-y 0))
    (labels ((emit (x y) (push (cons x y) current) (setf pen-x x pen-y y))
             (finish () (when (cddr current) (push (nreverse current) polygons))
                     (setf current '())))
      (dolist (command commands)
        (ecase (first command)
          (:move (finish) (destructuring-bind (x y) (rest command) (emit x y)))
          (:line (destructuring-bind (x y) (rest command) (emit x y)))
          (:quad (destructuring-bind (cx cy x y) (rest command)
                   (let ((x0 pen-x) (y0 pen-y))
                     (loop for step from 1 to +curve-steps+
                           for at = (/ step +curve-steps+)
                           do (emit (%quadratic x0 cx x at)
                                    (%quadratic y0 cy y at))))))
          (:cubic (destructuring-bind (ax ay bx by x y) (rest command)
                    (let ((x0 pen-x) (y0 pen-y))
                      (loop for step from 1 to +curve-steps+
                            for at = (/ step +curve-steps+)
                            do (emit (%cubic x0 ax bx x at)
                                     (%cubic y0 ay by y at))))))
          (:close (finish))))
      (finish))
    (nreverse polygons)))

(defun path-spans (commands x y width height view-box)
  "COMMANDS, drawn in a VIEW-BOX-square coordinate space, as spans filling the
rectangle at (X, Y) of WIDTH by HEIGHT.

Scanline fill with the NONZERO rule, which is the one every icon format means:
an overlapping subpath wound the same way stays solid, and one wound the other
way cuts a hole. Each row is sampled down its middle, so a shape thinner than a
pixel is either in or out rather than half-drawn -- which is what antialiasing
would fix and what this deliberately does not have."
  (let* ((scale-x (/ width view-box))
         (scale-y (/ height view-box))
         (polygons (mapcar (lambda (polygon)
                             (mapcar (lambda (point)
                                       (cons (+ x (* (car point) scale-x))
                                             (+ y (* (cdr point) scale-y))))
                                     polygon))
                           (flatten-path commands)))
         (spans '()))
    (loop for row from (floor y) below (ceiling (+ y height))
          for sample = (+ row 1/2)
          do (let ((crossings '()))
               (dolist (polygon polygons)
                 (loop for tail on polygon
                       for a = (first tail)
                       for b = (or (second tail) (first polygon))
                       do (let ((ay (cdr a)) (by (cdr b)))
                            ;; Half-open on the scanline, so a vertex shared by
                            ;; two edges is counted once and a horizontal edge
                            ;; not at all.
                            (when (or (and (<= ay sample) (< sample by))
                                      (and (<= by sample) (< sample ay)))
                              (push (cons (+ (car a) (* (- (car b) (car a))
                                                        (/ (- sample ay) (- by ay))))
                                          (if (< ay by) 1 -1))
                                    crossings)))))
               (let ((winding 0) (start nil))
                 (dolist (crossing (sort crossings #'< :key #'car))
                   (let ((was winding))
                     (incf winding (cdr crossing))
                     (cond ((and (zerop was) (not (zerop winding)))
                            (setf start (car crossing)))
                           ((and (not (zerop was)) (zerop winding) start)
                            (let ((from (round start)) (to (round (car crossing))))
                              (when (> to from)
                                (push (list from row (- to from) 1) spans)))
                            (setf start nil))))))))
    (nreverse spans)))
