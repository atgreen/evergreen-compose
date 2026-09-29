(in-package :bliss)

;;;; A hole in the Bliss surface, with a real platform View behind it.
;;;;
;;;; Some things cannot be drawn: a WebView, a map, a camera preview, a video
;;;; surface. They are whole rendering engines with their own process-level
;;;; plumbing, and an application that needs one needs the real thing. Compose
;;;; calls this AndroidView.
;;;;
;;;; A PLATFORM-VIEW node takes part in layout like any box -- it has a size,
;;;; rows and columns place it, a scroller moves it -- and paints nothing. What
;;;; the host does with the rectangle is attach an actual View to the window at
;;;; those pixels.
;;;;
;;;; TWO THINGS THIS CANNOT DO, and no amount of work here will change either,
;;;; because they follow from there being one window:
;;;;
;;;; Z-ORDER. The View is a child of the window's content frame and our surface
;;;; is the window's own buffer, so the View draws ON TOP. A Bliss widget can
;;;; never appear over an embedded View -- a dialog, a snackbar, a dropdown will
;;;; all go behind it. The fix at the platform level is a SurfaceView with
;;;; Z-ordering, which is a different mechanism and a different bead.
;;;;
;;;; CLIPPING. The View is not clipped by anything Bliss draws, so one inside a
;;;; scroller does not slide under the app bar: it slides over it. What is done
;;;; here instead is the cheap half of the answer -- a View whose rectangle has
;;;; left the viewport entirely is hidden. Partial overlap still bleeds.

(defmethod measure-kind ((kind (eql :platform-view)) view constraints)
  (declare (ignore constraints))
  ;; No intrinsic size. A WebView will fill whatever it is given and a caller
  ;; who does not say how big means an invisible one, which is worth being
  ;; obvious rather than clever about.
  (values (view-prop view :width 0) (view-prop view :height 0)))

(defmethod render-kind ((kind (eql :platform-view)) view frame)
  "Nothing, unless :PLACEHOLDER says otherwise.

On the device the real View covers this rectangle completely, so a placeholder
is invisible there -- it is what a desktop, a test, and a screenshot taken
before the View attaches will see instead. That makes it worth having and not
worth defaulting on."
  (let ((placeholder (view-prop view :placeholder)))
    (when placeholder
      (list (list :fill-rect (rect-x frame) (rect-y frame)
                  (rect-width frame) (rect-height frame) (colour placeholder))))))

(defun platform-view (&key id (width 0) (height 0) view placeholder)
  "A rectangle for a real platform View.

ID names it across frames -- without one there is no way to tell the same View
in the next frame from a new one, so a node with no ID is ignored by the host.
VIEW is called once, on the platform's main thread, and must return a handle to
an attached View; it is the application's, because deciding WHICH View to make
is exactly the part a UI framework should not be guessing at."
  (list :platform-view (list :id id :width width :height height
                             :view view :placeholder placeholder)))

(defun platform-view-rects (placed &key (x-scale 1) (y-scale 1) clip)
  "Every PLATFORM-VIEW in PLACED, as (ID VIEW-FN X Y WIDTH HEIGHT VISIBLE-P).

X-SCALE and Y-SCALE convert Bliss's logical units to the window's pixels, which
are not the same number and are not the same ratio on both axes -- the buffer's
aspect is not the display's. Rounded, because a View's geometry is integral.

CLIP, when given, is the rectangle the host can actually show. A node whose
frame does not meet it at all comes back with VISIBLE-P false, which is the only
part of clipping a child View allows."
  (let ((found '()))
    (labels ((walk (node)
               (let ((view (laid-out-view node))
                     (frame (laid-out-frame node)))
                 (when (and (eq (view-kind view) :platform-view)
                            (view-prop view :id))
                   (push (list (view-prop view :id)
                               (view-prop view :view)
                               (round (* x-scale (rect-x frame)))
                               (round (* y-scale (rect-y frame)))
                               (round (* x-scale (rect-width frame)))
                               (round (* y-scale (rect-height frame)))
                               (or (null clip)
                                   (and (rect-intersect frame clip) t)))
                         found))
                 (mapc #'walk (laid-out-children node)))))
      (walk placed))
    (nreverse found)))
