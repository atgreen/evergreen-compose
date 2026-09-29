(in-package :bliss)

;;;; What a screen means, as opposed to what it looks like.
;;;;
;;;; A screen reader cannot read pixels. It needs to be told that this rounded
;;;; rectangle is a button, that its name is "Save", that the square beside it is
;;;; a checkbox and is currently off. None of that is derivable from a display
;;;; list, so it is carried on the view -- as props, like everything else, so a
;;;; label is quotable and printable and a test can read it without a device.
;;;;
;;;; This is the half of accessibility that is ours. Handing it to Android is
;;;; the other half and is in src/a11y.lisp, which is where the awkwardness
;;;; lives: explore-by-touch wants an AccessibilityNodeProvider, and that is a
;;;; CLASS to subclass rather than an interface to implement, so it is out of
;;;; reach without DEX. Announcements are not, and they are what we can give.

(defparameter +roles+
  '(:button :checkbox :radio :switch :link :image :heading :text :field :list :item)
  "What a node is, for something that cannot see it. Deliberately short: a role
that no reader treats differently is a role that only costs a reader time.")

(defun semantic-p (node)
  "Whether the laid-out NODE says anything about its meaning."
  (or (node-prop node :label) (node-prop node :role)))

(defun merges-p (node)
  "Whether NODE speaks for everything inside it.

A list row is one thing to a reader -- Wi-Fi, item, Connected -- and its
headline and its supporting line are not two more. Without this a row reads as
itself and then as its parts, which is not a cosmetic problem: it is three times
the words for the same content, and it is what the first test of SEMANTICS
caught. Compose spells it mergeDescendants and it is the same idea."
  (node-prop node :merge))

(defun semantics (placed)
  "Everything on the screen that says what it means, in reading order.

Each entry is (LABEL ROLE VALUE FRAME). Depth first and children in order,
because that is the order a reader moves through, and it is the order the view
tree is already in -- the tree IS the reading order, which is one of the
arguments for it being a tree."
  (let ((found '()))
    (labels ((walk (node)
               (when (semantic-p node)
                 (push (list (node-prop node :label)
                             (node-prop node :role)
                             (node-prop node :value)
                             (laid-out-frame node))
                       found))
               (unless (merges-p node)
                 (mapc #'walk (laid-out-children node)))))
      (walk placed))
    (nreverse found)))

(defun describe-node (label role value)
  "LABEL, ROLE and VALUE as one line for a reader to speak.

The order is the one every screen reader uses: what it is called, then what it
is, then what it says. \"Wi-Fi, switch, on\" -- not \"switch Wi-Fi on\", which
is an instruction rather than a description."
  (format nil "~@[~A~]~@[, ~(~A~)~]~@[, ~A~]"
          label
          (when role (string role))
          (cond ((eq value t) "on")
                ((eq value nil) nil)
                (t value))))
