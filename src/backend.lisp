(in-package :bliss)

;;;; The backend protocol.
;;;;
;;;; This is where CLOS earns its place, and the view tree is where it does not.
;;;;
;;;; A backend is a long-lived object -- one per application, holding a surface
;;;; or a JNI handle or a GL context -- and there are several with genuinely
;;;; different implementations of one idea. That is what generic functions are
;;;; for. A view NODE is the opposite: thousands per second, thrown away every
;;;; frame, and wanted as data that can be quoted, printed, read back, diffed
;;;; and built by a macro. Measured on release x86-64, a CLOS instance costs
;;;; 11.6us to allocate against 3.2us for a list, and a generic call 1.4us
;;;; against 0.5us for an ECASE -- about 7% of a frame at fifty nodes, which is
;;;; affordable. The reason the tree stays lists is not the cost; it is that
;;;; EQUAL on lists is what lets an unchanged frame skip drawing, and that a
;;;; user's own widget is a DEFUN returning primitives rather than a class with
;;;; methods to implement.

(defclass backend () ()
  (:documentation "Something that can put a display list somewhere."))

(defgeneric present (backend display-list)
  (:documentation "Draw DISPLAY-LIST. Returns the backend."))

(defgeneric backend-size (backend)
  (:documentation "The backend's drawable size, as width and height."))

(defgeneric backend-text-metrics (backend)
  (:documentation "A function of (text scale) giving the size this backend will
actually draw, or NIL to keep the built-in bitmap metrics.

Layout centres a label by the width it is told. A backend that draws with a
different font than the one measured lays every box out for a font that never
appears -- which is not a hypothetical, it is a bug this framework had.")
  (:method ((backend backend)) nil))

(defun use-backend (backend)
  "Install BACKEND's text metrics, so layout measures what will be drawn."
  (let ((metrics (backend-text-metrics backend)))
    (when metrics (setf *measure-text* metrics)))
  ;; Unconditionally: every remembered size was measured with whatever font was
  ;; installed before, and the memo now outlives a frame, so a stale entry
  ;; outlives the reason it was right. A backend with no metrics of its own does
  ;; not make that safer -- it leaves the PREVIOUS backend's installed.
  (forget-layout)
  backend)

(defun draw-frame (backend view)
  "Lay out VIEW to BACKEND's size, render it, and present it.
Returns the laid-out tree, which is what hit testing needs."
  (multiple-value-bind (width height) (backend-size backend)
    (let ((placed (layout view 0 0 (constraints 0 width 0 height))))
      (present backend (render placed))
      placed)))
