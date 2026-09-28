(load "bliss.lisp")
(in-package :cl-user)

;;;; Animation. The view is still a pure function of state -- the only new thing
;;;; is that one piece of state moves toward another every frame, and the view
;;;; says so by calling APPROACH, which asks for the next frame on its behalf.

(defparameter *on* nil)
(defparameter *knob* 0.0 "Where the switch knob actually is, 0 to 1.")
(defparameter *bar* 0.0)
(defparameter *target* 0.0)

(defun ui (width height)
  ;; Both of these move toward their target and request another frame until they
  ;; arrive. Nothing schedules them and nothing cancels them.
  (setf *knob* (bliss:approach *knob* (if *on* 1.0 0.0) :rate 14))
  (setf *bar* (bliss:approach *bar* *target* :rate 8))
  `(column (:padding 20 :gap 16 :background ,(bliss:theme :surface)
            :width ,width :height ,height)
     ,(bliss:text "Animation" :size 5)
     ,(bliss:text "a frame clock, not a timer" :size 2 :colour (bliss:theme :muted))
     ,(bliss:spacer :height 8)
     (row (:gap 14 :cross-align :center)
       ,(bliss:switch :id :sw :position *knob*
                      :on-change (lambda (n) (declare (ignore n))
                                   (setf *on* (not *on*))))
       ,(bliss:text (if *on* "on" "off") :size 3))
     ,(bliss:spacer :height 8)
     ,(bliss:labelled "Animated bar"
                      (bliss:progress *bar* :width (- width 40) :height 18))
     (row (:gap 12 :width ,(- width 40))
       ,(bliss:button "0%" :id :z :size 3 :grow 1
                      :on-press (lambda (n) (declare (ignore n)) (setf *target* 0.0)))
       ,(bliss:button "50%" :id :h :size 3 :grow 1
                      :on-press (lambda (n) (declare (ignore n)) (setf *target* 0.5)))
       ,(bliss:button "100%" :id :f :size 3 :grow 1
                      :on-press (lambda (n) (declare (ignore n)) (setf *target* 1.0))))
     ,(bliss:spacer :height 8)
     ,(bliss:text (format nil "~,2Fs since launch" (bliss:now))
                  :size 2 :colour (bliss:theme :muted))))

(defun android-main (window)
  (bliss:run-android-app window #'ui))
