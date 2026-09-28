(in-package :bliss)

;;;; Layout: constraints down, sizes up, then absolute placement.
;;;;
;;;; A parent hands each child a CONSTRAINTS -- a minimum and maximum on each
;;;; axis -- and the child answers with a size inside them. This is Flutter's
;;;; BoxConstraints protocol, and it is the smallest thing that can express the
;;;; two demands every real widget makes: "fill the remaining width" and "centre
;;;; me in my parent". Intrinsic sizing alone can express neither, because a
;;;; node sized only by its content never learns how much room it was given.
;;;;
;;;; MEASURE is memoised per layout pass. A parent needs its children's sizes to
;;;; decide the container's own size, and again to place them; without a cache
;;;; that is an exponential walk on a deep tree, since each visit re-measures
;;;; the whole subtree beneath it.

(defstruct (constraints (:constructor constraints (min-width max-width min-height max-height)))
  min-width max-width min-height max-height)

(defun unbounded ()
  "No limit on either axis. A maximum of NIL means unbounded, which is what an
intrinsically-sized subtree is measured under."
  (constraints 0 nil 0 nil))

(defun tight (width height) (constraints width width height height))

(defun clamp-to (value minimum maximum)
  (max minimum (if maximum (min value maximum) value)))

(defstruct (laid-out (:constructor laid-out (view frame children)))
  view frame children)

(defun padding-of (view)
  "Padding as top, right, bottom, left. A number for all four sides, or a list."
  (let ((p (view-prop view :padding 0)))
    (etypecase p
      (number (values p p p p))
      (list (values (first p) (second p) (third p) (fourth p))))))

(defun row-p (view) (eq (view-kind view) :row))
(defun stack-p (view) (member (view-kind view) '(:row :column)))

;;; Axis helpers. A row and a column differ only in which axis is "main", so
;;; every rule below is written once and read through these.
(defun main-of (row-p width height) (if row-p width height))
(defun cross-of (row-p width height) (if row-p height width))
(defun sized (row-p main cross) (if row-p (values main cross) (values cross main)))

(defvar *measured* nil
  "Per-pass memo: an EQ table from a view node to an alist of constraints.

Keyed by the node's IDENTITY, which is the only thing that can be hashed cheaply
here. Keying by EQUAL on a list CONTAINING the view walks the entire subtree to
hash it and again to compare it -- per node, twice per pass -- which turns the
cache that exists to avoid an exponential walk into a quadratic one. Measured on
a Pixel 10 Pro XL, that mistake cost 73ms per frame against 4ms.

A node's identity is stable within one pass, which is all the memo needs to
live for, and it is exactly what makes the reuse legitimate: the same list
object under the same constraints has the same size by construction.")

(defun measure (view &optional (constraints (unbounded)))
  "The size VIEW takes under CONSTRAINTS, as width and height."
  (check-view view)
  (let* ((cache (or *measured* (make-hash-table :test #'eq)))
         (key (list (constraints-min-width constraints)
                    (constraints-max-width constraints)
                    (constraints-min-height constraints)
                    (constraints-max-height constraints)))
         (entries (gethash view cache))
         (hit (assoc key entries :test #'equal)))
    (if hit
        (values (cadr hit) (cddr hit))
        (multiple-value-bind (w h) (%measure view constraints)
          (setf (gethash view cache) (cons (cons key (cons w h)) entries))
          (values w h)))))

(defgeneric measure-kind (kind view constraints)
  (:documentation "The content size of a VIEW of KIND, before its own :WIDTH or
:HEIGHT and the incoming constraints are applied.

A generic function, specialised on the kind KEYWORD, so a primitive can be added
from outside this file. That is the open-for-extension part of CLOS applied
where it costs nothing -- once per node rather than once per pixel -- while the
tree itself stays data that can be quoted, printed, read back and diffed.

A composite widget needs none of this: it is a function returning existing
primitives. This is only for a genuinely NEW primitive.")
  (:method (kind view constraints)
    (declare (ignore constraints))
    (error "No MEASURE-KIND method for ~S. A new primitive needs one, and a ~
            RENDER-KIND method; a composite widget needs neither -- write a ~
            function returning existing primitives instead. View: ~S" kind view)))

(defmethod measure-kind ((kind (eql :box)) view constraints)
  (declare (ignore constraints))
  (values (view-prop view :width 0) (view-prop view :height 0)))

(defmethod measure-kind ((kind (eql :label)) view constraints)
  (declare (ignore constraints))
  (multiple-value-bind (top right bottom left) (padding-of view)
    (multiple-value-bind (w h)
        (text-extent (view-prop view :text "") (view-prop view :size 1))
      (values (+ w left right) (+ h top bottom)))))

(defmethod measure-kind ((kind (eql :row)) view constraints)
  (multiple-value-bind (main cross) (stack-metrics view constraints)
    (sized t main cross)))

(defmethod measure-kind ((kind (eql :column)) view constraints)
  (multiple-value-bind (main cross) (stack-metrics view constraints)
    (sized nil main cross)))

(defun %measure (view constraints)
  (multiple-value-bind (width height) (measure-kind (view-kind view) view constraints)
    (values (clamp-to (view-prop view :width width)
                      (constraints-min-width constraints)
                      (constraints-max-width constraints))
            (clamp-to (view-prop view :height height)
                      (constraints-min-height constraints)
                      (constraints-max-height constraints)))))

(defun stack-metrics (view constraints)
  "The content size of a row or column, as main and cross, including padding.
Also returns the per-child sizes, so placement need not re-derive them."
  (multiple-value-bind (top right bottom left) (padding-of view)
    (let* ((row (row-p view))
           (gap (view-prop view :gap 0))
           (children (view-children view))
           (main-pad (main-of row (+ left right) (+ top bottom)))
           (cross-pad (cross-of row (+ left right) (+ top bottom)))
           ;; An explicit :WIDTH or :HEIGHT is room the container KNOWS it has,
           ;; so it is offered to the children even when the constraints coming
           ;; in are unbounded. Without this a root that sizes itself to the
           ;; screen still tells its children nothing, and nothing can grow.
           (own-width (view-prop view :width))
           (own-height (view-prop view :height))
           (outer-main (or (main-of row own-width own-height)
                           (main-of row (constraints-max-width constraints)
                                    (constraints-max-height constraints))))
           (outer-cross (or (cross-of row own-width own-height)
                            (cross-of row (constraints-max-width constraints)
                                      (constraints-max-height constraints))))
           (room (when outer-main (max 0 (- outer-main main-pad))))
           (cross-room (when outer-cross (max 0 (- outer-cross cross-pad))))
           (gaps (* gap (max 0 (1- (length children)))))
           (grows (mapcar (lambda (c) (view-prop c :grow 0)) children))
           (total-grow (reduce #'+ grows))
           (sizes (make-list (length children))))
      ;; Children that do not grow are measured first, loosely: they take what
      ;; they need, and what they take decides how much is left to share.
      (loop for child in children
            for grow in grows
            for i from 0
            when (zerop grow)
              do (setf (nth i sizes)
                       (multiple-value-list
                        (measure child (if row
                                           (constraints 0 room 0 cross-room)
                                           (constraints 0 cross-room 0 room))))))
      (let* ((fixed (loop for size in sizes when size
                            sum (main-of row (first size) (second size))))
             (leftover (when room (max 0 (- room fixed gaps)))))
        ;; Growers split what is left, in proportion, and are measured TIGHT on
        ;; the main axis: "fill the remaining width" is a constraint, not a size
        ;; the child gets to argue with. Without a bound there is nothing to
        ;; share, so they fall back to measuring loosely.
        (loop with remaining = (or leftover 0)
              with shares = total-grow
              for child in children
              for grow in grows
              for i from 0
              when (plusp grow)
                do (let ((share (if (and leftover (plusp shares))
                                    (floor (* remaining grow) shares)
                                    nil)))
                     (setf (nth i sizes)
                           (multiple-value-list
                            (measure child
                                     (cond ((null share)
                                            (if row (constraints 0 room 0 cross-room)
                                                (constraints 0 cross-room 0 room)))
                                           (row (constraints share share 0 cross-room))
                                           (t (constraints 0 cross-room share share))))))))
        (let ((main (+ main-pad gaps
                       (loop for size in sizes
                             sum (main-of row (first size) (second size)))))
              (cross (+ cross-pad
                        (loop for size in sizes
                              maximize (cross-of row (first size) (second size))
                                into m
                              finally (return (or m 0))))))
          ;; A stack with a grower fills the room it was offered rather than
          ;; shrinking to its content -- that is what the grower asked for.
          (values (if (and room (plusp total-grow)) (+ room main-pad) main)
                  cross
                  sizes))))))

(defun align-offset (alignment free)
  "Where a child sits in FREE leftover pixels."
  (ecase alignment
    ((:start nil) 0)
    (:center (floor free 2))
    (:end free)))

(defun layout (view x y &optional (constraints (unbounded)))
  "Place VIEW at (X, Y) under CONSTRAINTS; return a tree of absolute frames."
  (check-view view)
  (let ((*measured* (or *measured* (make-hash-table :test #'eq))))
    (%layout view x y constraints)))

(defun %layout (view x y constraints)
  (multiple-value-bind (width height) (measure view constraints)
    (multiple-value-bind (top right bottom left) (padding-of view)
      (declare (ignore right bottom))
      (let ((frame (rect x y width height))
            (children '()))
        (when (stack-p view)
          (multiple-value-bind (main cross sizes) (stack-metrics view constraints)
            (declare (ignore main cross))
            (let* ((row (row-p view))
                   (gap (view-prop view :gap 0))
                   (kids (view-children view))
                   (content (+ (* gap (max 0 (1- (length kids))))
                               (loop for size in sizes
                                     sum (main-of row (first size) (second size)))))
                   (inner-main (- (main-of row width height)
                                  (main-of row (+ left (nth-value 1 (padding-of view)))
                                           (+ top (nth-value 2 (padding-of view))))))
                   (inner-cross (- (cross-of row width height)
                                   (cross-of row (+ left (nth-value 1 (padding-of view)))
                                             (+ top (nth-value 2 (padding-of view))))))
                   (cursor (+ (main-of row x y)
                              (main-of row left top)
                              (align-offset (view-prop view :align)
                                            (max 0 (- inner-main content))))))
              (loop for child in kids
                    for size in sizes
                    do (let* ((child-main (main-of row (first size) (second size)))
                              (child-cross (cross-of row (first size) (second size)))
                              (cross-start
                                (+ (cross-of row x y)
                                   (cross-of row left top)
                                   (align-offset (view-prop view :cross-align)
                                                 (max 0 (- inner-cross child-cross)))))
                              (cx (if row cursor cross-start))
                              (cy (if row cross-start cursor)))
                         (push (%layout child cx cy
                                        (if row
                                            (tight child-main child-cross)
                                            (tight child-cross child-main)))
                               children)
                         (incf cursor (+ child-main gap)))))))
        (laid-out view frame (nreverse children))))))
