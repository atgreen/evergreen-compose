(in-package :bliss)

;;; The reference backend: a plain RGBA byte buffer and a rasterizer with no
;;; dependencies at all.
;;;
;;; It exists so everything above the display list can be developed and tested
;;; on any machine, with no GPU, no window system, no emulator and no phone.
;;; That is not a fallback -- it is the only way the layout and paint layers get
;;; a fast, deterministic test loop, and it doubles as the oracle a GLES backend
;;; can be checked against.

(defstruct (surface (:constructor %make-surface (width height pixels)))
  width height pixels)

(defun make-surface (width height &optional (fill +transparent+))
  ;; One 32-bit word per pixel, not four bytes. Measured on release x86-64, the
  ;; same 500k pixels cost 987ms as four byte stores and 237ms as one word store
  ;; -- the per-store cost is identical, so the win is entirely in doing a
  ;; quarter as many. Clearing a screen is the largest fill in any frame, which
  ;; makes this the single biggest lever the rasterizer has (bliss-5fg).
  (let ((surface (%make-surface width height
                                (make-array (* width height)
                                            :element-type '(unsigned-byte 32)
                                            :initial-element 0))))
    (clear surface fill)
    surface))

(defun pixel-index (surface x y) (+ x (* y (surface-width surface))))

(defun native-pixel (colour)
  "COLOUR as the word the buffer stores.

The bytes must read R, G, B, A in memory: that is Android's RGBA_8888, and what
WRITE-PPM and a window blit both expect. On a little-endian host -- x86-64 and
aarch64, the only targets here -- that word is #xAABBGGRR. Storing the packed
#xRRGGBBAA colour directly would put the bytes down backwards."
  (logior (colour-red colour)
          (ash (colour-green colour) 8)
          (ash (colour-blue colour) 16)
          (ash (colour-alpha colour) 24)))

(defun colour-from-native (word)
  (rgba (ldb (byte 8 0) word) (ldb (byte 8 8) word)
        (ldb (byte 8 16) word) (ldb (byte 8 24) word)))

(defun pixel-at (surface x y)
  "The packed colour at (X, Y). Tests and the exporters read frames through this
rather than touching the vector, so the storage word order stays internal."
  (colour-from-native (aref (surface-pixels surface) (pixel-index surface x y))))

(defun (setf pixel-at) (colour surface x y)
  (setf (aref (surface-pixels surface) (pixel-index surface x y))
        (native-pixel colour))
  colour)

(defun clear (surface colour)
  "Paint the whole surface. Goes through the same span filler as everything
else: this is the single largest fill in a frame, and doing it a pixel at a time
through the PIXEL-AT accessors cost more than all the drawing that followed."
  (%span surface 0 0 (surface-width surface) (surface-height surface) colour)
  surface)

(defun surface-rect (surface)
  (rect 0 0 (surface-width surface) (surface-height surface)))

(defun %span (surface x0 y0 x1 y1 colour)
  "Fill the half-open box [x0,x1) x [y0,y1), which the caller has already clipped.

The inner loop walks a running byte index rather than recomputing
(* 4 (+ x (* y width))) per pixel, and an opaque colour skips the read and the
blend entirely -- four stores instead of four loads, a blend and four stores.
Most pixels in an interface are opaque, so that fast path is the common one."
  (declare (optimize (speed 3) (safety 1)))
  (let ((pixels (surface-pixels surface))
        (width (surface-width surface))
        (alpha (colour-alpha colour)))
    (if (= alpha 255)
        ;; The stored word is the same for every pixel, so build it once.
        (let ((word (native-pixel colour)))
          (loop for y from y0 below y1
                do (let ((i (+ x0 (* y width))))
                     (loop repeat (- x1 x0)
                           do (setf (aref pixels i) word)
                              (incf i)))))
        (loop for y from y0 below y1
              do (let ((i (+ x0 (* y width))))
                   (loop repeat (- x1 x0)
                         do (setf (aref pixels i)
                                  (native-pixel
                                   (blend colour (colour-from-native (aref pixels i)))))
                            (incf i)))))))

(defun fill-rect (surface x y width height colour)
  "Paint a rectangle, clipped to the surface. Clipping here rather than in the
caller means a view placed partly offscreen is drawn, not dropped -- which is
what scrolling will need.

The clip is integer MIN/MAX rather than RECT-INTERSECT: this is called once per
glyph run, and allocating two rectangles to express a comparison made the
rasterizer spend its whole time in the allocator (bliss-5fg)."
  (let ((x0 (max x 0))
        (y0 (max y 0))
        (x1 (min (+ x width) (surface-width surface)))
        (y1 (min (+ y height) (surface-height surface))))
    (when (and (< x0 x1) (< y0 y1))
      (%span surface x0 y0 x1 y1 colour))))

(defun draw-glyphs (surface x y text scale colour)
  "Draw TEXT at SCALE. One source pixel becomes a SCALE x SCALE block, so text
scales without a resampler and stays crisp.

Lit pixels are emitted as horizontal RUNS, not one rectangle each: a glyph row
of \"#####\" is a single fill rather than five. Combined with a fill that no
longer allocates, this is what took the rasterizer out of the allocator."
  (loop for character across text
        for pen = x then (+ pen (* scale +glyph-advance+))
        for glyph = (glyph character)
        when glyph
          do (dotimes (row +glyph-height+)
               ;; Scan one column past the glyph so a run reaching the last
               ;; column is flushed by the same branch as any other.
               (let ((start nil))
                 (dotimes (column (1+ +glyph-width+))
                   (let ((lit (and (< column +glyph-width+)
                                   (glyph-pixel-p glyph column row))))
                     (cond ((and lit (null start)) (setf start column))
                           ((and (not lit) start)
                            (fill-clipped surface
                                          (+ pen (* start scale))
                                          (+ y (* row scale))
                                          (* (- column start) scale)
                                          scale colour *glyph-clip*)
                            (setf start nil)))))))))

(defun draw (surface display-list)
  "Execute a display list onto SURFACE.

Rounded rectangles and clipping arrive already resolved: FLATTEN-TO-RECTS turns
corners into spans and intersects everything with the clip stack, so this
backend still only has to fill axis-aligned rectangles. Text is the exception --
it is drawn directly, because expanding a glyph to one rectangle per lit pixel
and then filling each is what made this slow in the first place."
  (let ((clips (list nil)))
    (dolist (op display-list surface)
      (ecase (first op)
        (:clip-push (destructuring-bind (x y w h &optional (radius 0)) (rest op)
                      (setf clips (push-clip clips x y w h radius))))
        (:clip-pop (pop clips))
        (:fill-rect (destructuring-bind (x y w h colour) (rest op)
                      (fill-clipped surface x y w h colour (first clips))))
        (:fill-round-rect
         (destructuring-bind (x y w h radius colour) (rest op)
           (dolist (span (round-rect-spans x y w h radius))
             (destructuring-bind (sx sy sw sh) span
               (fill-clipped surface sx sy sw sh colour (first clips))))))
        ;; Rings, not a Gaussian -- see SHADOW-RECTS. This rasterizer exists so
        ;; layout and rendering can be tested with no GPU and no phone, and a
        ;; real blur would be the most expensive thing in it by a wide margin.
        (:shadow (dolist (rect (apply #'shadow-rects (rest op)))
                   (destructuring-bind (sx sy sw sh ink) rect
                     (fill-clipped surface sx sy sw sh ink (first clips)))))
        (:stroke-rect
         (destructuring-bind (x y w h radius thickness ink) (rest op)
           (dolist (span (stroke-spans x y w h radius thickness))
             (destructuring-bind (sx sy sw sh) span
               (fill-clipped surface sx sy sw sh ink (first clips))))))
        (:path
         (destructuring-bind (x y w h view-box commands ink) (rest op)
           (dolist (span (path-spans commands x y w h view-box))
             (destructuring-bind (sx sy sw sh) span
               (fill-clipped surface sx sy sw sh ink (first clips))))))
        (:image (destructuring-bind (x y w h source) (rest op)
                  (draw-image surface x y w h source (first clips))))
        (:glyphs (destructuring-bind (x y text scale colour) (rest op)
                   (let ((*glyph-clip* (first clips)))
                     (draw-glyphs surface x y text scale colour))))))))

(defvar *glyph-clip* nil "Clip applied to glyph fills, or NIL for none.")

(defun draw-image (surface x y width height source clip)
  "Blit SOURCE into SURFACE at (X,Y), scaled to WIDTH by HEIGHT.

Nearest-neighbour: the destination pixel asks which source pixel it lands on,
which is the right sampling for the pixel art this rasterizer exists to draw and
the wrong one for a photograph. A backend with a real image pipeline -- Canvas
has one -- should draw the image itself rather than come through here."
  (when (and (plusp width) (plusp height))
    (let ((source-width (surface-width source))
          (source-height (surface-height source)))
      ;; Per SPAN, not per rectangle, so an image inside a rounded container is
      ;; clipped to the corners the container actually draws.
      (dolist (span (clip-spans x y width height clip))
        (destructuring-bind (sx* sy* sw sh) span
          (let ((area (rect-intersect (rect sx* sy* sw sh) (surface-rect surface))))
            (when area
              (loop for py from (rect-y area) below (rect-bottom area)
                    do (let ((sy (min (1- source-height)
                                      (floor (* (- py y) source-height) height))))
                         (loop for px from (rect-x area) below (rect-right area)
                               do (let ((sx (min (1- source-width)
                                                 (floor (* (- px x) source-width) width))))
                                    (setf (pixel-at surface px py)
                                          (blend (pixel-at source sx sy)
                                                 (pixel-at surface px py))))))))))))))

(defun fill-clipped (surface x y width height colour clip)
  "FILL-RECT, first cut to CLIP -- which may be rounded, and then arrives as one
span per row rather than one rectangle."
  (dolist (span (clip-spans x y width height clip))
    (destructuring-bind (sx sy sw sh) span
      (fill-rect surface sx sy sw sh colour))))

;;; ── Getting a frame out ───────────────────────────────────────────────

(defun write-ppm (surface path)
  "Write SURFACE as a binary PPM. No encoder, no dependency, and every image
viewer opens it -- enough to look at a frame during development."
  (with-open-file (stream path :direction :output :element-type '(unsigned-byte 8)
                               :if-exists :supersede :if-does-not-exist :create)
    (let ((header (format nil "P6~%~D ~D~%255~%"
                          (surface-width surface) (surface-height surface))))
      (loop for character across header do (write-byte (char-code character) stream)))
    (dotimes (y (surface-height surface) path)
      (dotimes (x (surface-width surface))
        (let ((c (pixel-at surface x y)))
          (write-byte (colour-red c) stream)
          (write-byte (colour-green c) stream)
          (write-byte (colour-blue c) stream))))))

(defun ascii-art (surface &key (stream *standard-output*) (ink #\#) (paper #\.))
  "Print SURFACE as text, one character per pixel.
The point is to be able to SEE a frame in a terminal, over adb, or in a test
failure, without an image viewer -- a rendering bug is usually obvious at a
glance and invisible in a pixel assertion."
  (dotimes (y (surface-height surface) surface)
    (dotimes (x (surface-width surface))
      (let ((c (pixel-at surface x y)))
        ;; Luminance, so any dark ink on any light ground reads correctly.
        (write-char (if (< (+ (* 299 (colour-red c)) (* 587 (colour-green c))
                              (* 114 (colour-blue c)))
                           128000)
                        ink paper)
                    stream)))
    (terpri stream)))

;;; ── as a backend ──────────────────────────────────────────────────────

(defclass software-backend (backend)
  ((surface :initarg :surface :reader software-backend-surface))
  (:documentation "Draws into an RGBA surface. The reference implementation:
no GPU, no window system, no device, which is what makes the framework above it
testable anywhere."))

(defun make-software-backend (width height &optional (fill +white+))
  (make-instance 'software-backend :surface (make-surface width height fill)))

(defmethod backend-size ((backend software-backend))
  (let ((surface (software-backend-surface backend)))
    (values (surface-width surface) (surface-height surface))))

(defmethod present ((backend software-backend) display-list &optional damage)
  (let ((surface (software-backend-surface backend)))
    (if damage
        ;; No CLEAR: outside the damage the surface already holds the last
        ;; frame, which is the whole premise. Clearing would be the bug.
        (draw surface (append (list (list :clip-push (rect-x damage) (rect-y damage)
                                          (rect-width damage) (rect-height damage)))
                              display-list
                              (list (list :clip-pop))))
        (progn (clear surface +white+)
               (draw surface display-list))))
  backend)
