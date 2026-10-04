(load "egl.lisp")
(load "bliss.lisp")
(in-package :cl-user)

;;;; Bliss drawn by Android's own Skia, through android.graphics.Canvas.
;;;;
;;;; No EGL, no GL, no shaders. Skia fills a Bitmap, libjnigraphics hands over
;;;; its pixels, and ANativeWindow_lock puts them on screen -- a path measured at
;;;; one vsync per frame, so the transport is free.

(defparameter *touches* 0)
(defparameter *last-x* 0)
(defparameter *last-y* 0)
(defparameter *frames* 0)

(defun ui (width height)
  `(column (:padding 16 :gap 14 :background "#101820" :width ,width :height ,height)
     (label (:text "Bliss" :size 6 :colour "#ffffff"))
     (label (:text "Drawn by Skia, described in Lisp" :size 2 :colour "#7fd4ff"))
     (row (:gap 8)
       (box (:width 40 :height 40 :fill "#e04040"))
       (box (:width 40 :height 40 :fill "#40c040"))
       (box (:width 40 :height 40 :fill "#4080ff")))
     (label (:text ,(format nil "Touches: ~D" *touches*) :size 4 :colour "#ffd040"))
     (label (:text ,(format nil "x ~D  y ~D" *last-x* *last-y*) :size 2 :colour "#a0a0a0"))))

(defun android-main (window)
  (android:log (format nil "canvas: JNI ready, version #x~X" (bliss:jni-start)))
  (let* ((lib (egcl-ffi:load-foreign-library "libandroid.so"))
         (set-geometry (egcl-ffi:foreign-symbol-pointer "ANativeWindow_setBuffersGeometry" lib))
         (lock (egcl-ffi:foreign-symbol-pointer "ANativeWindow_lock" lib))
         (post (egcl-ffi:foreign-symbol-pointer "ANativeWindow_unlockAndPost" lib))
         ;; Skia does the rasterizing, so the logical surface can be far larger
         ;; than the software backend could afford.
         (height 747)
         (buffer (egcl-ffi:foreign-alloc 48))
         (memcpy (egcl-ffi:foreign-symbol-pointer "memcpy"))
         (last-display nil)
         ;; Ask for a width, then find out what the window ACTUALLY gives: it
         ;; pads the stride for alignment (360 becomes 384 on this device). A
         ;; Bitmap the width of the padded stride makes the blit ONE memcpy
         ;; instead of one per row, which was 747 foreign calls and most of the
         ;; frame. Probing beats hardcoding, since the alignment is the
         ;; compositor's business and not the same everywhere.
         (width (progn
                  (egcl-ffi:foreign-call set-geometry :int '(:pointer :int :int :int)
                                          (list window 360 height 1))
                  (egcl-ffi:foreign-call lock :int '(:pointer :pointer :pointer)
                                          (list window buffer (egcl-ffi:null-pointer)))
                  (let ((stride (egcl-ffi:mem-ref buffer :int 8)))
                    (egcl-ffi:foreign-call post :int '(:pointer) (list window))
                    stride)))
         (canvas (bliss:canvas-open width height)))
    (egcl-ffi:foreign-call set-geometry :int '(:pointer :int :int :int)
                            (list window width height 1))
    (android:log (format nil "canvas: ~Dx~D, memcpy ~:[MISSING~;ok~]" width height
                         (and memcpy (not (egcl-ffi:null-pointer-p memcpy)))))
    (loop while (android:running-p)
          do (if (android:paused-p)
                 (sleep 0.02)
                 (progn
                   (loop for event = (multiple-value-list (android:poll-touch))
                         while (first event)
                         do (when (= (first event) 0)
                              (incf *touches*)
                              (setf *last-x* (truncate (second event))
                                    *last-y* (truncate (third event)))))
                   (let ((display (bliss:render (bliss:layout (ui width height) 0 0))))
                     (if (equal display last-display)
                         (sleep 0.008)
                         (let ((start (get-internal-real-time)))
                           (setf last-display display)
                           (bliss:canvas-draw canvas display)
                           (let ((drawn (get-internal-real-time)))
                             ;; Bitmap -> window. Both are RGBA_8888; when the
                             ;; strides agree this is one memcpy, and when they
                             ;; do not it has to be one per row or the image
                             ;; skews.
                             (multiple-value-bind (src src-stride) (bliss:canvas-pixels canvas)
                               (egcl-ffi:foreign-call lock :int '(:pointer :pointer :pointer)
                                                       (list window buffer (egcl-ffi:null-pointer)))
                               (let ((dst (egcl-ffi:mem-ref buffer :pointer 16))
                                     (dst-stride (egcl-ffi:mem-ref buffer :int 8)))
                                 (when (= *frames* 0)
                                   (android:log (format nil "canvas: bitmap stride ~D, window stride ~D"
                                                        src-stride dst-stride)))
                                 (if (= src-stride dst-stride)
                                     (egcl-ffi:foreign-call memcpy :pointer
                                                             '(:pointer :pointer :long)
                                                             (list dst src (* 4 src-stride height)))
                                     (dotimes (row height)
                                       (egcl-ffi:foreign-call
                                        memcpy :pointer '(:pointer :pointer :long)
                                        (list (egcl-ffi:inc-pointer dst (* 4 row dst-stride))
                                              (egcl-ffi:inc-pointer src (* 4 row src-stride))
                                              (* 4 width))))))
                               (bliss:canvas-release-pixels canvas)
                               (egcl-ffi:foreign-call post :int '(:pointer) (list window)))
                             (incf *frames*)
                             (android:log
                              (format nil "canvas redraw ~D: skia ~Dms blit ~Dms (~D ops)"
                                      *frames*
                                      (round (* 1000 (- drawn start))
                                             internal-time-units-per-second)
                                      (round (* 1000 (- (get-internal-real-time) drawn))
                                             internal-time-units-per-second)
                                      (length display)))))))))))
)
