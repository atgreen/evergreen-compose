;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; Planet Lisp — live stories, an offline cache, and a quiet reading view.
;;;;
;;;; The shared runtime fetches RSS in the background. Completion callbacks
;;;; update these Lisp values; the next view reflects the result. Feed text
;;;; stays plain text, and the original publisher is always a tap away.

(in-package :evergreen-news)

;;; Feed state

(defvar *live-posts* nil)
(defvar *next-live-id* 1000)
(defvar *refreshing* nil)
(defvar *feed-status* "Refresh to load Planet Lisp.")
(defvar *feed-error* nil)
(defvar *updated* nil)

;;; Refresh and cache

(defun receive-news (items status failure)
  (declare (ignore status))
  (setf *refreshing* nil
        *feed-error* failure)
  (if failure
      (setf *feed-status* "Couldn't refresh. Your saved stories are still here.")
      (let ((incoming nil))
        ;; Match the publisher's key before allocating an ID, so bookmarks
        ;; keep pointing to the same story when its title or text changes.
        (dolist (item items)
          (let* ((key (getf item :key))
                 (old (find key *live-posts*
                            :key (lambda (post) (getf post :key))
                            :test #'equal))
                 (id (or (getf old :id) (incf *next-live-id*))))
            (unless (find key incoming
                          :key (lambda (post) (getf post :key))
                          :test #'equal)
              (push (list :id id
                          :key key
                          :title (getf item :title)
                          :link (getf item :link)
                          :author (let ((author (getf item :author)))
                                    (if (equal author "") "Planet Lisp" author))
                          :date (getf item :date)
                          :summary (getf item :summary)
                          :minutes 1)
                    incoming))))
        (setf incoming (nreverse incoming))
        ;; Retain older rows during this session: a queued tap may still
        ;; refer to one, even after the publisher removes it from the feed.
        (setf *live-posts*
              (append incoming
                      (remove-if
                       (lambda (post)
                         (find (getf post :key) incoming
                               :key (lambda (entry) (getf entry :key))
                               :test #'equal))
                       *live-posts*))
              *updated* (get-universal-time)
              *feed-status* "Up to date · Available offline"))))

(defun refresh-news ()
  (unless *refreshing*
    (setf *refreshing* t
          *feed-error* nil
          *feed-status* "Updating stories…")
    (handler-case
        (evergreen-compose:fetch-feed "https://planet.lisp.org/rss20.xml" #'receive-news)
      (error (condition)
        (receive-news nil 0 (princ-to-string condition))))))

;;; Story presentation

(defun title-separator (entry)
  ;; Planet Lisp commonly puts the author before a colon in the title.
  ;; Only infer a byline when RSS did not supply one separately.
  (when (equal (getf entry :author) "Planet Lisp")
    (let ((separator (position #\: (getf entry :title))))
      (when (and separator (< 0 separator 65)) separator))))

(defun story-author (entry)
  (let ((separator (title-separator entry)))
    (if separator
        (subseq (getf entry :title) 0 separator)
        (getf entry :author))))

(defun story-title (entry)
  (let ((separator (title-separator entry)))
    (if separator
        (string-left-trim " " (subseq (getf entry :title) (1+ separator)))
        (getf entry :title))))

(defun story-date (date)
  (let ((comma (position #\, date)))
    (cond
      ;; RSS: "Sat, 19 Sep 2026 17:55:05 GMT".
      ((and comma (>= (length date) (+ comma 13)))
       (string-trim " " (subseq date (+ comma 2) (+ comma 13))))
      ;; Atom: keep the date portion of an ISO timestamp.
      ((and (>= (length date) 10) (char= (char date 4) #\-))
       (subseq date 0 10))
      (t date))))

(defun article-paragraphs (text)
  ;; Split on blank lines, preserving single line breaks in quotations/code.
  ;; Separate lazy-list items make long articles easier to scroll and read.
  (let ((paragraphs nil)
        (start 0)
        (length (length text)))
    (loop for index from 0 below length
          when (and (char= (char text index) #\Newline)
                    (< (1+ index) length)
                    (char= (char text (1+ index)) #\Newline))
            do (let ((paragraph (string-trim '(#\Space #\Newline #\Return)
                                               (subseq text start index))))
                 (unless (zerop (length paragraph)) (push paragraph paragraphs)))
               (setf start (1+ index)))
    (let ((paragraph (string-trim '(#\Space #\Newline #\Return)
                                 (subseq text start))))
      (unless (zerop (length paragraph)) (push paragraph paragraphs)))
    (nreverse paragraphs)))

(defun story-excerpt (entry)
  (let ((text (getf entry :summary)))
    (substitute #\Space #\Newline (subseq text 0 (min 260 (length text))))))

(defun story-card (entry &key featured (section "live"))
  (let* ((id (getf entry :id))
         (key (format nil "~A-~D" section id))
         (ink (if featured "#f4f6ed" :on-surface))
         (muted (if featured "#c4dacb" :muted)))
    (ui :card :id key :fill-width t :radius 20
        :container-color (if featured "#234b38" (if *dark* "#1b2a22" "#ffffff"))
        :children
        (list
         (ui :column :padding 20 :spacing 14 :children
             (list
              (ui :row :fill-width t :spacing 8 :children
                  (list
                   (ui :text :text (if featured "FEATURED STORY" (story-author entry))
                       :style :label :color muted :weight 1)
                   (action (concatenate 'string "save-" key) :star
                           (if (bookmarked-p id) "Unsave article" "Save article")
                           (lambda () (toggle-bookmark id))
                           :color (if (bookmarked-p id) (if featured "#e9d79a" :primary) muted))))
              (ui :column :id (concatenate 'string "open-" key)
                  :fill-width t :spacing 12
                  :on-click (lambda () (setf *article* id))
                  :children
                  (list
                   (ui :text :text (story-title entry)
                       :style (if featured :headline :title)
                       :font-weight :bold :color ink :max-lines 4)
                   (ui :text :text (story-excerpt entry)
                       :font-size 14 :color muted :max-lines (if featured 3 2))
                   (ui :text :style :label :color muted
                       :text (if featured
                                 (format nil "~A  ·  ~A" (story-author entry)
                                         (story-date (getf entry :date)))
                                 (story-date (getf entry :date))))))))))))

;;; The community feed

(defun live-news ()
  (ui :lazy-column :id "live-news" :fill t :content-padding 20 :spacing 18
      :children
      (append
       (list
        (ui :column :spacing 8 :padding-vertical 8 :children
            (list
             (ui :text :text "THE LISP COMMUNITY" :style :label :color :primary)
             (ui :text :text "Planet Lisp" :style :headline :font-size 34 :font-weight :bold)
             (ui :text :text "Ideas, projects, and notes from around the Lisp world."
                 :color :muted)))
        (ui :row :fill-width t :spacing 12 :children
            (list
             (ui :column :weight 1 :spacing 4 :children
                 (list
                  (ui :text :text (if *refreshing* "Updating…" "Latest dispatches")
                      :font-weight :bold)
                  (ui :text :text (if *updated* "Ready to read offline" "A little reading for your REPL break")
                      :style :label :color :muted)))
             (ui :text-button :id "refresh-news" :text "Refresh"
                 :enabled (not *refreshing*) :on-click #'refresh-news)))
        (when *feed-error*
          (ui :card :container-color :primary-container :children
              (list (ui :text :text *feed-status* :padding 16))))
        (when *live-posts* (story-card (first *live-posts*) :featured t)))
       (loop for entry in (rest *live-posts*) collect (story-card entry))
       (unless *live-posts*
         (list (ui :text :text (if *refreshing* "Finding your next good read…"
                                  "No stories yet. Tap Refresh to try again.")
                   :padding-vertical 24 :color :muted)))
       (list (ui :text :text "Collected by Planet Lisp. Written by the community."
                 :style :label :color :muted :padding-vertical 12)))))

;;; The reader

(defun live-article (entry)
  (let ((id (getf entry :id)))
    (ui :lazy-column :id (format nil "live-article-~D" id)
        :fill t :content-padding 24 :spacing 20
        :children
        (append
         (list
          (ui :text :text "FROM PLANET LISP" :style :label :color :primary)
          (ui :text :text (story-title entry) :style :headline :font-weight :bold)
          (ui :row :spacing 12 :children
              (list
               (ui :box :width 44 :height 44 :radius 22
                   :background :primary-container :alignment :center
                   :children
                   (list (ui :text :text "λ" :font-size 24 :color :primary)))
               (ui :column :spacing 4 :weight 1 :children
                   (list
                    (ui :text :text (story-author entry) :font-weight :medium)
                    (ui :text :text (story-date (getf entry :date))
                        :style :label :color :muted)))))
          (ui :divider))
         (loop for paragraph in (article-paragraphs (getf entry :summary))
               for index from 0
               collect (ui :text :id (format nil "article-~D-paragraph-~D" id index)
                           :text paragraph :font-size 16))
         (list
          (ui :divider)
          (ui :text :text "Continue the conversation at the original source."
              :color :muted :style :label)
          (ui :outlined-button :id "original" :text "Visit original article"
              :fill-width t :enabled (plusp (length (getf entry :link)))
              :on-click (lambda () (evergreen-compose:open-url (getf entry :link)))))))))

;;; Startup

(defun start-news ()
  ;; Prune before the first view, when no queued taps can reference old rows.
  ;; Bookmarked stories survive even when they fall outside the recent cache.
  (setf *live-posts*
        (loop for entry in *live-posts* for index from 0
              when (or (< index 100) (member (getf entry :id) *bookmarks*))
                collect entry)
        *page* :live)
  (refresh-news))
