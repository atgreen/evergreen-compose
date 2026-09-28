(load "bliss.lisp")
(in-package :cl-user)

;;;; A Bliss application.
;;;;
;;;; The whole thing is a function of four variables and a call to
;;;; RUN-ANDROID-APP. There is no window handling, no touch arithmetic, no
;;;; blit, and no frame loop here -- those live in the framework, because
;;;; that is where their bugs lived when they were here.

(defparameter *count* 0)
(defparameter *loud* nil)
(defparameter *last* "nothing yet")

(defun ui (width height)
  `(column (:padding 20 :gap 14 :background ,(bliss:theme :surface)
            :width ,width :height ,height)
     ,(bliss:text "Bliss widgets" :size 5)
     ,(bliss:text "a UI that is Lisp data" :size 2 :colour (bliss:theme :muted))
     ,(bliss:spacer :height 6)
     ,(bliss:text (format nil "Count: ~D" *count*) :size 6)
     (row (:gap 12 :width ,(- width 40))
       ,(bliss:button "Less" :id :minus :size 4 :grow 1
                      :pressed (eq bliss:*pressed* :minus)
                      :on-press (lambda (n) (declare (ignore n))
                                  (decf *count*) (setf *last* "less")))
       ,(bliss:button "More" :id :plus :size 4 :grow 2
                      :pressed (eq bliss:*pressed* :plus)
                      :on-press (lambda (n) (declare (ignore n))
                                  (incf *count*) (setf *last* "more"))))
     (row (:gap 12 :width ,(- width 40))
       ,(bliss:toggle "Loud" :id :loud :on *loud* :size 3 :grow 1
                      :on-press (lambda (n) (declare (ignore n))
                                  (setf *loud* (not *loud*) *last* "loud")))
       ,(bliss:button "Reset" :id :reset :size 3 :grow 1
                      :pressed (eq bliss:*pressed* :reset)
                      :disabled (zerop *count*)
                      :on-press (lambda (n) (declare (ignore n))
                                  (setf *count* 0 *last* "reset"))))
     ,(bliss:labelled "Progress"
                      (bliss:progress (/ (mod *count* 10) 10.0)
                                      :width (- width 40) :height 16))
     ,(bliss:spacer :height 4)
     (row (:gap 12 :cross-align :center)
       ,(bliss:switch :id :sw :on *loud*
                      :on-change (lambda (n) (declare (ignore n))
                                   (setf *loud* (not *loud*) *last* "switch")))
       ,(bliss:text "a real switch" :size 2 :colour (bliss:theme :muted)))
     ,(bliss:spacer :height 6)
     ,(bliss:text (format nil "last: ~A" *last*) :size 2 :colour (bliss:theme :muted))))

(defun android-main (window)
  (bliss:run-android-app window #'ui))
