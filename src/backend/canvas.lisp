(in-package :bliss)

;;;; The Canvas backend: Bliss display lists drawn by Android's own Skia.
;;;;
;;;; android.graphics.Canvas IS Skia -- it is what every Android app draws
;;;; through -- so this gets shaped, antialiased, font-fallback text and real
;;;; path filling without shipping a renderer or a font.
;;;;
;;;; Why this shape, given the measurements: a JNI call costs ~35us here and
;;;; almost all of that is EGCL's FFI rather than Java. So the winning move is
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
  set-mask-filter blur-class blur-init blur-normal
  path-class path-init path-move path-line path-quad path-cubic path-close
  path-reset path-add-round-rect path-direction-cw clip-path clip-shape
  draw-path translate scale
  set-style set-stroke-width style-fill style-stroke
  paint-class paint-init
  matrix matrix-set-scale path-copy-init path-transform path-offset scratch-path
  ;; (PAINT . CURRENT-ARGB) for an outline, with its style set to STROKE once.
  stroke-paint (stroke-width :unknown)
  (strings (make-hash-table :test #'equal))
  (images (make-hash-table :test #'eq))
  (blurs (make-hash-table :test #'eql))
  (paths (make-hash-table :test #'eq))
  (scaled-paths (make-hash-table :test #'eq))
  ;; (PAINT . CURRENT-ARGB) per blur radius, with the mask filter already on it.
  (shadow-paints (make-hash-table :test #'eql))
  (ascents (make-hash-table :test #'eql))
  ;; What the Paint is currently set to, so a frame does not keep saying it.
  (current-colour :unknown)
  (current-text-size :unknown))

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
         (graphics (egcl-ffi:load-foreign-library "libjnigraphics.so")))
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
                   ;; Skia can clip to a PATH, which is what makes a rounded
                   ;; container clip its children to the shape it draws instead
                   ;; of to the square around it (bliss-cvj).
                   :clip-path (jni-method canvas-class "clipPath"
                                          "(Landroid/graphics/Path;)Z")
                   :path-reset (jni-method (jni-find-class "android/graphics/Path")
                                           "reset" "()V")
                   :path-add-round-rect
                   (jni-method (jni-find-class "android/graphics/Path") "addRoundRect"
                               "(FFFFFFLandroid/graphics/Path$Direction;)V")
                   :path-direction-cw
                   (jni-static-object-field (jni-find-class "android/graphics/Path$Direction")
                                            "CW" "Landroid/graphics/Path$Direction;")
                   ;; One Path, reused for every rounded clip.
                   :clip-shape
                   (jni-global (jni-new (jni-find-class "android/graphics/Path")
                                        (jni-method (jni-find-class "android/graphics/Path")
                                                    "<init>" "()V")
                                        (jni-args)))
                   :draw-text (jni-method canvas-class "drawText"
                                          "(Ljava/lang/String;FFLandroid/graphics/Paint;)V")
                   :draw-colour (jni-method canvas-class "drawColor" "(I)V")
                   :set-colour (jni-method paint-class "setColor" "(I)V")
                   :set-text-size (jni-method paint-class "setTextSize" "(F)V")
                   :set-anti-alias (jni-method paint-class "setAntiAlias" "(Z)V")
                   :ascent (jni-method paint-class "ascent" "()F")
                   :lock-pixels (egcl-ffi:foreign-symbol-pointer
                                 "AndroidBitmap_lockPixels" graphics)
                   :unlock-pixels (egcl-ffi:foreign-symbol-pointer
                                   "AndroidBitmap_unlockPixels" graphics)
                   :bitmap-info (egcl-ffi:foreign-symbol-pointer
                                 "AndroidBitmap_getInfo" graphics)
                   :info-buffer (ffi-alloc 32)
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
                                          "set" "(FFFF)V")
                   ;; Skia has a real Gaussian, so a raised surface gets a real
                   ;; shadow here rather than the rings SHADOW-RECTS reduces one
                   ;; to for backends that can only fill rectangles.
                   :set-mask-filter (jni-method paint-class "setMaskFilter"
                                                "(Landroid/graphics/MaskFilter;)Landroid/graphics/MaskFilter;")
                   :blur-class (jni-find-class "android/graphics/BlurMaskFilter")
                   :blur-init (jni-method (jni-find-class "android/graphics/BlurMaskFilter")
                                          "<init>"
                                          "(FLandroid/graphics/BlurMaskFilter$Blur;)V")
                   :set-style (jni-method paint-class "setStyle"
                                          "(Landroid/graphics/Paint$Style;)V")
                   :set-stroke-width (jni-method paint-class "setStrokeWidth" "(F)V")
                   :style-fill (jni-static-object-field
                                (jni-find-class "android/graphics/Paint$Style")
                                "FILL" "Landroid/graphics/Paint$Style;")
                   :style-stroke (jni-static-object-field
                                  (jni-find-class "android/graphics/Paint$Style")
                                  "STROKE" "Landroid/graphics/Paint$Style;")
                   :blur-normal (jni-static-object-field
                                 (jni-find-class "android/graphics/BlurMaskFilter$Blur")
                                 "NORMAL" "Landroid/graphics/BlurMaskFilter$Blur;")
                   ;; Skia fills paths with antialiasing and its own curve
                   ;; rasterizer, so PATH-SPANS is for backends that cannot.
                   :path-class (jni-find-class "android/graphics/Path")
                   :path-init (jni-method (jni-find-class "android/graphics/Path")
                                          "<init>" "()V")
                   :path-move (jni-method (jni-find-class "android/graphics/Path")
                                          "moveTo" "(FF)V")
                   :path-line (jni-method (jni-find-class "android/graphics/Path")
                                          "lineTo" "(FF)V")
                   :path-quad (jni-method (jni-find-class "android/graphics/Path")
                                          "quadTo" "(FFFF)V")
                   :path-cubic (jni-method (jni-find-class "android/graphics/Path")
                                           "cubicTo" "(FFFFFF)V")
                   :path-close (jni-method (jni-find-class "android/graphics/Path")
                                           "close" "()V")
                   :draw-path (jni-method canvas-class "drawPath"
                                          "(Landroid/graphics/Path;Landroid/graphics/Paint;)V")
                   :translate (jni-method canvas-class "translate" "(FF)V")
                   :scale (jni-method canvas-class "scale" "(FF)V")
                   :paint-class paint-class :paint-init paint-init
                   ;; A path is drawn by OFFSETTING a copy already scaled to its
                   ;; size into one scratch Path and drawing that: two calls,
                   ;; where save/translate/scale/draw/restore were five. The
                   ;; scaling happens once per size, through this one Matrix.
                   :matrix (let ((class (jni-find-class "android/graphics/Matrix")))
                             (jni-global (jni-new class (jni-method class "<init>" "()V")
                                                  (jni-args))))
                   :matrix-set-scale (jni-method (jni-find-class "android/graphics/Matrix")
                                                 "setScale" "(FF)V")
                   :path-copy-init (jni-method (jni-find-class "android/graphics/Path")
                                               "<init>" "(Landroid/graphics/Path;)V")
                   :path-transform (jni-method (jni-find-class "android/graphics/Path")
                                               "transform" "(Landroid/graphics/Matrix;)V")
                   :path-offset (jni-method (jni-find-class "android/graphics/Path")
                                            "offset" "(FFLandroid/graphics/Path;)V")
                   :scratch-path
                   (jni-global (jni-new (jni-find-class "android/graphics/Path")
                                        (jni-method (jni-find-class "android/graphics/Path")
                                                    "<init>" "()V")
                                        (jni-args))))))
      ;; Antialiasing on, once. It is a Paint flag, not a per-call argument, and
      ;; it is the reason for using Skia at all.
      (jni-call-void paint (canvas-set-anti-alias canvas) (jni-args (list :int 1)))
      ;; A second Paint that is always an outline, so a stroke no longer has to
      ;; flip the shared one to STROKE and back around every rectangle.
      (let ((stroke (canvas-new-paint canvas)))
        (jni-call-void stroke (canvas-set-style canvas)
                       (jni-args (list :object (canvas-style-stroke canvas))))
        (setf (canvas-stroke-paint canvas) (cons stroke :unknown)))
      (jni-check)
      ;; Layout must measure with the font that will be drawn, so this is part
      ;; of opening a canvas rather than something a caller can forget.
      (canvas-install-metrics canvas)
      canvas)))

(defun canvas-colour (canvas colour)
  "Set the paint colour, unless the paint is already that colour.

Every drawing operation sets one, and a UI repeats them relentlessly -- one
surface, one ink, one accent, over and over. Measured on a Pixel 10 Pro XL, a
crossing into C costs about 170us and PRESENT makes 190 of them a frame, which
is the whole of its 32ms: clipping the entire display list to a single pixel
changed nothing at all (bliss-asd). So a crossing not made is worth more than
anything it could have drawn."
  (let ((argb (android-colour colour)))
    (unless (eql argb (canvas-current-colour canvas))
      (setf (canvas-current-colour canvas) argb)
      (jni-call :void (canvas-paint canvas) (canvas-set-colour canvas) :int argb))))

(defun canvas-text-size (canvas size)
  "Set the text size, unless it is already that. See CANVAS-COLOUR."
  (unless (eql size (canvas-current-text-size canvas))
    (setf (canvas-current-text-size canvas) size)
    (jni-call :void (canvas-paint canvas) (canvas-set-text-size canvas) :float size)))

(defun canvas-new-paint (canvas)
  "A fresh antialiased Paint, as a global reference."
  (let ((paint (jni-global (jni-new (canvas-paint-class canvas) (canvas-paint-init canvas)
                                    (jni-args)))))
    (jni-call-void paint (canvas-set-anti-alias canvas) (jni-args (list :int 1)))
    paint))

(defun paint-colour (canvas entry colour)
  "ENTRY is (PAINT . CURRENT-ARGB). Set its colour unless it is already that,
as CANVAS-COLOUR does for the shared Paint, and return the Paint."
  (let ((argb (android-colour colour)))
    (unless (eql argb (cdr entry))
      (setf (cdr entry) argb)
      (jni-call :void (car entry) (canvas-set-colour canvas) :int argb))
    (car entry)))

(defun canvas-shadow-paint (canvas blur)
  "(PAINT . CURRENT-ARGB) with a BLUR mask filter already on it, made once per
radius and kept. A shadow used to put the filter on the shared Paint and take it
off again -- two calls, each returning a reference that had to be released --
around every shadow of every frame, to say a radius that did not change."
  (or (gethash blur (canvas-shadow-paints canvas))
      (setf (gethash blur (canvas-shadow-paints canvas))
            (let ((paint (canvas-new-paint canvas)))
              (jni-release (jni-call-object paint (canvas-set-mask-filter canvas)
                                            (jni-args (list :object (canvas-blur canvas blur)))))
              (cons paint :unknown)))))

(defun canvas-ascent-for (canvas size)
  "The shared Paint's ascent at text SIZE, asked once per size. It depends on
nothing but the size, and every label asked again."
  (or (gethash size (canvas-ascents canvas))
      (setf (gethash size (canvas-ascents canvas))
            (progn
              (canvas-text-size canvas size)
              (jni-call :float (canvas-paint canvas) (canvas-ascent canvas))))))

(defun canvas-blur (canvas radius)
  "A BlurMaskFilter of RADIUS, made once per radius and kept.

A UI uses two or three elevations, so this table never holds more than that --
and building one per shadow per frame would cost an allocation and a constructor
call, at ~35us each, to say a number that did not change."
  (or (gethash radius (canvas-blurs canvas))
      (setf (gethash radius (canvas-blurs canvas))
            (jni-global (jni-new (canvas-blur-class canvas) (canvas-blur-init canvas)
                                 (jni-args (list :float (max 1 radius))
                                           (list :object (canvas-blur-normal canvas))))))))

(defun canvas-path (canvas commands)
  "COMMANDS as an android.graphics.Path, built once and kept.

Keyed by the command list's IDENTITY, which is what makes this worth doing: an
icon's commands are a constant built at load time, so the same list arrives every
frame and the ten or so JNI calls that build the Path happen once for the life of
the process rather than sixty times a second."
  (or (gethash commands (canvas-paths canvas))
      (setf (gethash commands (canvas-paths canvas))
            (let ((path (jni-global (jni-new (canvas-path-class canvas)
                                             (canvas-path-init canvas) (jni-args)))))
              (dolist (command commands path)
                (ecase (first command)
                  (:move (destructuring-bind (x y) (rest command)
                           (jni-call-void path (canvas-path-move canvas)
                                          (jni-args (list :float x) (list :float y)))))
                  (:line (destructuring-bind (x y) (rest command)
                           (jni-call-void path (canvas-path-line canvas)
                                          (jni-args (list :float x) (list :float y)))))
                  (:quad (destructuring-bind (cx cy x y) (rest command)
                           (jni-call-void path (canvas-path-quad canvas)
                                          (jni-args (list :float cx) (list :float cy)
                                                    (list :float x) (list :float y)))))
                  (:cubic (destructuring-bind (ax ay bx by x y) (rest command)
                            (jni-call-void path (canvas-path-cubic canvas)
                                           (jni-args (list :float ax) (list :float ay)
                                                     (list :float bx) (list :float by)
                                                     (list :float x) (list :float y)))))
                  (:close (jni-call-void path (canvas-path-close canvas) (jni-args)))))))))

(defun canvas-scaled-path (canvas commands view-box w h)
  "COMMANDS as a Path already scaled from VIEW-BOX units to W x H pixels, built
once per size it is drawn at and kept. An icon appears at one or two sizes, so
this holds one or two Paths per icon for the life of the process."
  (let ((sizes (or (gethash commands (canvas-scaled-paths canvas))
                   (setf (gethash commands (canvas-scaled-paths canvas))
                         (make-hash-table :test #'equal))))
        (key (list view-box w h)))
    (or (gethash key sizes)
        (setf (gethash key sizes)
              (let ((path (jni-global
                           (jni-new (canvas-path-class canvas) (canvas-path-copy-init canvas)
                                    (jni-args (list :object (canvas-path canvas commands)))))))
                (jni-call-void (canvas-matrix canvas) (canvas-matrix-set-scale canvas)
                               (jni-args (list :float (/ w view-box))
                                         (list :float (/ h view-box))))
                (jni-call-void path (canvas-path-transform canvas)
                               (jni-args (list :object (canvas-matrix canvas))))
                path)))))

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
                      (canvas-text-size canvas size)
                      (let* ((width (egcl::%ffi-call
                                     (jni-slot +jni-call-float-method-a+) :float
                                     '(:pointer :pointer :pointer :pointer)
                                     (list *env* paint measure
                                           (jni-args (list :object (canvas-string canvas text))))))
                             (rise (egcl::%ffi-call
                                    (jni-slot +jni-call-float-method-a+) :float
                                    '(:pointer :pointer :pointer :pointer)
                                    (list *env* paint (canvas-ascent canvas) (jni-args))))
                             (fall (egcl::%ffi-call
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
             (address (ffi-alloc 8)))
        (jni-check)
        (unless (zerop (egcl::%ffi-call (canvas-lock-pixels canvas) :int
                                               '(:pointer :pointer :pointer)
                                               (list *env* bitmap address)))
          (error "AndroidBitmap_lockPixels failed for an image"))
        (egcl::%foreign-memory :copy-in (ffi-ref address :pointer)
                                (surface-pixels source) :unsigned-int)
        (egcl::%ffi-call (canvas-unlock-pixels canvas) :int '(:pointer :pointer)
                                (list *env* bitmap))
        (ffi-free address)
        (setf (gethash source (canvas-images canvas)) bitmap))))

(defun canvas-string (canvas text)
  "TEXT as a cached jstring. Built once per distinct string: at ~27us each,
rebuilding a label's string every frame costs more than drawing it."
  (or (gethash text (canvas-strings canvas))
      (setf (gethash text (canvas-strings canvas)) (jni-string text))))

(defvar *draw-profile* nil
  "When non-NIL, a plist of op-kind -> (count . milliseconds), filled by
CANVAS-DRAW. Off by default and tested once per operation, because the point is
to find out where PRESENT's time goes without changing what it does.

Seed it with something NON-EMPTY -- (list :on (cons 0 0)) -- since an empty
plist is NIL and would read as \"off\". Then read it back after the frames you
care about:

  (setf bliss:*draw-profile* (list :on (cons 0 0)))
  ... let some frames run ...
  bliss:*draw-profile*  =>  (:GLYPHS (123 . 207) :SHADOW (30 . 167) ...)

That is how PRESENT was traced to the FFI rather than to Skia: every operation's
cost turned out to be proportional to the number of JNI calls it makes, not to
the number of pixels it touches.")

(defun draw-profile-note (kind start)
  (let* ((elapsed (- (get-internal-real-time) start))
         (entry (getf *draw-profile* kind)))
    (if entry
        (setf (car entry) (1+ (car entry))
              (cdr entry) (+ (cdr entry) elapsed))
        (setf (getf *draw-profile* kind) (cons 1 elapsed)))))

(defun canvas-draw (canvas display-list)
  "Execute DISPLAY-LIST through Skia.

Text is drawn by Canvas, not expanded into rectangles: this is the whole point.
A :glyphs op that the software backend turns into ~180 rectangles becomes one
drawText call, with real shaping and antialiasing.

Every call here is a JNI-CALL through the variadic entry: one crossing per
operation, with the arguments in it, and no jvalue buffer to fill first."
  (let ((paint (canvas-paint canvas))
        (object (canvas-object canvas)))
    (dolist (op display-list)
      (let ((%start (when *draw-profile* (get-internal-real-time))))
       (ecase (first op)
        ;; SAVE/RESTORE is Skia's own clip stack, so nothing has to be
        ;; intersected by hand and text is clipped as correctly as anything else.
        (:clip-push
         (destructuring-bind (x y w h &optional (radius 0)) (rest op)
           (jni-call :int object (canvas-save canvas))
           (if (plusp radius)
               ;; One Path, reset and refilled: a clip is pushed once per
               ;; rounded container per frame, and allocating a Java object for
               ;; each of them is a garbage collection nobody asked for.
               (let ((shape (canvas-clip-shape canvas)))
                 (jni-call :void shape (canvas-path-reset canvas))
                 (jni-call :void shape (canvas-path-add-round-rect canvas)
                           :float x :float y :float (+ x w) :float (+ y h)
                           :float radius :float radius
                           :object (canvas-path-direction-cw canvas))
                 (jni-call :boolean object (canvas-clip-path canvas) :object shape))
               (jni-call :boolean object (canvas-clip-rect canvas)
                         :float x :float y :float (+ x w) :float (+ y h)))))
        (:clip-pop (jni-call :void object (canvas-restore canvas)))
        (:fill-round-rect
         (destructuring-bind (x y w h radius colour) (rest op)
           (canvas-colour canvas colour)
           (jni-call :void object (canvas-draw-round-rect canvas)
                     :float x :float y :float (+ x w) :float (+ y h)
                     :float radius :float radius :object paint)))
        (:shadow
         (destructuring-bind (x y w h radius blur dy colour) (rest op)
           (let ((paint (paint-colour canvas (canvas-shadow-paint canvas blur) colour)))
             (jni-call :void object (canvas-draw-round-rect canvas)
                       :float x :float (+ y dy) :float (+ x w) :float (+ y dy h)
                       :float radius :float radius :object paint))))
        (:stroke-rect
         (destructuring-bind (x y w h radius thickness ink) (rest op)
           ;; Skia centres a stroke ON the path, so drawing the frame itself
           ;; would put half the outline outside the view. Inset by half.
           (let ((half (/ thickness 2.0))
                 (paint (paint-colour canvas (canvas-stroke-paint canvas) ink)))
             (unless (eql thickness (canvas-stroke-width canvas))
               (setf (canvas-stroke-width canvas) thickness)
               (jni-call :void paint (canvas-set-stroke-width canvas) :float thickness))
             (jni-call :void object (canvas-draw-round-rect canvas)
                       :float (+ x half) :float (+ y half)
                       :float (- (+ x w) half) :float (- (+ y h) half)
                       :float radius :float radius :object paint))))
        (:path
         (destructuring-bind (x y w h view-box commands ink) (rest op)
           ;; The scaled Path is kept; only its position changes per frame, and
           ;; OFFSET writes the moved copy into the one scratch Path.
           (canvas-colour canvas ink)
           (let ((scratch (canvas-scratch-path canvas)))
             (jni-call :void (canvas-scaled-path canvas commands view-box w h)
                       (canvas-path-offset canvas)
                       :float x :float y :object scratch)
             (jni-call :void object (canvas-draw-path canvas)
                       :object scratch :object paint))))
        (:image
         (destructuring-bind (x y w h source) (rest op)
           (let ((bitmap (canvas-image canvas source)))
             (jni-call :void (canvas-src-rect canvas) (canvas-rect-set canvas)
                       :int 0 :int 0 :int (surface-width source) :int (surface-height source))
             (jni-call :void (canvas-dst-rect canvas) (canvas-rectf-set canvas)
                       :float x :float y :float (+ x w) :float (+ y h))
             (jni-call :void object (canvas-draw-bitmap canvas)
                       :object bitmap :object (canvas-src-rect canvas)
                       :object (canvas-dst-rect canvas) :object paint))))
        (:fill-rect
         (destructuring-bind (x y w h colour) (rest op)
           (canvas-colour canvas colour)
           (jni-call :void object (canvas-draw-rect canvas)
                     :float x :float y :float (+ x w) :float (+ y h) :object paint)))
        (:glyphs
         (destructuring-bind (x y text scale colour) (rest op)
           (canvas-colour canvas colour)
           ;; A Bliss :size is a multiple of the 5x7 bitmap cell, so the nearest
           ;; Canvas equivalent is that many pixels of text height.
           (canvas-text-size canvas (* scale +glyph-height+))
           ;; Bliss places text by its TOP edge; Canvas places it by the
           ;; baseline. ASCENT is negative, so subtracting it moves down.
           (let ((ascent (canvas-ascent-for canvas (* scale +glyph-height+))))
             (jni-call :void object (canvas-draw-text canvas)
                       :object (canvas-string canvas text)
                       :float x :float (- y ascent) :object paint)))))
       (when %start (draw-profile-note (first op) %start))))
    (jni-check)))

(defun canvas-pixels (canvas)
  "Lock the Bitmap and return its pixel pointer and stride, in pixels."
  (let ((address (ffi-alloc 8)))
    (unless (zerop (egcl::%ffi-call (canvas-bitmap-info canvas) :int
                                           '(:pointer :pointer :pointer)
                                           (list *env* (canvas-bitmap canvas)
                                                 (canvas-info-buffer canvas))))
      (error "AndroidBitmap_getInfo failed"))
    (unless (zerop (egcl::%ffi-call (canvas-lock-pixels canvas) :int
                                           '(:pointer :pointer :pointer)
                                           (list *env* (canvas-bitmap canvas) address)))
      (error "AndroidBitmap_lockPixels failed"))
    ;; AndroidBitmapInfo is width, height, stride, format, flags -- stride in BYTES.
    (values (ffi-ref address :pointer)
            (floor (ffi-ref (canvas-info-buffer canvas) :int 8) 4))))

(defun canvas-release-pixels (canvas)
  (egcl::%ffi-call (canvas-unlock-pixels canvas) :int '(:pointer :pointer)
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

(defparameter *clear-colour* (rgb 0 0 0)
  "What a pixel nothing paints is. Black, because that is what an Android
surface shows where an application has drawn nothing.")

(defmethod present ((backend canvas-backend) display-list &optional damage)
  ;; Outside the damage the bitmap holds the last frame, and that is the whole
  ;; premise. INSIDE it, the old pixels are wrong by definition -- a region
  ;; that was painted and is painted no more would otherwise keep what it had,
  ;; which is how half a line of text stayed under the navigation bar after
  ;; the insets shrank the layout above it. So the damage is cleared first, and
  ;; then the operations that touch it are drawn: Skia rejects a draw outside
  ;; the clip by its bounds, and CULL-DISPLAY stops the calls that would be
  ;; rejected, which is where the time was.
  (canvas-draw (canvas-backend-canvas backend)
               (if damage
                   (append (list (list :clip-push (rect-x damage) (rect-y damage)
                                       (rect-width damage) (rect-height damage))
                                 (list :fill-rect (rect-x damage) (rect-y damage)
                                       (rect-width damage) (rect-height damage)
                                       *clear-colour*))
                           (cull-display display-list damage)
                           (list (list :clip-pop)))
                   (cons (list :fill-rect 0 0 (canvas-width (canvas-backend-canvas backend))
                               (canvas-height (canvas-backend-canvas backend)) *clear-colour*)
                         display-list)))
  backend)

(defmethod backend-text-metrics ((backend canvas-backend))
  ;; CANVAS-OPEN already installed these; returning them makes the arrangement
  ;; explicit rather than a side effect a caller has to know about.
  *measure-text*)
