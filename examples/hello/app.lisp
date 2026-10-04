;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(load "evergreen-compose.lisp")

(defvar *count* 0)
(defvar *name* "")
(defvar *dark* nil)
(defvar *dialog* nil)
;; Immutable rows are reusable. Theme colors come from their Compose parent.
(defparameter *numbers*
  (loop for i below 1000 collect
    (evergreen-compose:ui :text :id (format nil "number-~D" i) :padding 8
              :text (format nil "Number ~D" i))))

(defun greeting ()
  (evergreen-compose:ui :theme :dark *dark* :children
    (list (evergreen-compose:ui :column :padding 24 :spacing 16 :children
      (list (evergreen-compose:ui :text :text "Hello, Evergreen Compose 🌱" :style :headline)
            (evergreen-compose:ui :button :id "count" :text (format nil "Count: ~D" *count*)
                      :on-click (lambda () (incf *count*)))
            (evergreen-compose:ui :text-field :id "name" :label "Your name" :value *name*
                      :on-change (lambda (text) (setf *name* text)))
            (evergreen-compose:ui :text :text (format nil "Hello ~A" *name*))
            (evergreen-compose:ui :row :spacing 12 :children
              (list (evergreen-compose:ui :text :text "Dark theme")
                    (evergreen-compose:ui :switch :id "theme" :checked *dark*
                              :on-change (lambda (value) (setf *dark* value)))))
            (evergreen-compose:ui :button :id "open" :text "Open dialog"
                      :on-click (lambda () (setf *dialog* t)))
            (evergreen-compose:ui :lazy-column :id "numbers" :weight 1 :fill-width t :spacing 8
              :children *numbers*)
            (when *dialog*
              (evergreen-compose:ui :dialog :id "dialog" :on-dismiss (lambda () (setf *dialog* nil))
                :children (list (evergreen-compose:ui :text :text "A Compose dialog")
                                (evergreen-compose:ui :button :id "close" :text "Close"
                                          :on-click (lambda () (setf *dialog* nil)))))))))))

(defun android-main (window)
  (declare (ignore window))
  (evergreen-compose:run-compose-app #'greeting :trace t))
