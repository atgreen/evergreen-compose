;;;; SPDX-FileCopyrightText: Copyright 2022 The Android Open Source Project
;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; Evergreen News — sample stories and a live Planet Lisp journal.
;;;; Adapted from JetNews; upstream attribution is in NOTICE.
;;;; State and actions live here; feed.lisp supplies the live feed and reader.

(unless (find-package :evergreen-compose) (load "evergreen-compose.lisp"))
(defpackage :evergreen-news
  (:use :cl)
  (:import-from :evergreen-compose #:ui)
  (:export #:view #:reset))
(in-package :evergreen-news)
(load (merge-pathnames "data.lisp" *load-truename*))

;;; Navigation and user choices

(defvar *page* :home)
(defvar *live-posts* nil)
(defvar *article* nil)
(defvar *drawer* nil)
(defvar *dark* nil)
(defvar *tab* :topics)
(defvar *bookmarks* nil)
(defvar *subscriptions* nil)

(defun reset ()
  (setf *page* :home *article* nil *drawer* nil *dark* nil
        *tab* :topics *bookmarks* nil *subscriptions* nil))

(defun back ()
  (cond (*drawer* (setf *drawer* nil))
        (*article* (setf *article* nil))
        (t (setf *page* :home))))

;;; Story lookup and saved stories

(defun post (id) (find id (append *posts* *live-posts*) :key (lambda (entry) (getf entry :id))))
(defun bookmarked-p (id) (not (null (member id *bookmarks*))))
(defun toggle-bookmark (id)
  (setf *bookmarks* (if (bookmarked-p id) (remove id *bookmarks*) (cons id *bookmarks*))))

;;; Shared controls and bundled sample stories

(defun action (id icon description callback &rest properties)
  (apply #'ui :icon-button :id id :icon icon :description description
         :on-click callback properties))

(defun post-row (entry section)
  (when (getf entry :key)
    (return-from post-row (story-card entry :section section)))
  (let* ((id (getf entry :id)) (key (format nil "~A-~D" section id)))
    (ui :row :id key :fill-width t :spacing 12 :padding 12 :children
      (list (if (getf entry :thumb)
                (ui :image :asset (getf entry :thumb) :width 64 :height 64 :radius 8 :scale :crop :description (getf entry :title))
                (ui :icon :icon :info :size 40 :description "Live article"))
            (ui :column :id (concatenate 'string "open-" key) :weight 1 :spacing 4
                :on-click (lambda () (setf *article* id)) :children
              (list (ui :text :text (getf entry :title) :font-weight :bold :max-lines 3)
                    (ui :text :style :label :color :muted
                        :text (format nil "~A · ~D min read" (getf entry :author) (getf entry :minutes)))))
            (action (concatenate 'string "save-" key) :star "Save article"
                    (lambda () (toggle-bookmark id)) :color (if (bookmarked-p id) :primary :muted))))))

(defun feed ()
  (let ((featured (post 6)))
    (ui :lazy-column :id "feed" :fill t :content-padding 16 :spacing 12 :children
      (append
        (list (ui :text :text "Top stories for you" :font-weight :bold)
              (ui :column :id "featured" :on-click (lambda () (setf *article* 6)) :spacing 10 :children
                (list (ui :image :asset (getf featured :image) :height 190 :fill-width t :scale :crop :radius 12
                          :description (getf featured :title))
                      (ui :text :text (getf featured :title) :style :title :font-weight :bold)
                      (ui :text :text (getf featured :author) :color :muted)
                      (ui :text :text (format nil "~A · ~D min read" (getf featured :date) (getf featured :minutes)) :style :label :color :muted))))
        (loop for id in '(1 2 3) append (list (ui :divider) (post-row (post id) "recommended")))
        (list (ui :divider) (ui :text :text "Popular on Evergreen News" :style :title)
              (ui :lazy-row :id "popular" :height 240 :spacing 16 :children
                (loop for id in '(5 1 2) for entry = (post id) collect
                  (let ((selected id))
                    (ui :card :id (format nil "popular-~D" id) :width 220
                        :on-click (lambda () (setf *article* selected)) :children
                      (list (ui :image :asset (getf entry :image) :height 130 :fill-width t :scale :crop)
                            (ui :text :text (getf entry :title) :padding 12 :font-weight :bold :max-lines 3))))))
              (ui :text :text "Recent stories" :style :title))
        (loop for id in '(6 3 4 5) collect (post-row (post id) "recent"))))))

(defun paragraph-markdown (paragraph)
  (let ((text (getf paragraph :text)))
    (case (getf paragraph :kind)
      (:header (format nil "## ~A" text))
      (:subhead (format nil "### ~A" text))
      (:codeblock (format nil "```~%~A~%```" text))
      (:quote (format nil "> ~A" text))
      (:bullet (format nil "- ~A" text))
      (otherwise text))))

(defun article ()
  (let ((entry (post *article*)))
    (when (getf entry :key) (return-from article (live-article entry)))
    (ui :lazy-column :id "article-body" :fill t :content-padding 20 :spacing 16 :children
      (append
        (list (ui :image :asset (getf entry :image) :height 210 :fill-width t :scale :crop :radius 12)
              (ui :text :text (getf entry :title) :style :headline :font-weight :bold)
              (ui :text :text (getf entry :subtitle) :style :title :color :muted)
              (ui :text :text (format nil "~A · ~A · ~D min read"
                                     (getf entry :author) (getf entry :date) (getf entry :minutes)) :style :label)
              (ui :divider))
        (loop for paragraph in (getf entry :paragraphs) for index from 0 collect
          (ui :markdown :id (format nil "paragraph-~D" index) :fill-width t
              :text (paragraph-markdown paragraph)))))))

;;; Interest selection

(defun interest-items ()
  (case *tab*
    (:topics '("Common Lisp / Getting started" "Common Lisp / Functions" "Common Lisp / Macros"
               "Common Lisp / CLOS" "Common Lisp / Sequences" "Common Lisp / Conditions"
               "Evergreen / Compose" "Evergreen / Android" "Tools / REPL" "Tools / ASDF"))
    (:people '("Sample editor / Common Lisp" "Sample editor / UI development"
               "Sample editor / Libraries" "Sample editor / Interactive programming"))
    (:publications '("Evergreen News" "Common Lisp Notes" "The REPL Notebook"
                     "Macros in Practice" "Evergreen Compose Journal"))))

(defun interests ()
  (ui :column :fill t :children
    (list
      (ui :tabs :children
        (loop for (tab label) on '(:topics "Topics" :people "People" :publications "Publications") by #'cddr collect
          (let ((selected tab))
            (ui :tab :id (string-downcase tab) :text label :selected (eq tab *tab*)
                :on-click (lambda () (setf *tab* selected))))))
      (ui :lazy-column :weight 1 :fill-width t :content-padding 16 :spacing 8 :children
        (loop for title in (interest-items) for index from 0 collect
          (let ((key title))
            (ui :row :fill-width t :spacing 12 :children
              (list (ui :checkbox :id (format nil "interest-~D" index)
                        :checked (not (null (member key *subscriptions* :test #'equal)))
                        :on-change (lambda (selected)
                                     (setf *subscriptions* (remove key *subscriptions* :test #'equal))
                                     (when selected (push key *subscriptions*))))
                    (ui :text :text title :weight 1)))))))))

;;; App shell — theme, navigation, and the active screen

(defun view ()
  (ui :theme :id "screen" :dark *dark* :primary (if *dark* "#8bd5ad" "#176b46")
      :on-primary (if *dark* "#003822" "#ffffff")
      :surface (if *dark* "#111c16" "#f7f7f0")
      :background (if *dark* "#111c16" "#f7f7f0")
      :on-surface (if *dark* "#e8eee7" "#202b24")
      :on-background (if *dark* "#e8eee7" "#202b24")
      :on-surface-variant (if *dark* "#b2c3b5" "#59675d")
      :primary-container (if *dark* "#2a4635" "#e4edde")
      :on-back #'back :back-enabled (or *drawer* (not (null *article*)) (not (eq *page* :home)))
      :children
    (list (ui :navigation-drawer :id "drawer" :open *drawer* :on-dismiss (lambda () (setf *drawer* nil)) :children
      (append
        (list (ui :text :slot :drawer :text "Evergreen News" :style :headline :padding 24))
        (loop for (page label icon) on '(:home "Sample stories" :home :live "Planet Lisp • Live" :info :interests "Interests" :favorite :bookmarks "Saved stories" :star) by #'cdddr collect
          (let ((selected page))
            (ui :drawer-item :id (string-downcase page) :text label :icon icon :selected (eq page *page*)
                :on-click (lambda () (setf *page* selected *drawer* nil *article* nil)))))
        (list (ui :scaffold :fill t :children
          (list
            (ui :top-bar :slot :top :text (cond (*article* "Evergreen News") ((eq *page* :interests) "Interests") (t "Evergreen News"))
                :children
              (append
                (list (action (if *article* "back" "menu") (if *article* :back :menu)
                              (if *article* "Back" "Open navigation")
                              (if *article* #'back (lambda () (setf *drawer* t))) :slot :navigation))
                (when *article*
                  (list (action "bookmark" :star "Save article" (lambda () (toggle-bookmark *article*))
                                :color (if (bookmarked-p *article*) :primary :muted))))
                (list (action "theme" :settings "Toggle dark theme" (lambda () (setf *dark* (not *dark*)))))))
            (cond (*article* (article))
                  ((eq *page* :interests) (interests))
                  ((eq *page* :live) (live-news))
                  ((eq *page* :bookmarks)
                   (ui :lazy-column :fill t :content-padding 16 :spacing 12 :children
                     (if *bookmarks* (mapcar (lambda (id) (post-row (post id) "saved")) *bookmarks*)
                         (list (ui :text :text "Save a story with its star to read it here." :padding 16)))))
                  (t (feed)))))))))))

;;; Persistence and Android entry point
;;; Save user choices and cached stories; leave transient navigation local.

(load (merge-pathnames "feed.lisp" *load-truename*))

(defparameter *saved-variables*
  '(*bookmarks* *subscriptions* *dark* *live-posts* *next-live-id* *updated*))

(in-package :cl-user)
(defun android-main (window)
  (declare (ignore window))
  (evergreen-compose:run-compose-app #'evergreen-news:view :state evergreen-news::*saved-variables*
    :on-start #'evergreen-news::start-news))
