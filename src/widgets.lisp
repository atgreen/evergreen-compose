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
    :accent "#4080ff" :accent-pressed "#2a5fcf" :disabled "#30404f")
  "Colours widgets read, as a plist so an application can rebind or replace it.")

(defun theme (key) (colour (getf *theme* key "#ff00ff")))

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
              :id ,id
              :align :center :cross-align :center
              ,@(when grow (list :grow grow))
              ,@(unless disabled (list :on-press on-press)))
       (label (:text ,label :size ,size
               :colour ,(if disabled (theme :muted) (theme :ink)))))))

(defun spacer (&key (width 0) (height 0))
  "Empty space. A box with no :fill emits nothing to draw, so this costs a node
in the tree and nothing at all in the display list."
  `(box (:width ,width :height ,height)))

(defun text (string &key (size 2) (colour nil))
  `(label (:text ,string :size ,size :colour ,(or colour (theme :ink)))))

(defun toggle (label &key id on-press on (size 3) grow)
  "A button whose accent shows its state. ON is told, like PRESSED."
  (button (format nil "~A: ~:[off~;on~]" label on)
          :id id :on-press on-press :pressed on :size size :grow grow))
