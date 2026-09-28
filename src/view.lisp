(in-package :bliss)

;;; A view is a list: (KIND PROPERTIES . CHILDREN), where PROPERTIES is a plist.
;;;
;;;   (column (:padding 8 :gap 4 :background "#fff")
;;;     (label (:text "BLISS" :size 2))
;;;     (box   (:width 40 :height 8 :fill "#f00")))
;;;
;;; It is a list rather than a struct or an object graph on purpose. A view tree
;;; can be quoted, built with backquote, transformed by ordinary list functions,
;;; produced by a macro, printed, read back, and diffed -- and a user can grow a
;;; vocabulary for their own domain without the framework offering an extension
;;; point, because the vocabulary is just functions that return lists.

(defun view-kind (view)
  "The node's kind as a KEYWORD, whatever package the tree was written in.

A view tree is data a USER writes, in the user's own package, so (COLUMN ...)
there reads as CL-USER::COLUMN and not BLISS::COLUMN. Dispatching on the symbol
itself would therefore work only for trees built inside this package -- which is
exactly the bug that took the first Android run down. Interning the name as a
keyword makes the vocabulary package-independent, which is what a data DSL needs
and what keywords exist for."
  (intern (symbol-name (first view)) :keyword))
(defun view-props (view) (second view))
(defun view-children (view) (cddr view))

(defun view-prop (view key &optional default)
  (getf (view-props view) key default))

(defun view-p (value)
  "True when VALUE has the shape of a view. Children are checked by the layout
walk rather than here, so a malformed node reports at its own position."
  (and (consp value) (symbolp (first value)) (listp (second value))))

(defun check-view (view)
  (unless (view-p view)
    (error "Not a view: ~S. A view is (KIND PLIST . CHILDREN)." view))
  view)
