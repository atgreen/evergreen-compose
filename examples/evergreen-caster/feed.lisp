;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(in-package :evergreen-caster)
(defvar *feed-url* "https://feeds.zencastr.com/f/8BBgc1Lp.rss")
(defvar *live-episodes* nil)
(defvar *next-live-id* 1000)
(defvar *refreshing* nil)
(defvar *feed-status* "Add an RSS feed to stream real episodes.")
(defvar *updated* nil)
(defun all-episodes () (append *live-episodes* *episodes*))
(defun receive-episodes (url items status failure)
  (declare (ignore status))
  (setf *refreshing* nil)
  (if failure (setf *feed-status* (concatenate 'string "Refresh failed; cached episodes remain available. " failure))
      (let ((incoming nil))
        (dolist (item items)
          (when (plusp (length (getf item :audio "")))
            (let* ((key (concatenate 'string url "|" (getf item :key)))
                   (old (find key *live-episodes* :key (lambda (e) (getf e :key)) :test #'equal)))
              (unless (find key incoming :key (lambda (e) (getf e :key)) :test #'equal)
                (push (list :id (or (getf old :id) (incf *next-live-id*)) :key key :show 4
                            :title (getf item :title) :description (subseq (getf item :summary) 0 (min 1500 (length (getf item :summary))))
                            :date (getf item :date) :audio (getf item :audio) :link (getf item :link)
                            :seconds 0 :transcript (getf item :summary)) incoming)))))
        (if (null incoming) (setf *feed-status* "This feed has no playable HTTPS audio or video enclosures.")
            (progn
              (setf incoming (nreverse incoming))
              (setf *live-episodes* (append incoming (remove-if
                        (lambda (e) (find (getf e :key) incoming :key (lambda (i) (getf i :key)) :test #'equal)) *live-episodes*))
                    *updated* (get-universal-time)
                    *feed-status* (format nil "~D live episodes. Streaming uses your connection." (length incoming))))))))
(defun refresh-podcast ()
  (unless *refreshing*
    (let ((url (string-trim '(#\Space #\Tab #\Newline) *feed-url*)))
      (setf *refreshing* t *feed-status* "Refreshing podcast…")
      (handler-case (evergreen-compose:fetch-feed url (lambda (items status failure) (receive-episodes url items status failure)))
        (error (e) (receive-episodes url nil 0 (princ-to-string e)))))))
(defun feed-settings ()
  (ui :column :spacing 8 :children
    (list (ui :text :text "Live podcast feed" :style :title)
          (ui :text :text "Starts with defn, a Clojure podcast. Paste another RSS or Atom URL to change it." :style :label)
          (ui :text-field :id "feed-url" :label "HTTPS feed URL" :value *feed-url* :fill-width t
              :on-change (lambda (text) (setf *feed-url* text)))
          (ui :button :id "refresh-podcast" :text "Refresh podcast" :enabled (not *refreshing*) :on-click #'refresh-podcast)
          (ui :text :text *feed-status* :style :label))))

(defun start-podcast ()
  (setf *live-episodes* (loop for entry in *live-episodes* for index from 0
                              when (or (< index 100) (member (getf entry :id) *favorites*)
                                       (member (getf entry :id) *queue*)) collect entry))
  (refresh-podcast))
