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

(defun run-tests ()
  (setf *failures* 0 *checks* 0)
  (test-geometry) (test-paint) (test-font)
  (test-layout) (test-render) (test-raster)
  (format t "~%~D checks, ~D failures~%" *checks* *failures*)
  *failures*)
