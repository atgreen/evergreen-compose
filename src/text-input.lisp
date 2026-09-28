(in-package :bliss)

;;;; Which field the keyboard is talking to.
;;;;
;;;; Text is the one kind of input a UI framework cannot own. A touch is a
;;;; coordinate and belongs to whoever was drawn there; text arrives from an
;;;; input method that knows nothing about our tree, that may commit a whole word
;;;; at once, autocorrect what it committed a moment ago, or hand back an emoji
;;;; that was never typed. So the editor's text is the truth and a TEXT-FIELD
;;;; renders it -- not the other way round.
;;;;
;;;; The platform half is behind *TEXT-INPUT* rather than called directly, for
;;;; two reasons. The widget stays in the portable half, where it can be laid
;;;; out and rendered and TESTED with no device in the room. And the contract is
;;;; four functions, which is a small enough surface to say out loud.

(defvar *text-input* nil
  "The platform's text input, as a plist, or NIL where there is none.

  :SHOW   (function) raise the keyboard against an editor, returning true
  :HIDE   (function) put it away
  :READ   (function) the editor's text now, as a string
  :WRITE  (function of a string) replace the editor's text

On Android IME.LISP installs this. On a desktop there is nothing to install, and
a TEXT-FIELD then renders exactly as it would on a phone and never changes --
which is what lets layout and rendering be tested without one.")

(defun text-input-call (key &rest arguments)
  (let ((f (getf *text-input* key)))
    (when f (apply f arguments))))

(defvar *text-focus* nil
  "(ID VALUE . ON-CHANGE) for the field the keyboard is bound to, or NIL.

VALUE is what we last saw the editor holding, kept so that PUMP-TEXT-INPUT can
tell a change from a re-read. It is not the application's copy of the string:
the application's copy is whatever it did with ON-CHANGE.")

(defun text-focus-id () (car *text-focus*))

(defun focus-text-field (id value on-change)
  "Bind the keyboard to field ID, seeded with VALUE.

Seeding matters and is easy to leave out: without it the editor keeps whatever
the last field put there, and the first keystroke appends to someone else's
text."
  (setf *text-focus* (list* id (or value "") on-change))
  (text-input-call :write (or value ""))
  (text-input-call :show)
  (invalidate)
  id)

(defun blur-text-field ()
  (setf *text-focus* nil)
  (text-input-call :hide)
  (invalidate)
  nil)

(defun pump-text-input ()
  "Fire the focused field's ON-CHANGE if its text has moved. Once per frame.

Polled rather than pushed because a callback from the input method would be a
Java class we cannot define, and because at one read per frame the cost is two
JNI calls -- about 70us -- against a keystroke rate no human reaches."
  (let ((focus *text-focus*))
    (when focus
      (let ((text (text-input-call :read)))
        (when (and text (not (string= text (cadr focus))))
          (setf (cadr focus) text)
          (when (cddr focus) (funcall (cddr focus) text))
          (invalidate)
          text)))))
