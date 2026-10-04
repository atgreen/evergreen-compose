;;;; SPDX-FileCopyrightText: Copyright 2022 The Android Open Source Project
;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; Reply: local sample mail, with no account connection or network delivery.
(unless (find-package :evergreen-compose) (load "evergreen-compose.lisp"))
(defpackage :evergreen-reply (:use :cl) (:import-from :evergreen-compose #:ui)
  (:export #:view #:reset))
(in-package :evergreen-reply)
(load (merge-pathnames "data.lisp" *load-truename*))
(defvar *mails* nil)
(defvar *mailbox* :inbox)
(defvar *selected* nil)
(defvar *detail* nil)
(defvar *query* "")
(defvar *drawer* nil)
(defvar *composing* nil)
(defvar *reply-to* nil)
(defvar *draft-id* nil)
(defvar *recipient* "")
(defvar *subject* "")
(defvar *body* "")
(defvar *notice* nil)
(defvar *dark* nil)
(defun reset ()
  (setf *mails* (copy-tree *initial-mails*) *mailbox* :inbox *selected* nil *detail* nil
        *query* "" *drawer* nil *composing* nil *reply-to* nil *draft-id* nil *recipient* "" *subject* ""
        *body* "" *notice* nil *dark* nil))
(reset)
(defun mail (id) (find id *mails* :key (lambda (m) (getf m :id))))
(defun set-mail-property (id property value)
  (let ((cell (member id *mails* :key (lambda (m) (getf m :id)))))
    (when cell (setf (getf (car cell) property) value))))
(defun visible-mails ()
  (remove-if-not
    (lambda (m) (and (if (plusp (length *query*)) t
                        (if (eq *mailbox* :starred) (getf m :starred) (eq *mailbox* (getf m :mailbox))))
                    (or (search *query* (getf m :subject) :test #'char-equal)
                        (search *query* (getf m :sender) :test #'char-equal)
                        (search *query* (getf m :body) :test #'char-equal)))) *mails*))
(defun open-mail (id)
  (set-mail-property id :read t)
  (let ((message (mail id)))
    (if (eq (getf message :mailbox) :drafts)
        (setf *composing* t *draft-id* id *reply-to* (getf message :reply-to) *detail* nil
              *recipient* (getf message :recipient "") *subject* (getf message :subject)
              *body* (getf message :body) *notice* nil)
        (setf *detail* id *notice* nil))))
(defun toggle-star (id) (set-mail-property id :starred (not (getf (mail id) :starred))))
(defun move-mails (ids destination)
  (dolist (id ids) (set-mail-property id :mailbox destination))
  (setf *detail* nil *selected* nil))
(defun start-compose (&optional reply)
  (setf *reply-to* reply *draft-id* nil *composing* t *body* "" *notice* nil
        *recipient* (if reply (getf (mail reply) :sender) "")
        *subject* (if reply (concatenate 'string "Re: " (getf (mail reply) :subject)) "")))
(defun store-composition (box)
  (unless *composing* (return-from store-composition nil))
  (when (or (eq box :drafts) (and (plusp (length (string-trim " " *recipient*))) (plusp (length (string-trim " " *body*)))))
    (let ((entry (list :id (or *draft-id* (1+ (reduce #'max *mails* :key (lambda (m) (getf m :id)) :initial-value 0)))
                       :sender "You" :recipient *recipient* :avatar "avatar_10.jpg"
                       :subject (if (zerop (length *subject*)) "(No subject)" *subject*)
                       :body *body* :reply-to *reply-to* :mailbox box :read t :time "Just now")))
      (when *draft-id* (setf *mails* (remove *draft-id* *mails* :key (lambda (m) (getf m :id)))))
      (push entry *mails*)
      (when (and *reply-to* (eq box :sent))
        (set-mail-property *reply-to* :replies (append (getf (mail *reply-to*) :replies) (list entry)))))
    (setf *composing* nil *draft-id* nil *detail* nil *reply-to* nil *selected* nil *query* ""
          *notice* (if (eq box :sent) "Saved to sample Sent. No email was transmitted." "Draft saved on this screen session."))))
(defun back ()
  (cond (*drawer* (setf *drawer* nil)) (*composing* (store-composition :drafts))
        (*detail* (setf *detail* nil)) (*selected* (setf *selected* nil))
        (t (setf *mailbox* :inbox *query* ""))))
(defun action (id icon label callback &rest props)
  (apply #'ui :icon-button :id id :icon icon :description label :on-click callback props))
(defun mail-card (m)
  (let ((id (getf m :id)))
    (ui :card :id (format nil "mail-~D" id) :fill-width t
        :container-color (if (member id *selected*) :primary-container :surface-variant) :children
      (list (ui :row :padding 12 :spacing 12 :children
              (list (ui :image :id (format nil "select-~D" id) :asset (getf m :avatar) :width 44 :height 44 :radius 22 :scale :crop
                        :description (if (member id *selected*) "Deselect message" "Select message")
                        :on-click (lambda () (setf *selected* (if (member id *selected*) (remove id *selected*) (cons id *selected*)))))
                    (ui :column :id (format nil "open-~D" id) :weight 1 :spacing 5 :on-click (lambda () (open-mail id)) :children
                      (list (ui :text :text (format nil "~A · ~A" (getf m :sender) (getf m :time)) :style :label)
                            (ui :text :text (getf m :subject) :font-weight (if (getf m :read) :normal :bold) :max-lines 2)
                            (ui :text :text (getf m :body) :max-lines 2 :color :muted)))
                    (action (format nil "star-~D" id) :star "Toggle star" (lambda () (toggle-star id)) :color (if (getf m :starred) :primary :muted))))))))
(defun mailbox-view ()
  (ui :column :fill t :spacing 8 :children
    (append
      (list (ui :text-field :id "search" :value *query* :label "Search all sample mail" :fill-width t :padding-horizontal 16
                :on-change (lambda (s) (setf *query* s)))
            (ui :text :text "Local sample mailbox" :style :label :padding-horizontal 20 :color :muted))
      (when *notice* (list (ui :text :text *notice* :padding 12 :color :primary)))
      (when *selected*
        (list (ui :row :spacing 8 :padding-horizontal 16 :children
                (list (ui :text :text (format nil "~D selected" (length *selected*)) :weight 1)
                      (action "archive-selected" :down "Archive selected" (lambda () (move-mails *selected* :archive)))
                      (action "trash-selected" :delete "Trash selected" (lambda () (move-mails *selected* :trash)))))))
      (list (ui :lazy-column :id (format nil "mailbox-~(~A~)" *mailbox*) :weight 1 :fill-width t :spacing 10 :content-padding 16 :children
              (let ((items (visible-mails)))
                (if items (mapcar #'mail-card items) (list (ui :text :text "No messages here." :padding 24)))))))))
(defun body-view (m key)
  (ui :column :id key :spacing 16 :children
    (append
      (list (ui :text :text (getf m :sender) :style :title)
            (ui :text :text (getf m :time) :style :label :color :muted)
            (ui :text :text (if (zerop (length (getf m :body))) "(Empty message)" (getf m :body))))
      (loop for (asset description) in (getf m :attachments) collect
        (ui :image :asset asset :description description :fill-width t :height 220 :scale :crop :radius 16)))))
(defun detail-view ()
  (let ((m (mail *detail*)))
    (ui :lazy-column :id (format nil "thread-~D" *detail*) :fill t :content-padding 20 :spacing 20 :children
      (append (list (ui :text :text (getf m :subject) :style :headline)
                    (body-view m "original-body"))
              (loop for reply in (getf m :replies) collect (body-view reply (format nil "reply-~D" (getf reply :id))))
              (list (ui :button :id "reply" :text "Reply locally" :on-click (lambda () (start-compose *detail*))))))))
(defun compose-view ()
  (ui :lazy-column :id "composer" :fill t :content-padding 20 :spacing 16 :children
    (list (ui :text :text "Local draft · this sample does not send email" :color :muted :style :label)
          (ui :text-field :id "to" :label "To" :value *recipient* :fill-width t :on-change (lambda (s) (setf *recipient* s)))
          (ui :text-field :id "subject" :label "Subject" :value *subject* :fill-width t :on-change (lambda (s) (setf *subject* s)))
          (ui :text-field :id "body" :label "Message" :value *body* :single-line nil :height 240 :fill-width t :on-change (lambda (s) (setf *body* s)))
          (ui :button :id "send-local" :text "Save to sample Sent" :on-click (lambda () (store-composition :sent)))
          (ui :outlined-button :id "save-draft" :text "Save draft" :on-click (lambda () (store-composition :drafts))))))
(defun view ()
  (let ((detail *detail*))
  (ui :theme :id "screen" :dark *dark* :primary (if *dark* "#a8caff" "#315f93")
      :on-back #'back :back-enabled (not (null (or *drawer* detail *composing* *selected* (not (eq *mailbox* :inbox)) (plusp (length *query*))))) :children
    (list (ui :navigation-drawer :id "drawer" :open *drawer* :on-dismiss (lambda () (setf *drawer* nil)) :children
            (append
              (list (ui :text :slot :drawer :text "Reply" :style :headline :padding 24))
              (loop for (box label) on '(:inbox "Inbox" :starred "Starred" :sent "Sent" :drafts "Drafts" :archive "Archive" :trash "Trash") by #'cddr collect
                (let ((destination box))
                  (ui :drawer-item :id (format nil "box-~(~A~)" box) :text label :icon :more :selected (eq box *mailbox*)
                      :on-click (lambda () (setf *mailbox* destination *detail* nil *selected* nil *query* "" *drawer* nil)))))
              (list (ui :scaffold :fill t :children
                      (append
                        (list (ui :top-bar :slot :top :text (cond (*composing* "New message") (detail "Reply") (t (string-capitalize *mailbox*))) :children
                                (append
                                  (list (action "menu-back" (if (or detail *composing*) :back :menu) "Back or open mailboxes"
                                                (if (or detail *composing*) #'back (lambda () (setf *drawer* t))) :slot :navigation))
                                  (when detail
                                    (list (action "star" :star "Toggle star" (lambda () (toggle-star detail)) :color (if (getf (mail detail) :starred) :primary :muted))
                                          (action "archive" :down "Archive" (lambda () (move-mails (list detail) :archive)))
                                          (action "trash" :delete "Move to trash" (lambda () (move-mails (list detail) :trash)))))
                                  (unless (or detail *composing*) (list (action "theme" :settings "Toggle theme" (lambda () (setf *dark* (not *dark*)))))))))
                        (unless (or detail *composing*)
                          (list (ui :fab :slot :fab :id "compose" :text "Compose" :on-click #'start-compose)))
                        (list (cond (*composing* (compose-view)) (detail (detail-view)) (t (mailbox-view)))))))))))))

(defparameter *saved-variables*
  '(*mails* *mailbox* *composing* *reply-to* *draft-id* *recipient* *subject* *body* *dark*))

(in-package :cl-user)
(defun android-main (window)
  (declare (ignore window))
  (evergreen-compose:run-compose-app #'evergreen-reply:view :state evergreen-reply::*saved-variables*))
