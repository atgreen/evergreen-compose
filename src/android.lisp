(in-package :bliss)

;;;; The Android host: window, canvas, touch mapping and the frame loop.
;;;;
;;;; This exists because every line of it was, briefly, copied into an
;;;; application -- and both of the worst bugs so far lived here rather than in
;;;; any widget. A single touch ratio for two axes put every hit 7% out
;;;; vertically, which only small controls noticed; and the window's native
;;;; orientation meant the bottom half of the screen delivered no touches at
;;;; all. Neither is a thing an application author should have to know, and
;;;; neither is discoverable from the symptom.
;;;;
;;;; An application supplies a function of (width height) returning a view. That
;;;; is the whole contract.

(defvar *pressed* nil
  "The :ID currently held down, or NIL.

Bound by the host and READ by the view function, which is what lets a widget be
told whether it is pressed without remembering anything itself.")

(defclass android-host ()
  ((window :initarg :window :reader host-window)
   (library :initarg :library :reader host-library)
   (backend :initarg :backend :reader host-backend)
   (buffer :initarg :buffer :reader host-buffer)
   (memcpy :initarg :memcpy :reader host-memcpy)
   (width :initarg :width :reader host-width)
   (height :initarg :height :reader host-height)
   (x-ratio :initarg :x-ratio :reader host-x-ratio)
   (y-ratio :initarg :y-ratio :reader host-y-ratio)
   (placed :initform nil :accessor host-placed)
   (started :initform nil :accessor host-started)
   (last-frame :initform nil :accessor host-last-frame)
   (drag-chain :initform '() :accessor host-drag-chain)
   (drag-origin :initform nil :accessor host-drag-origin)
   (drag-last :initform nil :accessor host-drag-last)
   (dragging :initform nil :accessor host-dragging)
   (drag-samples :initform '() :accessor host-drag-samples)
   (insets :initform '(0 0 0 0) :accessor host-insets)
   (last-display :initform nil :accessor host-last-display)))

(defun android-call (host name return types arguments)
  (torcl-ffi:foreign-call
   (torcl-ffi:foreign-symbol-pointer name (host-library host)) return types arguments))

(defun open-android-host (window &key (design-width 360) (design-height 747))
  "Prepare a host for WINDOW, laying out at roughly DESIGN-WIDTH logical pixels.

The actual width is the window's STRIDE, not the requested size: the compositor
pads it for alignment -- 360 becomes 384 here -- and matching it makes the blit
one memcpy rather than one per row.

Touch ratios are computed PER AXIS. The buffer's aspect is not the display's, so
one ratio is wrong on one of them, and wrong by little enough that only small
controls miss."
  ;; JNI belongs to the host: Canvas cannot be opened without it, and an
  ;; application should not have to know that drawing goes through Java.
  (jni-start)
  (let* ((library (torcl-ffi:load-foreign-library "libandroid.so"))
         (host (make-instance 'android-host :window window :library library
                              :buffer (torcl-ffi:foreign-alloc 48)
                              :memcpy (torcl-ffi:foreign-symbol-pointer "memcpy")
                              :backend nil :width 0 :height 0 :x-ratio 1 :y-ratio 1)))
    ;; The window reports its NATIVE orientation, which on a portrait phone is
    ;; landscape. Touches arrive in portrait coordinates, so the display is the
    ;; same pair the other way round.
    (let* ((a (android-call host "ANativeWindow_getWidth" :int '(:pointer) (list window)))
           (b (android-call host "ANativeWindow_getHeight" :int '(:pointer) (list window)))
           (display-width (min a b))
           (display-height (max a b))
           (height design-height))
      (android-call host "ANativeWindow_setBuffersGeometry" :int '(:pointer :int :int :int)
                    (list window design-width height 1))
      (android-call host "ANativeWindow_lock" :int '(:pointer :pointer :pointer)
                    (list window (host-buffer host) (torcl-ffi:null-pointer)))
      (let ((width (torcl-ffi:mem-ref (host-buffer host) :int 8)))
        (android-call host "ANativeWindow_unlockAndPost" :int '(:pointer) (list window))
        (android-call host "ANativeWindow_setBuffersGeometry" :int '(:pointer :int :int :int)
                      (list window width height 1))
        (reinitialize-instance host
                               :width width :height height
                               :x-ratio (/ display-width width)
                               :y-ratio (/ display-height height)
                               :backend (use-backend (make-canvas-backend width height)))
        (android:log (format nil "bliss: ~Dx~D logical on ~Dx~D display"
                             width height display-width display-height))
        host))))

(defun host-blit (host)
  "Move the rendered bitmap to the window. One memcpy, because the canvas was
opened at the window's own stride."
  (multiple-value-bind (source stride)
      (canvas-pixels (canvas-backend-canvas (host-backend host)))
    (android-call host "ANativeWindow_lock" :int '(:pointer :pointer :pointer)
                  (list (host-window host) (host-buffer host) (torcl-ffi:null-pointer)))
    (torcl-ffi:foreign-call (host-memcpy host) :pointer '(:pointer :pointer :long)
                            (list (torcl-ffi:mem-ref (host-buffer host) :pointer 16)
                                  source (* 4 stride (host-height host))))
    (canvas-release-pixels (canvas-backend-canvas (host-backend host)))
    (android-call host "ANativeWindow_unlockAndPost" :int '(:pointer)
                  (list (host-window host)))))

(defun refresh-insets (host)
  "Re-read what the system is covering, in LOGICAL pixels. True if it changed.

Polled once a frame rather than subscribed to, because subscribing is
View.setOnApplyWindowInsetsListener and a listener is a Java class we cannot
define. Costs a handful of JNI crossings; the keyboard opening is not something
an application can be told about any other way."
  (multiple-value-bind (bl bt br bb) (window-insets :system-bars)
    (multiple-value-bind (il it ir ib) (window-insets :ime)
      (let ((next (list (floor (max bl il) (host-x-ratio host))
                        (floor (max bt it) (host-y-ratio host))
                        (floor (max br ir) (host-x-ratio host))
                        (floor (max bb ib) (host-y-ratio host)))))
        (unless (equal next (host-insets host))
          (setf (host-insets host) next)
          (invalidate)
          t)))))

(defmacro with-frame-clock ((host) &body body)
  "Run BODY as one frame: the clock fixed, and another frame asked for if the
view says it is not settled.

A macro, and exported, because a hand-written loop needs exactly this and
copying it is how the two drift apart. The demo's own loop did not have it, so
ANIMATING did nothing there and no animation could ever have run."
  (let ((now (gensym "NOW")) (h (gensym "HOST")))
    `(let ((,h ,host))
       ;; A FLOAT, not the exact ratio the division gives: a rational clock is
       ;; surprising to arithmetic that expects a number it can print, and ~F
       ;; rejects it outright -- which killed the worker on the first frame
       ;; after a touch and left the last frame on screen looking like dead
       ;; input.
       (let* ((,now (float (/ (get-internal-real-time) internal-time-units-per-second)
                           1.0d0))
              (*frame-time* (- ,now (or (host-started ,h)
                                        (setf (host-started ,h) ,now))))
              (*frame-delta* (min 1/10 (- *frame-time*
                                          (or (host-last-frame ,h) *frame-time*))))
              (*animating* nil))
         (setf (host-last-frame ,h) *frame-time*)
         (multiple-value-prog1 (progn ,@body)
           ;; The view said it is not settled, so it is owed another frame.
           ;; Asked for AFTER the build, so an animation that just finished
           ;; does not get one.
           (when *animating* (invalidate)))))))

(defun host-draw (host view)
  "Lay out and present VIEW, unless the frame is identical to the last one.

RENDER is a pure function of the tree, so an unchanged tree means the frame on
screen is still correct and the whole draw can be skipped. That is what keeps an
event-driven interface responsive: the cost is paid once per change instead of
continuously, and touches stop queueing behind frames nobody needed.

When it HAS changed, only the part that changed is drawn. The difference between
this frame's operations and the last one's bounds everything that can look
different, and the backend's surface already holds the rest."
  (let* ((placed (layout view 0 0 (constraints 0 (host-width host) 0 (host-height host))))
         (display (render placed))
         (last (host-last-display host)))
    (setf (host-placed host) placed)
    (unless (equal display last)
      ;; NIL on the first frame, which is exactly right: with nothing behind it
      ;; there is nothing correct to keep, and everything must be drawn.
      (let ((damage (when last
                      (display-damage display last
                                      (rect 0 0 (host-width host) (host-height host))))))
        (setf (host-last-display host) display)
        (present (host-backend host) display damage)
        (host-blit host)))))

(defvar *touch-events* 0
  "Diagnostic: touch events drained since it was last zeroed.

Worth counting separately from frames. Too few, and the finger is outrunning
what we are told about it, which is a delivery problem. Plenty, and the motion
is merely being redrawn at the frame rate, which is a cost problem. The two feel
the same and are fixed in different places.")

(defun host-pump-touches (host)
  "Drain the touch queue and dispatch. Returns true if anything changed.

Drained rather than polled once per frame: POLL-TOUCH yields ONE queued event,
so taking one per frame makes input arrive at the frame rate and a burst of taps
appears seconds later. That is a backlog, not slow drawing, and the two look
identical from outside.

A press ARMS a widget and a release fires it, and only when the release lands on
the widget the press armed -- which is what lets a finger slide off to cancel."
  (let ((acted nil))
    (loop for event = (multiple-value-list (android:poll-touch))
          while (first event)
          do (incf *touch-events*)
             (destructuring-bind (action x y) event
               (multiple-value-bind (lx ly)
                   (scale-point (truncate x) (truncate y)
                                (host-x-ratio host) (host-y-ratio host))
                 (let ((placed (host-placed host)))
                   ;; Looked up only where it is USED, which is the press and
                   ;; the release. A drag asked for it too and threw it away,
                   ;; and a drag is fourteen of every sixteen events: measured on
                   ;; a Pixel 10 Pro XL, that was 31-79ms a frame, as much as
                   ;; drawing, and invisible because nothing timed this loop.
                   (flet ((hit ()
                            (and placed
                                 (hit-test placed lx ly
                                           (lambda (n) (node-prop n :on-press))))))
                   (case action
                     ;; Both edges owe a frame: a press changes the held
                     ;; highlight even when it fires nothing.
                     (0 (when (and placed (accessibility-enabled-p))
                          ;; A second hit test, and only when something is
                          ;; listening: with no reader running this costs one
                          ;; boolean, and with one running a tree walk per press
                          ;; is nothing against speaking a sentence.
                          (let ((spoken (hit-test placed lx ly #'semantic-p)))
                            (when spoken (announce-node spoken))))
                        (setf *pressed* (let ((hit (hit))) (and hit (node-prop hit :id)))
                              acted t
                              (host-dragging host) nil
                              (host-drag-origin host) (cons lx ly)
                              (host-drag-last host) (cons lx ly)
                              (host-drag-samples host) '()
                              ;; Every handler from the touch outwards, not just
                              ;; the innermost: a finger landing on a button
                              ;; inside a list scrolls the list, and a list that
                              ;; reaches its end hands the rest to the page.
                              (host-drag-chain host)
                              (remove-if-not (lambda (n) (node-prop n :on-drag))
                                             (reverse (hit-path placed lx ly)))))
                     (2 (let ((chain (host-drag-chain host))
                              (origin (host-drag-origin host)))
                          (when (and chain origin)
                            ;; Past the slop the touch is a drag, and stops
                            ;; being a press: a finger that scrolls away from a
                            ;; button must not also press it.
                            (when (or (host-dragging host)
                                      (> (+ (abs (- lx (car origin)))
                                            (abs (- ly (cdr origin))))
                                         *drag-slop*))
                              (unless (host-dragging host)
                                (setf (host-dragging host) t *pressed* nil))
                              (let ((last (host-drag-last host))
                                    (now (/ (float (get-internal-real-time))
                                            internal-time-units-per-second)))
                                ;; Offer the movement inwards out. A handler
                                ;; says how much it USED; anything that is not a
                                ;; number means all of it, so a handler written
                                ;; before this existed -- and they all end in
                                ;; INVALIDATE, which returns T -- behaves
                                ;; exactly as it did.
                                (let ((dx (- lx (car last)))
                                      (dy (- ly (cdr last))))
                                  (dolist (node chain)
                                    (when (and (zerop dx) (zerop dy)) (return))
                                    (multiple-value-bind (used-x used-y)
                                        (funcall (node-prop node :on-drag) node dx dy)
                                      (setf dx (if (numberp used-x) (- dx used-x) 0)
                                            dy (if (numberp used-y) (- dy used-y) 0)))))
                                ;; Real time, not the frame clock: a dozen
                                ;; touches arrive between two frames and the
                                ;; frame clock gives them all the same instant,
                                ;; which makes every velocity infinite or zero.
                                (push (list* now lx ly) (host-drag-samples host))
                                (setf (host-drag-samples host)
                                      (remove-if (lambda (sample)
                                                   (> (- now (first sample)) 1/10))
                                                 (host-drag-samples host))))
                              (setf (host-drag-last host) (cons lx ly)
                                    acted t)))))
                     (1 (let ((hit (hit)))
                          (when (and hit *pressed* (not (host-dragging host))
                                     (eq *pressed* (node-prop hit :id)))
                            (funcall (node-prop hit :on-press) hit)))
                        ;; A lifted finger that was moving hands its speed over.
                        ;; What to do with it is the application's: a list that
                        ;; should not fling simply does not keep the number.
                        (let ((node (find-if (lambda (n) (node-prop n :on-fling))
                                             (host-drag-chain host))))
                          (when (and node (host-dragging host))
                            (multiple-value-bind (vx vy)
                                (drag-velocity (host-drag-samples host))
                              (funcall (node-prop node :on-fling) node vx vy))))
                        (setf *pressed* nil acted t
                              (host-drag-chain host) '()
                              (host-drag-samples host) '()
                              (host-dragging host) nil))))))))
    acted))

(defun run-android-app (window view-function &key (design-width 360) (design-height 747))
  "Run an application until its window goes away.

VIEW-FUNCTION is called with the logical width and height and returns a view
tree. It may read *PRESSED* to render a held control. That is the whole contract:
no window handling, no touch arithmetic, no blit.

The loop only builds a frame when it is DIRTY. This matters more than it sounds:
measured on a Pixel 10 Pro XL, rebuilding and laying out this interface costs
~70ms, and doing it unconditionally at every pass burned 88% of the loop on a
screen nobody had touched -- which is what made touches queue behind work nobody
needed and read as lag. An interface that changes only when the user does
something should cost nothing when they are not doing anything."
  (let ((host (open-android-host window :design-width design-width
                                        :design-height design-height)))
    (setf *dirty* t)
    (loop while (android:running-p)
          do (cond ((android:paused-p) (sleep 0.02))
                   (t
                    ;; A touch may fire a handler, which may change anything the
                    ;; view reads, so any dispatched touch owes a frame.
                    (when (host-pump-touches host) (invalidate))
                    (refresh-insets host)
                    (cond (*dirty*
                           (setf *dirty* nil)
                           (with-frame-clock (host)
                             (host-draw host (funcall view-function
                                                      (host-width host)
                                                      (host-height host)))))
                          (t (sleep 0.008))))))))
