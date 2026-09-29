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

(defparameter *shadow-colour* (rgba 0 0 0 110)
  "What a raised surface casts. A view may override it with :SHADOW-COLOUR.

Here rather than in the theme because the display list must not depend on the
widget vocabulary -- a backend receives operations, not decisions.")

(defun shadow-op (view frame)
  "The :SHADOW operation for a raised surface, or NIL when it is not raised.

Material measures elevation in dp and derives the blur and the offset from it.
Same idea, constants in one place: twice the elevation of blur, and the
elevation itself of downward offset, which is what makes a raised thing look
lit from above."
  (let ((elevation (view-prop view :elevation 0)))
    (when (plusp elevation)
      (list :shadow (rect-x frame) (rect-y frame) (rect-width frame) (rect-height frame)
            (view-prop view :radius 0) (* 2 elevation) elevation
            (colour (view-prop view :shadow-colour *shadow-colour*))))))

(defun shadow-rects (x y width height radius blur dy colour)
  "A shadow as plain rectangles: concentric rings of a low-alpha colour.

There is no blur here and none coming. A backend that can only fill rectangles
can still show that something is raised, and a real Gaussian would be the most
expensive thing in this framework by a wide margin. Under source-over the rings
accumulate into a falloff that reads as a shadow at the sizes a UI uses, which
is all this has to do. A backend with a real blur -- Canvas has one -- should
draw :SHADOW itself and never come through here."
  (let* ((rings (max 1 (min blur 6)))
         (ink (rgba (colour-red colour) (colour-green colour) (colour-blue colour)
                    (max 1 (floor (colour-alpha colour) rings))))
         (rects '()))
    (loop for ring from rings downto 1
          for inset = (round (* blur ring) rings)
          do (dolist (span (round-rect-spans (- x inset) (+ y dy (- inset))
                                             (+ width inset inset) (+ height inset inset)
                                             (+ radius inset)))
               (push (append span (list ink)) rects)))
    (nreverse rects)))

(defparameter *border-colour* (rgba 0 0 0 255)
  "What an outline is drawn in when a view does not say. Here rather than in the
theme for the same reason as *SHADOW-COLOUR*: the display list must not depend on
the widget vocabulary.")

(defun stroke-spans (x y width height radius thickness)
  "An outlined rectangle as spans: the shape, minus the shape inset by THICKNESS.

Subtracting one span set from the other rather than drawing four edges, because
four edges are wrong at a corner -- they meet in a square notch where the
rounding should be. Doing it by rows costs nothing extra: ROUND-RECT-SPANS
already produces one span per row, so the difference is a lookup and at most two
pieces per row."
  (let* ((outer (round-rect-spans x y width height radius))
         (inner (round-rect-spans (+ x thickness) (+ y thickness)
                                  (max 0 (- width thickness thickness))
                                  (max 0 (- height thickness thickness))
                                  (max 0 (- radius thickness))))
         (holes (make-hash-table :test #'eql))
         (spans '()))
    (dolist (span inner) (setf (gethash (second span) holes) span))
    (dolist (span outer (nreverse spans))
      (destructuring-bind (sx sy sw sh) span
        (let ((hole (gethash sy holes)))
          (if hole
              (destructuring-bind (hx hole-y hw hole-h) hole
                (declare (ignore hole-y hole-h))
                ;; Left of the hole, and right of it. A row through the middle
                ;; of the outline gives both; a row through the top gives
                ;; neither, because there is no hole in that row at all.
                (when (> hx sx) (push (list sx sy (- hx sx) sh) spans))
                (let ((right (+ hx hw)) (end (+ sx sw)))
                  (when (> end right) (push (list right sy (- end right) sh) spans))))
              (push span spans)))))))

(defun %box-ops (view frame)
  "The fill for a box or a container background, rounded when asked, over the
shadow it casts when it is raised.

A shadow needs something to cast it: a view with :ELEVATION and no fill is
transparent, and a shadow under nothing is a bug rather than a feature."
  (let ((fill (or (view-prop view :fill) (view-prop view :background)))
        (radius (view-prop view :radius 0)))
    (append
     (when fill (let ((shadow (shadow-op view frame))) (when shadow (list shadow))))
     (when fill
      (list (if (plusp radius)
                (list :fill-round-rect (rect-x frame) (rect-y frame)
                      (rect-width frame) (rect-height frame) radius (colour fill))
                (list :fill-rect (rect-x frame) (rect-y frame)
                      (rect-width frame) (rect-height frame) (colour fill)))))
     ;; After the fill, because an outline is drawn ON the edge -- and without
     ;; one, because an outline round nothing is exactly what a checkbox is.
     (let ((border (view-prop view :border 0)))
       (when (plusp border)
         (list (list :stroke-rect (rect-x frame) (rect-y frame)
                     (rect-width frame) (rect-height frame)
                     radius border
                     (colour (view-prop view :border-colour *border-colour*)))))))))

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

(defmethod measure-kind ((kind (eql :path)) view constraints)
  (declare (ignore constraints))
  ;; Square by default, like every icon set: the drawing is described in a
  ;; VIEW-BOX-square space and :SIZE says how big that square comes out.
  (let ((size (view-prop view :size 24)))
    (values size size)))

(defmethod render-kind ((kind (eql :path)) view frame)
  (let ((commands (view-prop view :commands)))
    (when commands
      (list (list :path (rect-x frame) (rect-y frame)
                  (rect-width frame) (rect-height frame)
                  (view-prop view :view-box 24) commands
                  (colour (view-prop view :colour +black+)))))))

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
          (:shadow (dolist (rect (apply #'shadow-rects (rest op)))
                     (apply #'clipped rect)))
          (:path
           (destructuring-bind (x y w h view-box commands ink) (rest op)
             (dolist (span (path-spans commands x y w h view-box))
               (apply #'clipped (append span (list ink))))))
          (:stroke-rect
           (destructuring-bind (x y w h radius thickness ink) (rest op)
             (dolist (span (stroke-spans x y w h radius thickness))
               (apply #'clipped (append span (list ink))))))
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

;;; ── Diagnostics: how much of a frame could be reused? ─────────────────
;;;
;;; The display list carries ABSOLUTE coordinates, so a node's operations are
;;; reusable next frame only if the node is the same object AND lands in the
;;; same place. Whether that is a large fraction or a rounding error decides
;;; whether caching them is worth building, so it is measured first.

(defun record-placement (placed)
  "VIEW to (X Y WIDTH HEIGHT) for every node of a laid-out tree."
  (let ((table (make-hash-table :test #'eq)))
    (labels ((walk (node)
               (let ((f (laid-out-frame node)))
                 (setf (gethash (laid-out-view node) table)
                       (list (rect-x f) (rect-y f) (rect-width f) (rect-height f))))
               (mapc #'walk (laid-out-children node))))
      (walk placed))
    table))

(defun placement-overlap (placed previous &optional bounds)
  "MATCHED, TOTAL, and the DAMAGE rectangle.

MATCHED and TOTAL count nodes that were the same view in the same place last
frame -- the set whose operations could be reused verbatim. DAMAGE is the union
of everything else, which is the more useful number: a backend that keeps its
last frame need only redraw that rectangle, and node COUNT says nothing about
how much of the screen it covers.

BOUNDS clamps each contributing frame, and is not optional in practice. A
virtual list's spacers stand in for every item it did not build, so one of them
is as wide as the whole list -- 347,900 units for a five-thousand-card shelf --
and an unclamped union is that wide too. The first attempt at this reported 91146
percent of the screen damaged, which is how that was found."
  (let ((matched 0) (total 0) (damage nil))
    (labels ((walk (node)
               (incf total)
               (let ((f (laid-out-frame node))
                     (was (and previous (gethash (laid-out-view node) previous))))
                 (when (and was
                            (eql (first was) (rect-x f))
                            (eql (second was) (rect-y f))
                            (eql (third was) (rect-width f))
                            (eql (fourth was) (rect-height f)))
                   (incf matched))
                 (unless was
                   ;; Changed, moved, or new. A node that merely MOVED damages
                   ;; where it went; where it came FROM is damaged by whatever
                   ;; replaced it, which is this same union on another node.
                   (let ((visible (if bounds (rect-intersect f bounds) f)))
                     (when visible
                       (setf damage (if damage (rect-union damage visible) visible))))))
               (mapc #'walk (laid-out-children node))))
      (walk placed))
    (values matched total damage)))

(defun op-bounds (op)
  "The rectangle an operation paints in, or NIL for one that paints nothing."
  (case (first op)
    ((:fill-rect :fill-round-rect :image :path :clip-push :stroke-rect)
     (destructuring-bind (x y w h &rest ignored) (rest op)
       (declare (ignore ignored))
       (rect x y w h)))
    ;; A shadow is blurred and dropped, so it reaches past the rectangle casting it.
    (:shadow (destructuring-bind (x y w h radius blur dy colour) (rest op)
               (declare (ignore radius colour))
               (rect (- x blur) (- y blur) (+ w blur blur) (+ h blur blur dy))))
    (:glyphs (destructuring-bind (x y text scale colour) (rest op)
               (declare (ignore colour))
               (multiple-value-bind (w h) (text-extent text scale)
                 (rect x y w h))))
    (t nil)))

(defun display-damage (new old &optional bounds)
  "The rectangle covering every operation that differs between OLD and NEW.

Compared as OPERATIONS rather than as nodes, which is the whole point. A
container rebuilt every frame is a different LIST but paints the identical
rectangle in the identical place, so node identity calls it changed and its
drawing is not. The root container is exactly that case, and it covers the whole
screen, which is why a node-level damage region reported 100% every frame while
43% of nodes were provably unmoved."
  (let ((before (make-hash-table :test #'equal))
        (damage nil))
    (dolist (op old) (incf (gethash op before 0)))
    (flet ((mark (op)
             (let ((box (op-bounds op)))
               (when box
                 (let ((visible (if bounds (rect-intersect box bounds) box)))
                   (when visible
                     (setf damage (if damage (rect-union damage visible) visible))))))))
      ;; Painted now and not before.
      (dolist (op new)
        (let ((seen (gethash op before 0)))
          (if (plusp seen)
              (setf (gethash op before) (1- seen))
              (mark op))))
      ;; Painted before and not now: whatever it left behind must be covered.
      (maphash (lambda (op count) (when (plusp count) (mark op))) before))
    damage))
