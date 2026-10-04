(in-package :bliss)

;;; The GLES backend: it draws the display list with glScissor and glClear.
;;;
;;; No shader, no texture, no vertex buffer, no glyph atlas -- six GL entry
;;; points in total. Every operation in a Bliss display list is an axis-aligned
;;; rectangle of solid colour (FLATTEN-TO-RECTS makes that literally true), and
;;; a scissored clear is exactly "fill this rectangle with this colour". Using
;;; the pipeline for it would mean uploading geometry to say the same thing.
;;;
;;; MEASURED COST, on a Pixel 10 Pro XL at 1080x2243: about 500 rectangles takes
;;; 100-300ms, which is 3-10 frames per second. The claim this file used to make
;;; -- that scaling with ink rather than area is the right trade for a UI -- is
;;; true of a CPU rasterizer and false here. A scissored clear on a tile-based
;;; mobile GPU can force a tile resolve, so hundreds of them per frame is close
;;; to the worst thing you can ask an Adreno to do, and the per-rectangle FFI
;;; cost of three GL calls is paid on top.
;;;
;;; It is kept because it is correct, it is eighty lines, and it needs no shader
;;; pipeline -- which made it the right way to get the framework onto a device
;;; and prove the display-list contract end to end. It is NOT the backend to
;;; animate with: batching every rectangle into one vertex buffer and one draw
;;; call is the fix, and is filed. An application whose screen changes only when
;;; the user does something is served well by this as it stands, since the host
;;; can skip the draw entirely when the display list is unchanged.

(defconstant +gl-color-buffer-bit+ #x4000)
(defconstant +gl-scissor-test+ #x0C11)
(defconstant +egl-height+ #x3056)
(defconstant +egl-width+ #x3057)

(defparameter *gl* (make-hash-table :test #'equal))

(defun gl (name &rest arguments)
  (let ((entry (gethash name *gl*)))
    (unless entry (error "GL function not bound: ~A" name))
    (egcl::%ffi-call (first entry) (second entry) (third entry) arguments)))

(defun gles-init (&optional (library (egcl-ffi:load-foreign-library "libGLESv2.so")))
  "Bind the GL entry points the backend uses. Call once the EGL context is
current, since that is when the driver will resolve them. LIBRARY is accepted so
a host that has already opened libGLESv2 can pass it rather than opening a
second handle -- and so this file never has to know who set the context up."
  (let ((library library))
    (dolist (spec '(("glEnable" :void (:int))
                    ("glDisable" :void (:int))
                    ("glScissor" :void (:int :int :int :int))
                    ("glClearColor" :void (:float :float :float :float))
                    ("glClear" :void (:int))
                    ("glViewport" :void (:int :int :int :int))))
      (destructuring-bind (name return types) spec
        (let ((pointer (egcl-ffi:foreign-symbol-pointer name library)))
          (when (or (null pointer) (egcl-ffi:null-pointer-p pointer))
            (error "libGLESv2.so has no ~A" name))
          (setf (gethash name *gl*) (list pointer return types)))))
    (gl "glEnable" +gl-scissor-test+)
    library))

(defun gles-surface-size (egl-library display surface)
  "The drawable size in pixels, asked of EGL rather than assumed.
A phone can letterbox, rotate, or hand back a surface that is not the whole
display, so the only trustworthy size is the one the surface itself reports.
The EGL handles are passed in: this file draws, and does not own the context."
  (let ((query-fn (egcl-ffi:foreign-symbol-pointer "eglQuerySurface" egl-library))
        (out (ffi-alloc 4)))
    (unwind-protect
         (flet ((query (attribute)
                  (egcl::%ffi-call query-fn :int '(:pointer :pointer :int :pointer)
                                          (list display surface attribute out))
                  (ffi-ref out :int)))
           (values (query +egl-width+) (query +egl-height+)))
      (ffi-free out))))

(defparameter *last-clear-colour* nil
  "The colour currently set in the GL context, or NIL when unknown.

Every foreign call is expensive enough here -- 33us measured on a Pixel 10 Pro
XL, for a call taking no arguments at all -- that not making one is the cheapest
optimisation available. Consecutive rectangles almost always share a colour,
because every inked pixel of a label is one glyph colour, so tracking what the
context already holds removes about a third of the calls in a frame without
reordering anything. Order must be preserved: these rectangles composite.")

(defun gles-fill (x y width height colour surface-height scale)
  "One rectangle, in Bliss coordinates, scaled and flipped into GL's."
  (let* ((sx (* x scale))
         (sw (* width scale))
         (sh (* height scale))
         ;; Bliss measures y downward from the top like every UI system; GL
         ;; measures it upward from the bottom. The flip belongs here, once,
         ;; rather than in the layout engine.
         (sy (- surface-height (* y scale) sh)))
    (gl "glScissor" sx sy sw sh)
    (unless (eql colour *last-clear-colour*)
      (setf *last-clear-colour* colour)
      (gl "glClearColor"
          (/ (colour-red colour) 255.0) (/ (colour-green colour) 255.0)
          (/ (colour-blue colour) 255.0) (/ (colour-alpha colour) 255.0)))
    (gl "glClear" +gl-color-buffer-bit+)))

(defun gles-draw (display-list surface-width surface-height scale)
  "Execute DISPLAY-LIST onto the current GL surface at an integer SCALE."
  ;; The context is only ours for the duration of a frame, so what it holds at
  ;; the start of one cannot be assumed.
  (setf *last-clear-colour* nil)
  (gl "glViewport" 0 0 surface-width surface-height)
  ;; The whole surface first, so nothing from the previous frame survives where
  ;; this one does not paint.
  (gles-fill 0 0 (ceiling surface-width scale) (ceiling surface-height scale)
             +white+ surface-height scale)
  (dolist (rect (flatten-to-rects display-list))
    (destructuring-bind (x y width height colour) rect
      (gles-fill x y width height colour surface-height scale))))
