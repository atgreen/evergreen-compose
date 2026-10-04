;;;; Microseconds per call, for the things the frame loop does on every pass.
;;;;
;;;; GET-INTERNAL-REAL-TIME ticks once a millisecond, so one call cannot be
;;;; timed; N of them can. Loaded by a demo that wants the numbers, never by
;;;; default: this holds the loop for a second or two at start-up.
(in-package :cl-user)

(defmacro bench (name count &body body)
  `(let ((start (get-internal-real-time)))
     (dotimes (i ,count) ,@body)
     (let ((ms (- (get-internal-real-time) start)))
       (android:log (format nil "bench ~36A ~7,1F us" ,name (/ (* 1000.0 ms) ,count))))))

(defun run-bench (host)
  (let* ((api (egcl-ffi:foreign-symbol-pointer "egcl_android_api_version"
                                               egcl-android::*runtime*))
         (insets-class (bliss::java-class bliss::+insets-class+))
         (activity (bliss::java-activity))
         (get-window (bliss::java-method bliss::+activity-class+ "getWindow"
                                         "()Landroid/view/Window;")))
    (bench "get-internal-real-time" 20000 (get-internal-real-time))
    (bench "%ffi-call, no args" 2000 (egcl::%ffi-call api :int nil nil))
    (bench "android:activity" 2000 (android:activity))
    (bench "jni-args (:int 1)" 2000 (bliss::jni-args (list :int 1)))
    (bench "jni-call-object getWindow" 2000
      (bliss::jni-call-object activity get-window (bliss::jni-args)))
    (bench "java-method, cached" 2000
      (bliss::java-method bliss::+activity-class+ "getWindow" "()Landroid/view/Window;"))
    (bench "gethash fresh 3-string key" 2000
      (gethash (list "android/view/Window" "getDecorView" "()Landroid/view/View;")
               bliss::*java*))
    (bench "with-c-string 30 chars" 2000
      (android:with-c-string (p "android/view/WindowInsets$Type") p))
    (bench "foreign-alloc+free 8" 2000
      (egcl-ffi:foreign-free (egcl-ffi:foreign-alloc 8)))
    (bench "with-local-refs empty" 2000 (bliss::with-local-refs () 1))
    (bench "decor-view" 500 (bliss::decor-view))
    (bench "jni-field left" 500 (bliss::jni-field insets-class "left" "I"))
    (bench "window-insets :ime" 200 (bliss::window-insets :ime))
    (bench "refresh-insets" 100 (bliss:refresh-insets host))
    (bench "poll-touch, empty" 2000 (android:poll-touch))
    (bench "host-tap-tick" 2000 (bliss::host-tap-tick host))
    (bench "host-pump-touches, empty" 500 (bliss:host-pump-touches host))
    (bench "pump-text-input, no focus" 2000 (bliss:pump-text-input))
    (bench "live-repl-poll" 2000 (bliss:live-repl-poll))
    (bench "sync-platform-views" 200 (bliss:sync-platform-views host))
    (bench "keep-app-state" 200 (keep-app-state))))

(defun bench-gc (host)
  "TIME a burst of foreign calls, to logcat: the GC count is the point."
  (declare (ignore host))
  (let ((api (egcl-ffi:foreign-symbol-pointer "egcl_android_api_version"
                                              egcl-android::*runtime*)))
    (android:log
     (with-output-to-string (s)
       (let ((*trace-output* s))
         (time (dotimes (i 5000) (egcl::%ffi-call api :int nil nil))))))))

(defun bench-variadic (host)
  "Can a JNI method be called through its VARIADIC entry -- CallVoidMethod,
not CallVoidMethodA -- with the arguments passed straight through %FFI-CALL's
fixed-count variadic support, and no jvalue buffer at all? Round-trips a
colour through Paint.setColor/getColor both ways, then times both."
  (let* ((canvas (bliss::canvas-backend-canvas (bliss:host-backend host)))
         (paint (bliss::canvas-paint canvas))
         (set-colour (bliss::canvas-set-colour canvas))
         (get-colour (bliss::jni-method (bliss::jni-find-class "android/graphics/Paint")
                                        "getColor" "()I"))
         (call-void (bliss::jni-slot 61))
         (call-int-a (bliss::jni-slot bliss::+jni-call-int-method-a+)))
    (flet ((get () (egcl::%ffi-call call-int-a :int '(:pointer :pointer :pointer :pointer)
                                    (list bliss::*env* paint get-colour (bliss::jni-args))))
           (set-a (c) (bliss::jni-call-void paint set-colour (bliss::jni-args (list :int c))))
           (set-v (c) (egcl::%ffi-call call-void :void '(:pointer :pointer :pointer :int)
                                       (list bliss::*env* paint set-colour c) 3)))
      (set-a -16711936) (android:log (format nil "variadic probe: via A ~D" (get)))
      (set-v -65536)    (android:log (format nil "variadic probe: via ... ~D (want -65536)" (get)))
      (bench "setColor via jni-args + A" 2000 (set-a -1))
      (bench "setColor variadic" 2000 (set-v -1)))))

(defun bench-variadic-float (host)
  "Floats through the variadic entry: C promotes a float argument to double,
so a jfloat parameter is passed as :DOUBLE. Round-trips Paint.setTextSize /
getTextSize, then times drawRoundRect's seven floats both ways."
  (let* ((canvas (bliss::canvas-backend-canvas (bliss:host-backend host)))
         (paint (bliss::canvas-paint canvas))
         (object (bliss::canvas-object canvas))
         (paint-class (bliss::jni-find-class "android/graphics/Paint"))
         (set-size (bliss::canvas-set-text-size canvas))
         (get-size (bliss::jni-method paint-class "getTextSize" "()F"))
         (draw (bliss::canvas-draw-round-rect canvas)))
    (egcl::%ffi-call (bliss::jni-slot 61) :void '(:pointer :pointer :pointer :double)
                     (list bliss::*env* paint set-size 37.5d0) 3)
    (android:log (format nil "variadic float probe: getTextSize ~A (want 37.5)"
                         (egcl::%ffi-call (bliss::jni-slot 55) :float '(:pointer :pointer :pointer)
                                          (list bliss::*env* paint get-size) 3)))
    (bliss::canvas-text-size canvas 12)
    (bench "drawRoundRect via jni-args + A" 1000
      (bliss::jni-call-void object draw
                            (bliss::jni-args (list :float 1) (list :float 2) (list :float 30)
                                             (list :float 40) (list :float 3) (list :float 3)
                                             (list :object paint))))
    (bench "drawRoundRect variadic" 1000
      (egcl::%ffi-call (bliss::jni-slot 61) :void
                       '(:pointer :pointer :pointer :double :double :double :double :double :double :pointer)
                       (list bliss::*env* object draw 1d0 2d0 30d0 40d0 3d0 3d0 paint) 3))))
