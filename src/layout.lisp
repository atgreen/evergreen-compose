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

(defstruct (laid-out (:constructor laid-out (view frame children &optional content)))
  view frame children
  (content 0)
  (:documentation "A placed node. CONTENT is how far its children actually
extend along the main axis, which is what a scroller needs to know how far it
may scroll -- the frame is the viewport, the content is what is inside it."))

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

(defvar *measure-calls* 0 "Diagnostic: MEASURE calls since it was last zeroed.")
(defvar *measure-misses* 0 "Diagnostic: of those, the ones that were not memoised.")

(defun measure (view &optional (constraints (unbounded)))
  "The size VIEW takes under CONSTRAINTS, as width and height."
  (incf *measure-calls*)
  (check-view view)
  (if *measured*
      (%measure-memoised view constraints)
      ;; Called outside a LAYOUT -- a test, or a widget sizing something for
      ;; itself. Binding here rather than on every call is the point: a special
      ;; rebind is ~2.5us and this is the hot path of the whole framework.
      (let ((*measured* (make-hash-table :test #'eq))
            (*stacked* (make-hash-table :test #'eq)))
        (%measure-memoised view constraints))))

(defun %measure-memoised (view constraints)
  (let ((min-width (constraints-min-width constraints))
        (max-width (constraints-max-width constraints))
        (min-height (constraints-min-height constraints))
        (max-height (constraints-max-height constraints))
        (entries (gethash view *measured*)))
    ;; Walked rather than ASSOCed against a freshly consed key: building the key
    ;; cost an allocation on every call including the hits, and EQUAL on two
    ;; four-element lists cost more than comparing four numbers.
    (let ((hit (loop for entry in entries
                     when (and (eql (first entry) min-width)
                               (eql (second entry) max-width)
                               (eql (third entry) min-height)
                               (eql (fourth entry) max-height))
                       return entry)))
      (if hit
          (values (fifth hit) (sixth hit))
          (multiple-value-bind (w h) (progn (incf *measure-misses*)
                                            (%measure view constraints))
            (setf (gethash view *measured*)
                  (cons (list min-width max-width min-height max-height w h) entries))
            (values w h))))))

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
  "A box with no children is a rectangle; a box WITH children stacks them.

Stacking on the z axis is the one arrangement ROW and COLUMN cannot express
between them, and everything that layers needs it: a badge over an icon, a label
over an image, a scrim over a sheet, a spinner centred on a panel. It is the
fourth most reached-for container in Compose for that reason.

The childless case is not a special case so much as what stacking nothing
reduces to, and it is the one SPACER and every plain fill rectangle rely on."
  (if (view-children view)
      (multiple-value-bind (width height) (box-metrics view constraints)
        (values width height))
      (values (view-prop view :width 0) (view-prop view :height 0))))

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

(defvar *stacked* nil
  "Per-pass memo for STACK-METRICS, keyed like *MEASURED*.

A container's metrics are computed twice -- once when it is measured and again
when its children are placed -- and each computation walks every child. Caching
the whole result, not just the child sizes, is what makes a container cost one
distribution pass per layout instead of two.")

(defun metrics-memo (view constraints compute)
  "COMPUTE's values for VIEW under CONSTRAINTS, remembered for this pass."
  (let* ((cache (or *stacked* (make-hash-table :test #'eq)))
         (key (list (constraints-min-width constraints)
                    (constraints-max-width constraints)
                    (constraints-min-height constraints)
                    (constraints-max-height constraints)))
         (hit (assoc key (gethash view cache) :test #'equal)))
    (if hit
        (values-list (cdr hit))
        (let ((computed (multiple-value-list (funcall compute view constraints))))
          (setf (gethash view cache) (cons (cons key computed) (gethash view cache)))
          (values-list computed)))))

(defun stack-metrics (view constraints)
  "Memoised wrapper: see %STACK-METRICS."
  (metrics-memo view constraints #'%stack-metrics))

(defun box-metrics (view constraints)
  "Memoised wrapper: see %BOX-METRICS."
  (metrics-memo view constraints #'%box-metrics))

(defun %box-metrics (view constraints)
  "The content size of a box with children, as width and height, with padding.

Also returns, per child, its size AND THE CONSTRAINTS IT WAS MEASURED UNDER, for
the reason %STACK-METRICS does: placing a child under anything else is a
different memo key, and re-measuring its whole subtree there is what makes
layout quadratic in depth.

Children are measured LOOSELY on both axes. Tight would make every child the
size of the box, which is what :GROW means elsewhere and is not what stacking
means -- a stack is as large as its largest member, not the other way round."
  (multiple-value-bind (top right bottom left) (padding-of view)
    (let* ((own-width (view-prop view :width))
           (own-height (view-prop view :height))
           (outer-width (or own-width (constraints-max-width constraints)))
           (outer-height (or own-height (constraints-max-height constraints)))
           (room (constraints 0 (when outer-width (max 0 (- outer-width left right)))
                              0 (when outer-height (max 0 (- outer-height top bottom)))))
           (sizes (mapcar (lambda (child)
                            (multiple-value-bind (w h) (measure child room)
                              (list w h room)))
                          (view-children view))))
      (values (+ left right (reduce #'max (mapcar #'first sizes) :initial-value 0))
              (+ top bottom (reduce #'max (mapcar #'second sizes) :initial-value 0))
              sizes))))

(defun stretch-p (view child)
  "Whether CHILD should fill VIEW's cross axis.

Per child, like Compose's Modifier.fillMaxWidth, because a form wants the field
full width and the caption above it not. A container may still say it for all of
them at once, which is what flexbox's align-items: stretch means."
  (or (view-prop child :stretch)
      (eq (view-prop view :cross-align) :stretch)))

(defun child-constraints (row stretch main-min main-max cross-room)
  "Constraints for one child of a stack.

MAIN is the axis the stack runs along, CROSS the other. A stretched child is
measured TIGHT across -- given a minimum equal to the room and not merely a
maximum -- which is the whole of what \"fill the width\" means under a
constraints protocol. No new axis, no second pass, no new primitive.

With no cross room to fill -- an unbounded measure, a subtree being sized for its
own content -- there is nothing to stretch to, and the child keeps its intrinsic
size rather than collapsing."
  (let ((cross-min (if (and stretch cross-room) cross-room 0)))
    (if row
        (constraints main-min main-max cross-min cross-room)
        (constraints cross-min cross-room main-min main-max))))

(defun %stack-metrics (view constraints)
  "The content size of a row or column, as main and cross, including padding.

Also returns, per child, its size AND THE CONSTRAINTS IT WAS MEASURED UNDER.
Placement needs the constraints, not just the size: laying a child out under
anything else is a different memo key, so its whole subtree is measured again,
and the cost compounds with depth. Handing the constraints back makes the
placement pass a cache hit at every level and the whole walk linear."
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
           ;; A scroller measures its children UNBOUNDED along the scroll axis.
           ;; Bounded by the viewport they are squashed to fit it, the content
           ;; is exactly the viewport, and there is nothing to scroll -- which
           ;; is a scroll view that silently does not.
           (child-room (if (view-prop view :scroll) nil room))
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
              do (let ((c (child-constraints row (stretch-p view child)
                                             0 child-room cross-room)))
                   (setf (nth i sizes)
                         (multiple-value-bind (w h) (measure child c) (list w h c)))))
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
                do (let* ((share (if (and leftover (plusp shares))
                                     (floor (* remaining grow) shares)
                                     nil))
                          (stretch (stretch-p view child))
                          (c (if share
                                 (child-constraints row stretch share share cross-room)
                                 (child-constraints row stretch 0 child-room cross-room))))
                     (setf (nth i sizes)
                           (multiple-value-bind (w h) (measure child c) (list w h c)))))
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
    ;; :STRETCH is not a position. A stretched child was measured to fill the
    ;; axis, so there is no slack left to place it in.
    ((:start :stretch nil) 0)
    (:center (floor free 2))
    (:end free)))

(defun layout (view x y &optional (constraints (unbounded)))
  "Place VIEW at (X, Y) under CONSTRAINTS; return a tree of absolute frames."
  (check-view view)
  (let ((*measured* (or *measured* (make-hash-table :test #'eq)))
        (*stacked* (or *stacked* (make-hash-table :test #'eq))))
    (%layout view x y constraints)))

(defun %layout (view x y constraints)
  (multiple-value-bind (width height) (measure view constraints)
    (multiple-value-bind (top right bottom left) (padding-of view)
      (let ((frame (rect x y width height))
            (children '())
            (content 0))
        ;; A box places every child at the same origin, aligned in whatever room
        ;; the box ended up with -- so they overlap, later ones over earlier.
        ;; :ALIGN is horizontal and :CROSS-ALIGN vertical, as in a row, since a
        ;; stack has no main axis to tell them apart.
        (when (and (eq (view-kind view) :box) (view-children view))
          (multiple-value-bind (w h sizes) (box-metrics view constraints)
            (declare (ignore w h))
            (let ((inner-width (max 0 (- width left right)))
                  (inner-height (max 0 (- height top bottom))))
              (loop for child in (view-children view)
                    for size in sizes
                    do (push (%layout child
                                      (+ x left (align-offset
                                                 (view-prop view :align)
                                                 (max 0 (- inner-width (first size)))))
                                      (+ y top (align-offset
                                                (view-prop view :cross-align)
                                                (max 0 (- inner-height (second size)))))
                                      (third size))
                             children)))))
        (when (stack-p view)
          (multiple-value-bind (main cross sizes) (stack-metrics view constraints)
            (declare (ignore main cross))
            (let* ((row (row-p view))
                   (gap (view-prop view :gap 0))
                   (kids (view-children view))
                   (ignore (setf content
                                 (+ (* gap (max 0 (1- (length kids))))
                                    (loop for size in sizes
                                          sum (main-of row (first size) (second size))))))
                   ;; RIGHT and BOTTOM are already in hand from the binding
                   ;; above. Asking PADDING-OF for them again cost four more
                   ;; calls per container, and a call here is ~2us.
                   (inner-main (progn ignore
                                      (- (main-of row width height)
                                         (main-of row (+ left right) (+ top bottom)))))
                   (inner-cross (- (cross-of row width height)
                                   (cross-of row (+ left right) (+ top bottom))))
                   ;; :OFFSET-Y and :OFFSET-X move the CHILDREN without moving
                   ;; the container. With :CLIP that is exactly a scroll view,
                   ;; and it needs no new primitive: the container is still a
                   ;; column and the children are still placed in order.
                   (offset (main-of row (view-prop view :offset-x 0)
                                    (view-prop view :offset-y 0)))
                   (cursor (+ (main-of row x y)
                              (main-of row left top)
                              (- offset)
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
                         ;; The constraints the child was MEASURED under, so its
                         ;; MEASURE below is a memo hit and its subtree is not
                         ;; walked a second time. Passing fresh tight constraints
                         ;; here is what made layout quadratic in depth.
                         (push (%layout child cx cy (third size)) children)
                         (incf cursor (+ child-main gap)))))))
        (laid-out view frame (nreverse children) content)))))
