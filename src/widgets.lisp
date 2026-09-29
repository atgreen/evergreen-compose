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

;;;; The design system.
;;;;
;;;; Colours are ROLES, not names. The old theme had :ACCENT and :INK, and every
;;;; widget that wanted a coloured surface had to decide for itself what text
;;;; goes on it -- BUTTON hard-coded ink on accent, which is legible on a dark
;;;; scheme by luck and unreadable on a light one. Material's answer is to pair
;;;; every colour with its ON-colour and make that the unit a widget asks for,
;;;; and it is the right answer: a widget should say "a primary surface" and be
;;;; told both halves.
;;;;
;;;; Sizes and spaces are NAMES for the same reason. :SIZE 4 for a title and 2
;;;; for a caption appeared at every call site, so a screen was consistent only
;;;; by the author remembering; and changing the scale meant finding them all.

(defparameter *schemes*
  '(:dark (:surface "#101820" :on-surface "#ffffff"
           :surface-variant "#1b2735" :on-surface-variant "#a0b0c0"
           :primary "#4080ff" :on-primary "#ffffff" :primary-pressed "#2a5fcf"
           :error "#ff5252" :on-error "#ffffff"
           :outline "#30404f" :disabled "#30404f" :on-disabled "#7a8896"
           :inverse-surface "#e6ebf2" :on-inverse-surface "#121417"
           :scrim "#000000b0")
    :light (:surface "#fbfcfe" :on-surface "#121417"
            :surface-variant "#e6ebf2" :on-surface-variant "#48525e"
            :primary "#2a5fcf" :on-primary "#ffffff" :primary-pressed "#1b3f8f"
            :error "#b3261e" :on-error "#ffffff"
            :outline "#c2cad4" :disabled "#dfe4ea" :on-disabled "#9aa4b0"
            :inverse-surface "#2b3038" :on-inverse-surface "#f2f5f9"
            :scrim "#00000060"))
  "Colour by ROLE, in two schemes. Every surface names the colour that goes ON
it, so a widget never has to guess and a scheme can be swapped whole.")

(defparameter *type-scale*
  '(:display 5 :headline 4 :title 3 :body 2 :label 2 :caption 1)
  "Text sizes by name. Material's own scale is display/headline/title/body/label,
and these are those, coarser: a size here multiplies the glyph height and is
therefore a whole number, so the scale has five steps rather than fifteen.")

(defparameter *spacing*
  '(:none 0 :tight 4 :small 8 :medium 12 :large 16 :huge 24)
  "Padding and gaps by name, on a four-unit grid.")

(defparameter *theme*
  (append (getf *schemes* :dark) '(:radius 10 :elevation 2))
  "What widgets read for their appearance, as a plist so an application can
rebind or replace it with LET. Non-colour entries live here too: a corner radius
is a theme decision, not a per-call one.")

(defun theme (key)
  "The colour for a role. An unknown role is magenta rather than an error,
because a missing colour should be visible on screen and not fatal in a frame."
  (colour (getf *theme* key "#ff00ff")))

(defun use-scheme (name &rest overrides)
  "Replace the colours in *THEME* with scheme NAME's, keeping everything else."
  (let ((scheme (or (getf *schemes* name)
                    (error "No such scheme: ~S. There are ~{~S~^ and ~}."
                           name (loop for (key nil) on *schemes* by #'cddr collect key)))))
    (setf *theme* (append overrides scheme
                          (list :radius (theme-value :radius 10)
                                :elevation (theme-value :elevation 2))))))

(defun type-size (name)
  "A size from the type scale, or NAME itself when it is already a number --
so a caller with a reason can still say what it means."
  (if (numberp name)
      name
      (or (getf *type-scale* name)
          (error "No such text size: ~S. There are ~{~S~^ ~}."
                 name (loop for (key nil) on *type-scale* by #'cddr collect key)))))

(defun space (name)
  "A distance from the spacing scale, or NAME itself when it is already a number."
  (if (numberp name)
      name
      (or (getf *spacing* name)
          (error "No such space: ~S. There are ~{~S~^ ~}."
                 name (loop for (key nil) on *spacing* by #'cddr collect key)))))

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
  (let ((size (type-size size))
        (pad (max 6 (round (type-size size) 2))))
    `(column (:padding ,pad
              :background ,(cond (disabled (theme :disabled))
                                 (pressed (theme :primary-pressed))
                                 (t (theme :primary)))
              :radius ,(theme-value :radius 0)
              :id ,id :role :button :label ,label :merge t
              :align :center :cross-align :center
              ,@(when grow (list :grow grow))
              ,@(unless disabled (list :on-press on-press)))
       (label (:text ,label :size ,size
               ;; The ON-colour of the surface it sits on, not a guess. This
               ;; said :INK before, which is white, which is legible on the dark
               ;; scheme's accent and invisible on the light scheme's.
               :colour ,(if disabled (theme :on-disabled) (theme :on-primary)))))))

(defun spacer (&key (width 0) (height 0) grow)
  "Empty space. A box with no :fill emits nothing to draw, so this costs a node
in the tree and nothing at all in the display list.

With :GROW it becomes the flexible spacer, which is the more useful form: it is
how \"push the rest to the far end\" is written without an alignment property on
every container."
  `(box (:width ,width :height ,height ,@(when grow (list :grow grow)))))

(defun text (string &key (size 2) (colour nil))
  `(label (:text ,string :size ,(type-size size)
           :role :text :label ,string
           :colour ,(or colour (theme :on-surface)))))

(defun paragraph (string &key (size 3) colour (align :start) max-lines padding grow)
  "Text that wraps to the width it is given.

TEXT is one line however long it is; this is the one to reach for when the
string is a sentence rather than a word. ALIGN is :START, :CENTER or :END, and
MAX-LINES truncates with an ellipsis."
  `(paragraph (:text ,string :size ,(type-size size)
               :role :text :label ,string
               :align ,align
               ,@(when max-lines (list :max-lines max-lines))
               ,@(when padding (list :padding padding))
               ,@(when grow (list :grow grow))
               :colour ,(or colour (theme :on-surface)))))

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
           :background ,(or background (theme :surface-variant)))
       (box (:width ,(round (* width fraction)) :height ,height
             :fill ,(or colour (theme :primary)))))))

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
           :background ,(mix-colours (theme :surface-variant) (theme :primary) fraction)
           :radius ,(floor height 2)
           :id ,id ,@(when on-change (list :on-press on-change)))
       ,(spacer :width (round (* fraction travel)))
       (box (:width ,knob :height ,knob :fill ,(theme :on-primary)
             :radius ,(floor knob 2))))))

(defun labelled (text-string child &key (gap 6) (size 2))
  "CHILD with a caption above it."
  `(column (:gap ,(space gap))
     ,(text text-string :size size :colour (theme :on-surface-variant)) ,child))

(defun scroll (children &key id (offset 0) on-drag on-fling height width grow
                                (axis :vertical))
  "A clipped container whose children are shifted by OFFSET along AXIS.

Not a new primitive: a stack that clips and offsets IS a scroll view, so this is
a function returning one. The offset lives in the application, like every other
widget state, and ON-DRAG is handed the laid-out node so SCROLL-BY can clamp
against the content it actually has.

:HORIZONTAL costs a row instead of a column and :OFFSET-X instead of :OFFSET-Y,
and nothing else: the layout already offsets along whichever axis its stack
runs, so the second direction was always there and only the vocabulary was
missing."
  (let ((horizontal (eq axis :horizontal)))
    `(,(if horizontal 'row 'column)
      (:clip t :scroll t
       ,(if horizontal :offset-x :offset-y) ,offset
       :id ,id
       ,@(when on-drag (list :on-drag on-drag))
       ,@(when on-fling (list :on-fling on-fling))
       ,@(when height (list :height height))
       ,@(when width (list :width width))
       ;; A scroller that fills what its parent has left, rather than being told
       ;; a height its parent already knows. :SCROLL unbounds the CHILDREN and
       ;; :GROW sizes the scroller, which are different axes of the same node.
       ,@(when grow (list :grow grow)))
      ,@children)))

(defun visible-range (offset viewport item-size count &key (overscan 2))
  "The half-open range of item indices worth building, as first and last.

Only the items on screen are built, plus OVERSCAN either side so a fast scroll
does not show a gap before the next frame catches up. This is the whole reason a
list is not just a loop: laying out a thousand rows to show ten costs a thousand
rows, and at the measured cost of a node that is over a second a frame."
  (let* ((first (max 0 (- (floor offset item-size) overscan)))
         (last (min count (+ (ceiling (+ offset viewport) item-size) overscan))))
    (values first (max first last))))

(defun virtual-list (count item &key id (offset 0) viewport (item-size 40)
                                     width height on-drag on-fling (overscan 2)
                                     (axis :vertical))
  "A scrolling list of COUNT items, of which only the visible ones are built.

ITEM is called with an index and returns a view. It is called only for rows in
view, so COUNT may be enormous.

The rows off screen are replaced by two SPACERS, one above and one below, sized
to exactly the space those rows would have taken. That keeps the content height
honest -- so SCROLL-BY clamps against the real extent and the scroll position
means what it says -- without building anything. It also means every row must be
exactly ITEM-SIZE along the scroll axis, which is why this wraps each one to
that size rather than trusting it: an item that disagrees would make the spacers
lie and the list would drift as it scrolled.

:AXIS :HORIZONTAL makes it a carousel. VIEWPORT is always the extent ALONG the
scroll, so it is the width of a horizontal list and the height of a vertical
one, and :WIDTH / :HEIGHT then say the other dimension."
  (let ((horizontal (eq axis :horizontal)))
    (multiple-value-bind (first last)
        (visible-range offset viewport item-size count :overscan overscan)
      (flet ((gap (size) (if horizontal (spacer :width size) (spacer :height size)))
             (cell (index)
               `(,(if horizontal 'row 'column)
                 (,(if horizontal :width :height) ,item-size)
                 ,(funcall item index))))
        (scroll
         (append (list (gap (* first item-size)))
                 (loop for index from first below last collect (cell index))
                 (list (gap (* (- count last) item-size))))
         :axis axis :id id :offset offset :on-drag on-drag :on-fling on-fling
         :height (if horizontal height viewport)
         :width (if horizontal viewport width))))))

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
         (size (type-size size))
         (pad (max 6 (round (type-size size) 2)))
         (press (lambda (node)
                  (declare (ignore node))
                  (focus-text-field id value on-change))))
    `(box (:padding ,pad
           :radius ,(theme-value :radius 0)
           :background ,(theme :surface-variant)
           ;; A focused field says so with a ring, which is the thing every
           ;; toolkit does and we could not until there were borders.
           ,@(when focused (list :border 2 :border-colour (theme :primary)))
           :id ,id :role :field :merge t
           :label ,(or placeholder "") :value ,(or value "")
           ,@(when grow (list :grow grow))
           ,@(when id (list :on-press press)))
       (row (:gap 1 :cross-align :center)
         (label (:text ,(if empty (or placeholder "") value)
                 :size ,size
                 :colour ,(if empty (theme :on-surface-variant) (theme :on-surface))))
         ,@(when focused
             ;; A caret is a filled rectangle the height of a line, which is why
             ;; this needs no primitive of its own. Measured from "M" rather than
             ;; from the field's own text, so an empty field still has one and it
             ;; does not change height as the text does.
             (list `(box (:width 2
                          :height ,(nth-value 1 (text-extent "M" size))
                          :fill ,(theme :primary)))))))))

(defun card (children &key (padding 12) (gap 8) elevation background radius grow stretch
                             outlined id on-press)
  "A raised surface with content in it.

The whole widget, which is rather the point. Compose's Card is six lines
delegating to Surface and eight hundred more of variants and design tokens;
this is the six, and a caller who wants the variants writes them."
  `(column (:padding ,padding :gap ,gap
            :radius ,(or radius (theme-value :radius 0))
            :background ,(or background (theme :surface-variant))
            ;; An outlined card is flat by convention: the outline is what
            ;; separates it, so a shadow as well is saying it twice.
            :elevation ,(if outlined 0 (or elevation (theme-value :elevation 0)))
            ,@(when outlined (list :border 1 :border-colour (theme :outline)))
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
  `(box (:height ,thickness :stretch t :fill ,(or colour (theme :outline)))))

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

(defun icon-names ()
  "Every icon's name, once. A generated set may shadow a built-in of the same
name, and both are still in the list."
  (remove-duplicates (loop for (name nil) on *icons* by #'cddr collect name)
                     :from-end t))

(defun icon (name &key (size 24) colour label)
  "One of *ICONS*, as a view."
  (let ((commands (getf *icons* name)))
    (unless commands
      (error "No such icon: ~S. There are ~{~S~^ ~}." name (icon-names)))
    `(path (:commands ,commands :size ,size :view-box 24
            ,@(when label (list :role :image :label label))
            :colour ,(or colour (theme :on-surface))))))

(defun icon-button (name &key id on-press (size 24) colour background)
  "An icon in a round tappable target."
  `(box (:padding 8 :radius 999 :align :center :cross-align :center
         ,@(when background (list :background background))
         ,@(when id (list :id id))
         ,@(when on-press (list :on-press on-press)))
     ,(icon name :size size :colour colour)))

;;; ── Screen structure ──────────────────────────────────────────────────
;;;
;;; Each of these is a function returning primitives, which is the whole claim
;;; the framework makes about widgets. They are here rather than in an
;;; application because the ARRANGEMENT is conventional -- a list row puts its
;;; text in the middle and lets it grow, an app bar pushes its actions to the
;;; end -- and getting that convention wrong is what makes a screen look homemade.

(defun list-item (headline &key supporting leading trailing id on-press)
  "A row of a list: LEADING, text that grows, TRAILING.

The text column is the thing that grows, so the leading icon and the trailing
control keep their own sizes and the headline takes whatever is left. That is
the arrangement every list row in every toolkit makes, and it is one :GROW."
  `(row (:padding ,(space :large) :gap ,(space :medium)
         :cross-align :center :stretch t
         :role :item :merge t
         :label ,headline ,@(when supporting (list :value supporting))
         ,@(when id (list :id id))
         ,@(when on-press (list :on-press on-press)))
     ,@(when leading (list leading))
     (column (:gap ,(space :tight) :grow 1)
       ,(text headline :size :body)
       ,@(when supporting
           (list (text supporting :size :caption :colour (theme :on-surface-variant)))))
     ,@(when trailing (list trailing))))

(defun app-bar (title &key leading actions)
  "A title bar: LEADING at the front, ACTIONS at the end, title next to the front.

The gap between the title and the actions is a SPACER that grows, which is how a
row says 'everything after this goes to the far end' without a second layout
concept."
  `(row (:padding ,(space :medium) :gap ,(space :medium)
         :cross-align :center :stretch t
         :background ,(theme :surface-variant))
     ,@(when leading (list leading))
     ,(text title :size :title)
     ,(spacer :grow 1)
     ,@actions))

(defun scaffold (&key top content bottom width height)
  "A screen: TOP, CONTENT filling what is left, BOTTOM.

CONTENT grows, so the bars sit against the edges however tall they are and
nothing has to be told the screen's height twice."
  `(column (:background ,(theme :surface) :cross-align :stretch
            ,@(when width (list :width width))
            ,@(when height (list :height height)))
     ,@(when top (list top))
     (column (:grow 1) ,@(if (and content (listp (first content))) content (list content)))
     ,@(when bottom (list bottom))))

(defun chip (label &key id on-press selected icon)
  "A small, rounded, tappable label. Filled rather than outlined, because an
outline is a border and a view cannot have one yet (bliss-jfq)."
  `(row (:padding ,(space :small) :gap ,(space :tight) :radius 999
         :cross-align :center
         :background ,(if selected (theme :primary) (theme :surface-variant))
         :role :button :merge t :label ,label :value ,selected
         ,@(when id (list :id id))
         ,@(when on-press (list :on-press on-press)))
     ,@(when icon
         (list (icon icon :size 16
                     :colour (if selected (theme :on-primary) (theme :on-surface-variant)))))
     ,(text label :size :label
            :colour (if selected (theme :on-primary) (theme :on-surface-variant)))))

;;; ── Selection ─────────────────────────────────────────────────────────

(defun checkbox (checked &key id on-press label (size 20))
  "A box that is an outline when empty and a filled tick when not.

The empty state is why :BORDER exists. It is an outline round NOTHING, which
could not be drawn before and could not be faked either: nesting a smaller box
of the parent's colour is a hole, and a hole is the wrong colour the moment the
checkbox is not on the surface it guessed -- inside a card, say."
  (if checked
      `(box (:width ,size :height ,size :radius 4
             :background ,(theme :primary)
             :role :checkbox :value t ,@(when label (list :label label))
             :align :center :cross-align :center
             ,@(when id (list :id id))
             ,@(when on-press (list :on-press on-press)))
         ,(icon :check :size (- size 4) :colour (theme :on-primary)))
      `(box (:width ,size :height ,size :radius 4
             :border 2 :border-colour ,(theme :on-surface-variant)
             :role :checkbox :value nil ,@(when label (list :label label))
             ,@(when id (list :id id))
             ,@(when on-press (list :on-press on-press))))))

(defun radio (selected &key id on-press label (size 20))
  "A ring, with a dot in it when chosen. Always outlined, unlike a checkbox,
which is what tells the two apart at a glance even before the shape does."
  `(box (:width ,size :height ,size :radius ,(floor size 2)
         :border 2
         :border-colour ,(if selected (theme :primary) (theme :on-surface-variant))
         :role :radio :value ,selected ,@(when label (list :label label))
         :align :center :cross-align :center
         ,@(when id (list :id id))
         ,@(when on-press (list :on-press on-press)))
     ,@(when selected
         (let ((dot (max 2 (- size 10))))
           (list `(box (:width ,dot :height ,dot :radius ,(floor dot 2)
                        :fill ,(theme :primary))))))))

;;; ── Overlays and choosing ─────────────────────────────────────────────

(defun snackbar (message &key action on-action)
  "A brief message along the bottom, deliberately the inverse of the page.

Inverse because that is what makes it read as a thing ON the screen rather than
part of it, and because a role pair means the text is legible without anyone
choosing a colour: :INVERSE-SURFACE carries :ON-INVERSE-SURFACE."
  `(row (:padding ,(space :medium) :gap ,(space :medium)
         :radius ,(theme-value :radius 0) :stretch t :elevation 3
         :background ,(theme :inverse-surface)
         :cross-align :center :role :item :merge t :label ,message)
     ,(text message :size :body :colour (theme :on-inverse-surface))
     ,(spacer :grow 1)
     ,@(when action
         (list (button action :id :snackbar-action :on-press on-action :size :label)))))

(defun dialog (title content &key actions width height)
  "A panel in the middle of a scrim that covers everything.

The scrim carries an :ON-PRESS that does nothing, and that is the point: DISPATCH
hands an event to the topmost node with a handler, so a full-screen one swallows
every touch meant for what is behind it. A modal needs no modality concept --
it needs to be on top and to have a handler."
  `(box (:align :center :cross-align :center
         :background ,(theme :scrim)
         :role :dialog :label ,title
         ,@(when width (list :width width))
         ,@(when height (list :height height))
         :id :scrim :on-press ,(lambda (node) (declare (ignore node)) nil))
     ,(card (append (list (text title :size :title))
                    content
                    (when actions
                      (list `(row (:gap ,(space :small))
                               ,(spacer :grow 1)
                               ,@actions))))
            :elevation 6)))

(defun tabs (labels selected &key on-select)
  "A row of choices with a line under the chosen one.

Every tab grows equally, so they share the width however many there are and
however long their words -- which is the arrangement, and it is one :GROW."
  `(column (:stretch t)
     (row (:stretch t)
       ,@(loop for label in labels
               for index from 0
               collect `(column (:grow 1 :padding ,(space :small)
                                 :align :center :cross-align :center
                                 :role :tab :merge t :label ,label
                                 :value ,(= index selected)
                                 ,@(when on-select
                                     (list :id (intern (format nil "TAB-~D" index) :keyword)
                                           :on-press
                                           (let ((chosen index))
                                             (lambda (node)
                                               (declare (ignore node))
                                               (funcall on-select chosen))))))
                          ,(text label :size :label
                                 :colour (if (= index selected)
                                             (theme :primary)
                                             (theme :on-surface-variant))))))
     (row (:stretch t)
       ,@(loop for index from 0 below (length labels)
               collect `(box (:grow 1 :height 2
                              :fill ,(if (= index selected)
                                         (theme :primary)
                                         (theme :outline))))))))

(defun slider (value &key id on-change (width 200) (height 24))
  "A track with a knob at VALUE, which runs from 0 to 1.

The knob is placed by a SPACER that grows with the value, rather than by any
absolute positioning, because a spacer is something the layout already does. The
drag handler is built here and not asked for, because converting a finger's
movement into a fraction needs the track's width and the slider is the only
thing that knows it."
  (let* ((fraction (max 0 (min 1 value)))
         (knob (- height 4))
         (travel (max 1 (- width knob)))
         (drag (when on-change
                 (lambda (node dx dy)
                   (declare (ignore node dy))
                   (funcall on-change (max 0 (min 1 (+ fraction (/ dx travel)))))))))
    `(box (:width ,width :height ,height :cross-align :center
           :role :slider :value ,fraction
           ,@(when id (list :id id))
           ,@(when drag (list :on-drag drag)))
       (box (:width ,width :height 4 :radius 2 :fill ,(theme :surface-variant)))
       (box (:width ,(max 1 (round (* fraction travel))) :height 4 :radius 2
             :fill ,(theme :primary)))
       (row (:cross-align :center)
         ,(spacer :width (round (* fraction travel)))
         (box (:width ,knob :height ,knob :radius ,(floor knob 2)
               :fill ,(theme :primary)))))))
