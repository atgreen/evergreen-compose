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
                              :id :l :offset 0 :viewport 200 :item-height 40)))
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
                  :id :l :offset 4000 :viewport 200 :item-height 40)
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

(defun run-tests ()
  (setf *failures* 0 *checks* 0)
  (test-geometry) (test-paint) (test-font)
  (test-layout) (test-render) (test-raster)
  (test-input) (test-widgets) (test-constraints) (test-backend) (test-extension)
  (test-utf8) (test-stacking) (test-text-field)
  (test-composites) (test-corners-and-clipping) (test-scroll) (test-clock) (test-virtual-list) (test-image)
  (format t "~%~D checks, ~D failures~%" *checks* *failures*)
  *failures*)
