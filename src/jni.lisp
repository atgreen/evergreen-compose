(in-package :bliss)


;;; ── Calling out ───────────────────────────────────────────────────────
;;;
;;; %FFI-CALL rather than EGCL-FFI:FOREIGN-CALL, everywhere in this file and in
;;; the backends. They do the same thing -- FOREIGN-CALL is a two-line DEFUN
;;; whose only job is to decide whether a variadic FIXED-COUNT was supplied --
;;; but measured on a Pixel 10 Pro XL, warmed, 5000 iterations:
;;;
;;;   (egcl::%ffi-call fn :int '() '())        3.6 us
;;;   (egcl-ffi:foreign-call fn :int '() '())  50.6 us
;;;
;;; The wrapper costs fourteen times the call it wraps. That is paid by every
;;; JNI crossing, and PRESENT is nothing but JNI crossings -- profiled by
;;; display-op kind, each operation's cost tracks the number of calls it makes
;;; rather than the pixels it covers. Nothing here is variadic, so the wrapper
;;; buys nothing at all.
;;;
;;; The wrapper being this expensive is itself a EGCL bug (egcl bliss-1dp);
;;; when it is fixed this file can go back to the public name.

;;;; A small JNI layer: enough to call Android's Java API from Lisp.
;;;;
;;;; There is no JavaVM handed to us, so the running one is found through
;;;; JNI_GetCreatedJavaVMs and the JNI function tables are walked by index.
;;;; JNIEnv and JavaVM are each a pointer to a table of function pointers, so a
;;;; call is: read the slot, call it with the env as the first argument.
;;;;
;;;; Measured on a Pixel 10 Pro XL: a call into Java costs ~35us, of which ~34us
;;;; is EGCL's FFI and barely 1us is JNI and Java combined. Four integer
;;;; arguments add 2us. NewStringUTF costs ~27us. Two consequences shape this
;;;; file: resolve classes and method IDs ONCE and cache them, and cache
;;;; jstrings rather than rebuilding them per frame.
;;;;
;;;; Indices are from JNINativeInterface. They are verified at startup rather
;;;; than trusted -- a wrong slot returns plausible garbage instead of failing,
;;;; which is the whole hazard of hand-indexing a vtable.

(defconstant +jni-find-class+ 6)
(defconstant +jni-get-method-id+ 33)
(defconstant +jni-call-object-method-a+ 36)
(defconstant +jni-call-int-method-a+ 51)
(defconstant +jni-call-boolean-method-a+ 39)
(defconstant +jni-call-void-method-a+ 63)
(defconstant +jni-call-float-method-a+ 57)
(defconstant +jni-new-object-a+ 30)
(defconstant +jni-new-global-ref+ 21)
(defconstant +jni-delete-global-ref+ 22)
(defconstant +jni-delete-local-ref+ 23)
(defconstant +jni-get-static-method-id+ 113)
(defconstant +jni-call-static-object-method-a+ 116)
(defconstant +jni-call-static-int-method-a+ 131)
(defconstant +jni-get-field-id+ 94)
(defconstant +jni-get-int-field+ 100)
(defconstant +jni-set-int-field+ 109)
(defconstant +jni-get-static-field-id+ 144)
(defconstant +jni-get-static-object-field+ 145)
(defconstant +jni-new-string-utf+ 167)
(defconstant +jni-exception-occurred+ 15)
(defconstant +jni-exception-clear+ 17)
(defconstant +jni-get-version+ 4)
(defconstant +jni-push-local-frame+ 19)
(defconstant +jni-pop-local-frame+ 20)
(defconstant +jni-get-string-utf-length+ 168)
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

(defvar *jni-calls* 0
  "Diagnostic: crossings into C since it was last zeroed.

Counted because PRESENT costs the same clipped to one pixel as unclipped
(bliss-asd), so its cost is the crossings and not the drawing, and the only way
to price a crossing is to know how many there were.")

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

(defun jni-find-class (name)
  "The class NAME (\"android/graphics/Canvas\"), as a GLOBAL reference."
  (android:with-c-string (text name)
    (let ((class (egcl::%ffi-call (jni-slot +jni-find-class+) :pointer
                                         '(:pointer :pointer) (list *env* text))))
      (when (egcl-ffi:null-pointer-p class) (error "No such Java class: ~A" name))
      (jni-global class))))

(defun jni-method (class name signature &key static)
  (android:with-c-string (n name)
    (android:with-c-string (s signature)
      (let ((id (egcl::%ffi-call
                 (jni-slot (if static +jni-get-static-method-id+ +jni-get-method-id+))
                 :pointer '(:pointer :pointer :pointer :pointer)
                 (list *env* class n s))))
        (when (egcl-ffi:null-pointer-p id)
          (error "No such Java method: ~A~A" name signature))
        id))))

(defun jni-static-object-field (class name signature)
  (android:with-c-string (n name)
    (android:with-c-string (s signature)
      (let ((id (egcl::%ffi-call (jni-slot +jni-get-static-field-id+) :pointer
                                        '(:pointer :pointer :pointer :pointer)
                                        (list *env* class n s))))
        (when (egcl-ffi:null-pointer-p id) (error "No such static field: ~A" name))
        (jni-global (egcl::%ffi-call (jni-slot +jni-get-static-object-field+)
                                            :pointer '(:pointer :pointer :pointer)
                                            (list *env* class id)))))))

;;; Arguments cross as a jvalue array: one 8-byte union per argument, with a
;;; jint or jfloat in its low half. One buffer is reused for every call, because
;;; allocating a fresh one per call would cost more than the call.

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
  (incf *jni-calls*)
  (egcl::%ffi-call (jni-slot +jni-call-void-method-a+) :void
                          '(:pointer :pointer :pointer :pointer)
                          (list *env* object method args)))

(defun jni-call-object (object method args)
  (incf *jni-calls*)
  (egcl::%ffi-call (jni-slot +jni-call-object-method-a+) :pointer
                          '(:pointer :pointer :pointer :pointer)
                          (list *env* object method args)))

(defun jni-call-static-object (class method args)
  (incf *jni-calls*)
  (egcl::%ffi-call (jni-slot +jni-call-static-object-method-a+) :pointer
                          '(:pointer :pointer :pointer :pointer)
                          (list *env* class method args)))

(defun jni-new (class constructor args)
  (incf *jni-calls*)
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
           (loop for byte across bytes
                 for index from 0
                 do (ffi-set byte buffer :uchar index))
           (ffi-set 0 buffer :uchar (length bytes))
           (jni-global (egcl::%ffi-call (jni-slot +jni-new-string-utf+) :pointer
                                               '(:pointer :pointer) (list *env* buffer))))
      (ffi-free buffer))))

(defun jni-call-boolean (object method args)
  (incf *jni-calls*)
  (plusp (egcl::%ffi-call (jni-slot +jni-call-boolean-method-a+) :int
                                 '(:pointer :pointer :pointer :pointer)
                                 (list *env* object method args))))

(defun jni-call-int (object method args)
  (incf *jni-calls*)
  (egcl::%ffi-call (jni-slot +jni-call-int-method-a+) :int
                          '(:pointer :pointer :pointer :pointer)
                          (list *env* object method args)))

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

(defun jni-release (local)
  "Release a local reference.

A thread attached with AttachCurrentThread never returns to a native frame, so
nothing ever pops its local reference table. A per-call result that is not
released therefore accumulates for the life of the thread, and a per-FRAME one
overflows the table and aborts the process."
  (unless (egcl-ffi:null-pointer-p local)
    (egcl::%ffi-call (jni-slot +jni-delete-local-ref+) :void
                            '(:pointer :pointer) (list *env* local))))

;;; ── Local references ──────────────────────────────────────────────────
;;;
;;; Every JNI call that returns an OBJECT returns a local reference, and a local
;;; reference lives until the native frame that made it returns. This thread was
;;; attached with AttachCurrentThread and is sitting in a Lisp loop: it has no
;;; native frame and will never return to one, so nothing ever pops its table.
;;; A call made once at startup is then a handful of words leaked for the life of
;;; the process, which is nothing -- and a call made EVERY FRAME fills the table
;;; and aborts:
;;;
;;;   JNI ERROR (app bug): local reference table overflow (max=512)
;;;
;;; JNI's own answer is a frame you open and close yourself, which is what this
;;; is. WITH-LOCAL-REFS around a per-frame call is the rule; JNI-RELEASE is for
;;; releasing one reference by hand where a frame would be heavier than the job.

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

(defun jni-field (class name signature)
  "A field ID. Unlike a method, a PUBLIC FIELD is how several small Android
value classes are read -- Insets carries left, top, right and bottom that way
and offers no getters at all."
  (android:with-c-string (n name)
    (android:with-c-string (sig signature)
      (let ((id (egcl::%ffi-call (jni-slot +jni-get-field-id+) :pointer
                                        '(:pointer :pointer :pointer :pointer)
                                        (list *env* class n sig))))
        (when (egcl-ffi:null-pointer-p id)
          (error "No such Java field: ~A ~A" name signature))
        id))))

(defun jni-int-field (object field)
  (egcl::%ffi-call (jni-slot +jni-get-int-field+) :int
                          '(:pointer :pointer :pointer) (list *env* object field)))

(defun jni-call-static-int (class method args)
  "A static method returning an int. NOT JNI-CALL-INT with the class as the
receiver: that is an instance call on a Class object, which is a different
method or none, and JNI will not say so."
  (incf *jni-calls*)
  (egcl::%ffi-call (jni-slot +jni-call-static-int-method-a+) :int
                          '(:pointer :pointer :pointer :pointer)
                          (list *env* class method args)))
