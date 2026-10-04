;;;; SPDX-FileCopyrightText: Copyright (C) 2026 Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: GPL-3.0-or-later WITH Classpath-exception-2.0

(in-package :evergreen-compose)


;;; The Compose bridge uses cached JNI classes/methods and bulk UTF-8 transfer.
;;; Call %FFI-CALL directly: measurements on EGCL showed substantial overhead
;;; in the public FOREIGN-CALL wrapper. JNI indices are from JNINativeInterface;
;;; JNI-START verifies the table with GetVersion before other calls use it.

(defconstant +jni-find-class+ 6)
(defconstant +jni-get-method-id+ 33)
(defconstant +jni-call-object-method-a+ 36)
(defconstant +jni-call-void-method-a+ 63)
(defconstant +jni-new-object-a+ 30)
(defconstant +jni-new-global-ref+ 21)
(defconstant +jni-delete-global-ref+ 22)
(defconstant +jni-delete-local-ref+ 23)
(defconstant +jni-new-string-utf+ 167)
(defconstant +jni-exception-occurred+ 15)
(defconstant +jni-exception-clear+ 17)
(defconstant +jni-get-version+ 4)
(defconstant +jni-push-local-frame+ 19)
(defconstant +jni-pop-local-frame+ 20)
(defconstant +jni-get-string-utf-chars+ 169)
(defconstant +jni-release-string-utf-chars+ 170)

(defvar *env* nil "This thread's JNIEnv, or NIL before JNI-START.")
(defvar *env-table* nil "The JNIEnv function table, read once.")

(defun word-at (pointer &optional (index 0))
  (ffi-ref pointer :pointer (* 8 index)))

(defvar *slots* nil
  "JNI function pointers by table index, resolved once.

Measured on a Pixel 10 Pro XL: reading one word out of the table with MEM-REF
costs 16us, and every JNI call did it. That is a quarter of a 60us setColor
spent looking up an answer that cannot change for the life of the process -- the
table is the VM's and it is not rewritten.")

(defun jni-slot (index)
  (or (svref *slots* index)
      (setf (svref *slots* index) (word-at *env-table* index))))

(defun jni-start ()
  "Attach this thread to the running VM and verify the function table.

GetVersion must answer 0x10006 or 0x10008. If it does not, the table base is
wrong and every other index in this file would return fiction, so this refuses
to continue rather than producing numbers that look real."
  (let* ((lib (egcl-ffi:load-foreign-library "libnativehelper.so"))
         (entry (egcl-ffi:foreign-symbol-pointer "JNI_GetCreatedJavaVMs" lib))
         (vm-out (ffi-alloc 8))
         (count-out (ffi-alloc 4)))
    (egcl::%ffi-call entry :int '(:pointer :int :pointer) (list vm-out 1 count-out))
    (unless (plusp (ffi-ref count-out :int))
      (error "No Java VM is running in this process"))
    (let* ((vm (ffi-ref vm-out :pointer))
           (attach (word-at (word-at vm) 4))
           (env-out (ffi-alloc 8)))
      (egcl::%ffi-call attach :int '(:pointer :pointer :pointer)
                              (list vm env-out (egcl-ffi:null-pointer)))
      (setf *env* (ffi-ref env-out :pointer)
            *env-table* (word-at *env*)
            ;; 233 entries in JNI 1.6; round up and leave room.
            *slots* (make-array 256 :initial-element nil))
      (let ((version (egcl::%ffi-call (jni-slot +jni-get-version+) :int
                                             '(:pointer) (list *env*))))
        (unless (member version '(#x10006 #x10008))
          (setf *env* nil)
          (error "JNI function table looks wrong: GetVersion returned #x~X" version))
        version))))

(defun jni-check ()
  "Signal if a Java exception is pending, and clear it.
Left pending, it makes the NEXT unrelated JNI call fail in a way that points at
the wrong line."
  (let ((thrown (egcl::%ffi-call (jni-slot +jni-exception-occurred+) :pointer
                                        '(:pointer) (list *env*))))
    (unless (egcl-ffi:null-pointer-p thrown)
      ;; Clear FIRST: with an exception pending, the toString call below would
      ;; itself fail, and the report would be "an exception was thrown" again.
      (egcl::%ffi-call (jni-slot +jni-exception-clear+) :void '(:pointer) (list *env*))
      (error "Java: ~A"
             (let* ((class (jni-find-class "java/lang/Object"))
                    (to-string (jni-method class "toString" "()Ljava/lang/String;")))
               (or (jni-text (jni-call-object thrown to-string (jni-args)))
                   "a throwable that would not describe itself"))))))

(defun jni-global (local)
  "Promote a local reference to a global one, so it survives past this call.
A cached class or method receiver must be global; a local reference is only
valid until the native call that produced it returns."
  (let ((global (egcl::%ffi-call (jni-slot +jni-new-global-ref+) :pointer
                                        '(:pointer :pointer) (list *env* local))))
    (egcl::%ffi-call (jni-slot +jni-delete-local-ref+) :void
                            '(:pointer :pointer) (list *env* local))
    global))

(defmacro with-c-string ((pointer text) &body body)
  "TEXT as a NUL-terminated C string at POINTER for the extent of BODY.

Not ANDROID:WITH-C-STRING. That one writes every byte through the MEM-SET
wrapper, and a wrapped FFI call on this runtime is ~150us, so a thirty-character
class name cost 4.6ms to hand over -- most of what a method or field lookup
cost, measured. FFI-SET is the builtin underneath the wrapper. One byte per
character, so this is for the ASCII names JNI takes and not for text; text is
JNI-STRING's job and it encodes properly."
  (let ((value (gensym "TEXT")) (i (gensym "I")))
    `(let* ((,value ,text) (,pointer (ffi-alloc (1+ (length ,value)))))
       (unwind-protect
            (progn
              (dotimes (,i (length ,value))
                (ffi-set (char-code (char ,value ,i)) ,pointer :uchar ,i))
              (ffi-set 0 ,pointer :uchar (length ,value))
              ,@body)
         (ffi-free ,pointer)))))

(defun jni-find-class (name)
  "The class NAME (\"java/lang/Object\"), as a GLOBAL reference."
  (with-c-string (text name)
    (let ((class (egcl::%ffi-call (jni-slot +jni-find-class+) :pointer
                                         '(:pointer :pointer) (list *env* text))))
      (when (egcl-ffi:null-pointer-p class) (error "No such Java class: ~A" name))
      (jni-global class))))

(defun jni-method (class name signature)
  (with-c-string (n name)
    (with-c-string (s signature)
      (let ((id (egcl::%ffi-call
                 (jni-slot +jni-get-method-id+)
                 :pointer '(:pointer :pointer :pointer :pointer)
                 (list *env* class n s))))
        (when (egcl-ffi:null-pointer-p id)
          (error "No such Java method: ~A~A" name signature))
        id))))

(defvar *args* nil)
(defparameter +max-args+ 8)

(defun jni-args (&rest specs)
  "Marshal SPECS -- (:int n), (:float x) or (:object p) -- into the jvalue buffer."
  (unless *args* (setf *args* (ffi-alloc (* 8 +max-args+))))
  (loop for spec in specs
        for offset from 0 by 8
        do (ecase (first spec)
             (:int (ffi-set (second spec) *args* :int offset))
             (:float (ffi-set (float (second spec) 1.0) *args* :float offset))
             (:object (ffi-set (second spec) *args* :pointer offset))))
  *args*)

(defun jni-call-void (object method args)
  (egcl::%ffi-call (jni-slot +jni-call-void-method-a+) :void
                          '(:pointer :pointer :pointer :pointer)
                          (list *env* object method args)))

(defun jni-call-object (object method args)
  (egcl::%ffi-call (jni-slot +jni-call-object-method-a+) :pointer
                          '(:pointer :pointer :pointer :pointer)
                          (list *env* object method args)))

(defun jni-new (class constructor args)
  (egcl::%ffi-call (jni-slot +jni-new-object-a+) :pointer
                          '(:pointer :pointer :pointer :pointer)
                          (list *env* class constructor args)))

(defun jni-string (text)
  "TEXT as a jstring GLOBAL reference. Callers cache these: at ~27us each,
rebuilding a label's string every frame costs more than drawing it."
  (let* ((bytes (%modified-utf8 text))
         (buffer (ffi-alloc (1+ (length bytes)))))
    (unwind-protect
         (progn
           ;; One checked native copy. A per-byte FFI loop made a 90KB Compose
           ;; snapshot take seconds on Android even though it was one JNI call.
           (egcl::%foreign-memory :copy-in buffer bytes :unsigned-char)
           (ffi-set 0 buffer :uchar (length bytes))
           (jni-global (egcl::%ffi-call (jni-slot +jni-new-string-utf+) :pointer
                                               '(:pointer :pointer) (list *env* buffer))))
      (ffi-free buffer))))

(defun jni-text (string)
  "The jstring STRING as a Lisp string, or NIL for a Java null.

The bytes are MODIFIED UTF-8, which is ordinary UTF-8 across the basic plane and
CESU-8 above it: a character outside that plane arrives as a surrogate PAIR,
three bytes each, rather than as one four-byte sequence. Both are decoded here
because text a person typed contains both -- an emoji is exactly the second
case, and reading it as two lone surrogates would produce two characters that
are not the one they typed."
  (unless (egcl-ffi:null-pointer-p string)
    (let ((bytes (egcl::%ffi-call (jni-slot +jni-get-string-utf-chars+) :pointer
                                         '(:pointer :pointer :pointer)
                                         (list *env* string (egcl-ffi:null-pointer)))))
      (unwind-protect (decode-modified-utf8 bytes)
        (egcl::%ffi-call (jni-slot +jni-release-string-utf-chars+) :void
                                '(:pointer :pointer :pointer)
                                (list *env* string bytes))))))

(defun jni-delete-global (global)
  "Release a global reference.

The counterpart of JNI-GLOBAL, and the one people forget: a global reference is
never collected on its own, so one made per frame is a leak that grows for the
life of the process. (It does NOT abort the way a local-reference overflow does
-- 250,000 leaked globals survived a measurement, at about 45 bytes each -- so
nothing tells you.)"
  (unless (egcl-ffi:null-pointer-p global)
    (egcl::%ffi-call (jni-slot +jni-delete-global-ref+) :void
                            '(:pointer :pointer) (list *env* global))))

(defun jni-push-frame (capacity)
  (egcl::%ffi-call (jni-slot +jni-push-local-frame+) :int
                          '(:pointer :int) (list *env* capacity)))

(defun jni-pop-frame (result)
  "Close the frame, promoting RESULT out of it when RESULT is a reference.

A body that answered with a Lisp value -- a string, a boolean, a number -- has
nothing to promote, and passing it to JNI would be a type error rather than a
no-op, so it is handed straight back."
  (let ((reference (and result (egcl-ffi:pointerp result))))
    (let ((promoted (egcl::%ffi-call
                     (jni-slot +jni-pop-local-frame+) :pointer
                     '(:pointer :pointer)
                     (list *env* (if reference result (egcl-ffi:null-pointer))))))
      (if reference promoted result))))

(defmacro with-local-refs ((&optional (capacity 16)) &body body)
  "Release every local reference BODY makes, keeping only what it returns.

ALL of what it returns. The first version kept only the primary value, so a body
answering (VALUES 0 0 0 0) came back as 0 and three NILs -- which surfaced as
\"the value NIL is not of type integer\" in a caller's FORMAT, a long way from
here. Only the first value can be promoted out of the frame, because only one
thing can be, and that is the right one: a body returning several references
would have to say which survives."
  (let ((values (gensym "VALUES")))
    `(progn
       (jni-push-frame ,capacity)
       (let ((,values nil))
         (unwind-protect (setf ,values (multiple-value-list (progn ,@body)))
           (setf ,values (cons (jni-pop-frame (first ,values)) (rest ,values))))
         (values-list ,values)))))
