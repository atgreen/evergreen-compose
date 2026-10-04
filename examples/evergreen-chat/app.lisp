;;;; SPDX-FileCopyrightText: Copyright 2020 The Android Open Source Project
;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; Evergreen Chat: Jetchat's conversation layout with a local Lisp community.
;;;; All people and messages are sample content. Upstream attribution: NOTICE.

(unless (find-package :evergreen-compose) (load "evergreen-compose.lisp"))
(defpackage :evergreen-chat (:use :cl) (:import-from :evergreen-compose #:ui)
  (:export #:view #:reset))
(in-package :evergreen-chat)

(defvar *channel* :lisp)
(defvar *histories* nil)
(defvar *drafts* nil)
(defvar *draft* "")
(defvar *next-id* 20)
(defvar *drawer* nil)
(defvar *profile* nil)
(defvar *attachments* nil)
(defvar *dark* nil)

(defun reset ()
  (setf *channel* :lisp *draft* "" *drafts* nil *next-id* 20
        *drawer* nil *profile* nil *attachments* nil *dark* nil
        *histories*
        (copy-tree
         '((:lisp
            (:id 1 :author :ada :time "09:41" :text "Welcome to #common-lisp! What are you making today?")
            (:id 2 :author :me :time "09:42" :text "An Android app with Evergreen Compose. The UI and callbacks are Common Lisp.")
            (:id 3 :author :ben :time "09:43" :text "Try describing a small view first, then wire up one callback. That makes the state flow easy to follow.")
            (:id 4 :author :ada :time "09:44" :text "The Evergreen News sample is a good place to explore navigation and bookmarks.")
            (:id 5 :author :me :time "09:45" :text "It is nice to pass a closure directly to :on-click.")
            (:id 6 :author :ada :time "09:46" :text "Coffee, parentheses, and a little cake for the next REPL session." :image "cupcake.jpg"))
           (:libraries
            (:id 7 :author :ada :time "10:01" :text "Which small Common Lisp libraries have you enjoyed using?")
            (:id 8 :author :ben :time "10:02" :text "I like starting with the sequence functions already in the language: MAP, REMOVE-IF-NOT, and REDUCE."))
           (:random
            (:id 9 :author :ben :time "11:15" :text "A quiet place for coffee breaks and snack photos.")
            (:id 10 :author :ada :time "11:16" :text "Happy hacking!" :image "sticker.png"))))))
(reset)

(defun channel-name () (ecase *channel* (:lisp "#common-lisp") (:libraries "#libraries") (:random "#random")))
(defun channel-messages () (cdr (assoc *channel* *histories*)))
(defun choose-channel (channel)
  (setf (getf *drafts* *channel*) *draft* *channel* channel
        *draft* (getf *drafts* channel "") *drawer* nil *profile* nil))
(defun send-message (&optional image)
  (let ((text (string-trim '(#\Space #\Tab #\Newline #\Return) *draft*)))
    (when (or image (plusp (length text)))
      (multiple-value-bind (second minute hour) (decode-universal-time (get-universal-time))
        (declare (ignore second))
        (setf (cdr (assoc *channel* *histories*))
              (append (channel-messages)
                      (list (list :id (incf *next-id*) :author :me :text text :image image
                                  :time (format nil "~2,'0D:~2,'0D" hour minute))))))
      (setf *draft* "" *attachments* nil))))
(defun back ()
  (cond (*attachments* (setf *attachments* nil)) (*drawer* (setf *drawer* nil))
        (*profile* (setf *profile* nil)) ((not (eq *channel* :lisp)) (choose-channel :lisp))))
(defun author-name (author) (ecase author (:me "You") (:ada "Ada Rivers") (:ben "Ben Park")))
(defun author-image (author) (if (eq author :ben) "someone_else.jpg" "ali.png"))
(defun icon-action (id icon label action &rest props)
  (apply #'ui :icon-button :id id :icon icon :description label :on-click action props))

(defun message-row (message)
  (let ((author (getf message :author)) (id (getf message :id)))
    (ui :row :id (format nil "message-~D" id) :fill-width t :spacing 10 :padding 4 :children
      (list
        (ui :image :id (format nil "author-~D" id) :asset (author-image author) :width 40 :height 40
            :radius 20 :scale :crop :description (author-name author)
            :on-click (lambda () (setf *profile* author)))
        (ui :column :weight 1 :spacing 6 :children
          (append
            (list (ui :text :text (format nil "~A   ~A" (author-name author) (getf message :time)) :style :label))
            (when (plusp (length (getf message :text)))
              (list (ui :text :text (getf message :text) :padding 12 :radius 14
                        :background (if (eq author :me) :primary-container :surface-variant))))
            (when (getf message :image)
              (list (ui :image :asset (getf message :image) :height 170 :fill-width t :scale :fit
                        :description "Shared sample attachment" :radius 14)))))))))

(defun conversation ()
  (ui :column :fill t :children
    (list
      (ui :text :text "Local sample conversation · 3 members" :style :label :color :muted :padding 12)
      (ui :lazy-column :id "timeline" :weight 1 :fill-width t :content-padding 12 :spacing 12
          :scroll-to (format nil "message-~D" (getf (car (last (channel-messages))) :id))
          :children (mapcar #'message-row (channel-messages)))
      (ui :divider)
      (ui :row :padding 8 :spacing 4 :fill-width t :children
        (list (icon-action "attach" :add "Add an attachment" (lambda () (setf *attachments* t)))
              (ui :text-field :id "draft" :weight 1 :value *draft* :label "Message"
                  :on-change (lambda (text) (setf *draft* text))
                  :on-submit (lambda (text) (setf *draft* text) (send-message)))
              (ui :text-button :id "send" :text "Send" :on-click #'send-message))))))

(defun profile-view ()
  (let ((person *profile*))
    (ui :lazy-column :fill t :content-padding 24 :spacing 18 :children
      (list (ui :image :asset (author-image person) :height 240 :fill-width t :scale :crop :radius 24
                :description (author-name person))
            (ui :text :text (author-name person) :style :headline)
            (ui :text :text "Common Lisp enthusiast" :style :title)
            (ui :text :text "Sample community member. Interested in interactive programming, small libraries, and native Android apps.")
            (ui :list-item :icon :person :text "Evergreen community" :supporting "Fictional profile for this local demo")
            (ui :button :id "profile-message" :text "Return to conversation" :on-click (lambda () (setf *profile* nil)))))))

(defun attachment-sheet ()
  (ui :bottom-sheet :id "attachments" :on-dismiss (lambda () (setf *attachments* nil)) :children
    (list (ui :text :text "Add to your message" :style :title)
          (ui :row :spacing 12 :children
            (loop for emoji in '("🌲" "λ" "☕" "💚") for index from 0 collect
              (let ((text emoji))
                (ui :text-button :id (format nil "emoji-~D" index) :text text
                    :on-click (lambda () (setf *draft* (concatenate 'string *draft* text) *attachments* nil))))))
          (ui :outlined-button :id "attach-sticker" :text "Send a sticker" :on-click (lambda () (send-message "sticker.png")))
          (ui :outlined-button :id "attach-photo" :text "Send a sample photo" :on-click (lambda () (send-message "cupcake.jpg"))))))

(defun view ()
  (ui :theme :id "screen" :dark *dark* :primary (if *dark* "#9ad9bd" "#176b46")
      :on-back #'back :back-enabled (not (null (or *profile* *drawer* *attachments* (not (eq *channel* :lisp))))) :children
    (append
      (list
        (ui :navigation-drawer :id "drawer" :open *drawer* :on-dismiss (lambda () (setf *drawer* nil)) :children
          (append
            (list (ui :text :slot :drawer :text "Evergreen Chat" :style :headline :padding 24))
            (loop for (channel label) on '(:lisp "#common-lisp" :libraries "#libraries" :random "#random") by #'cddr collect
              (let ((selected channel))
                (ui :drawer-item :id (format nil "channel-~(~A~)" channel) :text label :icon :more
                    :selected (eq channel *channel*) :on-click (lambda () (choose-channel selected)))))
            (list
              (ui :drawer-item :id "my-profile" :text "Your profile" :icon :person
                  :on-click (lambda () (setf *drawer* nil *profile* :me)))
              (ui :scaffold :fill t :children
                (list (ui :top-bar :slot :top :text (if *profile* "Profile" (channel-name)) :children
                        (list (icon-action (if *profile* "back" "menu") (if *profile* :back :menu)
                                           (if *profile* "Back" "Open channels")
                                           (if *profile* #'back (lambda () (setf *drawer* t))) :slot :navigation)
                              (icon-action "profile-ada" :info "Channel host profile" (lambda () (setf *profile* :ada)))
                              (icon-action "theme" :settings "Toggle theme" (lambda () (setf *dark* (not *dark*))))))
                      (if *profile* (profile-view) (conversation))))))))
      (when *attachments* (list (attachment-sheet))))))

(defparameter *saved-variables*
  '(*channel* *histories* *drafts* *draft* *next-id* *dark*))

(in-package :cl-user)
(defun android-main (window)
  (declare (ignore window))
  (evergreen-compose:run-compose-app #'evergreen-chat:view :state evergreen-chat::*saved-variables*))
