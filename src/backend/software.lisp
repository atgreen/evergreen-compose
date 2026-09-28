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
  (let ((surface (%make-surface width height
                                (make-array (* width height 4)
                                            :element-type '(unsigned-byte 8)
                                            :initial-element 0))))
    (clear surface fill)
    surface))

(defun pixel-index (surface x y) (* 4 (+ x (* y (surface-width surface)))))

(defun pixel-at (surface x y)
  "The packed colour at (X, Y). The tests read frames through this rather than
poking at the byte vector, so the storage layout stays an implementation detail."
  (let ((i (pixel-index surface x y))
        (p (surface-pixels surface)))
    (rgba (aref p i) (aref p (+ i 1)) (aref p (+ i 2)) (aref p (+ i 3)))))

(defun (setf pixel-at) (colour surface x y)
  (let ((i (pixel-index surface x y))
        (p (surface-pixels surface)))
    (setf (aref p i) (colour-red colour)
          (aref p (+ i 1)) (colour-green colour)
          (aref p (+ i 2)) (colour-blue colour)
          (aref p (+ i 3)) (colour-alpha colour))
    colour))

(defun clear (surface colour)
  (dotimes (y (surface-height surface) surface)
    (dotimes (x (surface-width surface))
      (setf (pixel-at surface x y) colour))))

(defun surface-rect (surface)
  (rect 0 0 (surface-width surface) (surface-height surface)))

(defun fill-rect (surface x y width height colour)
  "Paint a rectangle, clipped to the surface. Clipping here rather than in the
caller means a view placed partly offscreen is drawn, not dropped -- which is
what scrolling will need."
  (let ((area (rect-intersect (rect x y width height) (surface-rect surface))))
    (when area
      (loop for py from (rect-y area) below (rect-bottom area)
            do (loop for px from (rect-x area) below (rect-right area)
                     do (setf (pixel-at surface px py)
                              (blend colour (pixel-at surface px py))))))))

(defun draw-glyphs (surface x y text scale colour)
  (loop for character across text
        for pen = x then (+ pen (* scale +glyph-advance+))
        for glyph = (glyph character)
        when glyph
          do (dotimes (row +glyph-height+)
               (dotimes (column +glyph-width+)
                 (when (glyph-pixel-p glyph column row)
                   ;; One source pixel becomes a SCALE x SCALE block, so text
                   ;; scales without a resampler and stays crisp.
                   (fill-rect surface (+ pen (* column scale)) (+ y (* row scale))
                              scale scale colour))))))

(defun draw (surface display-list)
  "Execute a display list onto SURFACE."
  (dolist (op display-list surface)
    (ecase (first op)
      (:fill-rect (destructuring-bind (x y w h colour) (rest op)
                    (fill-rect surface x y w h colour)))
      (:glyphs (destructuring-bind (x y text scale colour) (rest op)
                 (draw-glyphs surface x y text scale colour))))))

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
