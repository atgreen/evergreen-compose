(load "egl.lisp")
(load "bliss.lisp")
(in-package :cl-user)

;;;; A Bliss application. The interesting part is that the UI is a FUNCTION
;;;; RETURNING DATA: nothing is retained between frames, nothing is mutated in
;;;; place, and the whole screen is whatever the list says this frame.

(defparameter *touches* 0)
(defparameter *last-x* 0)
(defparameter *last-y* 0)
(defparameter *frames* 0)

(defun ui (width height)
  ;; WIDTH and HEIGHT are logical, not physical: the root is pinned to the whole
  ;; surface so its background covers the screen. Without this the column sizes
  ;; to its content and everything below the last child stays unpainted.
  `(column (:padding 6 :gap 5 :background "#101820" :width ,width :height ,height)
     (label (:text "BLISS" :size 3 :colour "#ffffff"))
     (label (:text "LISP UI ON ANDROID" :size 1 :colour "#7fd4ff"))
     (row (:gap 3)
       (box (:width 14 :height 14 :fill "#e04040"))
       (box (:width 14 :height 14 :fill "#40c040"))
       (box (:width 14 :height 14 :fill "#4080ff")))
     (label (:text ,(format nil "TOUCHES ~D" *touches*) :size 2 :colour "#ffd040"))
     (label (:text ,(format nil "X ~D Y ~D" *last-x* *last-y*) :size 1 :colour "#a0a0a0"))))

(defun android-main (window)
  (torcl-egl:with-window (window)
    (bliss:gles-init torcl-egl::*gles*)
    (multiple-value-bind (width height)
        (bliss:gles-surface-size torcl-egl::*egl* torcl-egl::*display* torcl-egl::*surface*)
      ;; The UI is authored in logical pixels and scaled by a whole number, so a
      ;; 5x7 glyph stays a crisp block on a 1080-wide phone instead of being
      ;; resampled into mush. 120 logical columns is the design width. Logical
      ;; size rounds UP so the root covers the last partial pixel column rather
      ;; than leaving a seam at the right and bottom edges.
      (let* ((scale (max 1 (floor width 120)))
             (logical-width (ceiling width scale))
             (logical-height (ceiling height scale))
             ;; The skip-if-unchanged cache is scoped to THIS surface, and must
             ;; be, because it is really a statement about what is in the
             ;; surface's buffers. Backgrounding the app destroys the native
             ;; window and ANDROID-MAIN is re-entered with a new EGL surface
             ;; whose buffers are undefined; a cache that outlived the old
             ;; surface then reports "unchanged" against a black screen and
             ;; nothing is ever drawn again. Binding it here ties its lifetime
             ;; to the thing it describes.
             (last-display nil))
        (android:log (format nil "Bliss: surface ~Dx~D scale ~D" width height scale))
        ;; One-shot: what does a single foreign call cost here? glGetError takes
        ;; no arguments and returns an int, so this times the call path itself
        ;; with the context already current -- separating "the FFI is slow" from
        ;; "the GPU is slow", which the issue/swap split has already narrowed to
        ;; the issuing side.
        (let ((probe (torcl-ffi:foreign-symbol-pointer "glGetError" torcl-egl::*gles*))
              (n 5000))
          (let ((start (get-internal-real-time)))
            (dotimes (i n) (torcl-ffi:foreign-call probe :int (quote ()) (quote ())))
            (let ((ms (round (* 1000 (- (get-internal-real-time) start))
                             internal-time-units-per-second)))
              (android:log (format nil "ffi probe: ~D glGetError in ~Dms = ~,1F us/call"
                                   n ms (/ (* 1000.0 ms) n))))))
        (loop while (android:running-p)
              do (if (android:paused-p)
                     (sleep 0.02)
                     (progn
                       ;; DRAIN the queue rather than taking one event per frame.
                       ;; POLL-TOUCH returns a single queued event, so polling
                       ;; once per frame makes input arrive AT the frame rate:
                       ;; tap ten times at 10fps and the tenth is seen a second
                       ;; late. That is a backlog, not slow drawing, and from
                       ;; the outside the two look identical.
                       (loop for event = (multiple-value-list (android:poll-touch))
                             while (first event)
                             do (when (= (first event) 0)
                                  (incf *touches*)
                                  (setf *last-x* (truncate (second event))
                                        *last-y* (truncate (third event)))))
                       ;; RENDER is a pure function of the view tree, so an
                       ;; unchanged tree gives an EQUAL display list and the
                       ;; frame already on screen is still correct. Skipping the
                       ;; draw and the swap then costs nothing, and the front
                       ;; buffer keeps showing the last frame.
                       ;;
                       ;; This is what makes the UI feel responsive despite a
                       ;; ~100ms redraw: that cost is paid once per change
                       ;; instead of continuously, so touches stop queueing
                       ;; behind frames nobody needed.
                       (let ((display (bliss:render
                                       (bliss:layout (ui logical-width logical-height) 0 0))))
                         (if (equal display last-display)
                             (sleep 0.008)
                             ;; Split ISSUING the GL calls from SWAPPING. They
                             ;; fail differently: time in the first is FFI and
                             ;; driver call overhead, time in the second is this
                             ;; thread blocked waiting for the GPU to catch up.
                             ;; Only the second explains a cost that grows when
                             ;; frames come close together.
                             (let* ((t0 (get-internal-real-time))
                                    (ignore1 (setf last-display display))
                                    (ignore2 (bliss:gles-draw display width height scale))
                                    (t1 (get-internal-real-time))
                                    (ignore3 (torcl-egl:swap))
                                    (t2 (get-internal-real-time)))
                               (declare (ignore ignore1 ignore2 ignore3))
                               (incf *frames*)
                               (android:log
                                (format nil "redraw ~D: issue ~Dms swap ~Dms ~D rects" *frames*
                                        (round (* 1000 (- t1 t0)) internal-time-units-per-second)
                                        (round (* 1000 (- t2 t1)) internal-time-units-per-second)
                                        (length (bliss:flatten-to-rects display))))))))))))))
