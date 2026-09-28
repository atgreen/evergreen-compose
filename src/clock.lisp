(in-package :bliss)

;;;; The frame clock.
;;;;
;;;; The loop only builds a frame when something changed, which is what keeps an
;;;; event-driven interface cheap. Animation is the case that breaks that rule:
;;;; nothing changed except TIME, and the view is not settled yet.
;;;;
;;;; So a view declares it: calling ANIMATING while building says "I will want
;;;; another frame after this one". The host reads that flag after the build and
;;;; schedules one. Nothing registers, nothing is subscribed to, and an animation
;;;; that finishes simply stops asking -- which means it cannot leak a
;;;; permanently-dirty screen the way a forgotten unsubscribe can.

(defvar *frame-time* 0.0d0
  "Seconds since the application started, as a FLOAT, fixed for one frame.

A float rather than the exact ratio a division of internal time units gives:
an exact rational is contagious through any arithmetic a view does with it, and
~F refuses to print one at all.

Fixed, not sampled: two widgets reading the clock in the same frame must agree,
or an animation drawn in two places drifts apart by the time it took to build
the tree between them.")

(defvar *frame-delta* 0.0d0
  "Seconds since the previous frame, for rate-based motion.")

(defvar *animating* nil
  "Set during a build by ANIMATING. The host reads it and owes another frame.")

(defun now () *frame-time*)
(defun frame-delta () *frame-delta*)

(defun animating ()
  "Declare that this frame is not the last one. Idempotent and cheap."
  (setf *animating* t))

(defun approach (current target &key (rate 12) (epsilon 1/1000))
  "Move CURRENT toward TARGET, framerate-independently, and ask for a frame.

Exponential approach rather than a fixed step per frame: the distance covered
depends on ELAPSED TIME, so the motion looks the same at 60fps and at 20, which
matters here because the frame rate is whatever the work allows rather than a
promise.

Returns the new value. Once within EPSILON it snaps to the target and stops
asking for frames, which is what ends the animation -- an approach that never
quite arrives would keep the screen dirty forever."
  (let ((delta (- target current)))
    (if (< (abs delta) epsilon)
        target
        (progn
          (animating)
          ;; 1 - e^-rt, approximated well enough for motion by a clamped ratio.
          (+ current (* delta (min 1 (* rate (frame-delta)))))))))

(defun ease (fraction)
  "Smooth 0..1 into 0..1 with zero velocity at both ends (smoothstep)."
  (let ((f (max 0 (min 1 fraction))))
    (* f f (- 3 (* 2 f)))))
