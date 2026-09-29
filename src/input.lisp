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
viewport and its CONTENT is what is inside it, so the furthest it may scroll is the
difference. A scroller shorter than its viewport cannot scroll at all, which
falls out as a limit of zero rather than needing a case."
  (let* ((frame (laid-out-frame node))
         ;; Along the node's OWN axis. Clamping a horizontal scroller against
         ;; its height would let it run off the end or refuse to move at all,
         ;; depending only on which happened to be larger.
         (viewport (if (eq (view-kind (laid-out-view node)) :row)
                       (rect-width frame)
                       (rect-height frame)))
         (limit (max 0 (- (laid-out-content node) viewport))))
    (max 0 (min limit (+ offset delta)))))

;;; ── Fling ─────────────────────────────────────────────────────────────
;;;
;;; A scroller that stops dead when the finger lifts feels broken, and the fix
;;; is not "keep scrolling" but a decaying velocity: the content carries on and
;;; slows down, and a flick travels further than a shove.
;;;
;;; The physics is a pair of ordinary functions and the VELOCITY lives in the
;;; application, like every other piece of widget state. The host measures it
;;; and hands it over; what to do with it is not the framework's decision. A
;;; list that should not fling simply does not keep the number.

(defparameter *fling-friction* 4.0
  "How fast a fling loses speed, per second, as an exponential rate.

Exponential rather than a fixed subtraction, for the reason APPROACH is: the
distance covered then depends on ELAPSED TIME rather than on how many frames
happened to fit in it, so a fling looks the same at sixty frames a second and at
eleven -- which matters here, because eleven is what a busy screen gets.")

(defparameter *fling-minimum* 40.0
  "Pixels per second below which a fling has stopped. Without a floor it decays
towards zero for ever and the screen never settles.")

(defun flinging-p (velocity)
  "Whether VELOCITY is still worth animating."
  (and velocity (> (abs velocity) *fling-minimum*)))

(defun fling-step (node offset velocity elapsed)
  "Carry OFFSET along at VELOCITY for ELAPSED seconds, and slow it down.

Returns the new offset and the new velocity. Clamped by SCROLL-BY, so a fling
that reaches the end simply stops there rather than running past it -- and the
velocity is dropped when it does, because a fling that has hit the end is over
however fast it was going."
  ;; The distance is the INTEGRAL of a decaying velocity, not the starting
  ;; velocity times the time. Multiplying by ELAPSED is forward Euler and it
  ;; overshoots as the step grows: over half a second in one step it travels 500
  ;; pixels where the true answer is 216, so a fling on a slow screen goes more
  ;; than twice as far as the same flick on a fast one. Integrating exactly
  ;; costs one EXP that is already being computed.
  (let* ((decay (exp (- (* *fling-friction* elapsed))))
         (distance (/ (* velocity (- 1 decay)) *fling-friction*))
         (moved (scroll-by node offset distance)))
    (values moved
            (if (= moved offset)     ; the end, or nowhere to go
                0.0
                (* velocity decay)))))

(defun drag-velocity (samples)
  "Pixels per second from SAMPLES, newest first, as (TIME X . Y).

Measured across the whole window rather than between the last two: touches
arrive in bursts of a dozen per frame, so consecutive samples are often
microseconds and a hair apart, and dividing one by the other gives a number with
no relation to how fast the finger was moving."
  (let ((newest (first samples)) (oldest (car (last samples))))
    (if (or (null newest) (eq newest oldest))
        (values 0.0 0.0)
        (let ((seconds (- (first newest) (first oldest))))
          (if (<= seconds 0)
              (values 0.0 0.0)
              (values (/ (- (second newest) (second oldest)) seconds)
                      (/ (- (cddr newest) (cddr oldest)) seconds)))))))
