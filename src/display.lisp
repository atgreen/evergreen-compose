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

(defun round-rect-spans (x y width height radius)
  "A rounded rectangle as one horizontal span per row: (x y width height).

Decomposing to spans rather than teaching every backend about arcs means a
backend that can fill an axis-aligned rectangle gets rounded corners for free,
exactly as FLATTEN-TO-RECTS gets text for free. A backend that HAS arcs -- Canvas
does -- should use them instead and skip this.

The inset per row is the horizontal distance from the corner circle's centre to
its edge at that height, which is the circle equation and nothing cleverer."
  (let ((r (min radius (floor width 2) (floor height 2)))
        (spans '()))
    (dotimes (row height (nreverse spans))
      (let* ((from-top (- r row 1/2))
             (from-bottom (- r (- height row 1) 1/2))
             (depth (max (if (plusp from-top) from-top 0)
                         (if (plusp from-bottom) from-bottom 0)))
             (inset (if (plusp depth)
                        (- r (isqrt (max 0 (floor (- (* r r) (* depth depth))))))
                        0)))
        (when (< (* 2 inset) width)
          (push (list (+ x inset) (+ y row) (- width (* 2 inset)) 1) spans))))))

(defun %box-ops (view frame)
  "The fill for a box or a container background, rounded when asked."
  (let ((fill (or (view-prop view :fill) (view-prop view :background)))
        (radius (view-prop view :radius 0)))
    (when fill
      (list (if (plusp radius)
                (list :fill-round-rect (rect-x frame) (rect-y frame)
                      (rect-width frame) (rect-height frame) radius (colour fill))
                (list :fill-rect (rect-x frame) (rect-y frame)
                      (rect-width frame) (rect-height frame) (colour fill)))))))

(defmethod measure-kind ((kind (eql :image)) view constraints)
  (declare (ignore constraints))
  ;; An image wants its own pixel size; a caller who wants it scaled says so
  ;; with :WIDTH or :HEIGHT, which %MEASURE applies over the top of this.
  (let ((source (view-prop view :source)))
    (if source
        (values (surface-width source) (surface-height source))
        (values 0 0))))

(defmethod render-kind ((kind (eql :image)) view frame)
  (let ((source (view-prop view :source)))
    (when source
      (list (list :image (rect-x frame) (rect-y frame)
                  (rect-width frame) (rect-height frame) source)))))

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

(defmethod render-kind ((kind (eql :box)) view frame) (%box-ops view frame))

(defmethod render-kind ((kind (eql :label)) view frame)
  (list (list :glyphs (rect-x frame) (rect-y frame)
              (view-prop view :text "") (view-prop view :size 1)
              (colour (view-prop view :colour +black+)))))

(defmethod render-kind ((kind (eql :row)) view frame) (%box-ops view frame))
(defmethod render-kind ((kind (eql :column)) view frame) (%box-ops view frame))

(defun render (laid-out-tree)
  "The display list for a laid-out tree, as a list of operations."
  (let ((ops '()))
    (labels ((emit (op) (push op ops))
             (walk (node)
               (let* ((view (laid-out-view node))
                      (frame (laid-out-frame node))
                      (kind (view-kind view)))
                 (mapc #'emit (render-kind kind view frame))
                 ;; A container with :CLIP confines its children to its own
                 ;; frame. Emitted around the children rather than by the node
                 ;; itself, because that is the extent being clipped TO.
                 (when (view-prop view :clip)
                   (emit (list :clip-push (rect-x frame) (rect-y frame)
                               (rect-width frame) (rect-height frame))))
                 ;; Children after the parent's own background, so a container
                 ;; paints beneath what it contains.
                 (mapc #'walk (laid-out-children node))
                 (when (view-prop view :clip) (emit (list :clip-pop))))))
      (walk laid-out-tree))
    (nreverse ops)))

(defun flatten-to-rects (display-list)
  "DISPLAY-LIST reduced to nothing but (x y width height colour) rectangles.

Glyphs expand into their inked pixels. That sounds wasteful and is exactly what
makes a backend cheap to write: a device that can fill an axis-aligned rectangle
can run the whole framework, with no texture upload, no shader and no glyph
cache. The GLES backend is six entry points because of this."
  (let ((rects '())
        (clips (list nil)))
    (flet ((clipped (x y w h colour)
             ;; Intersect with the innermost clip before emitting, so a backend
             ;; that only fills rectangles needs to know nothing about clipping.
             (let ((area (if (first clips)
                             (rect-intersect (rect x y w h) (first clips))
                             (rect x y w h))))
               (when area
                 (push (list (rect-x area) (rect-y area)
                             (rect-width area) (rect-height area) colour)
                       rects)))))
      (dolist (op display-list (nreverse rects))
        (ecase (first op)
          (:clip-push (destructuring-bind (x y w h) (rest op)
                        (let ((new (rect x y w h)))
                          (push (if (first clips)
                                    (rect-intersect new (first clips))
                                    new)
                                clips))))
          (:clip-pop (pop clips))
          (:fill-round-rect
           (destructuring-bind (x y w h radius colour) (rest op)
             (dolist (span (round-rect-spans x y w h radius))
               (apply #'clipped (append span (list colour))))))
          (:fill-rect (apply #'clipped (rest op)))
          ;; An image is the one operation that does NOT reduce to rectangles.
          ;; A backend which only fills rectangles cannot draw one, and silently
          ;; dropping it would leave a hole nobody could account for.
          (:image (error "FLATTEN-TO-RECTS cannot reduce an image. A backend ~
                          that draws images must handle :IMAGE itself."))
          (:glyphs
           (destructuring-bind (x y text scale colour) (rest op)
             (loop for character across text
                   for pen = x then (+ pen (* scale +glyph-advance+))
                   for glyph = (glyph character)
                   when glyph
                     do (dotimes (row +glyph-height+)
                          (dotimes (column +glyph-width+)
                            (when (glyph-pixel-p glyph column row)
                              (clipped (+ pen (* column scale))
                                       (+ y (* row scale))
                                       scale scale colour))))))))))))
