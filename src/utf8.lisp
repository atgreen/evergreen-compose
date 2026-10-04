;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(in-package :evergreen-compose)

;;;; Java's modified UTF-8, both ways.
;;;;
;;;; Not quite UTF-8, and the differences are exactly the ones that break a UI:
;;;; NUL is written as two bytes so no interior NUL can end a string early, and a
;;;; character above the basic plane is written as its two SURROGATES of three
;;;; bytes each rather than as one four-byte sequence.
;;;;
;;;; This is its own file, and not part of the JNI layer, because it is text
;;;; encoding rather than foreign calling -- and because being loadable without
;;;; an Android in the room is what lets it be tested at all.

(defun %modified-utf8 (text)
  "TEXT as modified UTF-8 bytes.

Java's own encoding, and it differs from UTF-8 in two places that both matter
here: NUL is two bytes so that no interior NUL can end the string early, and a
character above the basic plane is written as its two SURROGATES of three bytes
each rather than as one four-byte sequence.

This is not a nicety. Passing a raw code point through as a byte is what the
first version did, and an emoji typed on the phone -- U+1F602, entirely ordinary
text -- took the renderer down with \"integer argument is outside the unsigned
8-bit range\" the moment it reached a label."
  ;; The native codec scans the string once. Repeated CHAR/AREF on EGCL's
  ;; UTF-8-backed strings makes a Lisp character-by-character pass quadratic.
  (let* ((utf8 (egcl-ext:string-to-octets text))
         (extra (loop for byte across utf8
                      sum (cond ((zerop byte) 1) ((>= byte #xf0) 2) (t 0)))))
    (if (zerop extra) utf8
        (let ((bytes (make-array (+ (length utf8) extra) :element-type '(unsigned-byte 8)))
              (at 0) (i 0))
          (macrolet ((emit (value) `(progn (setf (aref bytes at) ,value) (incf at)))
                     (unit (value)
                       `(let ((code ,value))
                          (emit (logior #xe0 (ash code -12)))
                          (emit (logior #x80 (logand (ash code -6) #x3f)))
                          (emit (logior #x80 (logand code #x3f))))))
            (loop while (< i (length utf8)) for byte = (aref utf8 i)
                  do (cond ((zerop byte) (emit #xc0) (emit #x80) (incf i))
                           ((>= byte #xf0)
                            (let ((code (- (logior (ash (logand byte 7) 18)
                                                   (ash (logand (aref utf8 (+ i 1)) #x3f) 12)
                                                   (ash (logand (aref utf8 (+ i 2)) #x3f) 6)
                                                   (logand (aref utf8 (+ i 3)) #x3f)) #x10000)))
                              (unit (+ #xd800 (ash code -10)))
                              (unit (+ #xdc00 (logand code #x3ff))))
                            (incf i 4))
                           (t (emit byte) (incf i)))))
          bytes))))

(defun %utf8-at (bytes offset)
  "The code point encoded at OFFSET, and how many bytes it took."
  (flet ((byte-at (n) (ffi-ref bytes :uchar (+ offset n)))
         (tail (n) (logand (ffi-ref bytes :uchar (+ offset n)) #x3f)))
    (let ((lead (byte-at 0)))
      (cond ((< lead #x80) (values lead 1))
            ((< lead #xe0) (values (logior (ash (logand lead #x1f) 6) (tail 1)) 2))
            ((< lead #xf0) (values (logior (ash (logand lead #x0f) 12)
                                           (ash (tail 1) 6) (tail 2))
                                   3))
            (t (values (logior (ash (logand lead #x07) 18) (ash (tail 1) 12)
                               (ash (tail 2) 6) (tail 3))
                       4))))))

(defun decode-modified-utf8 (bytes)
  "The NUL-terminated modified UTF-8 at the foreign pointer BYTES, as a string."
  (let ((text (make-array 0 :element-type 'character :adjustable t :fill-pointer 0))
        (high nil)
        (offset 0))
    (loop until (zerop (ffi-ref bytes :uchar offset))
          do (multiple-value-bind (code width) (%utf8-at bytes offset)
               (incf offset width)
               ;; A high surrogate is held back: on its own it is not a
               ;; character, and paired it is one character rather than two.
               (cond ((<= #xd800 code #xdbff) (setf high code))
                     ((and high (<= #xdc00 code #xdfff))
                      (vector-push-extend
                       (code-char (+ #x10000 (ash (- high #xd800) 10) (- code #xdc00)))
                       text)
                      (setf high nil))
                     (t (setf high nil)
                        (vector-push-extend (code-char code) text)))))
    (coerce text 'string)))
