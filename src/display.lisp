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

(defun round-rect-inset (radius height row)
  "How far a rounded rectangle's edge is inset at ROW, counted from its top.

The horizontal distance from the corner circle's centre to its edge at that
height: the circle equation and nothing cleverer. Its own function because
CLIP-SPANS needs exactly this for a row it did not generate."
  (let* ((from-top (- radius row 1/2))
         (from-bottom (- radius (- height row 1) 1/2))
         (depth (max (if (plusp from-top) from-top 0)
                     (if (plusp from-bottom) from-bottom 0))))
    (if (plusp depth)
        (- radius (isqrt (max 0 (floor (- (* radius radius) (* depth depth))))))
        0)))

(defun round-rect-spans (x y width height radius)
  "A rounded rectangle as one horizontal span per row: (x y width height).

Decomposing to spans rather than teaching every backend about arcs means a
backend that can fill an axis-aligned rectangle gets rounded corners for free,
exactly as FLATTEN-TO-RECTS gets text for free. A backend that HAS arcs -- Canvas
does -- should use them instead and skip this."
  (let ((r (min radius (floor width 2) (floor height 2)))
        (spans '()))
    (dotimes (row height (nreverse spans))
      (let ((inset (round-rect-inset r height row)))
        (when (< (* 2 inset) width)
          (push (list (+ x inset) (+ y row) (- width (* 2 inset)) 1) spans))))))

;;; ── The clip stack ────────────────────────────────────────────────────
;;;
;;; A clip is (AREA RADIUS ROUND): the rectangle to intersect with, and -- when
;;; the container that pushed it was rounded -- the radius and the rectangle
;;; that radius belongs to. ROUND is kept separately because AREA may already
;;; have been cut down by an outer clip, and the corners are a property of the
;;; rounded container, not of what is left of it.
;;;
;;; NIL is no clip at all, and a clip whose AREA is NIL clips everything away.

(defun clip-area (clip) (first clip))
(defun clip-radius (clip) (second clip))
(defun clip-round (clip) (third clip))

(defun push-clip (clips x y w h &optional (radius 0))
  "CLIPS with (X Y W H RADIUS) pushed on top, already intersected.

Two nested ROUNDED clips keep only the inner radius. Intersecting two rounded
shapes exactly would mean carrying a list of them and asking each one per row,
and nothing yet has needed it: a rounded container inside a rounded container is
a card inside a card, and the inner one is what the content touches."
  (let* ((current (first clips))
         (new (rect x y w h))
         (area (cond ((null current) new)
                     ((null (clip-area current)) nil)
                     (t (rect-intersect (clip-area current) new)))))
    (cons (if (plusp radius)
              (list area radius new)
              (list area (and current (clip-radius current))
                    (and current (clip-round current))))
          clips)))

(defun clip-spans (x y w h clip)
  "The parts of the rectangle that survive CLIP, as (x y width height) spans.

ONE span when the clip is rectangular -- the common case, and it costs nothing.
One span PER ROW when it is rounded, because that is what a rounded shape does
to a rectangle: each row loses a different amount to the corners."
  (cond ((null clip) (list (list x y w h)))
        ((null (clip-area clip)) '())
        (t
         (let ((area (rect-intersect (rect x y w h) (clip-area clip))))
           (cond ((null area) '())
                 ((null (clip-round clip))
                  (list (list (rect-x area) (rect-y area)
                              (rect-width area) (rect-height area))))
                 (t (%round-clip-spans area (clip-round clip) (clip-radius clip))))))))

(defun %round-clip-spans (area round radius)
  (let ((r (min radius (floor (rect-width round) 2) (floor (rect-height round) 2)))
        (spans '()))
    (loop for y from (rect-y area) below (rect-bottom area)
          do (let* ((inset (round-rect-inset r (rect-height round) (- y (rect-y round))))
                    (left (max (rect-x area) (+ (rect-x round) inset)))
                    (right (min (rect-right area) (- (rect-right round) inset))))
               (when (< left right)
                 (push (list left y (- right left) 1) spans))))
    (nreverse spans)))

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

(defmethod measure-kind ((kind (eql :paragraph)) view constraints)
  "Text broken to the width it is given.

The one primitive that genuinely needs its constraints: a :LABEL is as wide as
its string, and a paragraph is as wide as it is allowed to be and as tall as
that makes it."
  (multiple-value-bind (top right bottom left) (padding-of view)
    (let* ((max-width (constraints-max-width constraints))
           (room (when max-width (max 0 (- max-width left right))))
           (lines (wrap-text (view-prop view :text "") (view-prop view :size 1) room
                             :max-lines (view-prop view :max-lines))))
      (multiple-value-bind (w h) (wrapped-extent lines (view-prop view :size 1))
        ;; AS WIDE AS IT IS ALLOWED, not as wide as its widest line -- a block of
        ;; text, not a label. Three things break otherwise, and all three were
        ;; visible on the phone:
        ;;
        ;; RENDER re-breaks at the FRAME width, and if the frame shrank to the
        ;; widest line then measure and render are breaking at different widths.
        ;; For ordinary wrapping the two agree by accident; for :MAX-LINES they
        ;; do not, and the second pass re-wrapped the already-truncated text and
        ;; left a line holding nothing but the ellipsis.
        ;;
        ;; :ALIGN has nothing to centre within when the block is exactly as wide
        ;; as its content, so a centred paragraph came out flush left.
        ;;
        ;; And a ragged-right column that shrinks to its longest line makes the
        ;; whole block jump sideways whenever the text changes.
        ;;
        ;; A caller who wants shrink-to-fit wants TEXT, which is one line and
        ;; measures its own string.
        (values (if room (+ room left right) (+ w left right))
                (+ h top bottom))))))

(defmethod render-kind ((kind (eql :paragraph)) view frame)
  "One :GLYPHS operation per line.

Broken again here rather than carried over from measurement, because a frame is
not a measurement: a grower is measured loosely and placed tight, so the width
that decided the lines and the width they are drawn at are different numbers.
WRAP-TEXT is memoised, so the second break is a hash lookup."
  (multiple-value-bind (top right bottom left) (padding-of view)
    (declare (ignore bottom))
    (let* ((scale (view-prop view :size 1))
           (ink (colour (view-prop view :colour +black+)))
           (width (max 0 (- (rect-width frame) left right)))
           (lines (wrap-text (view-prop view :text "") scale width
                             :max-lines (view-prop view :max-lines)))
           (align (view-prop view :align :start))
           (y (+ (rect-y frame) top)))
      (loop for line in lines
            append (multiple-value-bind (w h) (text-extent line scale)
                     (prog1
                         (list (list :glyphs
                                     (+ (rect-x frame) left
                                        (ecase align
                                          (:start 0)
                                          (:center (floor (- width w) 2))
                                          (:end (- width w))))
                                     y line scale ink))
                       (incf y h)))))))

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
                   ;; The RADIUS travels with the clip, so a rounded container
                   ;; clips its children to the shape it actually draws. Without
                   ;; it a card with :RADIUS painted rounded corners and let an
                   ;; image inside it keep square ones (bliss-cvj).
                   (emit (list :clip-push (rect-x frame) (rect-y frame)
                               (rect-width frame) (rect-height frame)
                               (view-prop view :radius 0))))
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
             ;; that only fills rectangles needs to know nothing about clipping
             ;; -- rounded clipping included, which arrives here as one span per
             ;; row and leaves as ordinary rectangles.
             (dolist (span (clip-spans x y w h (first clips)))
               (push (append span (list colour)) rects))))
      (dolist (op display-list (nreverse rects))
        (ecase (first op)
          (:clip-push (destructuring-bind (x y w h &optional (radius 0)) (rest op)
                        (setf clips (push-clip clips x y w h radius))))
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
