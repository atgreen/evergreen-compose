(load "bliss.lisp")
(in-package :cl-user)

;;;; A hundred thousand rows. Only the dozen on screen are ever built.

(defparameter *offset* 0)
(defparameter *selected* nil)
(defparameter *rows* 100000)
(defconstant +row-height+ 52)

(defun item (index)
  (let ((id (intern (format nil "R~D" index) :keyword)))
    `(row (:padding 10 :gap 10 :cross-align :center :height ,+row-height+
           :background ,(if (eql *selected* index)
                            (bliss:theme :accent)
                            (bliss:theme :disabled))
           :radius 8 :id ,id
           :on-press ,(lambda (n) (declare (ignore n)) (setf *selected* index)))
       ,(bliss:text (format nil "Row ~D" index) :size 3)
       ,(bliss:spacer :grow 1)
       ,(bliss:text (if (evenp index) "even" "odd") :size 2
                    :colour (bliss:theme :muted)))))

(defun ui (width height)
  (let ((viewport (- height 130)))
    `(column (:padding 16 :gap 10 :background ,(bliss:theme :surface)
              :width ,width :height ,height)
       ,(bliss:text "100,000 rows" :size 5)
       ,(bliss:text (if *selected*
                        (format nil "selected row ~D" *selected*)
                        "drag to scroll, tap to select")
                    :size 2 :colour (bliss:theme :muted))
       ,(bliss:virtual-list
         *rows* #'item
         :id :list :offset *offset* :viewport viewport
         :item-size +row-height+ :width (- width 32)
         :on-drag (lambda (node dx dy)
                    (declare (ignore dx))
                    (setf *offset* (bliss:scroll-by node *offset* (- dy))))))))

(defun android-main (window)
  (bliss:run-android-app window #'ui))
