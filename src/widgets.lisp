(in-package :bliss)

;;;; Widgets.
;;;;
;;;; A widget is a FUNCTION THAT RETURNS VIEW DATA. It is not a class, not an
;;;; object, and it holds nothing: call it and you get a list, the same list you
;;;; could have written by hand. That means a user's own widgets are
;;;; indistinguishable from these -- there is no registry to add to and no
;;;; protocol to implement, because the framework only ever sees the list.
;;;;
;;;; State lives in the APPLICATION, not in the widget. A button does not know
;;;; whether it is pressed; it is told. This is what keeps the view a pure
;;;; function of the model, so redefining either at a REPL takes effect on the
;;;; next frame, and it is why there is no identity problem to solve: nothing
;;;; here needs to be matched up with its previous self between frames.
;;;;
;;;; Widgets that need to be referred to across frames -- to say which one is
;;;; pressed -- take an explicit :ID from the caller. Inferring identity from
;;;; tree position is where this kind of framework usually goes wrong.

(defparameter *theme*
  '(:surface "#101820" :ink "#ffffff" :muted "#a0b0c0"
    :raised "#1b2735" :accent "#4080ff" :accent-pressed "#2a5fcf" :disabled "#30404f"
    :radius 10 :elevation 2)
  "What widgets read for their appearance, as a plist so an application can
rebind or replace it. Non-colour entries live here too: a corner radius is a
theme decision, not a per-call one.")

(defun theme (key) (colour (getf *theme* key "#ff00ff")))

(defun theme-value (key &optional default)
  "A non-colour theme entry, returned as-is."
  (getf *theme* key default))

(defun button (label &key id on-press pressed (size 3) disabled grow)
  "A rectangle that reports touches, with its label centred.

Centred by CONSTRAINTS, not by padding the string with spaces: :ALIGN and
:CROSS-ALIGN place the label in whatever room the button ends up with, so it
stays centred when GROW makes the button wider than its text.

PRESSED and DISABLED are told, not remembered -- the caller holds that state and
passes it in, which is what lets the whole interface stay a function of a model."
  (let ((pad (max 6 (round size 2))))
    `(column (:padding ,pad
              :background ,(cond (disabled (theme :disabled))
                                 (pressed (theme :accent-pressed))
                                 (t (theme :accent)))
              :radius ,(theme-value :radius 0)
              :id ,id
              :align :center :cross-align :center
              ,@(when grow (list :grow grow))
              ,@(unless disabled (list :on-press on-press)))
       (label (:text ,label :size ,size
               :colour ,(if disabled (theme :muted) (theme :ink)))))))

(defun spacer (&key (width 0) (height 0) grow)
  "Empty space. A box with no :fill emits nothing to draw, so this costs a node
in the tree and nothing at all in the display list.

With :GROW it becomes the flexible spacer, which is the more useful form: it is
how \"push the rest to the far end\" is written without an alignment property on
every container."
  `(box (:width ,width :height ,height ,@(when grow (list :grow grow)))))

(defun text (string &key (size 2) (colour nil))
  `(label (:text ,string :size ,size :colour ,(or colour (theme :ink)))))

(defun toggle (label &key id on-press on (size 3) grow)
  "A button whose accent shows its state. ON is told, like PRESSED."
  (button (format nil "~A: ~:[off~;on~]" label on)
          :id id :on-press on-press :pressed on :size size :grow grow))

;;;; ── composites: everything below is a function returning primitives ───
;;;;
;;;; None of these adds a MEASURE-KIND or a RENDER-KIND method, touches a
;;;; backend, or is known to the framework in any way. That is the test of
;;;; whether a proposed widget is cheap: if it can be written as a function
;;;; returning existing primitives, it costs a DEFUN. If it cannot, it is
;;;; platform work wearing a widget's name.

(defun vstack (&rest children)
  "Alias for a column, for callers who prefer the stack vocabulary."
  `(column (:gap 0) ,@children))

(defun hstack (&rest children)
  `(row (:gap 0) ,@children))

(defun progress (value &key (width 120) (height 8) colour background)
  "A bar filled to VALUE, which is 0 to 1.

Two nested boxes. The track is a fixed box and the fill is another sized to a
fraction of it -- which needs no new primitive, because the fraction is computed
when the tree is BUILT. A value clamped here rather than at the caller means a
bad model cannot draw outside its own track."
  (let ((fraction (max 0 (min 1 value))))
    `(row (:width ,width :height ,height :radius ,(floor height 2)
           :clip t
           :background ,(or background (theme :disabled)))
       (box (:width ,(round (* width fraction)) :height ,height
             :fill ,(or colour (theme :accent)))))))

(defun switch (&key id on position on-change (width 52) (height 28))
  "A track with a knob. ON is told, like every other widget state.

POSITION is the knob's travel from 0 to 1 and defaults to ON, so a caller who
wants animation passes a fraction and one who does not passes nothing. The knob
is placed by a spacer of computed width rather than a growing one: :GROW can
only reach the far end, and a fraction has to stop in between.

The track colour interpolates over the same fraction, so the whole control moves
as one thing instead of the knob sliding across a track that snaps."
  (let* ((knob (- height 8))
         (fraction (max 0 (min 1 (or position (if on 1 0)))))
         (travel (max 0 (- width 8 knob))))
    `(row (:width ,width :height ,height :cross-align :center :padding 4
           :background ,(mix-colours (theme :disabled) (theme :accent) fraction)
           :radius ,(floor height 2)
           :id ,id ,@(when on-change (list :on-press on-change)))
       ,(spacer :width (round (* fraction travel)))
       (box (:width ,knob :height ,knob :fill ,(theme :ink) :radius ,(floor knob 2))))))

(defun labelled (text-string child &key (gap 6) (size 2))
  "CHILD with a caption above it."
  `(column (:gap ,gap) ,(text text-string :size size :colour (theme :muted)) ,child))

(defun scroll (children &key id (offset 0) on-drag height width)
  "A clipped container whose children are shifted by OFFSET.

Not a new primitive: a column that clips and offsets IS a scroll view, so this
is a function returning one. The offset lives in the application, like every
other widget state, and ON-DRAG is handed the laid-out node so SCROLL-BY can
clamp against the content it actually has."
  `(column (:clip t :scroll t :offset-y ,offset :id ,id
            ,@(when on-drag (list :on-drag on-drag))
            ,@(when height (list :height height))
            ,@(when width (list :width width)))
     ,@children))

(defun visible-range (offset viewport item-height count &key (overscan 2))
  "The half-open range of item indices worth building, as first and last.

Only the rows on screen are built, plus OVERSCAN either side so a fast scroll
does not show a gap before the next frame catches up. This is the whole reason a
list is not just a loop: laying out a thousand rows to show ten costs a thousand
rows, and at the measured cost of a node that is over a second a frame."
  (let* ((first (max 0 (- (floor offset item-height) overscan)))
         (last (min count (+ (ceiling (+ offset viewport) item-height) overscan))))
    (values first (max first last))))

(defun virtual-list (count item &key id (offset 0) viewport (item-height 40)
                                     width on-drag (overscan 2))
  "A scrolling list of COUNT rows, of which only the visible ones are built.

ITEM is called with an index and returns a view. It is called only for rows in
view, so COUNT may be enormous.

The rows off screen are replaced by two SPACERS, one above and one below, sized
to exactly the space those rows would have taken. That keeps the content height
honest -- so SCROLL-BY clamps against the real extent and the scroll position
means what it says -- without building anything. It also means every row must be
exactly ITEM-HEIGHT tall, which is why this wraps each one to that height rather
than trusting it: a row that disagrees would make the spacers lie and the list
would drift as it scrolled."
  (multiple-value-bind (first last)
      (visible-range offset viewport item-height count :overscan overscan)
    (scroll
     (append
      (list (spacer :height (* first item-height)))
      (loop for index from first below last
            collect `(column (:height ,item-height) ,(funcall item index)))
      (list (spacer :height (* (- count last) item-height))))
     :id id :offset offset :height viewport :width width :on-drag on-drag)))

(defun image (source &key width height)
  "SOURCE drawn at its own size, or scaled to WIDTH and HEIGHT.

SOURCE is a Bliss surface -- the same thing the software backend draws into --
so an image may equally be decoded from a file, generated, or rendered by Bliss
itself offscreen. The framework does not care where the pixels came from."
  `(image (:source ,source
           ,@(when width (list :width width))
           ,@(when height (list :height height)))))

(defun text-field (value &key id on-change placeholder (size 3) grow)
  "A tappable box showing VALUE, with a caret while it holds the keyboard.

Told, not remembered, like everything else here: the caller owns the string and
is handed a new one through ON-CHANGE. What the widget does NOT leave to the
caller is which field the keyboard is bound to, because that is a property of
the keyboard, and there is only one keyboard.

Tapping it calls FOCUS-TEXT-FIELD, which seeds the platform editor with VALUE
and raises the keyboard. The application's loop then calls PUMP-TEXT-INPUT once
a frame, which is what turns what the input method did into ON-CHANGE. That
indirection is the whole reason the editor is not consulted here: a soft keyboard
commits whole words, corrects what it committed a moment ago, and hands back
characters nobody typed, so the editor is the truth and this only draws it."
  (let* ((focused (and id (eq id (text-focus-id))))
         (empty (or (null value) (string= value "")))
         (pad (max 6 (round size 2)))
         (press (lambda (node)
                  (declare (ignore node))
                  (focus-text-field id value on-change))))
    `(box (:padding ,pad
           :radius ,(theme-value :radius 0)
           :background ,(theme :disabled)
           :id ,id
           ,@(when grow (list :grow grow))
           ,@(when id (list :on-press press)))
       (row (:gap 1 :cross-align :center)
         (label (:text ,(if empty (or placeholder "") value)
                 :size ,size
                 :colour ,(if empty (theme :muted) (theme :ink))))
         ,@(when focused
             ;; A caret is a filled rectangle the height of a line, which is why
             ;; this needs no primitive of its own. Measured from "M" rather than
             ;; from the field's own text, so an empty field still has one and it
             ;; does not change height as the text does.
             (list `(box (:width 2
                          :height ,(nth-value 1 (text-extent "M" size))
                          :fill ,(theme :accent)))))))))

(defun card (children &key (padding 12) (gap 8) elevation background radius grow stretch
                             id on-press)
  "A raised surface with content in it.

The whole widget, which is rather the point. Compose's Card is six lines
delegating to Surface and eight hundred more of variants and design tokens;
this is the six, and a caller who wants the variants writes them."
  `(column (:padding ,padding :gap ,gap
            :radius ,(or radius (theme-value :radius 0))
            :background ,(or background (theme :raised))
            :elevation ,(or elevation (theme-value :elevation 0))
            ,@(when grow (list :grow grow))
            ,@(when stretch (list :stretch t))
            ,@(when id (list :id id))
            ,@(when on-press (list :on-press on-press)))
     ,@children))

(defun divider (&key (thickness 1) colour)
  "A hairline across the container it is in.

Stretches rather than taking a width, which is the whole reason it can be
written at all: a divider that had to be told how wide it is would have to be
told again every time its parent's padding changed."
  `(box (:height ,thickness :stretch t :fill ,(or colour (theme :disabled)))))

;;; ── Icons ─────────────────────────────────────────────────────────────
;;;
;;; Drawn rather than shipped. A real icon set is a font or a directory of SVG,
;;; both of which are an asset and a licence decision; these are a handful of
;;; shapes whose geometry is COMPUTED here -- a thick line is four corners either
;;; side of a segment, a circle is four cubics -- so nothing is transcribed from
;;; artwork and nothing can be subtly wrong in a way that only looks right.
;;;
;;; The 24-unit box is every icon set's convention, so a real set can be dropped
;;; in later without every call site changing.

(defun thick-line (x1 y1 x2 y2 &optional (width 2))
  "A segment as a filled quadrilateral: the four corners half a width either
side of it, along the normal."
  (let* ((dx (- x2 x1)) (dy (- y2 y1))
         (span (sqrt (+ (* dx dx) (* dy dy))))
         (nx (if (zerop span) 0 (/ (* (- dy) width) (* 2 span))))
         (ny (if (zerop span) 0 (/ (* dx width) (* 2 span)))))
    (list (list :move (+ x1 nx) (+ y1 ny))
          (list :line (+ x2 nx) (+ y2 ny))
          (list :line (- x2 nx) (- y2 ny))
          (list :line (- x1 nx) (- y1 ny))
          (list :close))))

(defparameter +circle-k+ 0.5523
  "How far a cubic's controls sit from a quarter circle's ends, as a fraction of
the radius. The value that makes the curve match the arc to within a thousandth
of it, which at icon sizes is a small fraction of one pixel.")

(defun circle-path (cx cy radius &optional (direction 1))
  "A circle as four cubics. DIRECTION -1 winds it the other way, which under the
nonzero rule is how a filled disc becomes a ring: put the smaller one inside the
larger, wound against it, and the overlap cancels."
  (let ((k (* radius +circle-k+))
        (s direction))
    (list (list :move cx (- cy radius))
          (list :cubic (+ cx (* s k)) (- cy radius) (+ cx (* s radius)) (- cy k)
                (+ cx (* s radius)) cy)
          (list :cubic (+ cx (* s radius)) (+ cy k) (+ cx (* s k)) (+ cy radius)
                cx (+ cy radius))
          (list :cubic (- cx (* s k)) (+ cy radius) (- cx (* s radius)) (+ cy k)
                (- cx (* s radius)) cy)
          (list :cubic (- cx (* s radius)) (- cy k) (- cx (* s k)) (- cy radius)
                cx (- cy radius))
          (list :close))))

(defparameter *icons*
  (list :plus (append (thick-line 4 12 20 12) (thick-line 12 4 12 20))
        :minus (thick-line 4 12 20 12)
        :close (append (thick-line 6 6 18 18) (thick-line 18 6 6 18))
        :check (append (thick-line 5 13 10 18) (thick-line 10 18 19 7))
        :menu (append (thick-line 4 7 20 7) (thick-line 4 12 20 12)
                      (thick-line 4 17 20 17))
        :chevron-right (append (thick-line 9 5 16 12) (thick-line 16 12 9 19))
        :chevron-left (append (thick-line 15 5 8 12) (thick-line 8 12 15 19))
        :chevron-up (append (thick-line 5 15 12 8) (thick-line 12 8 19 15))
        :chevron-down (append (thick-line 5 9 12 16) (thick-line 12 16 19 9))
        :circle (circle-path 12 12 9)
        :ring (append (circle-path 12 12 9) (circle-path 12 12 7 -1))
        :search (append (circle-path 10 10 6) (circle-path 10 10 4 -1)
                        (thick-line 14 14 20 20)))
  "The built-in icons, as path commands in a 24-unit box.")

(defun icon-names () (loop for (name nil) on *icons* by #'cddr collect name))

(defun icon (name &key (size 24) colour)
  "One of *ICONS*, as a view."
  (let ((commands (getf *icons* name)))
    (unless commands
      (error "No such icon: ~S. There are ~{~S~^ ~}." name (icon-names)))
    `(path (:commands ,commands :size ,size :view-box 24
            :colour ,(or colour (theme :ink))))))

(defun icon-button (name &key id on-press (size 24) colour background)
  "An icon in a round tappable target."
  `(box (:padding 8 :radius 999 :align :center :cross-align :center
         ,@(when background (list :background background))
         ,@(when id (list :id id))
         ,@(when on-press (list :on-press on-press)))
     ,(icon name :size size :colour colour)))
