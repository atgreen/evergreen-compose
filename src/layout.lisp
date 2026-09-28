(in-package :bliss)

;;; Layout is two passes over the tree: MEASURE asks each node how big it wants
;;; to be, then PLACE assigns every node an ABSOLUTE frame. Absolute is what the
;;; display list wants -- a backend should never have to maintain a transform
;;; stack to know where a rectangle goes.

(defstruct (laid-out (:constructor laid-out (view frame children)))
  view frame children)

(defun padding-of (view)
  "Padding as top, right, bottom, left. Accepts a number for all four sides or a
four-element list, which covers what a real UI needs without a class for it."
  (let ((p (view-prop view :padding 0)))
    (etypecase p
      (number (values p p p p))
      (list (values (first p) (second p) (third p) (fourth p))))))

(defun measure (view)
  "The size VIEW wants, as width and height.
Intrinsic sizing only: a node's size comes from its content and its own props,
never from its parent. That keeps MEASURE a pure bottom-up function -- it is
called once per node per layout, and a parent can measure a child without
committing to placing it."
  (check-view view)
  (multiple-value-bind (top right bottom left) (padding-of view)
    (ecase (view-kind view)
      (:box (values (view-prop view :width 0) (view-prop view :height 0)))
      (:label (multiple-value-bind (w h)
                 (text-extent (view-prop view :text "") (view-prop view :size 1))
               (values (+ w left right) (+ h top bottom))))
      ((:row :column)
       (let ((gap (view-prop view :gap 0))
             (children (view-children view))
             (main 0) (cross 0))
         (loop for child in children
               for first = t then nil
               do (multiple-value-bind (w h) (measure child)
                    (let ((along (if (eq (view-kind view) :row) w h))
                          (across (if (eq (view-kind view) :row) h w)))
                      (incf main (if first along (+ gap along)))
                      (setf cross (max cross across)))))
         ;; An explicit :width/:height wins over the measured content, so a
         ;; container can be pinned without wrapping it in another node.
         (let ((w (if (eq (view-kind view) :row) main cross))
               (h (if (eq (view-kind view) :row) cross main)))
           (values (view-prop view :width (+ w left right))
                   (view-prop view :height (+ h top bottom)))))))))

(defun layout (view x y)
  "Place VIEW with its top-left at (X, Y) and return a LAID-OUT tree of absolute
frames. Children of a row or column are stacked in order with the gap between
them; every other kind is a leaf."
  (check-view view)
  (multiple-value-bind (width height) (measure view)
    (multiple-value-bind (top right bottom left) (padding-of view)
      (declare (ignore right bottom))
      (let ((frame (rect x y width height))
            (children '()))
        (when (member (view-kind view) '(:row :column))
          (let ((gap (view-prop view :gap 0))
                (cursor-x (+ x left))
                (cursor-y (+ y top)))
            (dolist (child (view-children view))
              (let ((placed (layout child cursor-x cursor-y)))
                (push placed children)
                (multiple-value-bind (cw ch) (measure child)
                  (if (eq (view-kind view) :row)
                      (incf cursor-x (+ cw gap))
                      (incf cursor-y (+ ch gap))))))))
        (laid-out view frame (nreverse children))))))
