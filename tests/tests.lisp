(in-package :bliss)

;;; A test harness small enough to have no dependencies, because the framework
;;; it tests has none either. Every check reports, and the runner exits non-zero
;;; if any failed, so this works from a shell, from CI, and over `adb shell`.

(defparameter *failures* 0)
(defparameter *checks* 0)

(defun check (name expected actual)
  (incf *checks*)
  (cond ((equal expected actual) (format t "  ok   ~A~%" name))
        (t (incf *failures*)
           (format t "  FAIL ~A~%       expected ~S~%       actual   ~S~%"
                   name expected actual))))

(defun check-true (name value) (check name t (and value t)))

;;; ── geometry ──────────────────────────────────────────────────────────
(defun test-geometry ()
  (format t "geometry~%")
  (let ((r (rect 10 20 30 40)))
    (check "right" 40 (rect-right r))
    (check "bottom" 60 (rect-bottom r))
    (check-true "contains its own origin" (rect-contains-p r 10 20))
    ;; Half-open: the bottom-right corner belongs to the NEXT rectangle, which is
    ;; what stops adjacent views double-painting a shared edge.
    (check-true "excludes its far corner" (not (rect-contains-p r 40 60))))
  (check "disjoint rects do not intersect" nil
         (rect-intersect (rect 0 0 5 5) (rect 10 10 5 5)))
  (let ((overlap (rect-intersect (rect 0 0 10 10) (rect 5 5 10 10))))
    (check "overlap origin" '(5 5) (list (rect-x overlap) (rect-y overlap)))
    (check "overlap size" '(5 5) (list (rect-width overlap) (rect-height overlap)))))

;;; ── paint ─────────────────────────────────────────────────────────────
(defun test-paint ()
  (format t "paint~%")
  (check "#rrggbb" (rgb 255 0 0) (colour "#ff0000"))
  (check "#rgb expands each nibble" (rgb 255 0 0) (colour "#f00"))
  (check "#rrggbbaa keeps alpha" 128 (colour-alpha (colour "#00000080")))
  (check "an integer passes through" (rgb 1 2 3) (colour (rgb 1 2 3)))
  (check "opaque source replaces" (rgb 255 0 0) (blend (rgb 255 0 0) (rgb 0 0 255)))
  (check "transparent source keeps ground" (rgb 0 0 255)
         (blend (rgba 255 0 0 0) (rgb 0 0 255)))
  ;; Half alpha over black is half intensity, within the rounding FLOOR gives.
  ;; 255*128/255 is exactly 128, so half alpha over black is 128, not 127.
  (check "half alpha blends" 128 (colour-red (blend (rgba 255 0 0 128) +black+))))

;;; ── font ──────────────────────────────────────────────────────────────
(defun test-font ()
  (format t "font~%")
  (check-true "has a glyph for A" (glyph #\A))
  (check-true "lowercase resolves to the same glyph" (eq (glyph #\a) (glyph #\A)))
  (check "unknown characters have no glyph" nil (glyph #\~))
  (check "empty text has no width" 0 (nth-value 0 (text-extent "" 1)))
  ;; One glyph is 5 wide; the trailing letter-space is not counted.
  (check "one glyph is its own width" 5 (nth-value 0 (text-extent "A" 1)))
  (check "two glyphs add one space" 11 (nth-value 0 (text-extent "AB" 1)))
  (check "scale multiplies" 22 (nth-value 0 (text-extent "AB" 2)))
  (check "height is the cell" 7 (nth-value 1 (text-extent "A" 1))))

;;; ── layout ────────────────────────────────────────────────────────────
(defun test-layout ()
  (format t "layout~%")
  (let ((box '(box (:width 10 :height 4))))
    (check "a box measures its props" '(10 4)
           (multiple-value-list (measure box))))
  ;; A row is the sum of its children plus the gaps BETWEEN them: two children
  ;; means one gap, not two.
  (let ((row '(row (:gap 2)
               (box (:width 10 :height 4))
               (box (:width 6 :height 9)))))
    (check "row width sums children and inner gaps" 18 (nth-value 0 (measure row)))
    (check "row height is the tallest child" 9 (nth-value 1 (measure row))))
  (let ((column '(column (:gap 3)
                  (box (:width 10 :height 4))
                  (box (:width 6 :height 9)))))
    (check "column height sums children and inner gaps" 16
           (nth-value 1 (measure column)))
    (check "column width is the widest child" 10 (nth-value 0 (measure column))))
  ;; The tree a user writes lives in the USER'S package, so COLUMN there is not
  ;; BLISS::COLUMN. Dispatching on the symbol rather than its name took the first
  ;; Android run down with "The value COLUMN is not of type (MEMBER BLISS::BOX
  ;; ...)". Building the tree with foreign symbols reproduces that on a desktop.
  (let ((foreign (list (list (intern "ROW" :cl-user) '(:gap 2)
                             (list (intern "BOX" :cl-user) '(:width 10 :height 4))
                             (list (intern "BOX" :cl-user) '(:width 6 :height 9))))))
    (check "a tree written in another package lays out the same" '(18 9)
           (multiple-value-list (measure (first foreign)))))
  (let ((padded '(column (:padding 5) (box (:width 10 :height 4)))))
    (check "padding grows both axes" '(20 14)
           (multiple-value-list (measure padded))))
  ;; Placement: children start inside the padding and advance by their own size.
  (let* ((tree '(column (:padding 5 :gap 2)
                 (box (:width 10 :height 4))
                 (box (:width 10 :height 6))))
         (placed (layout tree 100 200))
         (kids (laid-out-children placed)))
    (check "root sits where it was placed" '(100 200)
           (list (rect-x (laid-out-frame placed)) (rect-y (laid-out-frame placed))))
    (check "first child clears the padding" '(105 205)
           (list (rect-x (laid-out-frame (first kids)))
                 (rect-y (laid-out-frame (first kids)))))
    (check "second child clears the first plus the gap" 211
           (rect-y (laid-out-frame (second kids))))))

;;; ── display list ──────────────────────────────────────────────────────
(defun test-render ()
  (format t "display list~%")
  (let* ((tree '(column (:background "#ffffff")
                 (box (:width 4 :height 4 :fill "#ff0000"))))
         (ops (render (layout tree 0 0))))
    (check "a background and a fill" 2 (length ops))
    ;; The container paints before its children, or it would erase them.
    (check "background first" :fill-rect (first (first ops)))
    (check "background covers the frame" '(0 0 4 4) (subseq (first ops) 1 5))
    (check "child colour survives to the list" (rgb 255 0 0) (sixth (second ops))))
  ;; A box with no :fill contributes nothing to draw, rather than an invisible op.
  (check "an unfilled box emits nothing" 0
         (length (render (layout '(box (:width 4 :height 4)) 0 0))))
  ;; Same tree, same list: the renderer is a pure function of the tree, which is
  ;; what lets a frame be diffed between runs and cached between frames.
  (let ((tree '(row (:gap 1) (box (:width 2 :height 2 :fill "#123456")))))
    (check "rendering is deterministic"
           (render (layout tree 0 0)) (render (layout tree 0 0)))))

;;; ── rasterizer ────────────────────────────────────────────────────────
(defun test-raster ()
  (format t "raster~%")
  (let ((surface (make-surface 4 4 +white+)))
    (check "cleared to the fill" +white+ (pixel-at surface 0 0))
    (draw surface (list (list :fill-rect 1 1 2 2 (rgb 255 0 0))))
    (check "inside the rect is painted" (rgb 255 0 0) (pixel-at surface 1 1))
    (check "the far edge is not" +white+ (pixel-at surface 3 3))
    (check "outside the rect is untouched" +white+ (pixel-at surface 0 0)))
  ;; Clipping, not dropping: a rect hanging off the edge still paints what fits.
  (let ((surface (make-surface 4 4 +white+)))
    (draw surface (list (list :fill-rect -2 -2 4 4 +black+)))
    (check "a partly offscreen rect still paints" +black+ (pixel-at surface 0 0))
    (check "and stops where it should" +white+ (pixel-at surface 2 2)))
  ;; A glyph lands where it was asked to, and its blank columns stay blank.
  (let ((surface (make-surface 8 8 +white+)))
    (draw surface (list (list :glyphs 0 0 "T" 1 +black+)))
    (check "the top bar of T is inked" +black+ (pixel-at surface 0 0))
    (check "the stem of T is inked" +black+ (pixel-at surface 2 6))
    (check "T has no ink at its bottom-left" +white+ (pixel-at surface 0 6))))

;;; ── hit testing and dispatch ──────────────────────────────────────────
(defun test-input ()
  (format t "input~%")
  (let* ((tree '(column (:padding 10 :gap 5)
                 (box (:width 40 :height 20 :id :first :on-press t))
                 (box (:width 40 :height 20 :id :second :on-press t))))
         (placed (layout tree 0 0)))
    ;; First child sits at (10,10) after padding, 40x20.
    (check "hits the first child" :first
           (node-prop (hit-test placed 15 15) :id))
    ;; Second is below it by the first child's height plus the gap.
    (check "hits the second child" :second
           (node-prop (hit-test placed 15 40) :id))
    ;; Inside the container but on neither child: the container itself.
    (check "falls back to the container" nil
           (node-prop (hit-test placed 2 2) :id))
    (check "misses entirely" nil (hit-test placed 500 500)))
  ;; A later sibling paints over an earlier one, so it must win a shared point.
  (let* ((tree '(column (:padding 0 :gap 0)
                 (box (:width 40 :height 0 :id :under))
                 (box (:width 40 :height 20 :id :over))))
         (placed (layout tree 0 0)))
    (check "the last painted wins" :over (node-prop (hit-test placed 5 5) :id)))
  ;; DISPATCH calls the handler of the topmost node that HAS one, so a plain
  ;; child inside an interactive parent hands the event to the parent.
  (let* ((fired '())
         (tree `(column (:on-press ,(lambda (n) (push :outer fired)))
                  (box (:width 20 :height 20))
                  (box (:width 20 :height 20
                        :on-press ,(lambda (n) (push :inner fired))))))
         (placed (layout tree 0 0)))
    (dispatch placed 5 25 :on-press)
    (check "dispatch reaches the inner handler" '(:inner) fired)
    (dispatch placed 5 5 :on-press)
    (check "and the parent when the child has none" '(:outer :inner) fired)
    (check "a miss dispatches nothing" nil (dispatch placed 900 900 :on-press)))
  ;; Physical touches must be converted before they mean anything.
  (check "scales a touch to logical space" '(10 20)
         (multiple-value-list (scale-point 30 60 3)))
  ;; The axes scale independently: one ratio for both is wrong whenever the
  ;; buffer's aspect ratio is not the display's, which is the usual case.
  (check "and each axis by its own ratio" '(10 20)
         (multiple-value-list (scale-point 30 80 3 4))))

;;; ── widgets ──────────────────────────────────────────────────────────
(defun test-widgets ()
  (format t "widgets~%")
  ;; A widget is just a function returning view data: the result must be a
  ;; perfectly ordinary tree that LAYOUT and RENDER already understand.
  (let ((view (button "OK" :id :ok :on-press #'identity)))
    (check-true "a button is a view" (view-p view))
    (check "it carries its id" :ok (view-prop view :id))
    (check-true "it carries its handler" (view-prop view :on-press))
    (check-true "it lays out" (plusp (nth-value 0 (measure view))))
    (check-true "and it draws" (plusp (length (render (layout view 0 0))))))
  ;; Disabled buttons must not be dispatchable, or a greyed-out control still
  ;; fires when touched -- which looks like the app ignoring the disable.
  (let ((view (button "No" :id :no :on-press #'identity :disabled t)))
    (check "a disabled button has no handler" nil (view-prop view :on-press)))
  ;; Pressed is TOLD, not remembered: the same call with a different flag is a
  ;; different view, which is what keeps the interface a function of the model.
  (check-true "pressed changes the rendering"
              (not (equal (render (layout (button "A" :id :a) 0 0))
                          (render (layout (button "A" :id :a :pressed t) 0 0)))))
  ;; A spacer occupies room and paints nothing.
;; A grown button fills its row and keeps the label centred -- the thing
  ;; intrinsic sizing could not do, and the reason constraints exist.
  (let* ((tree `(row (:gap 0) ,(button "Go" :id :go :grow 1)))
         (placed (layout tree 0 0 (constraints 0 200 0 100)))
         (btn (first (laid-out-children placed)))
         (text (first (laid-out-children btn))))
    (check "a grown button fills the row" 200 (rect-width (laid-out-frame btn)))
    (check-true "and its label is centred in it"
                (let ((slack (- (rect-width (laid-out-frame btn))
                                (rect-width (laid-out-frame text)))))
                  (= (- (rect-x (laid-out-frame text)) (rect-x (laid-out-frame btn)))
                     (floor slack 2)))))
  (check "a spacer takes space" '(10 4) (multiple-value-list (measure (spacer :width 10 :height 4))))
  (check "and emits no drawing" 0 (length (render (layout (spacer :width 10 :height 4) 0 0)))))

;;; ── constraints ───────────────────────────────────────────────────────
(defun test-constraints ()
  (format t "constraints~%")
  ;; The two demands intrinsic sizing cannot express. First: fill what is left.
  (let* ((tree '(row (:gap 0)
                 (box (:width 30 :height 10))
                 (box (:height 10 :grow 1))))
         (placed (layout tree 0 0 (constraints 0 100 0 100)))
         (kids (laid-out-children placed)))
    (check "a grower takes the remaining width" 70
           (rect-width (laid-out-frame (second kids))))
    (check "and starts where the fixed child ended" 30
           (rect-x (laid-out-frame (second kids))))
    (check "the row fills the room it was offered" 100
           (rect-width (laid-out-frame placed))))
  ;; Two growers split in proportion, not equally.
  (let* ((tree '(row (:gap 0)
                 (box (:height 10 :grow 1))
                 (box (:height 10 :grow 3))))
         (kids (laid-out-children (layout tree 0 0 (constraints 0 80 0 80)))))
    (check "growers split by their factor" '(20 60)
           (list (rect-width (laid-out-frame (first kids)))
                 (rect-width (laid-out-frame (second kids))))))
  ;; Unbounded: there is no remaining space to claim, so a grower is intrinsic.
  (let* ((tree '(row () (box (:width 25 :height 10 :grow 1))))
         (placed (layout tree 0 0)))
    (check "a grower without a bound is intrinsic" 25
           (rect-width (laid-out-frame placed))))
  ;; Second demand: centre me in my parent.
  (let* ((tree '(column (:align :center :height 100)
                 (box (:width 10 :height 20))))
         (kid (first (laid-out-children (layout tree 0 0 (constraints 0 100 100 100))))))
    (check "align centres on the main axis" 40 (rect-y (laid-out-frame kid))))
  (let* ((tree '(column (:cross-align :center :width 100)
                 (box (:width 20 :height 10))))
         (kid (first (laid-out-children (layout tree 0 0 (constraints 100 100 0 100))))))
    (check "cross-align centres on the cross axis" 40 (rect-x (laid-out-frame kid))))
  (let* ((tree '(column (:align :end :height 100)
                 (box (:width 10 :height 20))))
         (kid (first (laid-out-children (layout tree 0 0 (constraints 0 100 100 100))))))
    (check "align :end pushes to the far edge" 80 (rect-y (laid-out-frame kid))))
;; A container that knows its own size offers it downward, even when nothing
  ;; above it said anything. This is the root case: a screen-sized column laid
  ;; out under unbounded constraints must still let its children fill.
  (let* ((tree '(column (:width 200 :height 50)
                 (row (:gap 0) (box (:height 10 :grow 1)))))
         (inner (first (laid-out-children (first (laid-out-children (layout tree 0 0)))))))
    (check "explicit size reaches the children" 200
           (rect-width (laid-out-frame inner))))
  ;; Padding still applies, and the grower gets what is inside it.
  (let* ((tree '(row (:padding 10) (box (:height 5 :grow 1))))
         (kid (first (laid-out-children (layout tree 0 0 (constraints 0 100 0 100))))))
    (check "a grower fills inside the padding" 80 (rect-width (laid-out-frame kid)))
    (check "and starts after it" 10 (rect-x (laid-out-frame kid)))))

;;; ── the backend protocol ──────────────────────────────────────────────
(defun test-backend ()
  (format t "backend~%")
  ;; CLOS where it belongs: one long-lived object per application, several real
  ;; implementations of one idea, dispatched once per frame rather than per node.
  (let ((backend (make-software-backend 40 20)))
    (check-true "a software backend is a backend" (typep backend 'backend))
    (check "it reports its size" '(40 20) (multiple-value-list (backend-size backend)))
    (check "and keeps the bitmap metrics" nil (backend-text-metrics backend))
    ;; DRAW-FRAME lays out to the backend's own size, so a grower fills it.
    (let* ((placed (draw-frame backend '(row (:gap 0) (box (:height 5 :grow 1 :fill "#ff0000")))))
           (kid (first (laid-out-children placed))))
      (check "draw-frame constrains to the backend" 40
             (rect-width (laid-out-frame kid)))
      (check "and it actually painted" (rgb 255 0 0)
             (pixel-at (software-backend-surface backend) 20 2)))))

;;; ── extending the framework from outside ──────────────────────────────
;;;
;;; A NEW PRIMITIVE, defined here in the test file rather than in the framework.
;;; Nothing in src/ knows :RULE exists. This is what the generic functions buy:
;;; the tree is still data, and the set of things a tree may contain is open.
;;;
;;; A composite widget needs none of this -- it is a function returning existing
;;; primitives. This is only for something the existing primitives cannot say.

(defmethod measure-kind ((kind (eql :rule)) view constraints)
  (declare (ignore constraints))
  ;; A rule is as wide as it is allowed to be and as thick as it is told.
  (values 0 (view-prop view :thickness 1)))

(defmethod render-kind ((kind (eql :rule)) view frame)
  (list (list :fill-rect (rect-x frame) (rect-y frame)
              (rect-width frame) (rect-height frame)
              (colour (view-prop view :colour "#808080")))))

(defun test-extension ()
  (format t "extension~%")
  (let ((view '(rule (:thickness 2 :colour "#ff0000"))))
    (check "a new primitive measures" '(0 2) (multiple-value-list (measure view)))
    ;; It takes part in constraints like anything else, so :GROW works on it
    ;; without the framework having heard of it.
    (let* ((tree '(row (:gap 0) (rule (:thickness 2 :grow 1))))
           (kid (first (laid-out-children (layout tree 0 0 (constraints 0 50 0 50))))))
      (check "and grows" 50 (rect-width (laid-out-frame kid))))
    ;; And it draws, through the same display list every backend already speaks.
    (let ((ops (render (layout view 0 0 (constraints 10 10 0 10)))))
      (check "it emits one rectangle" 1 (length ops))
      (check "of its own colour" (rgb 255 0 0) (sixth (first ops)))))
  ;; An unknown kind is a clear error, not a silent omission from the frame.
  (check "an unknown primitive is reported" t
         (handler-case (progn (measure '(nonesuch ())) nil)
           (error () t))))

;;; ── composites cost a DEFUN ───────────────────────────────────────────
(defun test-composites ()
  (format t "composites~%")
  ;; A progress bar is two boxes and some arithmetic. No primitive, no backend.
  (let* ((placed (layout (progress 0.25 :width 100 :height 10) 0 0))
         (fill (first (laid-out-children placed))))
    (check "progress fills its fraction" 25 (rect-width (laid-out-frame fill)))
    (check "and the track is the full width" 100 (rect-width (laid-out-frame placed))))
  (check "progress clamps above one" 100
         (rect-width (laid-out-frame (first (laid-out-children
                                             (layout (progress 5 :width 100) 0 0))))))
  (check "and below zero" 0
         (rect-width (laid-out-frame (first (laid-out-children
                                             (layout (progress -3 :width 100) 0 0))))))
  ;; A switch is a knob pushed to one end by a growing spacer: one tree, a flag.
  (let* ((off (layout (switch :id :s :on nil) 0 0))
         (on (layout (switch :id :s :on t) 0 0))
         (knob-x (lambda (placed)
                   (let ((kids (laid-out-children placed)))
                     (rect-x (laid-out-frame
                              (find-if (lambda (k) (view-prop (laid-out-view k) :fill))
                                       kids)))))))
    (check-true "the knob moves when on"
                (> (funcall knob-x on) (funcall knob-x off))))
  ;; A flexible spacer is what expresses "push to the far end".
  (let* ((tree `(row (:width 100) ,(spacer :grow 1) (box (:width 20 :height 5 :fill "#fff"))))
         (box (second (laid-out-children (layout tree 0 0)))))
    (check "a growing spacer pushes to the end" 80 (rect-x (laid-out-frame box)))))

;;; ── rounded corners and clipping ──────────────────────────────────────
(defun test-corners-and-clipping ()
  (format t "corners and clipping~%")
  ;; A rounded rect decomposes to one span per row, inset at the corners.
  (let ((spans (round-rect-spans 0 0 20 20 5)))
    (check "one span per row" 20 (length spans))
    ;; The middle rows are full width; the first is inset on both sides.
    (check "the middle is full width" 20 (third (nth 10 spans)))
    (check-true "the first row is inset" (< (third (first spans)) 20))
    (check-true "and symmetric" (= (third (first spans)) (third (car (last spans)))))
    ;; A radius larger than the box is clamped, not wrapped around.
    (check-true "an oversized radius is clamped"
                (every (lambda (s) (<= 0 (third s) 20)) (round-rect-spans 0 0 20 20 99))))
  ;; A :RADIUS makes the fill a rounded op, and the backends that can only fill
  ;; rectangles still get it, through FLATTEN.
  (let ((ops (render (layout '(box (:width 20 :height 20 :fill "#ff0000" :radius 5)) 0 0))))
    (check "a radius emits a rounded fill" :fill-round-rect (first (first ops)))
    (check-true "which flattens to spans" (> (length (flatten-to-rects ops)) 1)))
  ;; Clipping confines children to the container's frame.
  (let* ((tree '(column (:clip t :width 10 :height 10)
                 (box (:width 100 :height 100 :fill "#00ff00"))))
         (ops (render (layout tree 0 0)))
         (rects (flatten-to-rects ops)))
    (check "clip ops bracket the children" '(:clip-push :clip-pop)
           (list (first (first ops)) (first (car (last ops)))))
    (check "the child is clipped to the container" '(10 10)
           (list (third (first rects)) (fourth (first rects)))))
  ;; And a clipped surface really does not paint outside.
  (let ((surface (make-surface 20 20 +white+)))
    (draw surface (render (layout '(column (:clip t :width 5 :height 5)
                                    (box (:width 20 :height 20 :fill "#000000")))
                                  0 0)))
    (check "inside the clip is painted" +black+ (pixel-at surface 2 2))
    (check "outside it is not" +white+ (pixel-at surface 10 10)))
  ;; Text is clipped too, which is the case a hand-rolled clip usually misses.
  (let ((surface (make-surface 40 20 +white+)))
    (draw surface (render (layout '(column (:clip t :width 6 :height 20)
                                    (label (:text "HELLO" :size 1 :colour "#000000")))
                                  0 0)))
    (check "glyphs outside the clip are dropped" +white+ (pixel-at surface 20 3))))

;;; ── scrolling ─────────────────────────────────────────────────────────
(defun test-scroll ()
  (format t "scroll~%")
  ;; A laid-out container knows how far its children extend, which is the number
  ;; a scroller needs and the frame does not give.
  (let ((placed (layout '(column (:gap 0 :height 20 :scroll t)
                          (box (:width 10 :height 30))
                          (box (:width 10 :height 30)))
                        0 0 (constraints 0 100 0 20))))
    (check "content is what is inside, not the viewport" 60 (laid-out-content placed))
    (check "the frame is the viewport" 20 (rect-height (laid-out-frame placed))))
  ;; :OFFSET-Y moves the children and leaves the container where it is.
  (let* ((tree '(column (:gap 0 :offset-y 12 :height 20 :scroll t)
                 (box (:width 10 :height 30))))
         (placed (layout tree 0 0 (constraints 0 100 0 20))))
    (check "the container does not move" 0 (rect-y (laid-out-frame placed)))
    (check "the children do" -12
           (rect-y (laid-out-frame (first (laid-out-children placed))))))
  ;; SCROLL-BY clamps to what is actually scrollable.
  (let ((placed (layout '(column (:gap 0 :height 20 :scroll t)
                          (box (:width 10 :height 50)))
                        0 0 (constraints 0 100 0 20))))
    (check "scrolls within range" 10 (scroll-by placed 0 10))
    (check "stops at the end" 30 (scroll-by placed 0 999))
    (check "and does not go negative" 0 (scroll-by placed 5 -99)))
  ;; Content shorter than the viewport cannot scroll at all.
  (let ((placed (layout '(column (:gap 0 :height 50 :scroll t)
                          (box (:width 10 :height 10)))
                        0 0 (constraints 0 100 0 50))))
    (check "a short scroller does not move" 0 (scroll-by placed 0 100)))
  ;; The SCROLL widget is a clipping, offset column and nothing more.
  (let ((view (scroll (list '(box (:width 10 :height 99))) :id :s :offset 7 :height 20)))
    (check-true "scroll clips" (view-prop view :clip))
    (check-true "and measures its children unbounded" (view-prop view :scroll))
    (check "and carries its offset" 7 (view-prop view :offset-y))
    ;; Its children really are clipped away when off-screen.
    (let ((surface (make-surface 20 20 +white+)))
      (draw surface (render (layout (scroll (list '(box (:width 20 :height 20 :fill "#000000")))
                                            :id :s :offset 20 :height 20)
                                    0 0 (constraints 0 20 0 20))))
      (check "a fully scrolled child leaves nothing" +white+ (pixel-at surface 10 10)))))

;;; ── the frame clock ───────────────────────────────────────────────────
(defun test-clock ()
  (format t "clock~%")
  (let ((*frame-delta* 1/60) (*animating* nil))
    ;; APPROACH moves toward the target and declares itself unsettled.
    (let ((next (approach 0.0 1.0)))
      (check-true "approach moves toward the target" (< 0 next 1))
      (check-true "and asks for another frame" *animating*))
    ;; Within epsilon it SNAPS and stops asking, which is what ends an
    ;; animation -- one that never quite arrives keeps the screen dirty forever.
    (setf *animating* nil)
    (check "approach snaps at the end" 1.0 (approach 0.9999 1.0))
    (check "and stops asking" nil *animating*)
    ;; Framerate independence: a longer frame covers more ground.
    (let ((slow (let ((*frame-delta* 1/10)) (approach 0.0 1.0)))
          (fast (let ((*frame-delta* 1/120)) (approach 0.0 1.0))))
      (check-true "a longer frame moves further" (> slow fast))))
  (check "ease is bounded below" 0 (ease -5))
  (check "and above" 1 (ease 5))
  (check "and symmetric at the middle" 1/2 (ease 1/2))
  ;; Colour interpolation, which is what makes a control move as one thing.
  (check "mix at zero is the first colour" (rgb 0 0 0) (mix-colours +black+ +white+ 0))
  (check "mix at one is the second" (rgb 255 255 255) (mix-colours +black+ +white+ 1))
  (check "and halfway is halfway" 128 (colour-red (mix-colours +black+ +white+ 1/2)))
  ;; A switch at a fraction really places its knob partway.
  (let ((half (layout (switch :id :s :position 1/2) 0 0))
        (off (layout (switch :id :s :position 0) 0 0))
        (on (layout (switch :id :s :position 1) 0 0)))
    (flet ((knob-x (placed)
             (rect-x (laid-out-frame (second (laid-out-children placed))))))
      (check-true "a half-open switch is between its ends"
                  (< (knob-x off) (knob-x half) (knob-x on))))))

;;; ── virtualised lists ─────────────────────────────────────────────────
(defun test-virtual-list ()
  (format t "virtual list~%")
  ;; The window is what is on screen, plus overscan either side.
  (multiple-value-bind (first last) (visible-range 0 100 10 1000 :overscan 0)
    (check "from the top, the first screenful" '(0 10) (list first last)))
  (multiple-value-bind (first last) (visible-range 500 100 10 1000 :overscan 0)
    (check "scrolled, the window moves" '(50 60) (list first last)))
  (multiple-value-bind (first last) (visible-range 0 100 10 1000 :overscan 2)
    (check "overscan cannot go below zero" 0 first)
    (check "and extends past the screen" 12 last))
  (multiple-value-bind (first last) (visible-range 9990 100 10 1000)
    (declare (ignore first))
    (check "and cannot run past the end" 1000 last))
  ;; The point of all of it: a huge list builds only a handful of rows.
  (let ((built '()))
    (let ((view (virtual-list 100000 (lambda (i) (push i built)
                                       `(box (:width 10 :height 40 :fill "#ff0000")))
                              :id :l :offset 0 :viewport 200 :item-size 40)))
      (check-true "a 100000-row list builds a handful" (< (length built) 20))
      (check-true "and they are the ones on screen" (every (lambda (i) (< i 20)) built))
      ;; Content height stays honest, so scrolling clamps against the real extent.
      (let ((placed (layout view 0 0 (constraints 0 100 0 200))))
        (check "content is the whole list, not the built part" (* 100000 40)
               (laid-out-content placed))
        (check "so it scrolls to the very end" (- (* 100000 40) 200)
               (scroll-by placed 0 99999999)))))
  ;; Scrolling builds a different window.
  (let ((built '()))
    (virtual-list 1000 (lambda (i) (push i built) `(box (:width 10 :height 40)))
                  :id :l :offset 4000 :viewport 200 :item-size 40)
    (check-true "a scrolled list builds the scrolled rows"
                (and (every (lambda (i) (< 90 i 115)) built) built))))

;;; ── images ────────────────────────────────────────────────────────────
(defun test-image ()
  (format t "image~%")
  (let ((source (make-surface 2 2 (rgb 255 0 0))))
    (setf (pixel-at source 1 1) (rgb 0 0 255))
    ;; An image measures to its own pixels unless told otherwise.
    (check "an image is its own size" '(2 2)
           (multiple-value-list (measure (image source))))
    (check "unless scaled" '(20 20)
           (multiple-value-list (measure (image source :width 20 :height 20))))
    ;; It reaches the display list as one operation, not as rectangles.
    (let ((ops (render (layout (image source) 0 0))))
      (check "it emits one image op" :image (first (first ops)))
      ;; And FLATTEN refuses rather than silently dropping it, because a
      ;; rectangle-only backend genuinely cannot draw one.
      (check "flatten refuses an image" t
             (handler-case (progn (flatten-to-rects ops) nil) (error () t))))
    ;; Scaling is nearest-neighbour: the destination asks which source pixel it
    ;; lands on, so a 2x2 scaled to 4x4 puts each source pixel in a quadrant.
    (let ((target (make-surface 4 4 +white+)))
      (draw target (render (layout (image source :width 4 :height 4) 0 0)))
      (check "the scaled image fills its box" (rgb 255 0 0) (pixel-at target 0 0))
      (check "and keeps its own pixels apart" (rgb 0 0 255) (pixel-at target 3 3)))
    ;; Images clip like everything else.
    (let ((target (make-surface 8 8 +white+)))
      (draw target (render (layout `(column (:clip t :width 2 :height 2)
                                      ,(image source :width 8 :height 8))
                                   0 0 (constraints 0 8 0 8))))
      (check "an image is clipped" +white+ (pixel-at target 5 5))
      (check "inside the clip it draws" (rgb 255 0 0) (pixel-at target 0 0)))))

(defun test-utf8 ()
  ;; Java's modified UTF-8, which text typed on a phone exercises the moment
  ;; anyone reaches for an emoji.
  (flet ((bytes (text) (coerce (%modified-utf8 text) 'list))
         (round-trip (text)
           (let* ((encoded (%modified-utf8 text))
                  (buffer (torcl-ffi:foreign-alloc (1+ (length encoded)))))
             (unwind-protect
                  (progn (loop for byte across encoded
                               for index from 0
                               do (torcl-ffi:mem-set byte buffer :uchar index))
                         (torcl-ffi:mem-set 0 buffer :uchar (length encoded))
                         (decode-modified-utf8 buffer))
               (torcl-ffi:foreign-free buffer)))))
    (check "ASCII is one byte each" '(104 105) (bytes "hi"))
    (check "Latin-1 is two" '(#xc3 #xa9) (bytes (string (code-char #xe9))))
    (check "the basic plane is three" '(#xe2 #x82 #xac) (bytes (string (code-char #x20ac))))
    ;; U+1F602: four bytes in real UTF-8, six here, because Java writes the
    ;; surrogate PAIR rather than the code point.
    (check "above it, a surrogate pair of three bytes each"
           '(#xed #xa0 #xbd #xed #xb8 #x82) (bytes (string (code-char #x1f602))))
    (check "and NUL is never a zero byte" '(#xc0 #x80) (bytes (string (code-char 0))))
    (check "ASCII survives the round trip" "hello" (round-trip "hello"))
    (check "and so does an emoji, as ONE character"
           1 (length (round-trip (string (code-char #x1f602)))))
    (check "which is the character it started as"
           #x1f602 (char-code (char (round-trip (string (code-char #x1f602))) 0)))
    (check "mixed text keeps its length"
           5 (length (round-trip (format nil "a~Ab~Ac" (code-char #x1f602) (code-char #x20ac)))))))

(defun box-frame (node)
  "A laid-out node's frame as (X Y WIDTH HEIGHT). EQUAL compares structs by
identity, so a test that wants to compare two rectangles must compare numbers."
  (let ((f (laid-out-frame node)))
    (list (rect-x f) (rect-y f) (rect-width f) (rect-height f))))

(defun test-stacking ()
  (format t "stacking~%")
  ;; :BOX stacks its children on the z axis -- the one arrangement ROW and
  ;; COLUMN cannot express between them.
  (let ((placed (layout '(box (:width 20 :height 10 :fill "#f00")) 0 0)))
    (check "a childless box is still a plain rectangle"
           '(0 0 20 10) (box-frame placed))
    (check "and has no children to place" 0 (length (laid-out-children placed))))
  (let ((placed (layout '(box ()
                          (box (:width 10 :height 4))
                          (box (:width 6 :height 8)))
                        0 0)))
    (check "a box is as large as its largest child, per axis"
           '(0 0 10 8) (box-frame placed))
    (check "both children are placed" 2 (length (laid-out-children placed)))
    (check "and they overlap, at the same origin"
           '((0 0 10 4) (0 0 6 8))
           (mapcar #'box-frame (laid-out-children placed))))
  (let ((placed (layout '(box (:padding 3)
                          (box (:width 10 :height 4)))
                        0 0)))
    (check "padding grows the box" '(0 0 16 10) (box-frame placed))
    (check "and insets the child"
           '(3 3 10 4) (box-frame (first (laid-out-children placed)))))
  ;; :ALIGN is horizontal and :CROSS-ALIGN vertical, as in a row: a stack has no
  ;; main axis to tell them apart.
  (let ((placed (layout '(box (:width 20 :height 10 :align :center :cross-align :center)
                          (box (:width 4 :height 2)))
                        0 0)))
    (check "a centred child sits in the middle of the room"
           '(8 4 4 2) (box-frame (first (laid-out-children placed)))))
  (let ((placed (layout '(box (:width 20 :height 10 :align :end :cross-align :end)
                          (box (:width 4 :height 2)))
                        0 0)))
    (check "and :END puts it at the far corner"
           '(16 8 4 2) (box-frame (first (laid-out-children placed)))))
  ;; A box with a size of its own hands that size DOWN as a maximum, so a child
  ;; asking for more is clamped rather than overflowing -- the constraints
  ;; protocol doing its job, and the reason alignment slack is never negative.
  (let ((placed (layout '(box (:width 4 :height 4 :align :center)
                          (box (:width 10 :height 10)))
                        0 0)))
    (check "a child cannot outgrow the box it is stacked in"
           '(0 0 4 4) (box-frame (first (laid-out-children placed)))))
  ;; Painted back to front, so a later child covers an earlier one -- which is
  ;; the entire point of stacking.
  (let ((ops (render (layout '(box (:fill "#001122")
                               (box (:width 4 :height 4 :fill "#ff0000"))
                               (box (:width 2 :height 2 :fill "#00ff00")))
                             0 0))))
    (check "the box paints first, then its children in order"
           (list (colour "#001122") (colour "#ff0000") (colour "#00ff00"))
           (mapcar (lambda (op) (car (last op))) ops)))
  (let* ((placed (layout '(box ()
                           (box (:width 8 :height 8 :id :under))
                           (box (:width 8 :height 8 :id :over)))
                         0 0))
         (hit (hit-test placed 4 4)))
    (check "and a touch lands on the topmost of them"
           :over (node-prop hit :id))))

(defun test-text-field ()
  (format t "text field~%")
  ;; A stub platform editor: enough to drive focus and the pump with no phone.
  (let* ((editor "") (shown nil) (log '())
         (*text-input* (list :show (lambda () (setf shown t) (push :show log))
                             :hide (lambda () (setf shown nil) (push :hide log))
                             :read (lambda () editor)
                             :write (lambda (text) (setf editor text) (push :write log))))
         (*text-focus* nil)
         (changes '()))
    (flet ((field (value) (text-field value :id :name :placeholder "Name"
                                            :on-change (lambda (text) (push text changes))))
           ;; (box () (row () (label ...) [caret])) -- the row is the box's only
           ;; child, and the label is the row's first.
           (line (field) (first (view-children field))))
      (check "an empty field shows its placeholder"
             "Name" (view-prop (first (view-children (line (field "")))) :text))
      (check "a filled one shows its text"
             "Ada" (view-prop (first (view-children (line (field "Ada")))) :text))
      (check "and unfocused it has no caret"
             1 (length (view-children (line (field "")))))
      ;; Tapping it binds the keyboard: the editor is SEEDED, then raised.
      (dispatch (layout (field "Ada") 0 0) 4 4 :on-press)
      (check "tapping focuses the field" :name (text-focus-id))
      (check "the editor is seeded before it is shown" '(:show :write) log)
      (check "seeded with the field's own value" "Ada" editor)
      (check-true "and the keyboard is up" shown)
      (check "focused, it grows a caret"
             2 (length (view-children (line (field "Ada")))))
      ;; The input method is the truth; PUMP is what turns its edits into ours.
      (check "an unchanged editor fires nothing" nil (pump-text-input))
      (setf editor "Ada L")
      (check "a changed one reports the new text" "Ada L" (pump-text-input))
      (check "and calls ON-CHANGE with it" '("Ada L") changes)
      (check "reading it twice does not fire twice" nil (pump-text-input))
      (blur-text-field)
      (check "blurring unbinds the keyboard" nil (text-focus-id))
      (check-true "and puts it away" (not shown))
      (setf editor "typed after blur")
      (check "a blurred field ignores the editor" nil (pump-text-input)))))

(defun test-elevation ()
  (format t "elevation~%")
  (let ((ops (render (layout '(box (:width 10 :height 10 :fill "#ffffff" :elevation 2)) 2 2))))
    (check "a raised surface casts before it paints"
           '(:shadow :fill-rect) (mapcar #'first ops))
    (destructuring-bind (x y w h radius blur dy colour) (rest (first ops))
      (declare (ignore colour))
      (check "the shadow is cast by the surface's own rectangle" '(2 2 10 10) (list x y w h))
      (check "square, because the surface is" 0 radius)
      ;; Blur and offset come from the elevation, in one place: twice for the
      ;; blur, once for the drop, which is what reads as lit from above.
      (check "blur is twice the elevation" 4 blur)
      (check "and the drop is the elevation" 2 dy)))
  (check "an unraised surface casts nothing"
         '(:fill-rect)
         (mapcar #'first (render (layout '(box (:width 10 :height 10 :fill "#fff")) 0 0))))
  ;; A shadow needs something to cast it.
  (check "and neither does a raised one with no fill"
         '()
         (mapcar #'first (render (layout '(box (:width 10 :height 10 :elevation 4)) 0 0))))
  ;; Every backend that fills rectangles gets a shadow, GLES included.
  (let ((rects (flatten-to-rects (render (layout '(box (:width 8 :height 8
                                                        :fill "#ffffff" :elevation 2))
                                                 4 4)))))
    (check-true "a shadow reduces to plain rectangles" (> (length rects) 1))
    (check-true "which reach above and left of the surface"
                (some (lambda (r) (< (first r) 4)) rects)))
  ;; And it actually darkens pixels, below the surface rather than above it.
  (let ((target (make-surface 24 24 +white+)))
    (draw target (render (layout '(box (:width 8 :height 8 :fill "#ffffff" :elevation 3))
                                 8 8)))
    (check-true "the shadow darkens below the surface"
                (< (colour-red (pixel-at target 12 18)) 255))
    (check-true "and not above it"
                (= (colour-red (pixel-at target 12 2)) 255))
    (check "while the surface itself stays its own colour"
           +white+ (pixel-at target 12 12)))
  ;; CARD is the payoff: a composite, with no new primitive under it.
  (let ((ops (render (layout (card (list '(box (:width 4 :height 4 :fill "#f00")))) 0 0))))
    (check "a card is raised" :shadow (first (first ops)))))

(defun test-stretch ()
  (format t "stretch~%")
  ;; A column is as wide as its widest child. A STRETCHED child is as wide as
  ;; the column, which is the opposite direction of information and is why it
  ;; needs the constraints protocol rather than a second pass.
  (let* ((placed (layout '(column (:padding 2)
                           (box (:width 20 :height 4))
                           (box (:height 2 :stretch t)))
                         0 0 (constraints 0 40 0 40)))
         (kids (mapcar #'box-frame (laid-out-children placed))))
    (check "an unstretched child keeps its own width" '(2 2 20 4) (first kids))
    (check "a stretched one fills the content box" '(2 6 36 2) (second kids))
    (check "and the column is still sized by its content" '(0 0 40 10) (box-frame placed)))
  ;; A container may say it for all of them at once.
  (let ((kids (mapcar #'box-frame
                      (laid-out-children
                       (layout '(column (:cross-align :stretch)
                                 (box (:width 5 :height 3))
                                 (box (:width 5 :height 3)))
                               0 0 (constraints 0 30 0 30))))))
    (check "cross-align :stretch stretches every child"
           '((0 0 30 3) (0 3 30 3)) kids))
  ;; In a row the cross axis is height, and the rule is written once for both.
  (let ((kids (mapcar #'box-frame
                      (laid-out-children
                       (layout '(row (:cross-align :stretch)
                                 (box (:width 4 :height 2)))
                               0 0 (constraints 0 20 0 12))))))
    (check "in a row it is the height that fills" '((0 0 4 12)) kids))
  ;; Nothing to fill is not the same as fill nothing.
  (let ((kids (mapcar #'box-frame
                      (laid-out-children
                       (layout '(column () (box (:width 7 :height 3 :stretch t))) 0 0)))))
    (check "with no room to fill, a stretched child keeps its own size"
           '((0 0 7 3)) kids))
  (let ((kids (mapcar #'box-frame
                      (laid-out-children
                       (layout `(column (:padding 4) ,(divider))
                               0 0 (constraints 0 50 0 50))))))
    (check "a divider spans its container, minus its padding"
           '((4 4 42 1)) kids)))

(defun test-paths ()
  (format t "paths~%")
  ;; A filled square, stated as a path, to check the scanline fill itself before
  ;; anything shaped is asked of it.
  (let ((target (make-surface 16 16 +white+)))
    (draw target (render (layout '(path (:size 16 :view-box 16 :colour "#ff0000"
                                         :commands ((:move 4 4) (:line 12 4)
                                                    (:line 12 12) (:line 4 12) (:close))))
                                 0 0)))
    (check "a square path fills inside" (rgb 255 0 0) (pixel-at target 8 8))
    (check "and not outside" +white+ (pixel-at target 2 2))
    (check "the edge is where it was asked for" (rgb 255 0 0) (pixel-at target 4 4))
    (check "and stops" +white+ (pixel-at target 12 8)))
  ;; The nonzero rule: a subpath wound the other way cuts a hole. This is what
  ;; makes a ring a ring rather than a disc, and every icon set relies on it.
  (let ((target (make-surface 24 24 +white+)))
    (draw target (render (layout (icon :ring :size 24 :colour "#0000ff") 0 0)))
    (check "a ring is solid on its rim" (rgb 0 0 255) (pixel-at target 12 4))
    (check "and hollow in its middle" +white+ (pixel-at target 12 12)))
  (let ((target (make-surface 24 24 +white+)))
    (draw target (render (layout (icon :circle :size 24 :colour "#0000ff") 0 0)))
    (check "while a circle is solid all through" (rgb 0 0 255) (pixel-at target 12 12)))
  ;; A path scales into whatever box it is given: the drawing is described once,
  ;; in a 24-unit square, and :SIZE decides how big that square comes out.
  (let ((placed (layout (icon :plus :size 48) 0 0)))
    (check "an icon is square at its size" '(0 0 48 48) (box-frame placed)))
  (let ((target (make-surface 48 48 +white+)))
    (draw target (render (layout (icon :plus :size 48 :colour "#008000") 0 0)))
    (check "a scaled plus still crosses its centre" (rgb 0 128 0) (pixel-at target 24 24))
    (check "and still misses its corner" +white+ (pixel-at target 4 4)))
  ;; Every backend that fills rectangles gets paths, GLES included.
  (let ((rects (flatten-to-rects (render (layout (icon :plus :size 24) 0 0)))))
    (check-true "a path reduces to plain rectangles" (> (length rects) 4)))
  ;; A quadratic is NOT a cubic with its control point written twice, and this
  ;; is the number that says so: halfway along (0,0)->(10,10)->(20,0) the curve
  ;; is at (10, 5), under the control point at half its height. The tempting
  ;; wrong formula puts it at 7.5 -- close enough to look right on screen and
  ;; not the curve that was asked for.
  (check "a quadratic reaches half its control point's height"
         '(10 . 5)
         (let ((points (first (flatten-path '((:move 0 0) (:quad 10 10 20 0) (:close))))))
           (let ((middle (nth (floor +curve-steps+ 2) points)))
             (cons (round (car middle)) (round (cdr middle))))))
  (check "an unknown icon says which ones there are"
         t (handler-case (progn (icon :nonesuch) nil) (error () t))))

(defun test-horizontal-list ()
  (format t "horizontal list~%")
  ;; A carousel: the same virtualisation, turned ninety degrees.
  (let* ((built '())
         (view (virtual-list 100000 (lambda (i) (push i built) `(box (:width 40 :height 30)))
                             :axis :horizontal :id :c :offset 0
                             :viewport 200 :item-size 40 :height 30)))
    (check "a horizontal list is a row" :row (view-kind view))
    (check "it offsets along x" 0 (view-prop view :offset-x))
    (check "and not along y" nil (view-prop view :offset-y))
    ;; 200 wide / 40 each = 5 on screen, plus 2 overscan.
    (check "only the items on screen are built, plus overscan"
           '(0 1 2 3 4 5 6) (sort (copy-list built) #'<))
    (let ((kids (mapcar #'box-frame (laid-out-children (layout view 0 0)))))
      (check "the leading gap has no width at offset zero" 0 (third (first kids)))
      (check "and the items run left to right"
             '(0 40) (list (first (second kids)) (first (third kids))))))
  ;; Scrolled along, it builds the items that are actually there.
  (let ((built '()))
    (virtual-list 1000 (lambda (i) (push i built) `(box (:width 40 :height 30)))
                  :axis :horizontal :id :c :offset 4000 :viewport 200 :item-size 40 :height 30)
    (check "scrolled, it builds the items at that offset"
           '(98 99 100 101 102 103 104 105 106) (sort (copy-list built) #'<)))
  ;; SCROLL-BY clamped against the frame's HEIGHT whatever the axis, which for a
  ;; horizontal scroller is the wrong number entirely: here it would have allowed
  ;; 480 instead of 400, and the carousel would have run off its own end.
  (let ((node (layout (scroll (list '(box (:width 500 :height 20)))
                              :axis :horizontal :width 100 :height 20)
                      0 0)))
    (check "a horizontal scroller clamps against its width" 400 (scroll-by node 0 1000))
    (check "and still cannot scroll before its start" 0 (scroll-by node 0 -1000)))
  (let ((node (layout (scroll (list '(box (:width 20 :height 500)))
                              :width 20 :height 100)
                      0 0)))
    (check "a vertical one still clamps against its height" 400 (scroll-by node 0 1000))))

(defun test-memo-across-frames ()
  (format t "memo across frames~%")
  ;; A view tree is rebuilt, never mutated, so the same LIST under the same
  ;; constraints has the same size next frame as it had this one. That is what
  ;; lets an application hand back an unchanged subtree and have it cost nothing.
  (let ((tree `(column (:gap 2 :width 100 :height 200)
                 ,@(loop for i from 0 below 8
                         collect `(label (:text "x" :size 2))))))
    (forget-layout)
    (setf *measure-misses* 0)
    (layout tree 0 0 (constraints 0 100 0 200))
    (let ((first-pass *measure-misses*))
      (check-true "the first pass measures something" (plusp first-pass))
      (setf *measure-misses* 0)
      (layout tree 0 0 (constraints 0 100 0 200))
      (check "handing back the same tree measures nothing at all" 0 *measure-misses*)
      ;; A tree that is EQUAL but not EQ is a different tree as far as this is
      ;; concerned, which is the whole point: identity is the cheap question.
      (setf *measure-misses* 0)
      (layout (copy-tree tree) 0 0 (constraints 0 100 0 200))
      (check "an identical copy is measured again" first-pass *measure-misses*)))
  ;; Two generations, so a node built once does not live for ever.
  (let ((kept `(label (:text "kept" :size 2))))
    (forget-layout)
    (layout `(column () ,kept) 0 0 (constraints 0 100 0 200))
    (dotimes (i 3)
      (layout `(column () ,kept ,`(label (:text ,(format nil "gone~D" i) :size 2)))
              0 0 (constraints 0 100 0 200)))
    (setf *measure-misses* 0)
    (layout `(column () ,kept) 0 0 (constraints 0 100 0 200))
    ;; The column is new each time and must be measured; KEPT must not be.
    (check-true "a node reused every frame survives" (< *measure-misses* 3)))
  ;; A new backend means a new font, so every remembered size is wrong.
  (let ((tree `(label (:text "x" :size 2))))
    (forget-layout)
    (layout tree 0 0)
    (use-backend (make-software-backend 10 10))
    (setf *measure-misses* 0)
    (layout tree 0 0)
    (check-true "installing a backend forgets what was measured with the old font"
                (plusp *measure-misses*))))

(defun test-damage ()
  (format t "damage~%")
  (flet ((box (d) (and d (list (rect-x d) (rect-y d) (rect-width d) (rect-height d)))))
    (let ((a '((:fill-rect 0 0 100 100 1) (:fill-rect 10 10 20 20 2))))
      (check "an identical frame damages nothing" nil (box (display-damage a a)))
      ;; A node rebuilt every frame is a different LIST and paints the identical
      ;; rectangle. Comparing NODES calls that changed; comparing OPERATIONS does
      ;; not, and on the device that is the difference between a damage region of
      ;; 100% of the screen and one of 18%.
      (check "and so does an equal-but-fresh copy" nil (box (display-damage (copy-tree a) a)))
      (check "a moved operation damages where it went"
             '(10 40 20 20)
             (box (display-damage '((:fill-rect 0 0 100 100 1) (:fill-rect 10 40 20 20 2))
                                  '((:fill-rect 0 0 100 100 1)))))
      (check "an operation that vanished damages where it was"
             '(10 10 20 20)
             (box (display-damage '((:fill-rect 0 0 100 100 1)) a)))
      (check "one that moved damages both ends"
             '(10 10 20 50)
             (box (display-damage '((:fill-rect 0 0 100 100 1) (:fill-rect 10 40 20 20 2)) a)))
      (check "and damage is clamped to what is on screen"
             '(10 10 5 5)
             (box (display-damage '((:fill-rect 0 0 100 100 1)) a (rect 0 0 15 15))))))
  ;; A shadow is blurred and dropped, so it dirties more than the box casting it.
  (let ((d (op-bounds '(:shadow 20 20 10 10 0 4 2 0))))
    (check "a shadow reaches past its own rectangle"
           '(16 16 18 20) (list (rect-x d) (rect-y d) (rect-width d) (rect-height d))))
  (check "a clip pop paints nothing and bounds nothing" nil (op-bounds '(:clip-pop))))

(defun test-damaged-drawing ()
  (format t "damaged drawing~%")
  (let* ((backend (make-software-backend 20 20))
         (surface (software-backend-surface backend))
         (red '((:fill-rect 0 0 20 20 #xff0000ff)))
         (blue '((:fill-rect 0 0 20 20 #x0000ffff))))
    (present backend red nil)
    (check "a full present paints everything" (rgb 255 0 0) (pixel-at surface 1 1))
    ;; The same full-screen blue, but only a corner of it is allowed through.
    (present backend blue (rect 5 5 5 5))
    (check "inside the damage the new frame is drawn" (rgb 0 0 255) (pixel-at surface 7 7))
    (check "outside it the last frame is still there" (rgb 255 0 0) (pixel-at surface 1 1))
    (check "right up to the edge" (rgb 255 0 0) (pixel-at surface 4 4))
    (check "and from the first pixel inside it" (rgb 0 0 255) (pixel-at surface 5 5))
    ;; NIL damage means everything, which is what a first frame and a resize need.
    (present backend blue nil)
    (check "no damage means draw it all" (rgb 0 0 255) (pixel-at surface 1 1)))
  ;; And the thing that makes it safe: damage bounds every pixel that could
  ;; differ, so drawing only there is not an approximation.
  (let* ((a '((:fill-rect 0 0 20 20 #xff0000ff) (:fill-rect 2 2 4 4 #x00ff00ff)))
         (b '((:fill-rect 0 0 20 20 #xff0000ff) (:fill-rect 12 12 4 4 #x00ff00ff)))
         (damage (display-damage b a (rect 0 0 20 20)))
         (whole (make-software-backend 20 20))
         (partial (make-software-backend 20 20)))
    (present whole a nil) (present whole b nil)
    (present partial a nil) (present partial b damage)
    (let ((same t))
      (dotimes (y 20)
        (dotimes (x 20)
          (unless (equal (pixel-at (software-backend-surface whole) x y)
                         (pixel-at (software-backend-surface partial) x y))
            (setf same nil))))
      (check-true "a damaged redraw is pixel-identical to a full one" same))))

(defun test-design-system ()
  (format t "design system~%")
  (check "a size has a name" 3 (type-size :title))
  (check "and a number is still a size" 7 (type-size 7))
  (check "a space has a name" 12 (space :medium))
  (check "and a number is still a space" 5 (space 5))
  (check "an unknown size lists the ones there are"
         t (handler-case (progn (type-size :enormous) nil) (error () t)))
  (check "an unknown scheme does too"
         t (handler-case (progn (use-scheme :sepia) nil) (error () t)))
  ;; THE point of roles. A button's label takes the ON-colour of the surface it
  ;; sits on, in whichever scheme is installed. It used to say :INK -- white --
  ;; which is legible on the dark scheme's accent and invisible on the light
  ;; scheme's, and no test could have caught that because there was one scheme.
  (flet ((label-colour (view)
           (view-prop (first (view-children view)) :colour))
         (background (view) (view-prop view :background)))
    (let ((*theme* *theme*))
      (use-scheme :dark)
      (let ((b (button "Save" :id :s)))
        (check "on the dark scheme a button is primary" (theme :primary) (background b))
        (check "and its label is the colour that goes on primary"
               (theme :on-primary) (label-colour b)))
      (use-scheme :light)
      (let ((b (button "Save" :id :s)))
        (check "on the light scheme the button follows" (theme :primary) (background b))
        (check "and so does its label" (theme :on-primary) (label-colour b)))
      (check "the two schemes really differ"
             nil (equal (getf *schemes* :dark) (getf *schemes* :light)))
      ;; A disabled button pairs too, rather than reusing the enabled ink.
      (let ((b (button "Save" :id :s :disabled t)))
        (check "a disabled button is the disabled surface" (theme :disabled) (background b))
        (check "with the colour that goes on it" (theme :on-disabled) (label-colour b)))
      (use-scheme :dark)
      (check "switching schemes keeps the radius" 10 (theme-value :radius))
      (check "and an override survives it"
             255 (progn (use-scheme :dark :primary "#ff0000")
                        (colour-red (theme :primary)))))))

(defun test-screen-composites ()
  (format t "screen composites~%")
  ;; A list row: the TEXT is what grows, so the icon and the control keep their
  ;; own sizes and the headline takes what is left.
  (let* ((row (list-item "Wi-Fi" :supporting "Connected"
                         :leading (icon :check :size 16)
                         :trailing (icon :chevron-right :size 16)))
         (kids (view-children row)))
    (check "leading, text and trailing, in that order"
           '(:path :column :path) (mapcar #'view-kind kids))
    (check "the text column is the one that grows" 1 (view-prop (second kids) :grow))
    (check "headline and supporting" 2 (length (view-children (second kids)))))
  (check "a row with no supporting text has one line"
         1 (length (view-children (second (view-children (list-item "Wi-Fi"
                                                                   :leading (icon :check)))))))
  (check "and with nothing around it, the text is the only child"
         1 (length (view-children (list-item "Wi-Fi"))))
  ;; An app bar sends its actions to the far end with a growing spacer.
  (let ((bar (app-bar "Settings" :actions (list (icon :menu)))))
    (check "title, spacer, action" '(:label :box :path)
           (mapcar #'view-kind (view-children bar)))
    (check "and the spacer is what pushes them apart"
           1 (view-prop (second (view-children bar)) :grow)))
  ;; A scaffold's middle fills whatever the bars leave.
  (let* ((screen (scaffold :top (app-bar "T") :content (list (text "body"))
                           :bottom (text "b") :width 100 :height 200))
         (placed (layout screen 0 0 (constraints 0 100 0 200)))
         (kids (mapcar #'box-frame (laid-out-children placed))))
    (check "top, content, bottom" 3 (length kids))
    (check "the bars keep their own heights and the content takes the rest"
           200 (+ (fourth (first kids)) (fourth (second kids)) (fourth (third kids))))
    (check-true "and the content is the tall one"
                (> (fourth (second kids)) (fourth (first kids)))))
  ;; A chip pairs its colours like everything else.
  (let ((on (chip "Filter" :selected t)) (off (chip "Filter")))
    (check "a selected chip is primary" (theme :primary) (view-prop on :background))
    (check "with the colour that goes on it"
           (theme :on-primary) (view-prop (first (view-children on)) :colour))
    (check "an unselected one is the variant surface"
           (theme :surface-variant) (view-prop off :background))
    (check "with its on-colour too"
           (theme :on-surface-variant) (view-prop (first (view-children off)) :colour))))

(defparameter +search-svg+
  "<svg xmlns=\"http://www.w3.org/2000/svg\" height=\"24\" viewBox=\"0 0 24 24\" width=\"24\"><path d=\"M0 0h24v24H0z\" fill=\"none\"/><path d=\"M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z\"/></svg>"
  "Material's search icon, verbatim, including the bounding box it opens with.")

(defun test-svg ()
  (format t "svg~%")
  ;; SVG packs numbers together and a sign or a second dot starts a new one.
  (check "numbers run together" '(-0.79 0.5) (bliss::%svg-tokens "-.79.5"))
  (check "and commands separate from them" '(#\M 1 2 #\z) (bliss::%svg-tokens "M1 2z"))
  (check "an absolute move and line"
         '((:move 1 2) (:line 3 4)) (parse-svg-path "M1 2L3 4"))
  ;; Pairs after an M are LINES, not more moves. Getting this wrong makes every
  ;; polygon into a row of disconnected points.
  (check "further pairs after a move are lines"
         '((:move 1 2) (:line 3 4) (:line 5 6)) (parse-svg-path "M1 2 3 4 5 6"))
  (check "relative commands become absolute"
         '((:move 1 1) (:line 3 1) (:line 3 4)) (parse-svg-path "m1 1h2v3"))
  (check "close returns to where the subpath started"
         '((:move 1 1) (:line 5 1) (:close) (:line 1 3))
         (parse-svg-path "M1 1H5zv2"))
  (check "a cubic keeps all three points"
         '((:move 0 0) (:cubic 1 2 3 4 5 6)) (parse-svg-path "M0 0C1 2 3 4 5 6"))
  ;; S mirrors the previous control point through the point they share, which is
  ;; what makes a smooth join smooth.
  (check "a smooth cubic reflects the last control"
         '((:move 0 0) (:cubic 1 1 2 2 4 4) (:cubic 6 6 7 7 8 8))
         (parse-svg-path "M0 0C1 1 2 2 4 4S7 7 8 8"))
  (check "with no curve before it, there is nothing to mirror"
         '((:move 4 4) (:cubic 4 4 7 7 8 8)) (parse-svg-path "M4 4S7 7 8 8"))
  (check "arcs say so rather than being silently wrong"
         t (handler-case (progn (parse-svg-path "M0 0A1 1 0 0 1 2 2") nil) (error () t)))
  ;; The trap: every Material icon opens with a full-size box that must not be
  ;; drawn, or the icon becomes a solid square.
  (let ((painted (svg-path-strings +search-svg+)))
    (check "the fill=none bounding box is skipped" 1 (length painted))
    (check-true "and what is left is the icon"
                (> (length (first painted)) 100)))
  ;; And the real thing, end to end.
  (let ((commands (parse-svg-path (first (svg-path-strings +search-svg+)))))
    (check-true "the search icon parses" (> (length commands) 10))
    (check "it starts where the file says" '(:move 15.5 14) (first commands))
    (check "it is closed" :close (first (car (last commands))))
    ;; Two subpaths -- the glass and the hole in it -- which is what the nonzero
    ;; winding rule is for, and is why our :RING already works.
    (check "and it has two subpaths, the glass and its hole"
           2 (count :close commands :key #'first))))

(defun test-borders ()
  (format t "borders~%")
  ;; An outline is the shape minus the shape inset by its thickness, so it is
  ;; hollow -- which is the thing a nested box of the parent's colour is not.
  (let ((target (make-surface 20 20 +white+)))
    (draw target (render (layout '(box (:width 12 :height 12 :border 2
                                        :border-colour "#ff0000"))
                                 4 4)))
    (check "the edge is drawn" (rgb 255 0 0) (pixel-at target 4 4))
    (check "and the far edge too" (rgb 255 0 0) (pixel-at target 15 15))
    (check "the middle is left alone" +white+ (pixel-at target 10 10))
    (check "and so is everything outside" +white+ (pixel-at target 2 2))
    ;; Two pixels thick, so the third pixel in is already through it.
    (check "the outline is as thick as it was asked to be"
           +white+ (pixel-at target 6 10)))
  ;; An outline needs no fill. That is the whole reason it exists: an unchecked
  ;; checkbox is an outline round nothing.
  (check "a border with no fill still draws"
         '(:stroke-rect)
         (mapcar #'first (render (layout '(box (:width 10 :height 10 :border 1)) 0 0))))
  (check "and with a fill, the outline goes on top of it"
         '(:fill-rect :stroke-rect)
         (mapcar #'first (render (layout '(box (:width 10 :height 10 :fill "#fff"
                                                :border 1))
                                         0 0))))
  (check "no border, no operation"
         '(:fill-rect)
         (mapcar #'first (render (layout '(box (:width 10 :height 10 :fill "#fff")) 0 0))))
  ;; Every backend that fills rectangles gets outlines, GLES included.
  (check-true "an outline reduces to plain rectangles"
              (> (length (flatten-to-rects
                          (render (layout '(box (:width 10 :height 10 :border 2)) 0 0))))
                 1))
  ;; And the widgets that were waiting for it.
  (let ((empty (checkbox nil)) (full (checkbox t)))
    (check "an unchecked box is an outline" 2 (view-prop empty :border))
    (check "with nothing inside it" 0 (length (view-children empty)))
    (check "a checked one is filled instead" nil (view-prop full :border))
    (check "and has a tick in it" 1 (length (view-children full)))
    (check "in the colour that goes on it"
           (theme :on-primary) (view-prop (first (view-children full)) :colour)))
  (let ((off (radio nil)) (on (radio t)))
    (check "a radio is always a ring" 2 (view-prop off :border))
    (check "empty when unchosen" 0 (length (view-children off)))
    (check "with a dot when chosen" 1 (length (view-children on)))
    (check "and the ring takes the primary colour when it is"
           (theme :primary) (view-prop on :border-colour)))
  (check "an outlined card is flat, because the outline already separates it"
         0 (view-prop (card nil :outlined t) :elevation))
  (check "and it has an edge" 1 (view-prop (card nil :outlined t) :border)))

(defun test-fling ()
  (format t "fling~%")
  ;; Velocity is measured across the whole window, not between the last two
  ;; samples: touches arrive a dozen to a frame, so consecutive ones are often a
  ;; hair apart in space and microseconds apart in time.
  (multiple-value-bind (vx vy)
      (drag-velocity (list (list* 1.0 100 50) (list* 0.75 75 40)
                           (list* 0.5 50 30) (list* 0.0 0 10)))
    (check "velocity is the whole span over the whole time" 100.0 vx)
    (check "on both axes" 40.0 vy))
  (check "one sample is no velocity at all" 0.0 (drag-velocity (list (list* 1.0 5 5))))
  (check "and no samples is not an error" 0.0 (drag-velocity '()))
  (check "nor is a window with no time in it"
         0.0 (drag-velocity (list (list* 1.0 9 9) (list* 1.0 0 0))))
  (check-true "a fast fling is worth animating" (flinging-p 500.0))
  (check-true "a slow one is not" (not (flinging-p 5.0)))
  (check-true "and neither is nothing" (not (flinging-p nil)))
  ;; The point of an exponential decay: the same elapsed time covers the same
  ;; distance however many steps it is cut into, so a fling looks the same at
  ;; sixty frames a second and at eleven.
  (let ((node (layout (scroll (list '(box (:width 20 :height 4000)))
                              :width 20 :height 100)
                      0 0)))
    (flet ((travel (steps seconds)
             (let ((offset 0) (velocity 1000.0))
               (dotimes (i steps offset)
                 (multiple-value-setq (offset velocity)
                   (fling-step node offset velocity (/ seconds steps)))))))
      (let ((coarse (travel 6 0.5)) (fine (travel 60 0.5)))
        (check-true "a coarse fling and a fine one land within a pixel or two"
                    (< (abs (- coarse fine)) 3))
        (check-true "and both actually moved" (> fine 100)))))
  ;; A fling that reaches the end is over, however fast it was going.
  (let ((node (layout (scroll (list '(box (:width 20 :height 120)))
                              :width 20 :height 100)
                      0 0)))
    (multiple-value-bind (offset velocity) (fling-step node 0 100000.0 0.1)
      (check "it stops at the end" 20 offset)
      (check-true "still carrying speed, because it has not arrived yet"
                  (plusp velocity)))
    (multiple-value-bind (offset velocity) (fling-step node 20 100000.0 0.1)
      (check "and going no further" 20 offset)
      (check "it gives up the speed too" 0.0 velocity))))

(defun test-semantics ()
  (format t "semantics~%")
  ;; The reading order IS the tree order, depth first, which is one of the
  ;; arguments for the view being a tree at all.
  (let* ((screen (layout `(column ()
                            ,(text "Settings")
                            ,(list-item "Wi-Fi" :supporting "Connected")
                            ,(button "Save" :id :save)
                            ,(checkbox t :label "Notify")
                            ,(radio nil :label "Daily"))
                         0 0 (constraints 0 200 0 400)))
         (found (semantics screen)))
    (check "everything that says what it means is found" 5 (length found))
    (check "in reading order"
           '("Settings" "Wi-Fi" "Save" "Notify" "Daily") (mapcar #'first found))
    (check "with the roles the widgets gave them"
           '(:text :item :button :checkbox :radio) (mapcar #'second found))
    (check "a checkbox carries its state" t (third (fourth found)))
    (check "and an unselected radio carries that" nil (third (fifth found)))
    ;; A row speaks for its parts. Without that it reads as itself AND as its
    ;; headline AND as its supporting line: three times the words.
    (check "a merged row hides its own text" "Connected" (third (second found))))
  ;; A decorative icon says nothing, which is the right default: a reader that
  ;; announces every chevron is worse than one that announces none.
  (check "an unlabelled icon is silent" 0 (length (semantics (layout (icon :check) 0 0))))
  (check "a labelled one is not"
         '("Done") (mapcar #'first (semantics (layout (icon :check :label "Done") 0 0))))
  ;; Name, then what it is, then what it says -- the order every reader uses.
  (check "a described node reads as a reader would say it"
         "Wi-Fi, switch, on" (describe-node "Wi-Fi" :switch t))
  (check "with no value, it stops after the role"
         "Save, button" (describe-node "Save" :button nil))
  (check "a value that is a string is spoken as one"
         "City, field, London" (describe-node "City" :field "London"))
  (check "and a label alone is just the label" "Settings" (describe-node "Settings" nil nil)))

(defun test-overlays ()
  (format t "overlays and choosing~%")
  ;; A modal needs no modality concept: DISPATCH gives the event to the topmost
  ;; node with a handler, so a full-screen scrim with one swallows everything.
  (let* ((screen (layout `(box ()
                            ,(button "Behind" :id :behind :on-press (lambda (n) (declare (ignore n)) :reached))
                            ,(dialog "Delete?" (list (text "This cannot be undone."))
                                     :width 200 :height 200))
                         0 0 (constraints 0 200 0 200)))
         (hit (dispatch screen 100 100 :on-press)))
    (check "a touch through the scrim lands on the scrim" :scrim (node-prop hit :id)))
  (let ((no-scrim (layout `(box () ,(button "Behind" :id :behind
                                            :on-press (lambda (n) (declare (ignore n)) nil)))
                          0 0 (constraints 0 200 0 200))))
    (check "and without the dialog it lands on what is behind"
           :behind (node-prop (dispatch no-scrim 4 4 :on-press) :id)))
  ;; Tabs share the width however many there are.
  (let* ((placed (layout (tabs '("One" "Two" "Three") 1) 0 0 (constraints 0 300 0 100)))
         (row (first (laid-out-children placed)))
         (widths (mapcar (lambda (k) (rect-width (laid-out-frame k)))
                         (laid-out-children row))))
    (check "three tabs, equal widths" '(100 100 100) widths)
    (check "and an indicator under each"
           3 (length (laid-out-children (second (laid-out-children placed))))))
  (check "the chosen tab is marked for a reader"
         '(nil t nil)
         (mapcar #'third (remove :tab (semantics (layout (tabs '("a" "b" "c") 1) 0 0
                                                         (constraints 0 300 0 100)))
                                 :key #'second :test-not #'eq)))
  ;; A slider places its knob by a spacer that grows with the value.
  (flet ((knob-x (value)
           (let* ((placed (layout (slider value :width 200 :height 24) 0 0))
                  (row (third (laid-out-children placed))))
             (rect-x (laid-out-frame (second (laid-out-children row)))))))
    (check "at zero the knob is at the start" 0 (knob-x 0))
    (check "at one it is at the end" 180 (knob-x 1))
    (check "and halfway is halfway" 90 (knob-x 1/2))
    (check "a value past the end is clamped" 180 (knob-x 5))
    (check "and one below the start too" 0 (knob-x -2)))
  (check "a slider tells a reader where it is" 1/4
         (third (first (semantics (layout (slider 1/4) 0 0)))))
  ;; A snackbar is the inverse pair, so its text is legible without anyone
  ;; choosing a colour.
  (let ((bar (snackbar "Saved")))
    (check "a snackbar is the inverse surface"
           (theme :inverse-surface) (view-prop bar :background))
    (check "and its text the colour that goes on it"
           (theme :on-inverse-surface) (view-prop (first (view-children bar)) :colour))))

(defun test-nested-scroll ()
  (format t "nested scroll~%")
  ;; A laid-out tree points downwards only, so the path taken to reach a node is
  ;; the only way to ask what it is inside.
  (let* ((page (layout (scroll (list (scroll (list '(box (:width 40 :height 400 :id :inner-content)))
                                             :id :inner :axis :horizontal
                                             :width 40 :height 40))
                               :id :page :width 40 :height 100)
                       0 0))
         (path (hit-path page 10 10)))
    (check-true "the path reaches the innermost thing under the finger" (>= (length path) 3))
    (check "and it is outermost first" :page (node-prop (first path) :id))
    (check "the innermost scroller on the path is the inner one"
           :inner (node-prop (scrolling-ancestor path) :id)))
  ;; A scroller reports what it consumed, so its parent can have the rest.
  (let ((node (layout (scroll (list '(box (:width 20 :height 500)))
                              :width 20 :height 100)
                      0 0)))
    (multiple-value-bind (offset used) (drag-scroll node 0 -30)
      (check "a drag that fits is consumed whole" -30 used)
      (check "and moves the content by it" 30 offset))
    (multiple-value-bind (offset used) (drag-scroll node 390 -30)
      (check "at the end it consumes only what was left" -10 used)
      (check "and stops there" 400 offset))
    (multiple-value-bind (offset used) (drag-scroll node 400 -30)
      (check "past the end it consumes nothing at all" 0 used)
      (check "leaving the whole gesture for the parent" 400 offset)))
  ;; Bringing something into view is arithmetic on two frames.
  (let* ((page (layout (scroll (list `(column ()
                                        (box (:width 40 :height 200 :id :above))
                                        (box (:width 40 :height 40 :id :target))))
                               :id :page :width 40 :height 100)
                       0 0))
         (path (node-path page (lambda (n) (eq (node-prop n :id) :target))))
         (scroller (scrolling-ancestor path))
         (target (car (last path))))
    (check "the target is found by id" :target (node-prop target :id))
    (check "and it is inside the page" :page (node-prop scroller :id))
    (check "which must scroll to reach it" 140 (needed-scroll scroller target)))
  (let* ((page (layout (scroll (list '(box (:width 40 :height 40 :id :target)))
                               :id :page :width 40 :height 100)
                       0 0))
         (path (node-path page (lambda (n) (eq (node-prop n :id) :target)))))
    (check "something already visible needs no scrolling"
           0 (needed-scroll (scrolling-ancestor path) (car (last path))))))

(defun test-bring-into-view ()
  (format t "bring into view~%")
  (flet ((page (target-height)
           (layout (scroll (list `(column ()
                                    (box (:width 40 :height 200 :id :above))
                                    (box (:width 40 :height ,target-height :id :field))))
                           :id :page :width 40 :height 100)
                   0 0)))
    (multiple-value-bind (scroller delta)
        (bring-into-view (page 40) (lambda (n) (eq (node-prop n :id) :field)))
      (check "the page is what has to move" :page (node-prop scroller :id))
      (check "and it must move far enough to show the whole field" 140 delta)))
  ;; Already visible: nothing to do, and NIL says so rather than zero, so a
  ;; caller can tell "no move needed" from "moved by nothing".
  (check "something already in view needs no scrolling"
         nil (bring-into-view (layout (scroll (list '(box (:width 40 :height 40 :id :field)))
                                              :id :page :width 40 :height 100)
                                      0 0)
                              (lambda (n) (eq (node-prop n :id) :field))))
  (check "and a node that is not there at all is NIL too"
         nil (bring-into-view (layout (scroll (list '(box (:width 40 :height 40)))
                                              :id :page :width 40 :height 100)
                                      0 0)
                              (lambda (n) (eq (node-prop n :id) :missing))))
  ;; A node with no scrolling ancestor cannot be brought anywhere.
  (check "nor is there anything to do without a scroller"
         nil (bring-into-view (layout '(column () (box (:width 10 :height 500 :id :field)))
                                      0 0)
                              (lambda (n) (eq (node-prop n :id) :field)))))

(defun test-saved-state ()
  (format t "state that outlives the process~%")
  ;; The default store holds the string in this image, which is what makes any
  ;; of this testable without a phone.
  (let ((*state-store* (let ((held nil))
                         (list :read (lambda () held)
                               :write (lambda (text) (setf held text))))))
    (check "nothing saved yet reads as the default" :cold (restore-state :cold))
    (save-state '(:name "Ada" :city "London" :tab 2 :volume 1/2))
    (check "a plist comes back EQUAL"
           '(:name "Ada" :city "London" :tab 2 :volume 1/2) (restore-state))
    ;; A RATIO, not a float: the demo's volume is one, and PRIN1 is what keeps
    ;; it exact across the round trip.
    (check "and the ratio is still a ratio" 1/2 (getf (restore-state) :volume))
    ;; Text is user text. A quote or a backslash in it must not end the string
    ;; early, which is the whole reason for PRIN1 rather than a hand-rolled
    ;; format.
    (save-state (list :city "O\"Brien \\ \"quoted\""))
    (check "quotes and backslashes survive"
           "O\"Brien \\ \"quoted\"" (getf (restore-state) :city))
    (save-state nil)
    (check "saving NIL reads back as NIL, not as the default" nil (restore-state :cold))
    ;; Yesterday's build wrote a shape this one cannot read. Starting empty
    ;; beats refusing to start.
    (funcall (getf *state-store* :write) "(:unbalanced ")
    (check "an unreadable blob yields the default instead of signalling"
           :cold (restore-state :cold))
    (funcall (getf *state-store* :write) "#.(error \"never\")")
    (check "and #. is not evaluated on the way back in"
           :cold (restore-state :cold))))

(defun test-platform-view ()
  (format t "a hole for a real platform View~%")
  ;; It lays out like anything else: a row places it, a size is honoured, and
  ;; the frame that comes out is what the host has to put the real View at.
  (let* ((tree (layout `(column (:padding 10)
                          (box (:width 50 :height 20))
                          ,(platform-view :id :web :width 100 :height 40))
                       0 0))
         (rects (platform-view-rects tree)))
    (check "one view is found" 1 (length rects))
    (destructuring-bind (id fn x y w h visible) (first rects)
      (declare (ignore fn))
      (check "by its id" :web id)
      (check "placed below its sibling and inside the padding" '(10 30) (list x y))
      (check "at the size it asked for" '(100 40) (list w h))
      (check-true "and visible with no clip given" visible)))
  ;; Scale is per axis, because the buffer's aspect is not the display's.
  (let ((rects (platform-view-rects
                (layout (platform-view :id :web :width 10 :height 10) 4 6)
                :x-scale 3 :y-scale 2)))
    (destructuring-bind (id fn x y w h visible) (first rects)
      (declare (ignore id fn visible))
      (check "logical units are scaled to pixels per axis" '(12 12 30 20) (list x y w h))))
  ;; A node with no :ID cannot be told from a new one next frame, so it is not
  ;; reported at all rather than attached and then leaked.
  (check "a view with no id is ignored"
         '() (platform-view-rects (layout (platform-view :width 10 :height 10) 0 0)))
  ;; The only clipping a child View allows: gone when it has left entirely.
  (let ((tree (layout (platform-view :id :web :width 10 :height 10) 0 200)))
    (check-true "inside the viewport it is visible"
                (seventh (first (platform-view-rects tree :clip (rect 0 0 100 300)))))
    (check "scrolled out of it, it is not"
           nil (seventh (first (platform-view-rects tree :clip (rect 0 0 100 100))))))
  ;; It paints nothing, so whatever is behind shows through -- until a caller
  ;; asks for a placeholder, which is what a desktop and this test can see.
  (check "it contributes no display operations"
         '() (render (layout (platform-view :id :web :width 10 :height 10) 0 0)))
  (check "unless a placeholder is asked for"
         1 (length (render (layout (list :platform-view
                                         (list :id :web :width 10 :height 10
                                               :placeholder +black+))
                                   0 0)))))

(defun test-rounded-clipping ()
  (format t "a rounded container clips its children round~%")
  ;; The radius travels WITH the clip. Without it the display list says nothing
  ;; about the shape and every backend clips square (bliss-cvj).
  (let ((ops (render (layout '(column (:clip t :radius 6 :width 20 :height 20)
                               (box (:width 20 :height 20 :fill "#ff0000")))
                             0 0))))
    (check "the clip op carries the radius" '(:clip-push 0 0 20 20 6) (first ops)))
  ;; A container with no radius still says 0 rather than nothing, so a backend
  ;; never has to guess how long the operation is.
  (check "and says zero when there is none" '(:clip-push 0 0 20 20 0)
         (first (render (layout '(column (:clip t :width 20 :height 20)
                                  (box (:width 20 :height 20 :fill "#ff0000")))
                                0 0))))
  ;; A rectangular clip is still one span, which is the case that must stay free.
  (check "a square clip yields one span"
         '((2 2 6 6)) (clip-spans 0 0 10 10 (car (push-clip (list nil) 2 2 6 6))))
  ;; A rounded one yields a span per row, and the first row is the inset one.
  (let ((spans (clip-spans 0 0 20 20 (car (push-clip (list nil) 0 0 20 20 6)))))
    (check "a rounded clip yields one span per row" 20 (length spans))
    (check-true "whose first row is inset" (< (third (first spans)) 20))
    (check "while the middle is not" 20 (third (nth 10 spans))))
  ;; The corners are the point. A filled box inside a rounded clip must lose
  ;; them, and this is exactly what failed before: the background was rounded
  ;; and the content was square.
  (let ((surface (make-surface 20 20 +white+)))
    (draw surface (render (layout '(column (:clip t :radius 6 :width 20 :height 20)
                                    (box (:width 20 :height 20 :fill "#000000")))
                                  0 0)))
    (check "the corner is not painted" +white+ (pixel-at surface 0 0))
    (check "nor the other three" (list +white+ +white+ +white+)
           (list (pixel-at surface 19 0) (pixel-at surface 0 19) (pixel-at surface 19 19)))
    (check "the middle is" +black+ (pixel-at surface 10 10))
    (check "and so is the edge between the corners" +black+ (pixel-at surface 0 10)))
  ;; An image is clipped the same way -- it does not come through FILL-CLIPPED,
  ;; so it is the one that silently kept its square corners.
  (let ((source (make-surface 4 4 (rgb 255 0 0)))
        (surface (make-surface 20 20 +white+)))
    (draw surface (render (layout `(column (:clip t :radius 6 :width 20 :height 20)
                                     ,(image source :width 20 :height 20))
                                  0 0 (constraints 0 20 0 20))))
    (check "an image loses the corner too" +white+ (pixel-at surface 0 0))
    (check "and keeps the middle" (rgb 255 0 0) (pixel-at surface 10 10)))
  ;; A rectangle-only backend gets it through FLATTEN, as rows.
  (let ((rects (flatten-to-rects
                (render (layout '(column (:clip t :radius 6 :width 20 :height 20)
                                  (box (:width 20 :height 20 :fill "#00ff00")))
                                0 0)))))
    (check "flatten turns a rounded clip into rows" 20 (length rects))
    (check-true "the first of which is inset" (< (third (first rects)) 20))))

(defun run-tests ()
  (setf *failures* 0 *checks* 0)
  (test-geometry) (test-paint) (test-font)
  (test-layout) (test-render) (test-raster)
  (test-input) (test-widgets) (test-constraints) (test-backend) (test-extension)
  (test-utf8) (test-stacking) (test-text-field) (test-elevation) (test-stretch) (test-paths) (test-horizontal-list) (test-memo-across-frames) (test-damage) (test-damaged-drawing) (test-design-system) (test-screen-composites) (test-svg) (test-borders) (test-fling) (test-semantics) (test-overlays) (test-nested-scroll) (test-bring-into-view) (test-saved-state) (test-platform-view) (test-rounded-clipping)
  (test-composites) (test-corners-and-clipping) (test-scroll) (test-clock) (test-virtual-list) (test-image)
  (format t "~%~D checks, ~D failures~%" *checks* *failures*)
  *failures*)
