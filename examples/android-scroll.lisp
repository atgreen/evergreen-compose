(load "bliss.lisp")
(in-package :cl-user)

;;;; A scrolling list, drag-driven.

(defparameter *offset* 0)
(defparameter *selected* nil)

(defun row-item (n)
  (bliss:button (format nil "Item ~D" n)
                :id (intern (format nil "ITEM-~D" n) :keyword)
                :size 3 :grow 1
                :pressed (eq bliss:*pressed*
                             (intern (format nil "ITEM-~D" n) :keyword))
                :on-press (lambda (node) (declare (ignore node))
                            (setf *selected* n))))

(defun ui (width height)
  `(column (:padding 16 :gap 10 :background ,(bliss:theme :surface)
            :width ,width :height ,height)
     ,(bliss:text "Scroll" :size 5)
     ,(bliss:text (if *selected*
                      (format nil "selected: item ~D" *selected*)
                      "drag the list, tap an item")
                  :size 2 :colour (bliss:theme :muted))
     ,(bliss:scroll
       (loop for n from 1 to 40
             collect `(row (:gap 0 :width ,(- width 32)) ,(row-item n)))
       :id :list :offset *offset* :height (- height 120) :width (- width 32)
       :on-drag (lambda (node dx dy)
                  (declare (ignore dx))
                  ;; Content moves WITH the finger, so dragging up (negative dy)
                  ;; increases the offset.
                  (setf *offset* (bliss:scroll-by node *offset* (- dy)))))))

(defun android-main (window)
  (bliss:run-android-app window #'ui))
