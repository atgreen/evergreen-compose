(in-package :bliss)
;; A view tree is data, so an example is a value, not a program.
(defparameter *hello*
  '(column (:padding 4 :gap 3 :background "#ffffff")
     (label (:text "BLISS" :size 2 :colour "#000000"))
     (label (:text "ON ANDROID" :size 1 :colour "#444444"))
     (row (:gap 2)
       (box (:width 12 :height 6 :fill "#e04040"))
       (box (:width 12 :height 6 :fill "#40a040"))
       (box (:width 12 :height 6 :fill "#4060e0")))))

(defun demo (&key (art t))
  (let* ((placed (layout *hello* 0 0))
         (frame (laid-out-frame placed))
         (surface (make-surface (rect-width frame) (rect-height frame) +white+)))
    (draw surface (render placed))
    (when art (ascii-art surface))
    (format t "~&frame: ~Dx~D, ~D display ops~%"
            (rect-width frame) (rect-height frame) (length (render placed)))
    surface))
