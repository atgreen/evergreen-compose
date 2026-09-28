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

(defun render (laid-out-tree)
  "The display list for a laid-out tree, as a list of operations."
  (let ((ops '()))
    (labels ((emit (op) (push op ops))
             (walk (node)
               (let* ((view (laid-out-view node))
                      (frame (laid-out-frame node))
                      (kind (view-kind view)))
                 (case kind
                   (:box (let ((fill (view-prop view :fill)))
                          (when fill (emit (list :fill-rect
                                                 (rect-x frame) (rect-y frame)
                                                 (rect-width frame) (rect-height frame)
                                                 (colour fill))))))
                   (:label (emit (list :glyphs
                                      (rect-x frame) (rect-y frame)
                                      (view-prop view :text "")
                                      (view-prop view :size 1)
                                      (colour (view-prop view :colour +black+)))))
                   ((:row :column)
                    (let ((background (view-prop view :background)))
                      (when background
                        (emit (list :fill-rect
                                    (rect-x frame) (rect-y frame)
                                    (rect-width frame) (rect-height frame)
                                    (colour background)))))))
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
