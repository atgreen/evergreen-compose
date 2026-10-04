;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(in-package :evergreen-compose)

(defun encode-app-state (symbols)
  "Serialize only the application's explicitly selected variables."
  (let ((*package* (find-package :keyword)) (*print-readably* t) (*print-pretty* nil))
    (prin1-to-string
      (list :version 1 :values
            (mapcar (lambda (symbol)
                      (list (package-name (symbol-package symbol)) (symbol-name symbol)
                            (symbol-value symbol))) symbols)))))

(defun restore-app-state (text symbols)
  "Restore versioned data into the whitelist SYMBOLS; malformed data is ignored."
  (when (and text (plusp (length text)))
    (handler-case
        (let* ((*read-eval* nil) (*package* (find-package :keyword))
               (state (read-from-string text)) (entries (getf state :values)))
          (when (and (eql 1 (getf state :version)) (listp entries)
                     (every (lambda (entry) (and (listp entry) (= 3 (length entry))
                                                (stringp (first entry)) (stringp (second entry)))) entries))
            (dolist (symbol symbols)
              (let ((entry (find-if (lambda (entry)
                                     (and (equal (first entry) (package-name (symbol-package symbol)))
                                          (equal (second entry) (symbol-name symbol)))) entries)))
                (when entry (set symbol (third entry)))))
            t))
      (error () nil))))

(defvar *service-submit* nil)
(defvar *service-requests* (make-hash-table))
(defvar *service-sequence* 0)
(defun request-service (url kind callback)
  (unless *service-submit* (error "Network services require a running Compose app"))
  (when (>= (hash-table-count *service-requests*) 8) (error "Too many pending requests"))
  (let ((id (incf *service-sequence*)))
    (setf (gethash id *service-requests*) callback)
    (handler-case (funcall *service-submit* id url kind)
      (error (e) (remhash id *service-requests*) (error e)))
    id))
(defun http-get (url callback)
  "Asynchronously fetch HTTPS text. CALLBACK receives (body status error) on the
Lisp worker. Errors have a NIL body; transport failures have status zero.
Requests are limited to 2 MiB and bounded timeouts. Declare INTERNET in the APK."
  (request-service url "text" callback))
(defun fetch-feed (url callback)
  "Fetch RSS/Atom. CALLBACK receives (items status error); each item is a plist
with :KEY :TITLE :LINK :SUMMARY :AUTHOR :DATE :AUDIO. HTML is reduced to text."
  (request-service url "feed"
    (lambda (body status failure)
      (let ((items nil))
        (when body
          (handler-case (let ((*read-eval* nil)) (setf items (read-from-string body)))
            (error () (setf failure "Invalid feed response"))))
        (funcall callback items status failure)))))
(defun dispatch-service-result (result)
  (destructuring-bind (id status body failure) result
    (let ((callback (gethash id *service-requests*)))
      (when callback
        (remhash id *service-requests*)
        (funcall callback body status failure)
        (invalidate)))))

(defvar *open-url* nil)
(defun open-url (url)
  "Open an HTTP(S) article in the user's browser."
  (when *open-url* (funcall *open-url* url)))
