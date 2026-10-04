;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

;;;; State that outlives the process.
;;;;
;;;; Android destroys an Activity whenever it likes -- a configuration change,
;;;; or simply reclaiming memory from an app the user is not looking at -- and
;;;; recreates it later as though nothing had happened. Everything in this
;;;; image goes with it: every special variable, every closure, the whole
;;;; interpreter. What comes back is one blob of bytes the previous instance
;;;; asked to keep.
;;;;
;;;; So this is not a cache and not a preference store. It is the answer to
;;;; "what did the user have in front of them", and it is the difference between
;;;; an app that survives a phone call and one that starts over.
(in-package :evergreen-compose)

(defvar *state-store*
  (let ((held nil))
    (list :read (lambda () held)
          :write (lambda (text) (setf held text))))
  "(:READ fn :WRITE fn) -- where SAVE-STATE puts its string and RESTORE-STATE
looks for it.

The default pair holds the string in this image, which is exactly as durable as
the image and therefore useless on a phone -- but it means SAVE-STATE and
RESTORE-STATE work, and can be tested, with no platform at all. SRC/ANDROID-HOST.LISP
replaces it with the real one.")

(defun state-call (key &rest arguments)
  (let ((f (getf *state-store* key)))
    (when f (apply f arguments))))

(defun save-state (object)
  "Keep OBJECT for the next instance of this application. Returns OBJECT.

Written with PRIN1, so what may be saved is what can be printed READABLY: lists,
numbers, strings, keywords, symbols, characters. Not a closure, not a hash table,
not a laid-out view. That is a real restriction and it is the right one -- the
process that reads this back does not share a heap with the one that wrote it,
so anything whose identity matters could not survive anyway.

Call it when the state worth keeping changes, not once per frame: printing is
not free, and Android reads the result only when the Activity is stopping."
  (state-call :write (let ((*print-readably* nil) (*print-pretty* nil))
                       (prin1-to-string object)))
  object)

(defun restore-state (&optional default)
  "What the previous instance saved, or DEFAULT.

DEFAULT covers three cases that an application cannot tell apart and should not
try to: a genuine cold start, a fresh install, and a saved blob this version can
no longer read. The last one is why a read error is not signalled -- an app that
refuses to start because yesterday's build wrote a different shape is worse than
one that starts empty.

*READ-EVAL* is bound off. The blob is our own, but it has been out of this
process and through the platform, and #. in a restore path is a door that has no
reason to be open."
  (let ((text (state-call :read)))
    (if (and text (plusp (length text)))
        (handler-case
            (let ((*read-eval* nil))
              (multiple-value-bind (object position) (read-from-string text)
                (declare (ignore position))
                object))
          (error () default))
        default)))
