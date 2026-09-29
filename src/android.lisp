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
   (drag-node :initform nil :accessor host-drag-node)
   (drag-origin :initform nil :accessor host-drag-origin)
   (drag-last :initform nil :accessor host-drag-last)
   (dragging :initform nil :accessor host-dragging)
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
          do (destructuring-bind (action x y) event
               (multiple-value-bind (lx ly)
                   (scale-point (truncate x) (truncate y)
                                (host-x-ratio host) (host-y-ratio host))
                 (let* ((placed (host-placed host))
                        (hit (and placed
                                  (hit-test placed lx ly
                                            (lambda (n) (node-prop n :on-press))))))
                   (case action
                     ;; Both edges owe a frame: a press changes the held
                     ;; highlight even when it fires nothing.
                     (0 (setf *pressed* (and hit (node-prop hit :id))
                              acted t
                              (host-dragging host) nil
                              (host-drag-origin host) (cons lx ly)
                              (host-drag-last host) (cons lx ly)
                              ;; A drag may be captured by an ANCESTOR of what
                              ;; was pressed: a finger landing on a button
                              ;; inside a list still scrolls the list.
                              (host-drag-node host)
                              (hit-test placed lx ly
                                        (lambda (n) (node-prop n :on-drag)))))
                     (2 (let ((node (host-drag-node host))
                              (origin (host-drag-origin host)))
                          (when (and node origin)
                            ;; Past the slop the touch is a drag, and stops
                            ;; being a press: a finger that scrolls away from a
                            ;; button must not also press it.
                            (when (or (host-dragging host)
                                      (> (+ (abs (- lx (car origin)))
                                            (abs (- ly (cdr origin))))
                                         *drag-slop*))
                              (unless (host-dragging host)
                                (setf (host-dragging host) t *pressed* nil))
                              (let ((last (host-drag-last host)))
                                (funcall (node-prop node :on-drag) node
                                         (- lx (car last)) (- ly (cdr last))))
                              (setf (host-drag-last host) (cons lx ly)
                                    acted t)))))
                     (1 (when (and hit *pressed* (not (host-dragging host))
                                   (eq *pressed* (node-prop hit :id)))
                          (funcall (node-prop hit :on-press) hit))
                        (setf *pressed* nil acted t
                              (host-drag-node host) nil
                              (host-dragging host) nil)))))))
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
                    (cond (*dirty*
                           (setf *dirty* nil)
                           ;; A FLOAT, not the exact ratio the division gives:
                           ;; a rational clock is surprising to arithmetic that
                           ;; expects a number it can print, and ~F rejects it
                           ;; outright -- which killed the worker on the first
                           ;; frame after a touch and left the last frame on
                           ;; screen looking like dead input.
                           (let* ((clock (float (/ (get-internal-real-time)
                                                   internal-time-units-per-second)
                                                1.0d0))
                                  (*frame-time* (- clock (or (host-started host)
                                                             (setf (host-started host) clock))))
                                  (*frame-delta* (min 1/10
                                                      (- *frame-time*
                                                         (or (host-last-frame host)
                                                             *frame-time*))))
                                  (*animating* nil))
                             (setf (host-last-frame host) *frame-time*)
                             (host-draw host (funcall view-function
                                                      (host-width host)
                                                      (host-height host)))
                             ;; The view said it is not settled, so it is owed
                             ;; another frame. Asked for AFTER the build, so an
                             ;; animation that just finished does not get one.
                             (when *animating* (invalidate))))
                          (t (sleep 0.008))))))))
