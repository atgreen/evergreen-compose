(in-package :bliss)

;;;; Hit testing and event dispatch.
;;;;
;;;; LAYOUT already produces ABSOLUTE frames, so finding what a touch landed on
;;;; is a walk, not a search structure. That is the whole reason this file is
;;;; short: the expensive part was done when the frame was laid out.
;;;;
;;;; Handlers are ordinary closures stored in view props. That works here and
;;;; would not in a framework that diffed view trees, because a closure is never
;;;; EQUAL to a fresh one built next frame -- but the redraw check compares the
;;;; DISPLAY LIST, which contains only rectangles and text. Handlers never reach
;;;; it, so a tree full of closures still skips identical frames.

(defun hit-test (node x y &optional test)
  "The topmost, innermost laid-out node containing (X, Y) that satisfies TEST.

Children are searched in REVERSE order because later siblings paint over earlier
ones, so the last one drawn is the one a finger lands on. The search descends
before it accepts a parent, so a button inside a row beats the row."
  (let ((frame (laid-out-frame node)))
    (when (rect-contains-p frame x y)
      (or (some (lambda (child) (hit-test child x y test))
                (reverse (laid-out-children node)))
          (when (or (null test) (funcall test node)) node)))))

(defun node-prop (node key &optional default)
  (view-prop (laid-out-view node) key default))

(defun dispatch (root x y event)
  "Call the handler for EVENT on the topmost node at (X, Y) that has one.

Returns that node, or NIL when the touch hit nothing interactive -- which the
caller usually wants to know, because a touch that hits nothing is how a menu
learns to close. The handler is passed the node, so one closure can serve many
widgets by reading its own props."
  (let ((hit (hit-test root x y (lambda (node) (node-prop node event)))))
    (when hit
      (funcall (node-prop hit event) hit)
      hit)))

(defun scale-point (x y x-scale &optional (y-scale x-scale))
  "Physical touch coordinates as logical ones.

Touches arrive in device pixels and the view tree is laid out in logical ones,
so every dispatch needs this.

The axes scale SEPARATELY, and defaulting them to the same value is a trap worth
naming: a 384x747 buffer stretched over a 1080x2243 display is 2.81 across and
3.00 down. One ratio for both is wrong by 7% vertically, which large buttons
absorb and small controls do not -- a switch stops responding while everything
around it still works, which reads as a broken widget rather than broken
arithmetic."
  (values (floor x x-scale) (floor y y-scale)))

;;; ── drag ──────────────────────────────────────────────────────────────

(defparameter *drag-slop* 8
  "Logical pixels a finger must travel before a touch becomes a drag.

Without a threshold every tap is a one-pixel drag, because fingers move. With
one, a press that wanders slightly still fires as a press, and a scroll that
begins on a button does not press it.")

(defun scroll-by (node offset delta)
  "OFFSET moved by DELTA and clamped to what NODE can actually scroll.

Clamping needs both numbers the laid-out node already has: its frame is the
viewport and its CONTENT is what is inside, so the furthest it may scroll is the
difference. A scroller shorter than its viewport cannot scroll at all, which
falls out as a limit of zero rather than needing a case."
  (let ((limit (max 0 (- (laid-out-content node)
                         (rect-height (laid-out-frame node))))))
    (max 0 (min limit (+ offset delta)))))
