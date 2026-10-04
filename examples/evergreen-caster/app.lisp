;;;; SPDX-FileCopyrightText: Copyright 2021 The Android Open Source Project
;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; Evergreen Caster: live podcast feeds and original offline Lisp narration.
(unless (find-package :evergreen-compose) (load "evergreen-compose.lisp"))
(defpackage :evergreen-caster (:use :cl) (:import-from :evergreen-compose #:ui)
  (:export #:view #:reset))
(in-package :evergreen-caster)
(load (merge-pathnames "data.lisp" *load-truename*))
(defvar *page* :discover)
(defvar *show* nil)
(defvar *episode* nil)
(defvar *following* nil)
(defvar *favorites* nil)
(defvar *queue* nil)
(defvar *current* nil)
(defvar *play-request* 0)
(defvar *query* "")
(defvar *status* "")
(defvar *dark* t)
(defun reset () (setf *page* :discover *show* nil *episode* nil *following* nil *favorites* nil
                     *queue* nil *current* nil *play-request* 0 *query* "" *status* "" *dark* t))
(defun show (id)
  (if (eql id 4) '(:id 4 :title "Live podcasts" :cover "cover_1.png" :description "Episodes from your public podcast feed.")
      (find id *shows* :key (lambda (s) (getf s :id)))))
(defun episode (id) (find id (all-episodes) :key (lambda (e) (getf e :id))))
(defun filtered-episodes ()
  (remove-if-not (lambda (e) (or (search *query* (getf e :title) :test #'char-equal)
                                (search *query* (getf e :description) :test #'char-equal))) (all-episodes)))
(defun follow (id) (setf *following* (if (member id *following*) (remove id *following*) (cons id *following*))))
(defun favorite (id) (setf *favorites* (if (member id *favorites*) (remove id *favorites*) (cons id *favorites*))))
(defun enqueue (id) (unless (member id *queue*) (setf *queue* (append *queue* (list id)))))
(defun play (id)
  (incf *play-request*)
  (setf *current* id *status* "Loading audio…" *queue* (remove id *queue*)))
(defun play-next () (when *queue* (play (first *queue*))))
(defun back () (cond (*episode* (setf *episode* nil)) (*show* (setf *show* nil)) (t (setf *page* :discover))))
(defun action (id icon label callback &rest props)
  (apply #'ui :icon-button :id id :icon icon :description label :on-click callback props))
(defun show-card (s)
  (let ((id (getf s :id)))
    (ui :card :id (format nil "show-~D" id) :width 250 :on-click (lambda () (setf *show* id)) :children
      (list (ui :image :asset (getf s :cover) :height 145 :fill-width t :scale :crop :description (getf s :title))
            (ui :text :text (getf s :title) :style :title :padding 16 :max-lines 2)))))
(defun episode-row (e &optional (prefix "episode"))
  (let ((id (getf e :id)))
    (ui :card :id (format nil "~A-~D" prefix id) :fill-width t :on-click (lambda () (setf *episode* id)) :children
      (list (ui :row :padding 12 :spacing 12 :children
              (list (ui :image :asset (getf (show (getf e :show)) :cover) :width 64 :height 64 :radius 12 :scale :crop :description (getf e :title))
                    (ui :column :weight 1 :spacing 6 :children
                      (list (ui :text :text (getf e :title) :font-weight :bold)
                            (ui :text :text (getf e :description) :max-lines 2 :color :muted)
                            (ui :text :text (if (getf e :key) (getf e :date) (format nil "~D sec · narrated sample" (getf e :seconds))) :style :label)))
                    (action (format nil "play-~A-~D" prefix id) :next "Play episode" (lambda () (play id)))))))))
(defun browse ()
  (ui :column :fill t :spacing 10 :children
    (list (ui :text-field :id "query" :label "Search Common Lisp episodes" :value *query* :fill-width t :padding-horizontal 16
              :on-change (lambda (text) (setf *query* text)))
          (ui :lazy-column :id "discover" :weight 1 :fill-width t :content-padding 16 :spacing 16 :children
            (append
              (list (feed-settings))
              (unless (plusp (length *query*))
                (list (ui :text :text "Listen. Learn. Lisp." :style :headline)
                      (ui :text :text "Original sample shows · synthetic narration · available offline" :color :muted :style :label)
                      (ui :lazy-row :height 255 :spacing 16 :children (mapcar #'show-card (if *live-episodes* (cons (show 4) *shows*) *shows*)))
                      (ui :text :text "Latest episodes" :style :title)))
              (let ((episodes (filtered-episodes)))
                (if episodes (mapcar #'episode-row episodes) (list (ui :text :text "No episodes found.")))))))))
(defun show-view ()
  (let* ((id *show*) (s (show id)))
    (ui :lazy-column :id (format nil "show-detail-~D" id) :fill t :content-padding 20 :spacing 16 :children
      (append (list (ui :image :asset (getf s :cover) :height 220 :fill-width t :scale :crop :radius 20)
                    (ui :text :text (getf s :title) :style :headline)
                    (ui :text :text (getf s :description))
                    (ui :button :id "follow" :text (if (member id *following*) "Following" "Follow show") :on-click (lambda () (follow id))))
              (mapcar #'episode-row (remove id (all-episodes) :key (lambda (e) (getf e :show)) :test-not #'eql))))))
(defun episode-view ()
  (let* ((id *episode*) (e (episode id)))
    (ui :lazy-column :id (format nil "episode-detail-~D" id) :fill t :content-padding 20 :spacing 16 :children
      (list (ui :image :asset (getf (show (getf e :show)) :cover) :height 180 :fill-width t :scale :crop :radius 20)
            (ui :text :text (getf e :title) :style :headline)
            (ui :text :text (getf e :description))
            (ui :button :id "play" :text "Play episode" :on-click (lambda () (play id)))
            (ui :row :spacing 12 :children
              (list (ui :outlined-button :id "queue" :text (if (member id *queue*) "Queued" "Add to queue") :on-click (lambda () (enqueue id)))
                    (action "favorite" :favorite "Toggle favourite" (lambda () (favorite id)) :color (if (member id *favorites*) :primary :muted))))
            (ui :text :text (if (getf e :key) "Show notes" "Transcript") :style :title)
            (ui :text :text (if (getf e :key) "Publisher feed · stream requires a connection" "Original Common Lisp sample · synthetic voice") :style :label :color :muted)
            (ui :text :text (getf e :transcript))))))
(defun library ()
  (ui :lazy-column :id "library" :fill t :content-padding 20 :spacing 16 :children
    (append (list (ui :text :text "Followed shows" :style :headline))
            (if *following* (list (ui :lazy-row :height 255 :spacing 12 :children (mapcar (lambda (id) (show-card (show id))) *following*)))
                (list (ui :text :text "Follow a show to keep it here.")))
            (list (ui :text :text "Favourite episodes" :style :title))
            (if *favorites* (mapcar (lambda (id) (episode-row (episode id))) *favorites*)
                (list (ui :text :text "Tap an episode's heart to save it."))))))
(defun queue-view ()
  (ui :lazy-column :id "queue-list" :fill t :content-padding 20 :spacing 16 :children
    (append (list (ui :text :text "Your queue" :style :headline)
                  (ui :button :id "play-next" :text "Play next" :enabled (not (null *queue*)) :on-click #'play-next))
            (if *queue*
                (loop for id in *queue* collect
                  (let ((selected id))
                    (ui :column :id (format nil "queued-~D" id) :spacing 6 :children
                      (list (episode-row (episode id) "queued-episode")
                            (ui :text-button :id (format nil "remove-~D" id) :text "Remove from queue"
                                :on-click (lambda () (setf *queue* (remove selected *queue*))))))))
                (list (ui :text :text "Your queue is empty. Open an episode to add it."))))))
(defun player ()
  (let ((e (episode *current*)))
    (ui :column :id "player" :fill-width t :children
      (list (ui :row :padding-horizontal 12 :children
              (list (ui :text :text (getf e :title) :font-weight :bold :weight 1)
                    (action "next" :next "Play next queued episode" #'play-next :enabled (not (null *queue*)))
                    (action "stop" :close "Stop playback" (lambda () (setf *current* nil *status* "")))))
            (unless (zerop (length *status*)) (ui :text :text *status* :style :label :padding-horizontal 12))
            (ui :media-player :id (format nil "audio-~D" *play-request*) :height 180 :fill-width t :source (if (getf e :key) (getf e :audio) (concatenate 'string "asset:///" (getf e :audio)))
                :playing t :controls t :on-load (lambda (text) (declare (ignore text)) (setf *status* ""))
                :on-error (lambda (text) (setf *status* text)))))))
(defun view ()
  (ui :theme :id "screen" :dark *dark* :primary (if *dark* "#abd9be" "#176b46")
      :on-back #'back :back-enabled (not (null (or *show* *episode* (not (eq *page* :discover))))) :children
    (list (ui :column :fill t :children
            (append
              (list (ui :scaffold :weight 1 :fill-width t :children
                      (append
                        (list (ui :top-bar :slot :top :text "Evergreen Caster" :children
                                (append (when (or *show* *episode*) (list (action "back" :back "Back" #'back :slot :navigation)))
                                        (list (action "theme" :settings "Toggle theme" (lambda () (setf *dark* (not *dark*))))))))
                        (list (ui :bottom-bar :slot :bottom :children
                                (loop for (page label icon) on '(:discover "Discover" :search :library "Library" :favorite :queue "Queue" :more) by #'cdddr collect
                                  (let ((selected page))
                                    (ui :nav-item :id (format nil "nav-~(~A~)" page) :text label :icon icon :selected (eq page *page*)
                                        :on-click (lambda () (setf *page* selected *show* nil *episode* nil)))))))
                        (list (cond (*episode* (episode-view)) (*show* (show-view))
                                    ((eq *page* :library) (library)) ((eq *page* :queue) (queue-view)) (t (browse)))))))
              (when *current* (list (player))))))))

(load (merge-pathnames "feed.lisp" *load-truename*))

(defparameter *saved-variables*
  '(*following* *favorites* *queue* *dark* *feed-url* *live-episodes* *next-live-id* *updated*))

(in-package :cl-user)
(defun android-main (window)
  (declare (ignore window))
  (evergreen-compose:run-compose-app #'evergreen-caster:view :state evergreen-caster::*saved-variables* :on-start #'evergreen-caster::start-podcast))
