;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(in-package :evergreen-compose)

(defun test-sample-primitives ()
  (let ((session (make-compose-session)) (backs 0))
    (check-true "Application Back callbacks cross the protocol"
      (handler-case
          (progn
            (compose-snapshot session (ui :theme :id "screen" :on-back (lambda () (incf backs))))
            (compose-dispatch session '(1 "screen" "back" ""))
            (= backs 1))
        (error () nil))))
  (check-true "Vector drawing primitives cross the protocol"
    (handler-case
        (search "M0 0L100 100"
          (compose-snapshot (make-compose-session)
            (ui :canvas :width 100 :height 100 :view-width 100 :view-height 100
              :children (list (ui :path :data "M0 0L100 100" :stroke "#ff0000" :stroke-width 2)))))
      (error () nil))))

(defun sample-event (session view id kind &optional (value ""))
  (compose-dispatch session (list (1+ (compose-session-ack session)) id kind value))
  (compose-snapshot session (funcall view)))

(defun test-evergreen-news ()
  (load (merge-pathnames "../examples/evergreen-news/app.lisp" *tests-directory*))
  (let ((view (symbol-function (find-symbol "VIEW" :evergreen-news)))
        (reset (symbol-function (find-symbol "RESET" :evergreen-news)))
        (session (make-compose-session)))
    (funcall reset)
    (check-true "Evergreen News displays the Common Lisp highlighted story"
      (progn (compose-snapshot session (funcall view))
             (sample-has-text "A small app, written in Common Lisp" (funcall view))))
    (check-true "Evergreen News opens a full article"
      (search "article-body" (sample-event session view "featured" "click")))
    (sample-event session view "bookmark" "click")
    (sample-event session view "screen" "back")
    (check-true "Evergreen News bookmark survives leaving the article"
      (member 6 (symbol-value (find-symbol "*BOOKMARKS*" :evergreen-news))))
    (sample-event session view "menu" "click")
    (check-true "Evergreen News opens Interests from the drawer"
      (search "Topics" (sample-event session view "interests" "click")))
    (check-true "Evergreen News interests tabs change content"
      (search "Sample editor / Common Lisp" (sample-event session view "people" "click")))
    (check-true "Evergreen News subscriptions update"
      (search "\"checked\":true" (sample-event session view "interest-0" "change" "true")))))

(defun test-evergreen-chat ()
  (load (merge-pathnames "../examples/evergreen-chat/app.lisp" *tests-directory*))
  (let* ((package (find-package :evergreen-chat))
         (view (symbol-function (find-symbol "VIEW" package)))
         (messages (symbol-function (find-symbol "CHANNEL-MESSAGES" package)))
         (session (make-compose-session)))
    (funcall (find-symbol "RESET" package))
    (compose-snapshot session (funcall view))
    (let ((count (length (funcall messages))))
      (sample-event session view "draft" "change" "   ")
      (sample-event session view "send" "click")
      (check "Chat ignores a blank message" count (length (funcall messages)))
      (sample-event session view "draft" "change" "Hello from Common Lisp")
      (check-true "Chat send appears in timeline"
        (search "Hello from Common Lisp" (sample-event session view "send" "click")))
      (check "Chat appends exactly one message" (1+ count) (length (funcall messages)))
      (check "Chat clears the sent draft" "" (symbol-value (find-symbol "*DRAFT*" package))))
    (sample-event session view "menu" "click")
    (sample-event session view "channel-libraries" "click")
    (check-true "Chat keeps channel histories separate"
      (not (find "Hello from Common Lisp" (funcall messages) :key (lambda (m) (getf m :text)) :test #'equal)))
    (sample-event session view "attach" "click")
    (check-true "Chat sends a sticker attachment"
      (search "sticker.png" (sample-event session view "attach-sticker" "click")))
    (sample-event session view "profile-ada" "click")
    (check "Chat profile enables native Back with a boolean" t
      (getf (second (funcall view)) :back-enabled))
    (check-true "Chat opens the author profile"
      (search "Common Lisp enthusiast" (compose-snapshot (make-compose-session) (funcall view))))
    (check-true "Chat Back returns to its channel"
      (search "timeline" (sample-event session view "screen" "back")))))

(defun test-evergreen-snack ()
  (load (merge-pathnames "../examples/evergreen-snack/app.lisp" *tests-directory*))
  (let* ((package (find-package :evergreen-snack))
         (view (symbol-function (find-symbol "VIEW" package)))
         (total (symbol-function (find-symbol "CART-TOTAL" package)))
         (session (make-compose-session)))
    (funcall (find-symbol "RESET" package))
    (compose-snapshot session (funcall view))
    (check "Snack totals the initial cart in cents" 5444 (funcall total))
    (sample-event session view "open-picks-1" "click")
    (check "Snack detail enables native Back with a boolean" t
      (getf (second (funcall view)) :back-enabled))
    (sample-event session view "quantity" "change" "2")
    (sample-event session view "favorite" "click")
    (sample-event session view "add-cart" "click")
    (check "Snack adds the chosen quantity" 6042 (funcall total))
    (check-true "Snack remembers a favorite"
      (member 1 (symbol-value (find-symbol "*FAVORITES*" package))))
    (sample-event session view "added" "confirm")
    (sample-event session view "screen" "back")
    (sample-event session view "nav-search" "click")
    (sample-event session view "query" "change" "APPLE")
    (check "Snack search is case insensitive" 5
      (length (funcall (find-symbol "FILTERED-SNACKS" package))))
    (sample-event session view "query" "change" "no-such-snack")
    (check-true "Snack shows an empty search result"
      (search "No snacks found" (compose-snapshot (make-compose-session) (funcall view))))
    (sample-event session view "nav-cart" "click")
    (sample-event session view "remove-1" "click")
    (check "Snack removal updates the total" 5444 (funcall total))
    (sample-event session view "cart-5" "change" "1")
    (check "Snack quantity updates the total" 4945 (funcall total))
    (check "Snack quantity keeps the product in its original position" '(5 7 9)
      (mapcar #'car (symbol-value (find-symbol "*CART*" package))))
    (check-true "Snack checkout is explicitly a demo"
      (search "No order was placed" (sample-event session view "checkout" "click")))))

(defun test-reply ()
  (load (merge-pathnames "../examples/reply/app.lisp" *tests-directory*))
  (let* ((package (find-package :evergreen-reply))
         (view (symbol-function (find-symbol "VIEW" package)))
         (mail (symbol-function (find-symbol "MAIL" package)))
         (session (make-compose-session)))
    (funcall (find-symbol "RESET" package))
    (compose-snapshot session (funcall view))
    (sample-event session view "select-0" "click")
    (check "Reply selection enables native Back with a boolean" t
      (getf (second (funcall view)) :back-enabled))
    (sample-event session view "screen" "back")
    (check-true "Reply opens the full mail body"
      (search "neighborhood" (sample-event session view "open-1" "click")))
    (check-true "Reply marks opened mail read" (getf (funcall mail 1) :read))
    (sample-event session view "star" "click")
    (check-true "Reply stars a message" (getf (funcall mail 1) :starred))
    (compose-dispatch session (list (1+ (compose-session-ack session)) "archive" "click" ""))
    (compose-dispatch session (list (1+ (compose-session-ack session)) "archive" "click" ""))
    (compose-snapshot session (funcall view))
    (check "Reply archives the selected message" :archive (getf (funcall mail 1) :mailbox))
    (sample-event session view "compose" "click")
    (sample-event session view "to" "change" "friend@example.com")
    (sample-event session view "subject" "change" "Common Lisp meetup")
    (sample-event session view "body" "change" "Bring your REPL!")
    (sample-event session view "send-local" "click")
    (check-true "Reply stores sample sent mail locally"
      (find "Common Lisp meetup" (symbol-value (find-symbol "*MAILS*" package))
            :key (lambda (m) (getf m :subject)) :test #'equal))
    (sample-event session view "search" "change" "PARIS")
    (check "Reply search is case insensitive" 1
      (length (funcall (find-symbol "VISIBLE-MAILS" package))))
    (sample-event session view "compose" "click")
    (sample-event session view "to" "change" "draft@example.com")
    (sample-event session view "subject" "change" "Draft to resume")
    (sample-event session view "body" "change" "Keep these words")
    (sample-event session view "save-draft" "click")
    (let* ((mails (symbol-value (find-symbol "*MAILS*" package)))
           (draft (find "Draft to resume" mails :key (lambda (m) (getf m :subject)) :test #'equal)))
      (sample-event session view "menu-back" "click")
      (sample-event session view "box-drafts" "click")
      (sample-event session view (format nil "open-~D" (getf draft :id)) "click")
      (check "Reply resumes a draft's body" "Keep these words" (symbol-value (find-symbol "*BODY*" package)))
      (sample-event session view "send-local" "click")
      (check "Reply sends a draft without leaving a duplicate" 1
        (count "Draft to resume" (symbol-value (find-symbol "*MAILS*" package)) :key (lambda (m) (getf m :subject)) :test #'equal)))
    (funcall (find-symbol "RESET" package))
    (compose-snapshot session (funcall view))
    (sample-event session view "open-1" "click")
    (sample-event session view "box-sent" "click")
    (check "Reply changing mailbox closes the old message" nil
      (symbol-value (find-symbol "*DETAIL*" package)))
    (sample-event session view "box-inbox" "click")
    (sample-event session view "open-1" "click")
    (sample-event session view "reply" "click")
    (sample-event session view "body" "change" "A reply saved for later")
    (sample-event session view "save-draft" "click")
    (let ((id (getf (first (symbol-value (find-symbol "*MAILS*" package))) :id)))
      (sample-event session view "box-drafts" "click")
      (sample-event session view (format nil "open-~D" id) "click")
      (sample-event session view "send-local" "click")
      (check "Reply resumed draft stays in the original thread" 1
        (length (getf (funcall mail 1) :replies))))))

(defun test-evergreen-lagged ()
  (load (merge-pathnames "../examples/evergreen-lagged/app.lisp" *tests-directory*))
  (let* ((package (find-package :evergreen-lagged))
         (view (symbol-function (find-symbol "VIEW" package)))
         (duration (symbol-function (find-symbol "SLEEP-MINUTES" package)))
         (session (make-compose-session)))
    (funcall (find-symbol "RESET" package))
    (check "Sleep totals do not double count overlapping periods" 90
      (funcall duration '(:periods ((1320 1380 :light) (1350 1410 :rem) (1410 1430 :awake)))))
    (compose-snapshot session (funcall view))
    (check-true "Lagged renders sleep data"
      (sample-has-text "Sleep timeline" (funcall view)))
    (sample-event session view "period-day" "click")
    (check "Lagged Day selects one night" 1 (length (funcall (find-symbol "SELECTED-NIGHTS" package))))
    (sample-event session view "period-week" "click")
    (check "Lagged Week selects seven nights" 7 (length (funcall (find-symbol "SELECTED-NIGHTS" package))))
    (sample-event session view "night-7" "click")
    (check-true "Lagged expands a night into sleep stages"
      (sample-has-text "Deep" (funcall view)))
    (check "Lagged imports all heart rate samples" 176
      (length (symbol-value (find-symbol "*HEART-READINGS*" package))))))

(defun sample-has-text (text tree)
  (or (equal text (getf (second tree) :text))
      (some (lambda (child) (sample-has-text text child)) (getf (second tree) :children))))

(defun test-evergreen-caster ()
  (load (merge-pathnames "../examples/evergreen-caster/app.lisp" *tests-directory*))
  (let* ((package (find-package :evergreen-caster))
         (view (symbol-function (find-symbol "VIEW" package)))
         (session (make-compose-session)))
    (funcall (find-symbol "RESET" package))
    (compose-snapshot session (funcall view))
    (sample-event session view "show-1" "click")
    (sample-event session view "follow" "click")
    (check-true "Caster follows a show" (member 1 (symbol-value (find-symbol "*FOLLOWING*" package))))
    (sample-event session view "episode-1" "click")
    (sample-event session view "queue" "click")
    (sample-event session view "queue" "click")
    (check "Caster queues an episode only once" '(1) (symbol-value (find-symbol "*QUEUE*" package)))
    (sample-event session view "favorite" "click")
    (check-true "Caster favorites an episode" (member 1 (symbol-value (find-symbol "*FAVORITES*" package))))
    (check-true "Caster plays the real bundled audio"
      (search "asset:///episode_1.wav" (sample-event session view "play" "click")))
    (let ((first-player (sample-node-id :media-player (funcall view))))
      (sample-event session view "play" "click")
      (check-true "Caster explicit Play creates a fresh playback command"
        (not (equal first-player (sample-node-id :media-player (funcall view))))))
    (sample-event session view (sample-node-id :media-player (funcall view)) "error" "Decoder test failure")
    (check-true "Caster exposes playback errors" (sample-has-text "Decoder test failure" (funcall view)))
    (sample-event session view "screen" "back")
    (sample-event session view "screen" "back")
    (sample-event session view "nav-discover" "click")
    (sample-event session view "query" "change" "REPL")
    (check-true "Caster searches episode titles"
      (find 1 (funcall (find-symbol "FILTERED-EPISODES" package)) :key (lambda (e) (getf e :id))))))

(defun sample-node-id (type tree)
  (if (eq type (first tree)) (getf (second tree) :id)
      (some (lambda (child) (when child (sample-node-id type child))) (getf (second tree) :children))))
