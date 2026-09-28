(in-package :bliss)

;;;; The Canvas backend: Bliss display lists drawn by Android's own Skia.
;;;;
;;;; android.graphics.Canvas IS Skia -- it is what every Android app draws
;;;; through -- so this gets shaped, antialiased, font-fallback text and real
;;;; path filling without shipping a renderer or a font.
;;;;
;;;; Why this shape, given the measurements: a JNI call costs ~35us here and
;;;; almost all of that is TorCL's FFI rather than Java. So the winning move is
;;;; to make each call do as much as possible. One drawText call renders a whole
;;;; string; the software backend spends ~180 rectangles on the same label. The
;;;; corollary is that everything resolvable once -- classes, method IDs, the
;;;; Paint, the jstrings -- is resolved once and cached, because a cache miss
;;;; costs the same as the drawing.
;;;;
;;;; Canvas draws into a Bitmap rather than a Surface: NativeActivity hands out
;;;; an ANativeWindow, and the NDK has no ANativeWindow -> Surface conversion.
;;;; Skia fills the Bitmap, libjnigraphics hands us its pixels, and the window
;;;; blit that experiment 2 measured as free (vsync-bound) puts it on screen.

(defstruct canvas
  bitmap object paint
  draw-rect draw-round-rect draw-text draw-colour save restore clip-rect
  set-colour set-text-size set-anti-alias ascent
  width height
  lock-pixels unlock-pixels bitmap-info info-buffer
  create-bitmap bitmap-class argb-8888 draw-bitmap src-rect dst-rect rect-set rectf-set
  (strings (make-hash-table :test #'equal))
  (images (make-hash-table :test #'eq)))

(defun android-colour (colour)
  "A Bliss #xRRGGBBAA colour as Android's ARGB integer.

Sign matters: Android takes a Java int, and a colour with alpha above 0x7F has
its top bit set, so the value must be passed as the NEGATIVE two's-complement
int Java expects rather than a positive bignum."
  (let ((argb (logior (ash (colour-alpha colour) 24)
                      (ash (colour-red colour) 16)
                      (ash (colour-green colour) 8)
                      (colour-blue colour))))
    (if (> argb #x7FFFFFFF) (- argb #x100000000) argb)))

(defun canvas-open (width height)
  "Create a WIDTH x HEIGHT Canvas over a Bitmap, with everything cached."
  (let* ((bitmap-class (jni-find-class "android/graphics/Bitmap"))
         (config-class (jni-find-class "android/graphics/Bitmap$Config"))
         (canvas-class (jni-find-class "android/graphics/Canvas"))
         (paint-class (jni-find-class "android/graphics/Paint"))
         (argb-8888 (jni-static-object-field config-class "ARGB_8888"
                                             "Landroid/graphics/Bitmap$Config;"))
         (create (jni-method bitmap-class "createBitmap"
                             "(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;"
                             :static t))
         (bitmap (jni-global
                  (jni-call-static-object bitmap-class create
                                          (jni-args (list :int width) (list :int height)
                                                    (list :object argb-8888)))))
         (canvas-init (jni-method canvas-class "<init>" "(Landroid/graphics/Bitmap;)V"))
         (canvas (jni-global (jni-new canvas-class canvas-init
                                      (jni-args (list :object bitmap)))))
         (paint-init (jni-method paint-class "<init>" "()V"))
         (paint (jni-global (jni-new paint-class paint-init (jni-args))))
         (graphics (torcl-ffi:load-foreign-library "libjnigraphics.so")))
    (jni-check)
    (let ((canvas (make-canvas
                   :bitmap bitmap :object canvas :paint paint :width width :height height
                   :draw-rect (jni-method canvas-class "drawRect"
                                          "(FFFFLandroid/graphics/Paint;)V")
                   ;; Skia has real arcs and a real clip stack, so the backend
                   ;; uses them rather than the span decomposition that exists
                   ;; for backends which can only fill rectangles.
                   :draw-round-rect (jni-method canvas-class "drawRoundRect"
                                                "(FFFFFFLandroid/graphics/Paint;)V")
                   :save (jni-method canvas-class "save" "()I")
                   :restore (jni-method canvas-class "restore" "()V")
                   :clip-rect (jni-method canvas-class "clipRect" "(FFFF)Z")
                   :draw-text (jni-method canvas-class "drawText"
                                          "(Ljava/lang/String;FFLandroid/graphics/Paint;)V")
                   :draw-colour (jni-method canvas-class "drawColor" "(I)V")
                   :set-colour (jni-method paint-class "setColor" "(I)V")
                   :set-text-size (jni-method paint-class "setTextSize" "(F)V")
                   :set-anti-alias (jni-method paint-class "setAntiAlias" "(Z)V")
                   :ascent (jni-method paint-class "ascent" "()F")
                   :lock-pixels (torcl-ffi:foreign-symbol-pointer
                                 "AndroidBitmap_lockPixels" graphics)
                   :unlock-pixels (torcl-ffi:foreign-symbol-pointer
                                   "AndroidBitmap_unlockPixels" graphics)
                   :bitmap-info (torcl-ffi:foreign-symbol-pointer
                                 "AndroidBitmap_getInfo" graphics)
                   :info-buffer (torcl-ffi:foreign-alloc 32)
                   :create-bitmap create :bitmap-class bitmap-class :argb-8888 argb-8888
                   :draw-bitmap (jni-method canvas-class "drawBitmap"
                                            "(Landroid/graphics/Bitmap;Landroid/graphics/Rect;Landroid/graphics/RectF;Landroid/graphics/Paint;)V")
                   ;; One Rect and one RectF, reused and re-SET per draw. Making
                   ;; a pair per image per frame would cost two allocations and
                   ;; two constructor calls at ~35us each, to say four numbers.
                   :src-rect (let ((class (jni-find-class "android/graphics/Rect")))
                               (jni-global (jni-new class (jni-method class "<init>" "()V")
                                                    (jni-args))))
                   :dst-rect (let ((class (jni-find-class "android/graphics/RectF")))
                               (jni-global (jni-new class (jni-method class "<init>" "()V")
                                                    (jni-args))))
                   :rect-set (jni-method (jni-find-class "android/graphics/Rect")
                                         "set" "(IIII)V")
                   :rectf-set (jni-method (jni-find-class "android/graphics/RectF")
                                          "set" "(FFFF)V"))))
      ;; Antialiasing on, once. It is a Paint flag, not a per-call argument, and
      ;; it is the reason for using Skia at all.
      (jni-call-void paint (canvas-set-anti-alias canvas) (jni-args (list :int 1)))
      (jni-check)
      ;; Layout must measure with the font that will be drawn, so this is part
      ;; of opening a canvas rather than something a caller can forget.
      (canvas-install-metrics canvas)
      canvas)))

(defun canvas-install-metrics (canvas)
  "Make TEXT-EXTENT report what Skia will actually draw.

Without this, layout centres and sizes every label using the built-in 5x7 font
while Canvas draws Roboto, so boxes are laid out for a font that never appears.
Measurements are cached by text and size: each one is a JNI call at ~35us, and a
label measured during layout is measured again on the next frame otherwise."
  (let ((cache (make-hash-table :test #'equal))
        (paint (canvas-paint canvas))
        (measure (jni-method (jni-find-class "android/graphics/Paint")
                             "measureText" "(Ljava/lang/String;)F"))
        (descent (jni-method (jni-find-class "android/graphics/Paint")
                             "descent" "()F")))
    (setf *measure-text*
          (lambda (text scale)
            (let ((key (cons text scale)))
              (let ((hit (gethash key cache)))
                (if hit
                    (values (car hit) (cdr hit))
                    (let ((size (* scale +glyph-height+)))
                      (jni-call-void paint (canvas-set-text-size canvas)
                                     (jni-args (list :float size)))
                      (let* ((width (torcl-ffi:foreign-call
                                     (jni-slot +jni-call-float-method-a+) :float
                                     '(:pointer :pointer :pointer :pointer)
                                     (list *env* paint measure
                                           (jni-args (list :object (canvas-string canvas text))))))
                             (rise (torcl-ffi:foreign-call
                                    (jni-slot +jni-call-float-method-a+) :float
                                    '(:pointer :pointer :pointer :pointer)
                                    (list *env* paint (canvas-ascent canvas) (jni-args))))
                             (fall (torcl-ffi:foreign-call
                                    (jni-slot +jni-call-float-method-a+) :float
                                    '(:pointer :pointer :pointer :pointer)
                                    (list *env* paint descent (jni-args))))
                             ;; Layout works in whole pixels, and a box that
                             ;; rounds DOWN clips the glyph it was measured for.
                             (extent (cons (ceiling width) (ceiling (- fall rise)))))
                        (setf (gethash key cache) extent)
                        (values (car extent) (cdr extent)))))))))))

(defun canvas-image (canvas source)
  "SOURCE as a Java Bitmap, uploaded once and cached.

A Bliss surface stores one word per pixel with its bytes in R,G,B,A order, which
is exactly what Android calls ARGB_8888 in memory, so the upload is a bulk copy
into the Bitmap's own buffer rather than a per-pixel conversion. Cached by the
surface's identity: re-uploading an unchanged image every frame would cost more
than drawing it."
  (or (gethash source (canvas-images canvas))
      (let* ((width (surface-width source))
             (height (surface-height source))
             (bitmap (jni-global
                      (jni-call-static-object
                       (canvas-bitmap-class canvas) (canvas-create-bitmap canvas)
                       (jni-args (list :int width) (list :int height)
                                 (list :object (canvas-argb-8888 canvas))))))
             (address (torcl-ffi:foreign-alloc 8)))
        (jni-check)
        (unless (zerop (torcl-ffi:foreign-call (canvas-lock-pixels canvas) :int
                                               '(:pointer :pointer :pointer)
                                               (list *env* bitmap address)))
          (error "AndroidBitmap_lockPixels failed for an image"))
        (torcl::%foreign-memory :copy-in (torcl-ffi:mem-ref address :pointer)
                                (surface-pixels source) :unsigned-int)
        (torcl-ffi:foreign-call (canvas-unlock-pixels canvas) :int '(:pointer :pointer)
                                (list *env* bitmap))
        (torcl-ffi:foreign-free address)
        (setf (gethash source (canvas-images canvas)) bitmap))))

(defun canvas-string (canvas text)
  "TEXT as a cached jstring. Built once per distinct string: at ~27us each,
rebuilding a label's string every frame costs more than drawing it."
  (or (gethash text (canvas-strings canvas))
      (setf (gethash text (canvas-strings canvas)) (jni-string text))))

(defun canvas-draw (canvas display-list)
  "Execute DISPLAY-LIST through Skia.

Text is drawn by Canvas, not expanded into rectangles: this is the whole point.
A :glyphs op that the software backend turns into ~180 rectangles becomes one
drawText call, with real shaping and antialiasing."
  (let ((paint (canvas-paint canvas))
        (object (canvas-object canvas)))
    (dolist (op display-list)
      (ecase (first op)
        ;; SAVE/RESTORE is Skia's own clip stack, so nothing has to be
        ;; intersected by hand and text is clipped as correctly as anything else.
        (:clip-push
         (destructuring-bind (x y w h) (rest op)
           (torcl-ffi:foreign-call (jni-slot +jni-call-int-method-a+) :int
                                   '(:pointer :pointer :pointer :pointer)
                                   (list *env* object (canvas-save canvas) (jni-args)))
           (torcl-ffi:foreign-call (jni-slot +jni-call-boolean-method-a+) :int
                                   '(:pointer :pointer :pointer :pointer)
                                   (list *env* object (canvas-clip-rect canvas)
                                         (jni-args (list :float x) (list :float y)
                                                   (list :float (+ x w))
                                                   (list :float (+ y h)))))))
        (:clip-pop (jni-call-void object (canvas-restore canvas) (jni-args)))
        (:fill-round-rect
         (destructuring-bind (x y w h radius colour) (rest op)
           (jni-call-void paint (canvas-set-colour canvas)
                          (jni-args (list :int (android-colour colour))))
           (jni-call-void object (canvas-draw-round-rect canvas)
                          (jni-args (list :float x) (list :float y)
                                    (list :float (+ x w)) (list :float (+ y h))
                                    (list :float radius) (list :float radius)
                                    (list :object paint)))))
        (:image
         (destructuring-bind (x y w h source) (rest op)
           (let ((bitmap (canvas-image canvas source)))
             (jni-call-void (canvas-src-rect canvas) (canvas-rect-set canvas)
                            (jni-args (list :int 0) (list :int 0)
                                      (list :int (surface-width source))
                                      (list :int (surface-height source))))
             (jni-call-void (canvas-dst-rect canvas) (canvas-rectf-set canvas)
                            (jni-args (list :float x) (list :float y)
                                      (list :float (+ x w)) (list :float (+ y h))))
             (jni-call-void object (canvas-draw-bitmap canvas)
                            (jni-args (list :object bitmap)
                                      (list :object (canvas-src-rect canvas))
                                      (list :object (canvas-dst-rect canvas))
                                      (list :object paint))))))
        (:fill-rect
         (destructuring-bind (x y w h colour) (rest op)
           (jni-call-void paint (canvas-set-colour canvas)
                          (jni-args (list :int (android-colour colour))))
           (jni-call-void object (canvas-draw-rect canvas)
                          (jni-args (list :float x) (list :float y)
                                    (list :float (+ x w)) (list :float (+ y h))
                                    (list :object paint)))))
        (:glyphs
         (destructuring-bind (x y text scale colour) (rest op)
           (jni-call-void paint (canvas-set-colour canvas)
                          (jni-args (list :int (android-colour colour))))
           ;; A Bliss :size is a multiple of the 5x7 bitmap cell, so the nearest
           ;; Canvas equivalent is that many pixels of text height.
           (jni-call-void paint (canvas-set-text-size canvas)
                          (jni-args (list :float (* scale +glyph-height+))))
           ;; Bliss places text by its TOP edge; Canvas places it by the
           ;; baseline. ASCENT is negative, so subtracting it moves down.
           (let ((ascent (torcl-ffi:foreign-call
                          (jni-slot +jni-call-float-method-a+) :float
                          '(:pointer :pointer :pointer :pointer)
                          (list *env* paint (canvas-ascent canvas) (jni-args)))))
             (jni-call-void object (canvas-draw-text canvas)
                            (jni-args (list :object (canvas-string canvas text))
                                      (list :float x) (list :float (- y ascent))
                                      (list :object paint))))))))
    (jni-check)))

(defun canvas-pixels (canvas)
  "Lock the Bitmap and return its pixel pointer and stride, in pixels."
  (let ((address (torcl-ffi:foreign-alloc 8)))
    (unless (zerop (torcl-ffi:foreign-call (canvas-bitmap-info canvas) :int
                                           '(:pointer :pointer :pointer)
                                           (list *env* (canvas-bitmap canvas)
                                                 (canvas-info-buffer canvas))))
      (error "AndroidBitmap_getInfo failed"))
    (unless (zerop (torcl-ffi:foreign-call (canvas-lock-pixels canvas) :int
                                           '(:pointer :pointer :pointer)
                                           (list *env* (canvas-bitmap canvas) address)))
      (error "AndroidBitmap_lockPixels failed"))
    ;; AndroidBitmapInfo is width, height, stride, format, flags -- stride in BYTES.
    (values (torcl-ffi:mem-ref address :pointer)
            (floor (torcl-ffi:mem-ref (canvas-info-buffer canvas) :int 8) 4))))

(defun canvas-release-pixels (canvas)
  (torcl-ffi:foreign-call (canvas-unlock-pixels canvas) :int '(:pointer :pointer)
                          (list *env* (canvas-bitmap canvas))))

;;; ── as a backend ──────────────────────────────────────────────────────

(defclass canvas-backend (backend)
  ((canvas :initarg :canvas :reader canvas-backend-canvas))
  (:documentation "Draws through android.graphics.Canvas, which is Skia."))

(defun make-canvas-backend (width height)
  (make-instance 'canvas-backend :canvas (canvas-open width height)))

(defmethod backend-size ((backend canvas-backend))
  (let ((canvas (canvas-backend-canvas backend)))
    (values (canvas-width canvas) (canvas-height canvas))))

(defmethod present ((backend canvas-backend) display-list)
  (canvas-draw (canvas-backend-canvas backend) display-list)
  backend)

(defmethod backend-text-metrics ((backend canvas-backend))
  ;; CANVAS-OPEN already installed these; returning them makes the arrangement
  ;; explicit rather than a side effect a caller has to know about.
  *measure-text*)
