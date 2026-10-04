;;;; SPDX-FileCopyrightText: Copyright 2023 The Android Open Source Project
;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; Evergreen Lagged: JetLagged's sleep dashboard with fixed sample readings.
(unless (find-package :evergreen-compose) (load "evergreen-compose.lisp"))
(defpackage :evergreen-lagged (:use :cl) (:import-from :evergreen-compose #:ui)
  (:export #:view #:reset))
(in-package :evergreen-lagged)
(load (merge-pathnames "data.lisp" *load-truename*))
(defvar *period* :week)
(defvar *expanded* nil)
(defvar *page* :home)
(defvar *drawer* nil)
(defvar *dark* nil)
(defun reset () (setf *period* :week *expanded* nil *page* :home *drawer* nil *dark* nil))
(defun selected-nights () (if (eq *period* :day) (last *nights*) *nights*))
(defun interval-minutes (periods)
  (let ((end -1) (total 0))
    (dolist (period (sort (copy-list periods) #'< :key #'first) total)
      (incf total (max 0 (- (second period) (max end (first period)))))
      (setf end (max end (second period))))))
(defun sleep-minutes (night)
  (interval-minutes (remove :awake (getf night :periods) :key #'third)))
(defun bed-minutes (night)
  (let ((periods (getf night :periods)))
    (- (reduce #'max periods :key #'second) (reduce #'min periods :key #'first))))
(defun duration-label (minutes) (format nil "~Dh ~2,'0Dm" (floor minutes 60) (mod minutes 60)))
(defun clock-label (minutes) (format nil "~2,'0D:~2,'0D" (mod (floor minutes 60) 24) (mod minutes 60)))
(defun average-of (fn) (round (reduce #'+ (selected-nights) :key fn) (length (selected-nights))))
(defun stage-color (type) (ecase type (:awake "#efd45a") (:light "#acd0dc") (:deep "#566f9e") (:rem "#a399ce")))
(defun stage-row (type) (ecase type (:awake 0) (:light 1) (:deep 2) (:rem 3)))
(defun stage-label (type) (if (eq type :rem) "REM" (string-capitalize type)))
(defun night-label (night) (format nil "Night ~D" (- 8 (getf night :id))))
(defun sleep-graph (night expanded)
  (ui :canvas :width 660 :height (if expanded 144 44) :view-width 960 :view-height (if expanded 100 28)
      :description (format nil "~A sleep stages, ~A asleep" (night-label night) (duration-label (sleep-minutes night)))
      :children
    (loop for (start end type) in (getf night :periods) collect
      (ui :rect :x (- start 1200) :y (if expanded (+ 2 (* 24 (stage-row type))) 2)
          :width (- end start) :height (if expanded 20 24) :radius 4 :fill (stage-color type)))))
(defun night-card (night)
  (let* ((id (getf night :id)) (expanded (member id *expanded*)))
    (ui :card :id (format nil "night-~D" id) :fill-width t
        :on-click (lambda () (setf *expanded* (if (member id *expanded*) (remove id *expanded*) (cons id *expanded*))))
        :children
      (list (ui :column :padding 14 :spacing 10 :children
              (append
                (list (ui :text :text (format nil "~A · ~A · score ~D" (night-label night) (duration-label (sleep-minutes night)) (getf night :score))
                          :font-weight :bold)
                      (ui :text :text (format nil "~A – ~A · Tap to ~A"
                                                 (clock-label (reduce #'min (getf night :periods) :key #'first))
                                                 (clock-label (reduce #'max (getf night :periods) :key #'second))
                                                 (if expanded "collapse" "expand")) :style :label :color :muted)
                      (ui :lazy-row :height (if expanded 154 54) :children (list (sleep-graph night expanded))))
                (when expanded
                  (loop for type in '(:awake :light :deep :rem) collect
                    (ui :row :spacing 8 :children
                      (list (ui :box :width 12 :height 12 :radius 6 :background (stage-color type))
                            (ui :text :text (stage-label type) :weight 1)
                            (ui :text :text (duration-label (interval-minutes (remove type (getf night :periods) :key #'third :test-not #'eq))))))))))))))
(defun summary-card (title value)
  (ui :card :weight 1 :children (list (ui :column :padding 16 :spacing 8 :children
                                      (list (ui :text :text title :style :label)
                                            (ui :text :text value :style :title :font-weight :bold))))))
(defun heart-buckets ()
  (loop for start from 0 below 1440 by 30
        for readings = (remove-if-not (lambda (r) (<= start (first r) (+ start 29))) *heart-readings*)
        when readings collect (list (+ start 15) (round (reduce #'+ readings :key #'second) (length readings)))))
(defun heart-card ()
  (let ((buckets (heart-buckets)))
    (ui :card :fill-width t :children
      (list (ui :column :padding 16 :spacing 14 :children
              (list (ui :text :text "Heart rate" :style :title)
                    (ui :text :text (format nil "~D bpm average · 176 sample readings"
                                           (round (reduce #'+ *heart-readings* :key #'second) (length *heart-readings*))))
                    (ui :canvas :fill-width t :height 180 :view-width 1440 :view-height 150 :description "Heart rate, half-hour averages over one sample day"
                        :children (list (ui :path :fill "none" :stroke (if *dark* "#efd45a" "#805600") :stroke-width 3
                                           :data (format nil "~{~A~}" (loop for (minute bpm) in buckets for index from 0 collect
                                                                         (format nil "~A~D ~D " (if (zerop index) "M" "L") minute (- 190 bpm)))))))
                    (ui :text :text "00:00                 12:00                 24:00" :style :label :color :muted)
                    (ui :text :text "Synthetic sample data; no sensors or health account are connected." :style :label :color :muted)))))))
(defun dashboard ()
  (ui :lazy-column :id (format nil "dashboard-~(~A~)" *page*) :fill t :content-padding 16 :spacing 18 :children
    (append
      (list (ui :column :padding 22 :radius 24 :background "#f5de78" :spacing 10 :children
              (list (ui :text :text "Rest, then return to your REPL." :style :headline :font-weight :bold :color "#302800")
                    (ui :text :text "A week of sample sleep and activity" :color "#302800"))))
      (unless (eq *page* :heart)
        (append
          (list (ui :tabs :children
                  (loop for (period label) on '(:day "Day" :week "Week" :month "Month" :six-months "6 months") by #'cddr collect
                    (let ((chosen period)) (ui :tab :id (format nil "period-~(~A~)" period) :text label :selected (eq period *period*)
                                              :on-click (lambda () (setf *period* chosen))))))
                (ui :text :text (format nil "~D sample night~:P available in this period" (length (selected-nights))) :style :label :color :muted)
                (ui :row :spacing 12 :fill-width t :children
                  (list (summary-card "Average asleep" (duration-label (average-of #'sleep-minutes)))
                        (summary-card "Average in bed" (duration-label (average-of #'bed-minutes)))))
                (ui :text :text "Sleep timeline" :style :title)
                (ui :text :text "20:00 → 12:00 · swipe charts to see the whole night" :style :label :color :muted))
          (mapcar #'night-card (selected-nights))))
      (unless (eq *page* :sleep) (list (heart-card))))))
(defun view ()
  (ui :theme :id "screen" :dark *dark* :primary (if *dark* "#efd45a" "#705d00")
      :on-back (lambda () (setf *drawer* nil *page* :home)) :back-enabled (or *drawer* (not (eq *page* :home))) :children
    (list (ui :navigation-drawer :id "drawer" :open *drawer* :on-dismiss (lambda () (setf *drawer* nil)) :children
            (append (list (ui :text :slot :drawer :text "Evergreen Lagged" :style :headline :padding 24))
                    (loop for (page label) on '(:home "Overview" :sleep "Sleep" :heart "Heart rate") by #'cddr collect
                      (let ((chosen page)) (ui :drawer-item :id (format nil "page-~(~A~)" page) :text label :icon :favorite :selected (eq page *page*)
                                              :on-click (lambda () (setf *page* chosen *drawer* nil)))))
                    (list (ui :scaffold :fill t :children
                            (list (ui :top-bar :slot :top :text "Evergreen Lagged" :children
                                    (list (ui :icon-button :id "menu" :slot :navigation :icon :menu :description "Open navigation" :on-click (lambda () (setf *drawer* t)))
                                          (ui :icon-button :id "theme" :icon :settings :description "Toggle theme" :on-click (lambda () (setf *dark* (not *dark*))))))
                                  (dashboard)))))))))

(defparameter *saved-variables*
  '(*period* *dark*))

(in-package :cl-user)
(defun android-main (window)
  (declare (ignore window))
  (evergreen-compose:run-compose-app #'evergreen-lagged:view :state evergreen-lagged::*saved-variables*))
