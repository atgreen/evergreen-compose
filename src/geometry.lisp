(in-package :bliss)

;;; Rectangles are the only geometry the layout engine needs: every view is
;;; placed as an axis-aligned box in its parent's coordinate space, and the
;;; display list carries absolute boxes so a backend never has to walk a tree.

(defstruct (rect (:constructor rect (x y width height)))
  (x 0) (y 0) (width 0) (height 0))

(defun rect-right (r) (+ (rect-x r) (rect-width r)))
(defun rect-bottom (r) (+ (rect-y r) (rect-height r)))

(defun rect-offset (r dx dy)
  "R moved by (DX, DY). Layout is computed in local space and shifted on the way
down, so a subtree can be laid out once and placed anywhere."
  (rect (+ (rect-x r) dx) (+ (rect-y r) dy) (rect-width r) (rect-height r)))

(defun rect-intersect (a b)
  "The overlap of A and B, or NIL when they do not touch. Backends clip with
this so a view cannot paint outside the surface."
  (let ((x (max (rect-x a) (rect-x b)))
        (y (max (rect-y a) (rect-y b)))
        (right (min (rect-right a) (rect-right b)))
        (bottom (min (rect-bottom a) (rect-bottom b))))
    (when (and (< x right) (< y bottom))
      (rect x y (- right x) (- bottom y)))))

(defun rect-contains-p (r x y)
  (and (<= (rect-x r) x) (< x (rect-right r))
       (<= (rect-y r) y) (< y (rect-bottom r))))

(defun rect-union (a b)
  "The smallest rectangle containing both."
  (let ((x (min (rect-x a) (rect-x b)))
        (y (min (rect-y a) (rect-y b))))
    (rect x y
          (- (max (rect-right a) (rect-right b)) x)
          (- (max (rect-bottom a) (rect-bottom b)) y))))
