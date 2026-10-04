;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(in-package :evergreen-compose)

;;; A test harness small enough to have no dependencies, because the framework
;;; it tests has none either. Every check reports, and the runner exits non-zero
;;; if any failed, so this works from a shell, from CI, and over `adb shell`.

(defparameter *tests-directory*
  (make-pathname :name nil :type nil :defaults *load-truename*)
  "Where this file is, captured while it loads: RUN-TESTS is called from
run-tests.lisp, by which time *LOAD-TRUENAME* names that file instead.")

(defparameter *failures* 0)
(defparameter *checks* 0)

(defun check (name expected actual)
  (incf *checks*)
  (cond ((equal expected actual) (format t "  ok   ~A~%" name))
        (t (incf *failures*)
           (format t "  FAIL ~A~%       expected ~S~%       actual   ~S~%"
                   name expected actual))))

(defun check-true (name value) (check name t (and value t)))

(defun test-utf8 ()
  ;; Java's modified UTF-8, which text typed on a phone exercises the moment
  ;; anyone reaches for an emoji.
  (flet ((bytes (text) (coerce (%modified-utf8 text) 'list))
         (round-trip (text)
           (let* ((encoded (%modified-utf8 text))
                  (buffer (egcl-ffi:foreign-alloc (1+ (length encoded)))))
             (unwind-protect
                  (progn (loop for byte across encoded
                               for index from 0
                               do (egcl-ffi:mem-set byte buffer :uchar index))
                         (egcl-ffi:mem-set 0 buffer :uchar (length encoded))
                         (decode-modified-utf8 buffer))
               (egcl-ffi:foreign-free buffer)))))
    (check "ASCII is one byte each" '(104 105) (bytes "hi"))
    (check "Latin-1 is two" '(#xc3 #xa9) (bytes (string (code-char #xe9))))
    (check "the basic plane is three" '(#xe2 #x82 #xac) (bytes (string (code-char #x20ac))))
    ;; U+1F602: four bytes in real UTF-8, six here, because Java writes the
    ;; surrogate PAIR rather than the code point.
    (check "above it, a surrogate pair of three bytes each"
           '(#xed #xa0 #xbd #xed #xb8 #x82) (bytes (string (code-char #x1f602))))
    (check "and NUL is never a zero byte" '(#xc0 #x80) (bytes (string (code-char 0))))
    (check "ASCII survives the round trip" "hello" (round-trip "hello"))
    (check "and so does an emoji, as ONE character"
           1 (length (round-trip (string (code-char #x1f602)))))
    (check "which is the character it started as"
           #x1f602 (char-code (char (round-trip (string (code-char #x1f602))) 0)))
    (check "mixed text keeps its length"
           5 (length (round-trip (format nil "a~Ab~Ac" (code-char #x1f602) (code-char #x20ac)))))))

(defun test-saved-state ()
  (format t "state that outlives the process~%")
  ;; The default store holds the string in this image, which is what makes any
  ;; of this testable without a phone.
  (let ((*state-store* (let ((held nil))
                         (list :read (lambda () held)
                               :write (lambda (text) (setf held text))))))
    (check "nothing saved yet reads as the default" :cold (restore-state :cold))
    (save-state '(:name "Ada" :city "London" :tab 2 :volume 1/2))
    (check "a plist comes back EQUAL"
           '(:name "Ada" :city "London" :tab 2 :volume 1/2) (restore-state))
    ;; A RATIO, not a float: the demo's volume is one, and PRIN1 is what keeps
    ;; it exact across the round trip.
    (check "and the ratio is still a ratio" 1/2 (getf (restore-state) :volume))
    ;; Text is user text. A quote or a backslash in it must not end the string
    ;; early, which is the whole reason for PRIN1 rather than a hand-rolled
    ;; format.
    (save-state (list :city "O\"Brien \\ \"quoted\""))
    (check "quotes and backslashes survive"
           "O\"Brien \\ \"quoted\"" (getf (restore-state) :city))
    (save-state nil)
    (check "saving NIL reads back as NIL, not as the default" nil (restore-state :cold))
    ;; Yesterday's build wrote a shape this one cannot read. Starting empty
    ;; beats refusing to start.
    (funcall (getf *state-store* :write) "(:unbalanced ")
    (check "an unreadable blob yields the default instead of signalling"
           :cold (restore-state :cold))
    (funcall (getf *state-store* :write) "#.(error \"never\")")
    (check "and #. is not evaluated on the way back in"
           :cold (restore-state :cold))))

(load (merge-pathnames "compose.lisp" *tests-directory*))
(load (merge-pathnames "samples.lisp" *tests-directory*))
(load (merge-pathnames "services.lisp" *tests-directory*))
(load (merge-pathnames "sketchbook.lisp" *tests-directory*))
(defun run-tests ()
  (setf *failures* 0 *checks* 0)
  (test-utf8) (test-saved-state) (test-app-services)
  (test-compose) (test-compose-controls) (test-compose-catalog)
  (test-compose-only) (test-expanded-controls) (test-compose-deltas) (test-compose-hello)
  (test-sample-primitives) (test-evergreen-news)
  (test-evergreen-chat) (test-evergreen-snack) (test-reply)
  (test-evergreen-lagged) (test-evergreen-caster)
  (test-sample-persistence) (test-live-feeds) (test-news-reader)
  (test-drawing-pad) (test-sketchbook)
  (format t "~%~D checks, ~D failures~%" *checks* *failures*)
  *failures*)
