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

;;; ── Ancestors ─────────────────────────────────────────────────────────
;;;
;;; A laid-out tree points downwards only, so "the scroller this node is inside"
;;; is not a question a node can answer. It is a question about the PATH taken
;;; to reach it, which is why these return one.

(defun bring-into-view (root test)
  "The scroller that must move to reveal the first node satisfying TEST, and how
far. NIL when nothing matches, nothing scrolls, or nothing needs to move.

The caller applies it, because the offset is the application's -- the same
arrangement as every other piece of widget state. What the framework can do is
the part that needs the tree: which scroller, and how far."
  (let* ((path (node-path root test))
         (scroller (and path (scrolling-ancestor path))))
    (when scroller
      (let ((delta (needed-scroll scroller (car (last path)))))
        (unless (zerop delta)
          (values scroller delta))))))

(defun drag-scroll (node offset dx)
  "Scroll NODE by a finger movement of DX.

Returns the new offset and the amount of the MOVEMENT consumed, which is what a
nested :ON-DRAG hands back so its parent can have the rest. A scroller already
at its end consumes nothing and the page behind it takes the whole gesture,
which is the behaviour a phone user expects and never notices."
  (let ((moved (scroll-by node offset (- dx))))
    (values moved (- offset moved))))

(defun hit-path (node x y)
  "The chain from NODE down to the deepest node containing (X, Y), outermost
first, or NIL when the point misses.

HIT-TEST answers WHICH node was touched. This answers what it was inside, which
is what a gesture one node cannot finish needs to know."
  (when (rect-contains-p (laid-out-frame node) x y)
    (cons node
          (or (some (lambda (child) (hit-path child x y))
                    (reverse (laid-out-children node)))
              '()))))

(defun node-path (node test)
  "The chain from NODE down to the first descendant satisfying TEST, or NIL.

Depth first and in order, so it finds what a reader or a caret would reach
first."
  (if (funcall test node)
      (list node)
      (some (lambda (child)
              (let ((deeper (node-path child test)))
                (when deeper (cons node deeper))))
            (laid-out-children node))))

(defun scrolling-ancestor (path)
  "The innermost node in PATH that scrolls, or NIL."
  (find-if (lambda (node) (node-prop node :scroll)) (reverse path)))

(defun needed-scroll (scroller node)
  "How far SCROLLER must move along its own axis to bring NODE fully into view.

Zero when it already is. Positive means scroll further on -- the same sense as
SCROLL-BY's delta, so the answer can be handed straight to it."
  (let* ((row (eq (view-kind (laid-out-view scroller)) :row))
         (view (laid-out-frame scroller))
         (item (laid-out-frame node))
         (view-start (if row (rect-x view) (rect-y view)))
         (view-end (if row (rect-right view) (rect-bottom view)))
         (item-start (if row (rect-x item) (rect-y item)))
         (item-end (if row (rect-right item) (rect-bottom item))))
    (cond ((> item-end view-end) (- item-end view-end))
          ((< item-start view-start) (- item-start view-start))
          (t 0))))

;;; ── Taps: press, long press, double tap ───────────────────────────────
;;;
;;; A press is the only gesture the host understood, and it fired on release.
;;; Long press is how Android has opened context menus since 2008; double tap is
;;; how every map and photo zooms. Neither can be built on top of :ON-PRESS,
;;; because both are decided by TIME and an application is never told when the
;;; finger went down.
;;;
;;; The decisions live here, as a function of a state plist and an event, so
;;; they can be tested with no phone, no clock and no touchscreen -- which is
;;; the whole difficulty with gestures otherwise. The host supplies the events
;;; and the time and does nothing else.

(defparameter *long-press-time* 1/2
  "Seconds a finger must rest, without moving, before :ON-LONG-PRESS fires.
Android's own ViewConfiguration says 500ms and muscle memory is calibrated to
it, so this is not a number to have an opinion about.")

(defparameter *double-press-time* 3/10
  "Seconds within which a second tap on the same node is a double tap.")

(defun tap-step (state event &key node (now 0))
  "Advance the tap state machine. Returns the new STATE, the gesture, and the
node it belongs to.

EVENT is :DOWN, :UP, :CANCEL -- a drag took over, or the finger lifted somewhere
else -- or :TICK, meaning time passed and nothing arrived. TICK is not optional
garnish: a long press happens when NOTHING happens, so without it the gesture
can only be noticed by the next unrelated event.

The gesture is NIL, :PRESS, :LONG-PRESS or :DOUBLE-PRESS.

Whether a node HAS a handler decides the timing, which is what keeps this
compatible: a node with no :ON-DOUBLE-PRESS fires :PRESS the instant the finger
lifts, exactly as everything did before this existed, while a node that has one
cannot know a tap was single until the window has passed and must wait.

A double tap is matched on the node's :ID rather than on the node itself,
because the tree is rebuilt between the two taps and the second one is a
different structure describing the same thing. A node with no :ID therefore
cannot be double-tapped, which is the same rule the armed-press check has
always had."
  (let ((down (getf state :down))
        (down-at (getf state :down-at))
        (fired (getf state :fired))
        (pending (getf state :pending))
        (pending-id (getf state :pending-id))
        (pending-at (getf state :pending-at)))
    (flet ((keep (&rest overrides)
             (append overrides
                     (list :down down :down-at down-at :fired fired
                           :pending pending :pending-id pending-id
                           :pending-at pending-at))))
      (ecase event
        ;; A press does not disturb a pending tap: resolving that pending tap
        ;; against the UP still to come is how a double tap is recognised.
        (:down (values (keep :down node :down-at now :fired nil) nil nil))
        ;; The gesture is somebody else's now. A pending tap survives, because
        ;; a drag after a tap is not a double tap but does not un-tap the first.
        (:cancel (values (keep :down nil :down-at nil :fired nil) nil nil))
        (:tick
         (cond ((and down (not fired) (node-prop down :on-long-press)
                     (>= (- now down-at) *long-press-time*))
                (values (keep :fired t) :long-press down))
               ;; The window closed with no second tap, so it was a single one
               ;; after all. This is the deferred half of the double-tap rule.
               ((and pending (> (- now pending-at) *double-press-time*))
                (values (keep :pending nil :pending-id nil :pending-at nil)
                        :press pending))
               (t (values state nil nil))))
        (:up
         (cond
           ;; The long press already fired; the lift that ends it is not a tap.
           (fired (values (keep :down nil :down-at nil :fired nil) nil nil))
           ((null down) (values state nil nil))
           ;; BY :ID, NOT BY IDENTITY. The tree is rebuilt every frame, and the
           ;; first tap invalidates, so by the time the second arrives the node
           ;; is a different structure describing the same thing. EQ on the
           ;; node passed every desktop test -- where the same object is handed
           ;; in twice -- and never once recognised a double tap on the phone.
           ((and pending-id (eql pending-id (node-prop node :id))
                 (<= (- now pending-at) *double-press-time*))
            (values (keep :down nil :down-at nil
                          :pending nil :pending-id nil :pending-at nil)
                    :double-press node))
           ((node-prop node :on-double-press)
            (values (keep :down nil :down-at nil :pending node
                          :pending-id (node-prop node :id) :pending-at now)
                    nil nil))
           (t (values (keep :down nil :down-at nil) :press node))))))))

(defun tap-handler (gesture)
  "The property a GESTURE calls."
  (ecase gesture
    (:press :on-press)
    (:long-press :on-long-press)
    (:double-press :on-double-press)))

(defun tappable-p (node)
  "Whether NODE answers any tap at all. The hit test uses this, so a node with
only an :ON-LONG-PRESS is still found -- which it was not when :ON-PRESS was the
only thing anybody looked for."
  (or (node-prop node :on-press)
      (node-prop node :on-long-press)
      (node-prop node :on-double-press)))
