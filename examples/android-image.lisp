(load "bliss.lisp")
(in-package :cl-user)

;;;; Images. The source is a Bliss SURFACE, so the pixels can come from
;;;; anywhere -- here they are computed, which is the case a file-loader would
;;;; otherwise have hidden.

(defparameter *scale* 1)
(defparameter *plasma* nil)

(defun make-plasma (size)
  "A surface filled with something worth looking at."
  (let ((surface (bliss:make-surface size size)))
    (dotimes (y size surface)
      (dotimes (x size)
        (let* ((cx (- x (/ size 2))) (cy (- y (/ size 2)))
               (d (isqrt (+ (* cx cx) (* cy cy))))
               (ring (mod (* d 8) 256)))
          (setf (bliss:pixel-at surface x y)
                (bliss:rgb (min 255 (+ 40 ring))
                           (min 255 (floor (* 255 x) size))
                           (min 255 (floor (* 255 y) size)))))))))

(defun ui (width height)
  (unless *plasma* (setf *plasma* (make-plasma 64)))
  (let ((side (* 64 *scale*)))
    `(column (:padding 20 :gap 14 :background ,(bliss:theme :surface)
              :width ,width :height ,height :cross-align :center)
       ,(bliss:text "Images" :size 5)
       ,(bliss:text (format nil "64x64 surface drawn at ~Dx" *scale*)
                    :size 2 :colour (bliss:theme :muted))
       ,(bliss:spacer :height 8)
       ;; Rounded and clipped, to show an image is an ordinary participant.
       (column (:clip t :radius 16 :width ,side :height ,side)
         ,(bliss:image *plasma* :width side :height side))
       ,(bliss:spacer :height 8)
       (row (:gap 12)
         ,(bliss:button "1x" :id :s1 :size 3 :grow 1
                        :on-press (lambda (n) (declare (ignore n)) (setf *scale* 1)))
         ,(bliss:button "2x" :id :s2 :size 3 :grow 1
                        :on-press (lambda (n) (declare (ignore n)) (setf *scale* 2)))
         ,(bliss:button "4x" :id :s4 :size 3 :grow 1
                        :on-press (lambda (n) (declare (ignore n)) (setf *scale* 4)))))))

(defun android-main (window)
  (bliss:run-android-app window #'ui))
