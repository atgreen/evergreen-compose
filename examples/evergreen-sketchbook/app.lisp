;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; Evergreen Sketchbook — native ink, ordinary Lisp application state.
;;;;
;;;; Android draws each gesture immediately. On pen-up, :on-stroke delivers
;;;; a color, a width, and integer points in the page's 1000 × 1400 viewport.
;;;; Lisp owns the finished strokes, editing history, and saved sketchbook.

(unless (find-package :evergreen-compose)
  (load "evergreen-compose.lisp"))

(defpackage :evergreen-sketchbook
  (:use :cl)
  (:import-from :evergreen-compose #:ui)
  (:export #:view #:reset))

(in-package :evergreen-sketchbook)

;;; Sketchbook state

(defparameter *palette*
  '(("Forest" "#234b38") ("Ink" "#263238") ("Clay" "#c65d3b")
    ("Gold" "#c2962f") ("Blue" "#446fa1") ("Plum" "#835680")))

(defvar *sketches* nil)
(defvar *current-id* 1)
(defvar *next-id* 1)
(defvar *next-stroke-id* 0)
(defvar *pen-color* "#234b38")
(defvar *pen-width* 10)
(defvar *redo* nil)
(defvar *gallery* nil)
(defvar *dialog* nil)
(defvar *title-draft* "")

(defun reset ()
  (setf *sketches* (list (list :id 1 :title "Untitled 1" :strokes nil))
        *current-id* 1
        *next-id* 1
        *next-stroke-id* 0
        *pen-color* "#234b38"
        *pen-width* 10
        *redo* nil
        *gallery* nil
        *dialog* nil
        *title-draft* ""))

(reset)

(defun current-sketch ()
  (find *current-id* *sketches* :key (lambda (sketch) (getf sketch :id))))

(defun current-strokes ()
  (getf (current-sketch) :strokes))

(defun set-sketch-property (property value)
  (let ((cell (member *current-id* *sketches*
                      :key (lambda (sketch) (getf sketch :id)))))
    (setf (getf (car cell) property) value)))

;;; Completed strokes and edit history

(defun stroke-path (points)
  ;; The tiny segment makes a tap render as a round dot after acknowledgment.
  (with-output-to-string (out)
    (format out "M~D,~D" (first (first points)) (second (first points)))
    (if (rest points)
        (dolist (point (rest points))
          (format out "L~D,~D" (first point) (second point)))
        (write-string "l0.01,0" out))))

(defun add-stroke (stroke)
  (destructuring-bind (color width points) stroke
    (set-sketch-property
     :strokes
     (append (current-strokes)
             (list (list :id (incf *next-stroke-id*)
                         :color color :width width :path (stroke-path points)))))
    ;; A new branch of edits invalidates the old redo history.
    (setf *redo* nil)))

(defun undo-stroke ()
  (when (current-strokes)
    (push (car (last (current-strokes))) *redo*)
    (set-sketch-property :strokes (butlast (current-strokes)))))

(defun redo-stroke ()
  (when *redo*
    (set-sketch-property :strokes (append (current-strokes) (list (pop *redo*))))))

(defun open-sketch (id)
  (when (find id *sketches* :key (lambda (sketch) (getf sketch :id)))
    (setf *current-id* id *gallery* nil *redo* nil *dialog* nil)))

(defun new-sketch ()
  (let ((id (incf *next-id*)))
    (push (list :id id :title (format nil "Untitled ~D" id) :strokes nil) *sketches*)
    (open-sketch id)))

(defun back ()
  (cond (*dialog* (setf *dialog* nil))
        (*gallery* (setf *gallery* nil))
        (t (setf *gallery* t))))

;;; Reusable pieces of the view

(defun ink-nodes (sketch prefix)
  ;; Stable IDs let the host send only newly added or removed strokes.
  (loop for stroke in (getf sketch :strokes)
        collect (ui :ink-stroke
                    :id (format nil "~A-ink-~D" prefix (getf stroke :id))
                    :data (getf stroke :path)
                    :color (getf stroke :color)
                    :width (getf stroke :width))))

(defun paper (sketch &key preview)
  (let* ((id (getf sketch :id))
         (key (format nil "~A-~D" (if preview "preview" "paper") id)))
    (apply #'ui :drawing-pad
           :id key
           :view-width 1000 :view-height 1400
           :paper-color "#fffdf6"
           :background "#e8e9df"
           :radius 12
           :fill-width t
           :pen-color *pen-color*
           :pen-width *pen-width*
           :enabled (not preview)
           :description (if preview (format nil "Preview of ~A" (getf sketch :title))
                            "Drawing paper. Drag a finger or stylus to draw.")
           :children (ink-nodes sketch key)
           (if preview
               (list :height 200)
               (list :weight 1
                     :on-stroke (lambda (stroke)
                                  ;; A queued stroke belongs to the page that
                                  ;; emitted it, even if navigation followed it.
                                  (let ((*current-id* id)) (add-stroke stroke))))))))

(defun palette ()
  (ui :row :spacing 8 :fill-width t :children
      (loop for (name color) in *palette*
            collect
            (let ((selected-color color))
              (ui :box :id (concatenate 'string "color-" (string-downcase name))
                  :weight 1 :height 44 :radius 22 :background color
                  :alignment :center :description (concatenate 'string name " ink")
                  :on-click (lambda () (setf *pen-color* selected-color))
                  :children
                  (when (equal color *pen-color*)
                    (list (ui :icon :icon :check :color "#ffffff"
                              :description "Selected ink"))))))))

(defun brush-controls ()
  (ui :row :spacing 8 :children
      (loop for (width label) on '(4 "Fine" 10 "Pen" 24 "Brush") by #'cddr
            collect
            (let ((selected-width width))
              (ui :chip :id (format nil "brush-~D" width)
                  :text label :selected (= width *pen-width*)
                  :on-click (lambda () (setf *pen-width* selected-width)))))))

;;; Drawing desk

(defun editor ()
  (ui :column :fill t :padding-horizontal 16 :padding-vertical 8 :spacing 12
      :children
      (list
       (ui :row :fill-width t :children
           (list
            (ui :column :weight 1 :spacing 4 :children
                (list
                 (ui :text :text (getf (current-sketch) :title)
                     :style :title :font-weight :bold :max-lines 1)
                 (ui :text :text "Make a little room for an idea."
                     :style :label :color :muted)))
            (ui :icon-button :id "rename" :icon :edit :description "Rename sketch"
                :on-click (lambda ()
                            (setf *title-draft* (getf (current-sketch) :title)
                                  *dialog* :rename)))))
       (paper (current-sketch))
       (palette)
       (ui :row :fill-width t :children
           (list
            (ui :column :weight 1 :children (list (brush-controls)))
            (ui :text :text (format nil "~D strokes" (length (current-strokes)))
                :style :label :color :muted)))
       (ui :row :spacing 8 :fill-width t :children
           (list
            (ui :outlined-button :id "undo" :text "Undo" :weight 1
                :enabled (not (null (current-strokes))) :on-click #'undo-stroke)
            (ui :outlined-button :id "redo" :text "Redo" :weight 1
                :enabled (not (null *redo*)) :on-click #'redo-stroke)
            (ui :text-button :id "clear" :text "Clear"
                :enabled (not (null (current-strokes)))
                :on-click (lambda () (setf *dialog* :clear)))))
       (ui :text :text "Saved on this device · Finger or stylus"
           :style :label :color :muted))))

;;; Saved sketches

(defun gallery ()
  (ui :lazy-column :id "sketch-gallery" :fill t :content-padding 20 :spacing 16
      :children
      (append
       (list
        (ui :text :text "Your sketchbook" :style :headline :font-weight :bold)
        (ui :text :text "Small ideas, kept close." :color :muted)
        (ui :button :id "new-sketch" :text "New sketch" :on-click #'new-sketch))
       (loop for sketch in *sketches*
             collect
             (let ((id (getf sketch :id)))
               (ui :card :id (format nil "sketch-~D" id) :radius 16
                   :on-click (lambda () (open-sketch id))
                   :container-color "#ffffff"
                   :children
                   (list
                    (paper sketch :preview t)
                    (ui :column :padding 16 :spacing 4 :children
                        (list
                         (ui :text :text (getf sketch :title) :font-weight :bold)
                         (ui :text :text (format nil "~D strokes" (length (getf sketch :strokes)))
                             :style :label :color :muted))))))))))

;;; Dialogs and application shell

(defun overlay ()
  (case *dialog*
    (:clear
     (ui :alert-dialog :id "clear-confirm" :title "Clear this page?"
         :text "This removes all strokes from the current sketch."
         :confirm-label "Clear page" :dismiss-label "Keep drawing"
         :on-confirm (lambda ()
                       (set-sketch-property :strokes nil)
                       (setf *redo* nil *dialog* nil))
         :on-dismiss (lambda () (setf *dialog* nil))))
    (:rename
     (ui :dialog :id "rename-dialog" :on-dismiss (lambda () (setf *dialog* nil))
         :children
         (list
          (ui :text :text "Name your sketch" :style :title)
          (ui :text-field :id "sketch-title" :label "Title" :value *title-draft*
              :fill-width t :on-change (lambda (text) (setf *title-draft* text)))
          (ui :button :id "save-title" :text "Save name"
              :enabled (plusp (length (string-trim " " *title-draft*)))
              :on-click (lambda ()
                          (set-sketch-property :title (string-trim " " *title-draft*))
                          (setf *dialog* nil))))))))

(defun view ()
  (ui :theme :id "screen" :primary "#234b38" :on-primary "#ffffff"
      :surface "#f1f2e9" :background "#f1f2e9" :on-surface "#24372b"
      :on-surface-variant "#5e6d60" :primary-container "#dce8d9"
      :secondary-container "#dce8d9" :on-secondary-container "#234b38"
      :on-back #'back :back-enabled (not (null (or *gallery* *dialog*)))
      :children
      (list
       (ui :scaffold :fill t :children
           (list
            (ui :top-bar :slot :top :text "Evergreen Sketchbook" :children
                (list
                 (ui :icon-button :id "gallery" :slot :navigation
                     :icon (if *gallery* :back :menu)
                     :description (if *gallery* "Back to drawing" "Open sketchbook")
                     :on-click (lambda () (setf *gallery* (not *gallery*))))
                 (ui :icon-button :id "new" :icon :add :description "New sketch"
                     :on-click #'new-sketch)))
            (if *gallery* (gallery) (editor))))
       (when *dialog* (overlay)))))

;;; Durable state and Android entry point
;;;
;;; Finished strokes save after every callback. The current gesture and undo
;;; history are transient; reopening a sketch never starts an active gesture.

(defparameter *saved-variables*
  '(*sketches* *current-id* *next-id* *next-stroke-id* *pen-color* *pen-width*))

(in-package :cl-user)

(defun android-main (window)
  (declare (ignore window))
  (evergreen-compose:run-compose-app #'evergreen-sketchbook:view
                             :state evergreen-sketchbook::*saved-variables*))
