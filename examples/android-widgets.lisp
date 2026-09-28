(load "egl.lisp")
(load "bliss.lisp")
(in-package :cl-user)

;;;; Widgets, drawn by Skia, described in Lisp.
;;;;
;;;; The whole interface is a function of these four variables. Nothing in the
;;;; view tree remembers anything between frames, so redefining UI at a REPL
;;;; would change the running app on its next touch.

(defparameter *count* 0)
(defparameter *loud* nil)
(defparameter *pressed* nil "The :ID currently held down, or NIL.")
(defparameter *last* "nothing yet")

(defun ui (width height)
  `(column (:padding 20 :gap 14 :background ,(bliss:theme :surface)
            :width ,width :height ,height)
     ,(bliss:text "Bliss widgets" :size 5)
     ,(bliss:text "buttons, hit testing, dispatch" :size 2 :colour (bliss:theme :muted))
     ,(bliss:spacer :height 6)
     ,(bliss:text (format nil "Count: ~D" *count*) :size 6 :colour (bliss:theme :ink))
     ;; Both buttons GROW, so they split the row evenly and stay even when the
     ;; labels differ in width -- and each label is centred in whatever width it
     ;; lands with. Neither is expressible without constraints.
     (row (:gap 12 :width ,(- width 40))
       ,(bliss:button "Less" :id :minus :size 4 :grow 1 :pressed (eq *pressed* :minus)
                      :on-press (lambda (node) (declare (ignore node)) (decf *count*)))
       ,(bliss:button "More" :id :plus :size 4 :grow 2 :pressed (eq *pressed* :plus)
                      :on-press (lambda (node) (declare (ignore node)) (incf *count*))))
     ,(bliss:spacer :height 4)
     (row (:gap 12 :width ,(- width 40))
       ,(bliss:toggle "Loud" :id :loud :on *loud* :size 3 :grow 1
                      :on-press (lambda (node) (declare (ignore node)) (setf *loud* (not *loud*))))
       ,(bliss:button "Reset" :id :reset :size 3 :grow 1 :pressed (eq *pressed* :reset)
                      :disabled (zerop *count*)
                      :on-press (lambda (node) (declare (ignore node)) (setf *count* 0))))
     ,(bliss:spacer :height 6)
     ,(bliss:text (format nil "last: ~A" *last*) :size 2 :colour (bliss:theme :muted))))

(defun android-main (window)
  (bliss:jni-start)
  (let* ((lib (torcl-ffi:load-foreign-library "libandroid.so"))
         (call (lambda (name ret types args)
                 (torcl-ffi:foreign-call
                  (torcl-ffi:foreign-symbol-pointer name lib) ret types args)))
         ;; Ask the window its real size BEFORE changing the buffer geometry,
         ;; because afterwards it reports the buffer and not the display -- and
         ;; the ratio between them is what turns a touch into a hit.
         (physical-width (funcall call "ANativeWindow_getWidth" :int '(:pointer) (list window)))
         (buffer (torcl-ffi:foreign-alloc 48))
         (memcpy (torcl-ffi:foreign-symbol-pointer "memcpy"))
         (height 747)
         (width (progn
                  (funcall call "ANativeWindow_setBuffersGeometry" :int '(:pointer :int :int :int)
                           (list window 360 height 1))
                  (funcall call "ANativeWindow_lock" :int '(:pointer :pointer :pointer)
                           (list window buffer (torcl-ffi:null-pointer)))
                  (let ((stride (torcl-ffi:mem-ref buffer :int 8)))
                    (funcall call "ANativeWindow_unlockAndPost" :int '(:pointer) (list window))
                    stride)))
         (canvas (bliss:canvas-open width height))
         ;; Touches arrive in device pixels; the tree is laid out in logical
         ;; ones. A ratio, not an integer: 1080/384 is 2.8125.
         (ratio (/ physical-width width))
         (placed nil)
         (last-display nil))
    (funcall call "ANativeWindow_setBuffersGeometry" :int '(:pointer :int :int :int)
             (list window width height 1))
    (android:log (format nil "widgets: ~Dx~D logical, ~D physical, ratio ~A"
                         width height physical-width ratio))
    (loop while (android:running-p)
          do (if (android:paused-p)
                 (sleep 0.02)
                 (progn
                   (loop for event = (multiple-value-list (android:poll-touch))
                         while (first event)
                         do (destructuring-bind (action x y) event
                              (multiple-value-bind (lx ly)
                                  (bliss:scale-point (truncate x) (truncate y) ratio)
                                (when placed
                                  (case action
                                    ;; Press ARMS a widget; it does not fire it.
                                    ;; Firing on release, and only when the
                                    ;; release lands on the same widget, is what
                                    ;; lets a finger slide off to cancel.
                                    (0 (let ((hit (bliss:hit-test
                                                   placed lx ly
                                                   (lambda (n) (bliss:node-prop n :on-press)))))
                                         (setf *pressed* (and hit (bliss:node-prop hit :id)))))
                                    (1 (let ((hit (bliss:hit-test
                                                   placed lx ly
                                                   (lambda (n) (bliss:node-prop n :on-press)))))
                                         (when (and hit *pressed*
                                                    (eq *pressed* (bliss:node-prop hit :id)))
                                           (setf *last* (string-downcase
                                                         (princ-to-string *pressed*)))
                                           (funcall (bliss:node-prop hit :on-press) hit)))
                                       (setf *pressed* nil)))))))
                   (setf placed (bliss:layout (ui width height) 0 0))
                   (let ((display (bliss:render placed)))
                     (if (equal display last-display)
                         (sleep 0.008)
                         (progn
                           (setf last-display display)
                           (bliss:canvas-draw canvas display)
                           (multiple-value-bind (src stride) (bliss:canvas-pixels canvas)
                             (funcall call "ANativeWindow_lock" :int '(:pointer :pointer :pointer)
                                      (list window buffer (torcl-ffi:null-pointer)))
                             (torcl-ffi:foreign-call
                              memcpy :pointer '(:pointer :pointer :long)
                              (list (torcl-ffi:mem-ref buffer :pointer 16) src
                                    (* 4 stride height)))
                             (bliss:canvas-release-pixels canvas)
                             (funcall call "ANativeWindow_unlockAndPost" :int '(:pointer)
                                      (list window)))))))))))
