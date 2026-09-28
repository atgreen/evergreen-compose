(in-package :bliss)

;;; The display list is the framework's whole contract with a backend: a flat,
;;; ordered sequence of absolute drawing operations, painted back to front.
;;;
;;;   (:fill-rect x y width height colour)
;;;   (:glyphs    x y text scale colour)
;;;
;;; Flat and absolute, so a backend needs no tree walk and no transform stack;
;;; ordered, so painter's-algorithm compositing is the only rule. Keeping it
;;; data means a frame can be captured, printed, diffed between runs, or
;;; replayed -- which is how the tests below compare renders without a GPU, and
;;; how the same frame can go to a software surface here and to GLES on a phone.

(defgeneric render-kind (kind view frame)
  (:documentation "The display operations a VIEW of KIND contributes at FRAME,
as a list, painted before its children.

Specialised on the kind KEYWORD for the same reason as MEASURE-KIND: a new
primitive is added from outside, and the tree stays data. Returning a LIST
rather than writing to a stream keeps a method a pure function of its node,
which is what makes a frame comparable between renders.")
  (:method (kind view frame)
    (declare (ignore view frame))
    (error "No RENDER-KIND method for ~S." kind)))

(defmethod render-kind ((kind (eql :box)) view frame)
  (let ((fill (view-prop view :fill)))
    (when fill
      (list (list :fill-rect (rect-x frame) (rect-y frame)
                  (rect-width frame) (rect-height frame) (colour fill))))))

(defmethod render-kind ((kind (eql :label)) view frame)
  (list (list :glyphs (rect-x frame) (rect-y frame)
              (view-prop view :text "") (view-prop view :size 1)
              (colour (view-prop view :colour +black+)))))

(defun %background-ops (view frame)
  (let ((background (view-prop view :background)))
    (when background
      (list (list :fill-rect (rect-x frame) (rect-y frame)
                  (rect-width frame) (rect-height frame) (colour background))))))

(defmethod render-kind ((kind (eql :row)) view frame) (%background-ops view frame))
(defmethod render-kind ((kind (eql :column)) view frame) (%background-ops view frame))

(defun render (laid-out-tree)
  "The display list for a laid-out tree, as a list of operations."
  (let ((ops '()))
    (labels ((emit (op) (push op ops))
             (walk (node)
               (let* ((view (laid-out-view node))
                      (frame (laid-out-frame node))
                      (kind (view-kind view)))
                 (mapc #'emit (render-kind kind view frame))
                 ;; Children after the parent's own background, so a container
                 ;; paints beneath what it contains.
                 (mapc #'walk (laid-out-children node)))))
      (walk laid-out-tree))
    (nreverse ops)))

(defun flatten-to-rects (display-list)
  "DISPLAY-LIST reduced to nothing but (x y width height colour) rectangles.

Glyphs expand into their inked pixels. That sounds wasteful and is exactly what
makes a backend cheap to write: a device that can fill an axis-aligned rectangle
can run the whole framework, with no texture upload, no shader and no glyph
cache. The GLES backend is six entry points because of this."
  (let ((rects '()))
    (dolist (op display-list (nreverse rects))
      (ecase (first op)
        (:fill-rect (push (rest op) rects))
        (:glyphs
         (destructuring-bind (x y text scale colour) (rest op)
           (loop for character across text
                 for pen = x then (+ pen (* scale +glyph-advance+))
                 for glyph = (glyph character)
                 when glyph
                   do (dotimes (row +glyph-height+)
                        (dotimes (column +glyph-width+)
                          (when (glyph-pixel-p glyph column row)
                            (push (list (+ pen (* column scale))
                                        (+ y (* row scale))
                                        scale scale colour)
                                  rects)))))))))))
